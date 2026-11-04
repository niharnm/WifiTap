// GET /functions/v1/redeem-tag?token=<token>
// No user auth: the tag token is the credential. Optional header X-Client-Platform.
// 200 { ssid, password, security } | 404 not_found | 410 revoked or expired | 429 rate_limited

import { decryptSecret, TOKEN_PATTERN } from "../_shared/crypto.ts";
import { json } from "../_shared/http.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type Outcome = "delivered" | "revoked" | "expired" | "rate_limited";

const PLATFORMS = new Set(["ios", "android", "web", "unknown"]);
// Per client (hashed address, per tag) and a generous per-tag ceiling as an abuse backstop.
const CLIENT_LIMIT_MAX = 30;
const TAG_LIMIT_MAX = 1000;
const RATE_LIMIT_WINDOW_SECONDS = 10 * 60;

// Supabase's gateway sits behind Cloudflare, which sets cf-connecting-ip itself.
// X-Forwarded-For can carry client-supplied entries, so it is only a fallback.
function clientAddress(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  const real = req.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || "unknown";
}

// Salted, tag scoped SHA-256 so raw addresses are never stored or linkable across cards.
async function clientKey(req: Request, tagId: string): Promise<string> {
  const salt = Deno.env.get("RATE_LIMIT_SALT") ?? "";
  const data = new TextEncoder().encode(`${salt}|${tagId}|${clientAddress(req)}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

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

    // Atomic count-and-check in the database. Rate limited calls are still logged.
    const { data: quota, error: quotaError } = await admin.rpc("consume_redeem_quota", {
      p_tag_id: tag.id,
      p_client_key: await clientKey(req, tag.id),
      p_client_max: CLIENT_LIMIT_MAX,
      p_tag_max: TAG_LIMIT_MAX,
      p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
    });
    if (quotaError) throw new Error(`rate limit failed: ${quotaError.code} ${quotaError.message}`);

    let outcome: Outcome;
    let response: Response;
    if (quota !== "ok") {
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
