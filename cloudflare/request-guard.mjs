// Cost-aware, best-effort edge defense. No IPs or request content are persisted.
// Cloudflare's built-in Rate Limiting API is approximate and per edge location;
// zone WAF/DDoS and provider quotas are additional layers, not substitutes.
const COSTLY_PATHS = new Set([
  "/api/home-catalog",
  "/api/ndl",
  "/api/openbd",
  "/api/rakuten",
]);

function protectedRoute(request, { isCrawler = false, seoPath = false } = {}) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/{2,}/g, "/");
  const isApi = path.startsWith("/api/");
  const serverRenderedSeo =
    (isCrawler && (path === "/" || path === "/posts" ||
      /^\/posts\/[^/]+$/.test(path) || seoPath)) ||
    url.searchParams.get("seo_preview") === "1";
  const protectedPath = isApi || serverRenderedSeo ||
    path === "/sitemap.xml";
  return { protectedPath, costly: COSTLY_PATHS.has(path) };
}

function rejection(status, code) {
  return Response.json({ error: code }, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Retry-After": status === 429 ? "60" : "5",
    },
  });
}

// Check both bindings for expensive catalog proxy routes BEFORE any upstream
// fetch. Never trust X-Forwarded-For; use the connecting address Cloudflare
// writes at the edge. The "unknown" key is a conservative shared bucket.
export async function guardRequest(request, env, flags) {
  const { protectedPath, costly } = protectedRoute(request, flags);
  if (!protectedPath) return null;
  if (typeof env?.API_RATE_LIMIT?.limit !== "function" ||
      (costly && typeof env?.CATALOG_RATE_LIMIT?.limit !== "function")) {
    return rejection(503, "rate_limit_unavailable");
  }
  const key = request.headers.get("cf-connecting-ip") || "unidentified";
  try {
    const general = await env.API_RATE_LIMIT.limit({ key: `${key}:api` });
    if (!general?.success) return rejection(429, "rate_limited");
    if (costly) {
      const catalog = await env.CATALOG_RATE_LIMIT.limit({
        key: `${key}:catalog`,
      });
      if (!catalog?.success) return rejection(429, "catalog_rate_limited");
    }
  } catch {
    // Fail closed rather than accidentally exhausting a third-party API or
    // increasing free-tier costs if the limiter becomes unavailable.
    return rejection(503, "rate_limit_unavailable");
  }
  return null;
}

export const _test = { protectedRoute };
