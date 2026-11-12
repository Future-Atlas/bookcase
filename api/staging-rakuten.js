// Rakuten Books metadata proxy for Cloudflare production and staging. Never
// expose applicationId/accessKey or accept a client-selected upstream URL.
// Upstream traffic is serialized by the existing Cloudflare Durable Object.
const ENDPOINTS = Object.freeze({
  book: "https://openapi.rakuten.co.jp/services/api/BooksBook/Search/20170404",
  foreign: "https://openapi.rakuten.co.jp/services/api/BooksForeignBook/Search/20170404",
});
const SORTS = new Set([
  "standard", "sales", "+releaseDate", "-releaseDate", "+itemPrice",
  "-itemPrice", "reviewCount", "reviewAverage",
]);
const TEXT_FIELDS = ["title", "author", "publisherName", "keyword"];
const ALLOWED_INPUTS = new Set([
  "endpoint", "page", "hits", "booksGenreId", "isbn", "sort", ...TEXT_FIELDS,
]);

function badRequest(res) {
  res.setHeader("Cache-Control", "no-store");
  return res.status(400).json({ error: "invalid_rakuten_query" });
}

function createHandler({ request, env = {} } = {}) {
  return async function stagingRakuten(req, res) {
    res.setHeader("Cache-Control", "no-store");
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method_not_allowed" });
    }
    // Protect against unexpected direct routing outside approved environments.
    if (!new Set(["staging", "production"]).has(env.APP_ENV)) {
      return res.status(410).json({ error: "catalog_migrated" });
    }
    if (!env.RAKUTEN_APP_ID || !env.RAKUTEN_ACCESS_KEY ||
        typeof request !== "function") {
      return res.status(503).json({ error: "rakuten_unavailable" });
    }
    const input = req.query || {};
    if (Object.keys(input).some(key => !ALLOWED_INPUTS.has(key))) {
      return badRequest(res);
    }
    const scalar = (key, fallback = "") => {
      const value = input[key] ?? fallback;
      return typeof value === "string" ? value : null;
    };
    const endpoint = scalar("endpoint", "book");
    const page = scalar("page", "1");
    const hits = scalar("hits", "27");
    const pageNum = Number(page);
    const hitsNum = Number(hits);
    if (!Object.hasOwn(ENDPOINTS, endpoint) ||
        !/^[1-9][0-9]{0,2}$/.test(page || "") ||
        !/^[1-9][0-9]{0,1}$/.test(hits || "") ||
        pageNum > 100 || hitsNum > 30) {
      return badRequest(res);
    }
    const query = new URLSearchParams({
      format: "json",
      applicationId: env.RAKUTEN_APP_ID,
      accessKey: env.RAKUTEN_ACCESS_KEY,
      page: String(pageNum),
      hits: String(hitsNum),
    });
    // Do not accept client-supplied affiliateId; only configure server-owned
    // attribution. This response contains no rights-cleared jacket artwork.
    if (env.RAKUTEN_AFFILIATE_ID) {
      query.set("affiliateId", String(env.RAKUTEN_AFFILIATE_ID).trim());
    }
    const genre = scalar("booksGenreId");
    if (genre === null ||
        (genre !== "" &&
          (!/^\d{3}(?:\d{3}){0,3}$/.test(genre) ||
            !genre.startsWith(endpoint === "foreign" ? "005" : "001")))) {
      return badRequest(res);
    }
    if (genre) query.set("booksGenreId", genre);
    const isbn = scalar("isbn");
    if (isbn === null ||
        (isbn !== "" && !/^(?:\d{13}|\d{9}[\dX])$/.test(isbn))) {
      return badRequest(res);
    }
    if (isbn) query.set("isbn", isbn);
    const sort = scalar("sort");
    if (sort === null || (sort !== "" && !SORTS.has(sort))) {
      return badRequest(res);
    }
    if (sort) query.set("sort", sort);
    for (const field of TEXT_FIELDS) {
      const value = scalar(field);
      if (value === null || value.length > 120 ||
          /[\u0000-\u001f\u007f]/.test(value)) {
        return badRequest(res);
      }
      if (value.trim()) query.set(field, value.trim());
    }
    if (!genre && !isbn && !TEXT_FIELDS.some(field => query.has(field))) {
      return badRequest(res);
    }
    try {
      const upstream = await request(ENDPOINTS[endpoint] + "?" + query, {
        origin: env.RAKUTEN_REFERER || (env.APP_ENV === "production"
          ? "https://www.sharemarium.com/"
          : "https://sharemarium-staging.sharemarium.workers.dev/"),
      });
      // Rakuten Books documents HTTP 404 as a valid zero-hit search.
      // Do not convert it to 502: that falsely triggers client-wide cooldown
      // and causes already-collected results to be thrown away.
      if (upstream.status === 404) {
        res.setHeader("Cache-Control", "public, max-age=0, s-maxage=60");
        return res.status(200).json({ Items: [] });
      }
      if (!upstream.ok) {
        // The coordinator and Rakuten provider have distinct failure modes.
        // Only emit a numeric upstream status and a static, allowlisted code;
        // NEVER echo the upstream error body or credential-bearing URL.
        const status = upstream.status;
        let source = "provider";
        if (status === 502 || status === 403) {
          try {
            const payload = await upstream.json();
            if (typeof payload?.error === "string" &&
                ["rakuten_upstream_unavailable", "upstream_not_allowed",
                  "rakuten_queue_full", "rakuten_backoff_active",
                  "invalid_upstream_request"].includes(payload.error)) {
              source = "quota";
            }
          } catch { /* upstream body is not trusted */ }
        }
        if (status === 429 || status === 503) {
          res.setHeader("Retry-After", upstream.headers.get("retry-after") || "5");
          return res.status(503).json({
            error: "rakuten_busy", upstreamStatus: status, source,
          });
        }
        return res.status(502).json({
          error: "rakuten_unavailable", upstreamStatus: status, source,
        });
      }
      const body = await upstream.text();
      if (body.length > 3_000_000) {
        return res.status(502).json({ error: "rakuten_response_too_large" });
      }
      let parsed;
      try { parsed = JSON.parse(body); } catch { return res.status(502).json({ error: "rakuten_bad_response" }); }
      if (!Array.isArray(parsed?.Items)) {
        return res.status(502).json({ error: "rakuten_bad_response" });
      }
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=120");
      return res.status(200).send(body);
    } catch {
      return res.status(502).json({ error: "rakuten_unavailable" });
    }
  };
}

module.exports = { createHandler };
