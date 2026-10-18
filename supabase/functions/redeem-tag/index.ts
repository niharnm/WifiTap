// GET /functions/v1/redeem-tag?token=<token>
// No user auth: the tag token is the credential. Optional header X-Client-Platform.
// 200 { ssid, password, security } | 404 not_found | 410 revoked or expired | 429 rate_limited

import { decryptSecret, TOKEN_PATTERN } from "../_shared/crypto.ts";
import { json } from "../_shared/http.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type Outcome = "delivered" | "revoked" | "expired" | "rate_limited";

const PLATFORMS = new Set(["ios", "android", "web", "unknown"]);
const RATE_LIMIT_MAX = 30;
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;

Deno.serve(async (req) => {
  if (req.method !== "GET") return json(405, { error: "method_not_allowed" });

  // Malformed tokens can never match a row, so answer without touching the database.
  const token = new URL(req.url).searchParams.get("token");
  if (!token || !TOKEN_PATTERN.test(token)) return json(404, { error: "not_found" });

  const header = req.headers.get("X-Client-Platform")?.trim().toLowerCase();
  const platform = header && PLATFORMS.has(header) ? header : "unknown";

  try {
    const admin = createAdminClient();

    const { data: tag, error: tagError } = await admin
      .from("tags")
      .select("id, ssid, security, password_ciphertext, status, expires_at")
      .eq("token", token)
      .maybeSingle();
    if (tagError) throw new Error(`tag lookup failed: ${tagError.code} ${tagError.message}`);
    if (!tag) return json(404, { error: "not_found" });

    // Rate limited calls are logged but not counted, so the window slides once traffic stops.
    const since = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();
    const { count, error: countError } = await admin
      .from("tag_events")
      .select("id", { count: "exact", head: true })
      .eq("tag_id", tag.id)
      .eq("event", "redeem")
      .neq("outcome", "rate_limited")
      .gte("created_at", since);
    if (countError) throw new Error(`rate count failed: ${countError.code} ${countError.message}`);

    let outcome: Outcome;
    let response: Response;
    if ((count ?? 0) >= RATE_LIMIT_MAX) {
      outcome = "rate_limited";
      response = json(429, { error: "rate_limited" });
    } else if (tag.status === "revoked") {
      outcome = "revoked";
      response = json(410, { error: "revoked" });
    } else if (tag.expires_at && Date.parse(tag.expires_at) <= Date.now()) {
      outcome = "expired";
      response = json(410, { error: "expired" });
    } else {
      const password = tag.password_ciphertext ? await decryptSecret(tag.password_ciphertext) : null;
      outcome = "delivered";
      response = json(200, { ssid: tag.ssid, password, security: tag.security });
    }

    const { error: eventError } = await admin
      .from("tag_events")
      .insert({ tag_id: tag.id, event: "redeem", platform, outcome });
    // A logging failure should not block someone joining the network.
    if (eventError) {
      console.error("redeem-tag event insert failed:", eventError.code, eventError.message);
    }

    return response;
  } catch (err) {
    console.error("redeem-tag error:", err instanceof Error ? err.message : String(err));
    return json(500, { error: "server_error" });
  }
});
