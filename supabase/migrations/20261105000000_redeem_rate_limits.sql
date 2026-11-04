-- Per-client rate limiting for redeem-tag.
-- The previous limit counted tag_events per tag, so one caller could lock every guest
-- out of a card, and count-then-insert let concurrent calls slip past the limit.
-- This adds fixed-window counters keyed by (tag, hashed client) plus a per-tag ceiling
-- row, updated by a single atomic upsert inside consume_redeem_quota.

create table public.redeem_rate_limits (
  tag_id uuid not null references public.tags (id) on delete cascade,
  -- Hex SHA-256 of the client address (salted, tag scoped), or '*' for the per-tag ceiling.
  -- Raw addresses are never stored.
  client_key text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (tag_id, client_key, window_start)
);

create index redeem_rate_limits_window_start_idx on public.redeem_rate_limits (window_start);

revoke all on public.redeem_rate_limits from anon, authenticated, service_role;
grant select, insert, update, delete on public.redeem_rate_limits to service_role;
alter table public.redeem_rate_limits enable row level security;
-- No policies: only the service role (edge functions) touches this table.

-- Counts one redeem attempt. Returns 'ok', 'client_limited' or 'tag_limited'.
-- Attempts rejected for a single client do not consume the tag-wide ceiling, so one
-- noisy client cannot exhaust it on its own.
create function public.consume_redeem_quota(
  p_tag_id uuid,
  p_client_key text,
  p_client_max integer,
  p_tag_max integer,
  p_window_seconds integer
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_window timestamptz :=
    to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_hits integer;
begin
  insert into public.redeem_rate_limits as r (tag_id, client_key, window_start, hits)
  values (p_tag_id, p_client_key, v_window, 1)
  on conflict (tag_id, client_key, window_start) do update set hits = r.hits + 1
  returning r.hits into v_hits;
  if v_hits > p_client_max then
    return 'client_limited';
  end if;

  insert into public.redeem_rate_limits as r (tag_id, client_key, window_start, hits)
  values (p_tag_id, '*', v_window, 1)
  on conflict (tag_id, client_key, window_start) do update set hits = r.hits + 1
  returning r.hits into v_hits;
  if v_hits > p_tag_max then
    return 'tag_limited';
  end if;

  -- Opportunistic cleanup of expired windows.
  if random() < 0.01 then
    delete from public.redeem_rate_limits
    where window_start < now() - make_interval(secs => p_window_seconds * 6);
  end if;

  return 'ok';
end;
$$;

revoke all on function public.consume_redeem_quota(uuid, text, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_redeem_quota(uuid, text, integer, integer, integer)
  to service_role;
