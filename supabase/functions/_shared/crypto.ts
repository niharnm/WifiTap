// AES-256-GCM encryption for stored Wi-Fi passwords, plus tag token generation.
// Stored format: base64(12-byte IV || ciphertext with 16-byte GCM tag).

const IV_BYTES = 12;
const KEY_BYTES = 32;
const TOKEN_BYTES = 16;

let keyPromise: Promise<CryptoKey> | undefined;

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

// Return type is left to inference so it stays a BufferSource across TS lib versions.
function base64ToBytes(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeKey(encoded: string) {
  try {
    return base64ToBytes(encoded.trim());
  } catch {
    throw new Error("TAG_ENC_KEY is not valid base64");
  }
}

function getKey(): Promise<CryptoKey> {
  if (!keyPromise) {
    const encoded = Deno.env.get("TAG_ENC_KEY");
    if (!encoded) throw new Error("TAG_ENC_KEY is not set");
    const raw = decodeKey(encoded);
    if (raw.length !== KEY_BYTES) {
      throw new Error(`TAG_ENC_KEY must decode to ${KEY_BYTES} bytes`);
    }
    keyPromise = crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, [
      "encrypt",
      "decrypt",
    ]);
  }
  return keyPromise;
}

export async function encryptSecret(plaintext: string): Promise<string> {
  const key = await getKey();
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plaintext)),
  );
  const out = new Uint8Array(IV_BYTES + ciphertext.length);
  out.set(iv, 0);
  out.set(ciphertext, IV_BYTES);
  return bytesToBase64(out);
}

export async function decryptSecret(stored: string): Promise<string> {
  const key = await getKey();
  const bytes = base64ToBytes(stored);
  if (bytes.length <= IV_BYTES) throw new Error("ciphertext too short");
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: bytes.subarray(0, IV_BYTES) },
    key,
    bytes.subarray(IV_BYTES),
  );
  return new TextDecoder().decode(plaintext);
}

// 128 random bits as unpadded base64url: always 22 characters.
export function generateToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(TOKEN_BYTES));
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export const TOKEN_PATTERN = /^[A-Za-z0-9_-]{22}$/;
