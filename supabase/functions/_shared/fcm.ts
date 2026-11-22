declare const Deno: {
  env: { get(name: string): string | undefined };
};

// Firebase Cloud Messaging HTTP v1 without any SDK: a service-account JWT (RS256) is exchanged for an access
// token, which is cached until shortly before it expires.

export type ServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri?: string };

// FCM_SERVICE_ACCOUNT holds the service-account JSON, either as plain JSON or base64 of it
// (base64 avoids quoting trouble in `supabase secrets set --env-file`).
export function loadServiceAccount(): ServiceAccount | null {
  const raw = (Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "").trim();
  if (!raw) return null;
  try {
    const text = raw.startsWith("{") ? raw : atob(raw);
    const j = JSON.parse(text);
    if (j && j.project_id && j.client_email && j.private_key) {
      return { ...j, private_key: String(j.private_key).replace(/\\n/g, "\n") };
    }
  } catch {
    // fall through
  }
  return null;
}

const b64url = (input: ArrayBuffer | string): string => {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

let cached: { token: string; exp: number } | null = null;

async function accessToken(sa: ServiceAccount, force = false): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (!force && cached && cached.exp - 60 > now) return cached.token;

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", await importKey(sa.private_key), new TextEncoder().encode(unsigned));

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok || !j.access_token) throw new Error(`fcm_auth_failed (${res.status})`);
  cached = { token: j.access_token, exp: now + Number(j.expires_in ?? 3600) };
  return cached.token;
}

export type SendResult =
  | { ok: true }
  | { ok: false; invalidToken: boolean; retry: boolean; error: string };

export type PushMessage = {
  title: string;
  body: string;
  data: Record<string, string>; // FCM requires string values. IDs only.
  collapseKey?: string;
};

// Sends one message. Never throws: every failure comes back as a SendResult.
export async function sendFcm(sa: ServiceAccount, token: string, m: PushMessage, isRetry = false): Promise<SendResult> {
  let at: string;
  try {
    at = await accessToken(sa, isRetry);
  } catch (e) {
    return { ok: false, invalidToken: false, retry: true, error: (e as Error).message };
  }

  let res: Response;
  try {
    res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: m.title, body: m.body },
          data: m.data,
          android: { priority: "HIGH", ...(m.collapseKey ? { collapse_key: m.collapseKey } : {}) },
          apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
        },
      }),
    });
  } catch (e) {
    return { ok: false, invalidToken: false, retry: true, error: `network: ${(e as Error).message}` };
  }

  if (res.ok) return { ok: true };

  const j = await res.json().catch(() => ({}));
  const err = j?.error ?? {};
  const codes: string[] = (err.details ?? []).map((d: { errorCode?: string }) => d?.errorCode).filter(Boolean);
  const status = String(err.status ?? "");
  const message = String(err.message ?? "");

  // The access token may have been revoked or expired early: refresh once.
  if (res.status === 401 && !isRetry) return sendFcm(sa, token, m, true);

  // Token no longer valid: caller deletes it.
  if (codes.includes("UNREGISTERED") || status === "NOT_FOUND") {
    return { ok: false, invalidToken: true, retry: false, error: "unregistered" };
  }
  if (status === "INVALID_ARGUMENT" && /registration token/i.test(message)) {
    return { ok: false, invalidToken: true, retry: false, error: "invalid_token" };
  }

  const retry = res.status === 429 || res.status >= 500;
  return { ok: false, invalidToken: false, retry, error: `fcm_${res.status}_${status || "error"}` };
}