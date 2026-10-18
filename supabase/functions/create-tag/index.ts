// POST /functions/v1/create-tag
// Requires a Supabase user JWT (anonymous sign-in users allowed).
// Body: { ssid, password, security: "open" | "wpa2", mode?: "url_and_wifi" | "url_only" }
// 201: { id, token, url }

import { encryptSecret, generateToken } from "../_shared/crypto.ts";
import { json } from "../_shared/http.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type Security = "open" | "wpa2";
type Mode = "url_and_wifi" | "url_only";

interface CreateTagInput {
  ssid: string;
  password: string | null;
  security: Security;
  mode: Mode;
}

type ParseResult = { input: CreateTagInput } | { error: string };

function parseInput(body: unknown): ParseResult {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { error: "invalid_body" };
  }
  const { ssid, password, security, mode } = body as Record<string, unknown>;

  if (typeof ssid !== "string") return { error: "invalid_ssid" };
  const ssidBytes = new TextEncoder().encode(ssid).length;
  if (ssidBytes < 1 || ssidBytes > 32) return { error: "invalid_ssid" };

  if (security !== "open" && security !== "wpa2") return { error: "invalid_security" };

  const resolvedMode = mode ?? "url_and_wifi";
  if (resolvedMode !== "url_and_wifi" && resolvedMode !== "url_only") {
    return { error: "invalid_mode" };
  }

  if (security === "open") {
    if (password !== undefined && password !== null && password !== "") {
      return { error: "invalid_password" };
    }
    return { input: { ssid, password: null, security, mode: resolvedMode } };
  }

  if (typeof password !== "string") return { error: "invalid_password" };
  const passwordLength = [...password].length;
  if (passwordLength < 8 || passwordLength > 63) return { error: "invalid_password" };
  return { input: { ssid, password, security, mode: resolvedMode } };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const jwt = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!jwt) return json(401, { error: "unauthorized" });

  try {
    const admin = createAdminClient();

    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    if (userError || !userData.user) return json(401, { error: "unauthorized" });

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json(400, { error: "invalid_json" });
    }

    const parsed = parseInput(body);
    if ("error" in parsed) return json(400, { error: parsed.error });
    const { ssid, password, security, mode } = parsed.input;

    const baseUrl = Deno.env.get("PUBLIC_TAG_BASE_URL")?.replace(/\/+$/, "");
    if (!baseUrl) throw new Error("PUBLIC_TAG_BASE_URL is not set");

    const token = generateToken();
    const passwordCiphertext = password === null ? null : await encryptSecret(password);

    const { data: tag, error: insertError } = await admin
      .from("tags")
      .insert({
        owner_id: userData.user.id,
        token,
        ssid,
        security,
        password_ciphertext: passwordCiphertext,
        mode,
      })
      .select("id, token")
      .single();
    // Log only code and message: error details can echo the row being inserted.
    if (insertError) throw new Error(`insert failed: ${insertError.code} ${insertError.message}`);

    return json(201, { id: tag.id, token: tag.token, url: `${baseUrl}/t/${tag.token}` });
  } catch (err) {
    console.error("create-tag error:", err instanceof Error ? err.message : String(err));
    return json(500, { error: "server_error" });
  }
});
