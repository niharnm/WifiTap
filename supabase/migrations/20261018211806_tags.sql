-- Phase 1: NFC tags that resolve a URL token to Wi-Fi credentials.
-- Clients read and manage their own tags through RLS. Inserts and event logging
-- happen only in edge functions using the service role.

-- ---------------------------------------------------------------------------
-- tags
-- ---------------------------------------------------------------------------

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  token text not null unique,
  ssid text not null,
  security text not null,
  password_ciphertext text,
  mode text not null default 'url_and_wifi',
  status text not null default 'active',
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- 128-bit random token, base64url without padding.
  constraint tags_token_format check (token ~ '^[A-Za-z0-9_-]{22}$'),
  -- 802.11 limits an SSID to 32 bytes; octet_length counts UTF-8 bytes.
  constraint tags_ssid_length check (octet_length(ssid) between 1 and 32),
  constraint tags_security_valid check (security in ('open', 'wpa2')),
  constraint tags_mode_valid check (mode in ('url_and_wifi', 'url_only')),
  constraint tags_status_valid check (status in ('active', 'revoked')),
  constraint tags_password_matches_security check (
    (security = 'open' and password_ciphertext is null)
    or (security = 'wpa2' and password_ciphertext is not null)
  )
);

comment on column public.tags.password_ciphertext is
  'base64(12-byte IV || AES-256-GCM ciphertext). Key lives only in the TAG_ENC_KEY function secret.';

create index tags_owner_id_idx on public.tags (owner_id);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger tags_set_updated_at
  before update on public.tags
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tag_events
-- ---------------------------------------------------------------------------

create table public.tag_events (
  id bigint generated always as identity primary key,
  tag_id uuid not null references public.tags (id) on delete cascade,
  event text not null,
  platform text not null default 'unknown',
  outcome text not null,
  created_at timestamptz not null default now(),

  constraint tag_events_platform_valid check (platform in ('ios', 'android', 'web', 'unknown')),
  constraint tag_events_outcome_valid check (
    outcome in ('delivered', 'not_found', 'revoked', 'expired', 'rate_limited')
  )
);

-- Serves both the owner event list and the per-token rate limit window.
create index tag_events_tag_id_created_at_idx on public.tag_events (tag_id, created_at);

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

-- Older Supabase projects grant every new table in public to anon and authenticated;
-- newer ones grant nothing. Start from nothing either way and grant per role.
-- Column-level revokes do nothing while a table-level grant exists, so clients get
-- column grants instead of a table grant.
revoke all on public.tags from anon, authenticated, service_role;
revoke all on public.tag_events from anon, authenticated, service_role;

-- Edge functions (create-tag, redeem-tag) run as service_role.
grant select, insert, update, delete on public.tags to service_role;
grant select, insert on public.tag_events to service_role;

-- password_ciphertext is never readable by clients. Clients must name columns
-- explicitly (select=* on tags is rejected with a permission error).
grant select (
  id, owner_id, token, ssid, security, mode, status, expires_at, created_at, updated_at
) on public.tags to authenticated;

-- Owners may revoke, change mode, rename the SSID, or set an expiry. Changing the
-- password or security type needs re-encryption and belongs in an edge function.
grant update (ssid, mode, status, expires_at) on public.tags to authenticated;
grant delete on public.tags to authenticated;

grant select on public.tag_events to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.tags enable row level security;
alter table public.tag_events enable row level security;

-- No insert policy on tags: rows are created only by the create-tag function.
create policy "Owners can view their tags"
  on public.tags for select
  to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can update their tags"
  on public.tags for update
  to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

create policy "Owners can delete their tags"
  on public.tags for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

-- No insert policy on tag_events: rows are written only by the redeem-tag function.
create policy "Owners can view events for their tags"
  on public.tag_events for select
  to authenticated
  using (
    exists (
      select 1
      from public.tags t
      where t.id = tag_events.tag_id
        and t.owner_id = (select auth.uid())
    )
  );
