// Globally serialized Rakuten outbound requests within one Worker environment.
// A single SQLite-backed Durable Object per Rakuten application ID owns the
// upstream quota. No client can invoke this object without the Worker binding.
const INTERVAL_MS = 1100; // Conservative >1s spacing for 1 request/second.
const CACHE_TTL_MS = 5 * 60 * 1000;
const MAX_PENDING = 12;
const MAX_WAIT_MS = 12 * 1000;
const MAX_CACHED = 120;
const ALLOWED_PATHS = new Set([
  "/services/api/BooksBook/Search/20170404",
  "/services/api/BooksForeignBook/Search/20170404",
]);

function errorResult(status, error, retryAfter = null) {
  return {
    status,
    body: JSON.stringify({ error }),
    type: "application/json; charset=utf-8",
    retryAfter,
  };
}

function toResponse(result) {
  const headers = {
    "Content-Type": result.type,
    "Cache-Control": "no-store",
  };
  if (result.retryAfter != null) headers["Retry-After"] = String(result.retryAfter);
  return new Response(result.body, { status: result.status, headers });
}

export class RakutenCoordinator {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.tail = Promise.resolve();
    this.pending = 0;
    this.inFlight = new Map();
    this.cache = new Map();
  }

  async fetch(request) {
    if (request.method !== "POST") return toResponse(errorResult(405, "method_not_allowed"));
    let payload;
    let target;
    try {
      payload = await request.json();
      target = new URL(payload.url);
    } catch {
      return toResponse(errorResult(400, "invalid_upstream_request"));
    }
    // The DO is not a general-purpose HTTP proxy or a per-user limiter.
    if (target.protocol !== "https:" || target.hostname !== "openapi.rakuten.co.jp" ||
        target.username || target.password || target.port || !ALLOWED_PATHS.has(target.pathname) ||
        !this.env.RAKUTEN_APP_ID || !this.env.RAKUTEN_ACCESS_KEY ||
        target.searchParams.get("applicationId") !== this.env.RAKUTEN_APP_ID ||
        target.searchParams.get("accessKey") !== this.env.RAKUTEN_ACCESS_KEY) {
      return toResponse(errorResult(403, "upstream_not_allowed"));
    }

    const key = target.toString();
    const cached = this.cache.get(key);
    if (cached && cached.expiresAt > Date.now()) return toResponse(cached.result);
    if (cached) this.cache.delete(key);

    let pending = this.inFlight.get(key);
    if (!pending) {
      if (this.pending >= MAX_PENDING) {
        return toResponse(errorResult(429, "rakuten_queue_full", 5));
      }
      pending = this.requestUpstream(key, payload);
      this.inFlight.set(key, pending);
    }
    try {
      return toResponse(await pending);
    } finally {
      if (this.inFlight.get(key) === pending) this.inFlight.delete(key);
    }
  }

  async requestUpstream(url, payload) {
    this.pending++;
    const previous = this.tail;
    let release;
    this.tail = new Promise((resolve) => { release = resolve; });
    await previous;
    try {
      const now = Date.now();
      const nextAllowed = Number(await this.state.storage.get("nextAllowedAt") || 0);
      const backoffUntil = Number(await this.state.storage.get("backoffUntil") || 0);
      const delay = Math.max(0, Math.max(nextAllowed, backoffUntil) - now);
      // Never build an unbounded queue behind a throttled upstream.
      if (delay > MAX_WAIT_MS) {
        return errorResult(429, "rakuten_backoff_active", Math.ceil(delay / 1000));
      }
      if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
      // Persist reservation before making the request. This also survives
      // object eviction / a worker instance restart.
      await this.state.storage.put("nextAllowedAt", Date.now() + INTERVAL_MS);
      let upstream;
      try {
        const origin = payload.origin === "https://staging.sharemarium.com/"
          ? "https://staging.sharemarium.com/"
          : "https://www.sharemarium.com/";
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 15000);
        try {
          upstream = await fetch(url, {
            method: "GET",
            headers: {
              "Accept": "application/json",
              "Origin": new URL(origin).origin,
              "Referer": origin,
              "User-Agent": "Sharemarium-Rakuten-Proxy/1.1 (+https://www.sharemarium.com)",
            },
            signal: controller.signal,
          });
        } finally {
          clearTimeout(timeout);
        }
      } catch {
        return errorResult(502, "rakuten_upstream_unavailable");
      }
      const body = await upstream.text();
      if (upstream.status === 429) {
        const retryValue = Number(upstream.headers.get("retry-after"));
        const retrySeconds = Number.isFinite(retryValue) && retryValue > 0
          ? Math.min(Math.ceil(retryValue), 120) : 30;
        await this.state.storage.put("backoffUntil", Date.now() + retrySeconds * 1000);
      }
      const result = {
        status: upstream.status,
        body,
        type: upstream.headers.get("content-type") || "application/json; charset=utf-8",
        retryAfter: upstream.headers.get("retry-after") || null,
      };
      if (upstream.ok) {
        this.cache.set(url, { expiresAt: Date.now() + CACHE_TTL_MS, result });
        if (this.cache.size > MAX_CACHED) this.cache.delete(this.cache.keys().next().value);
      }
      return result;
    } finally {
      this.pending--;
      release();
    }
  }
}
