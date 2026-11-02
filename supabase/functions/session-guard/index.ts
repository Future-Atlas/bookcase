import { createClient } from "npm:@supabase/supabase-js@2";

// Browser CORS is defense in depth; Bearer token and live session validation
// are authoritative. Native clients send no Origin.
const ALLOWED_ORIGINS = new Set([
  "https://www.sharemarium.com",
  "https://sharemarium.com",
  "https://staging.sharemarium.com",
  "https://sharemarium-staging.sharemarium.workers.dev",
  "http://localhost:3000",
  "http://localhost:8080",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:8080",
]);

function headersFor(request: Request): Headers {
  const headers = new Headers({
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  });
  const origin = request.headers.get("Origin");
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
  }
  return headers;
}

function reply(request: Request, body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: headersFor(request) });
}

// Called ONLY after auth.getUser(token) has validated the JWT. Decoding it
// here is used to read the signed session_id, never as a replacement for
// getUser's signature and expiry validation.
function signedSessionClaims(token: string, verifiedUserId: string):
    { sessionId: string } | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const base64 = part.replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")));
    const sessionId = claims?.session_id;
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (claims?.sub !== verifiedUserId ||
        typeof sessionId !== "string" || !uuidPattern.test(sessionId)) {
      return null;
    }
    return { sessionId };
  } catch {
    return null;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: headersFor(request) });
  }
  if (request.method !== "POST") {
    return reply(request, { error: "method_not_allowed" }, 405);
  }
  const token = request.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token) return reply(request, { error: "unauthorized" }, 401);
  if (!supabaseUrl || !serviceRoleKey) {
    return reply(request, { error: "session_service_unavailable" }, 503);
  }

  // IP headers supplied by the caller are deliberately ignored. In ordinary
  // mobile connections IP may change without a security event and forwarded
  // headers are not an authentication or session-revocation mechanism.
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const userId = userData?.user?.id;
  if (userError || !userId) return reply(request, { error: "unauthorized" }, 401);
  const signedClaims = signedSessionClaims(token, userId);
  if (!signedClaims) return reply(request, { error: "invalid_session" }, 401);

  const { data: active, error: sessionError } = await admin.rpc(
    "is_active_auth_session",
    { p_profile_id: userId, p_session_id: signedClaims.sessionId },
  );
  if (sessionError) {
    return reply(request, { error: "session_service_unavailable" }, 503);
  }
  if (active !== true) return reply(request, { error: "session_revoked" }, 401);
  return reply(request, { ok: true, profileId: userId, sessionActive: true });
});
