const { requestRakuten } = require("./_rakuten_request");

const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 30;

const ENDPOINTS = {
  book: "https://openapi.rakuten.co.jp/services/api/BooksBook/Search/20170404",
  foreign:
    "https://openapi.rakuten.co.jp/services/api/BooksForeignBook/Search/20170404",
};

function createHandler({ request = requestRakuten, env = process.env } = {}) {
  const appId = env.RAKUTEN_APP_ID || "";
  const accessKey = env.RAKUTEN_ACCESS_KEY || "";
  const affiliateId = (env.RAKUTEN_AFFILIATE_ID || "").trim();
  const referer = env.RAKUTEN_REFERER || "https://www.sharemarium.com/";
  const requestCounts = new Map();

  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method_not_allowed" });
    }

  const forwardedFor = String(req.headers["x-forwarded-for"] || "");
  const realIp = String(req.headers["x-real-ip"] || "").trim();
  const clientIp = realIp || forwardedFor.split(",")[0].trim() || "unknown";
  const now = Date.now();
  const current = requestCounts.get(clientIp);
  if (!current || now - current.startedAt >= RATE_LIMIT_WINDOW_MS) {
    requestCounts.set(clientIp, { startedAt: now, count: 1 });
  } else {
    current.count += 1;
    if (current.count > RATE_LIMIT_MAX_REQUESTS) {
      res.setHeader("Retry-After", "60");
      return res.status(429).json({ error: "rate_limit_exceeded" });
    }
  }

    if (!appId || !accessKey) {
      return res.status(500).json({
        error: "rakuten_credentials_missing",
        message: "Rakuten credentials are not configured on the server.",
      });
    }

  const endpoint = String(req.query.endpoint || "book");
  if (!Object.hasOwn(ENDPOINTS, endpoint)) {
    return res.status(400).json({ error: "invalid_endpoint" });
  }
  const baseUrl = ENDPOINTS[endpoint];

  const passthrough = { ...req.query };
  delete passthrough.endpoint;
  const allowedParameters = new Set([
    "page",
    "hits",
    "booksGenreId",
    "title",
    "author",
    "publisherName",
    "keyword",
    "isbn",
    "sort",
  ]);

  const query = new URLSearchParams({
    format: "json",
    applicationId: appId,
    accessKey,
  });
  // Only the server-owned identifier may receive attribution.
  if (affiliateId) query.set("affiliateId", affiliateId);

  for (const [key, value] of Object.entries(passthrough)) {
    if (!allowedParameters.has(key)) continue;
    if (Array.isArray(value)) {
      value.slice(0, 1).forEach((item) =>
        query.append(key, String(item).slice(0, 200)),
      );
    } else if (value != null && String(value).length > 0) {
      query.set(key, String(value).slice(0, 200));
    }
  }

  const page = Number(query.get("page") || 1);
  const hits = Number(query.get("hits") || 10);
  if (
    !Number.isInteger(page) ||
    page < 1 ||
    page > 100 ||
    !Number.isInteger(hits) ||
    hits < 1 ||
    hits > 30
  ) {
    return res.status(400).json({ error: "invalid_pagination" });
  }

  const url = `${baseUrl}?${query.toString()}`;

  try {
    // The Vercel/legacy HTTP entrypoint has no Durable Object binding.
    // Never silently bypass the per-application-ID coordinator in production.
    // An injected request is only accepted for in-process tests; Cloudflare
    // supplies req.rakutenRequest from its bound coordinator.
    const upstreamRequest = typeof req.rakutenRequest === "function"
      ? req.rakutenRequest : request !== requestRakuten ? request : null;
    if (!upstreamRequest) {
      res.setHeader("Cache-Control", "no-store");
      res.setHeader("Retry-After", "5");
      return res.status(503).json({ error: "rakuten_quota_unavailable" });
    }
    const response = await upstreamRequest(url, {
      origin: referer,
      userAgent:
        "Sharemarium-Rakuten-Proxy/1.0 (+https://www.sharemarium.com)",
    });

    const body = await response.text();
    res.setHeader(
      "Cache-Control",
      response.status === 200 ? "public, s-maxage=120" : "no-store",
    );
    if (response.status === 429) {
      const retryAfter = response.headers?.get?.("retry-after");
      res.setHeader("Retry-After", retryAfter || "5");
    }
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("X-Rakuten-Proxy-Transport", "fetch");
    return res.status(response.status).send(body);
  } catch (error) {
    return res.status(502).json({
      error: "rakuten_proxy_failed",
      message: error instanceof Error ? error.message : String(error),
    });
    }
  };
}

const handler = createHandler();
handler.createHandler = createHandler;
module.exports = handler;
