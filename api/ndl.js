// Same-origin, read-only NDL OpenSearch proxy. Never accept arbitrary upstream URLs
// or provider IDs: partner-supplied records can have different reuse terms.
const NDL_URL = "https://ndlsearch.ndl.go.jp/api/opensearch";
const PROVIDERS = new Set([
  "iss-ndl-opac", "iss-ndl-opac-national", "iss-ndl-opac-inprocess",
  "ndl-boj",
]);
const SEARCH_KEYS = ["any", "title", "creator", "publisher", "ndc", "from", "until", "isbn"];
// Give slow NDL searches more time, but cap each attempt to protect Workers.
// The Flutter client timeout must exceed this value.
const NDL_TIMEOUT_MS = 18000;

function createHandler({ request = (...args) => fetch(...args) } = {}) {
  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method_not_allowed" });
    }
    const input = req.query || {};
    const provider = String(input.dpid || "iss-ndl-opac-national");
    const cnt = Number(input.cnt || 20);
    const idx = Number(input.idx || 1);
    if (!PROVIDERS.has(provider) || !Number.isInteger(cnt) ||
        cnt < 1 || cnt > 50 || !Number.isInteger(idx) ||
        idx < 1 || idx + cnt > 501) {
      return res.status(400).json({ error: "invalid_catalog_query" });
    }
    if (input.mediatype != null && String(input.mediatype) !== "books") {
      return res.status(400).json({ error: "invalid_mediatype" });
    }
    const query = new URLSearchParams({
      dpid: provider,
      cnt: String(cnt),
      idx: String(idx),
      mediatype: "books",
    });
    for (const key of SEARCH_KEYS) {
      if (input[key] == null) continue;
      if (typeof input[key] !== "string" || input[key].length > 150) {
        return res.status(400).json({ error: "invalid_catalog_query" });
      }
      const value = input[key].trim();
      if (!value) continue;
      if (key === "ndc" && !/^\d+(?:\.\d+)?$/.test(value)) {
        return res.status(400).json({ error: "invalid_catalog_query" });
      }
      if ((key === "from" || key === "until") &&
          !/^\d{4}(?:-\d{2}(?:-\d{2})?)?$/.test(value)) {
        return res.status(400).json({ error: "invalid_catalog_query" });
      }
      if (key === "isbn" && !/^(?:\d{13}|\d{9}[\dXx])$/.test(value)) {
        return res.status(400).json({ error: "invalid_catalog_query" });
      }
      query.set(key, value);
    }
    // NDL's Japan-related foreign-language bibliography can be searched by
    // provider plus the already-enforced mediatype=books constraint.
    // Never allow unrestricted blank searches against larger providers.
    if (!SEARCH_KEYS.some(key => query.has(key)) && provider !== "ndl-boj") {
      return res.status(400).json({ error: "missing_catalog_search" });
    }
    try {
      const response = await request(`${NDL_URL}?${query}`, {
        headers: { Accept: "application/rss+xml, application/xml;q=0.9" },
        signal: AbortSignal.timeout(NDL_TIMEOUT_MS),
      });
      if (!response.ok) {
        res.setHeader("Cache-Control", "no-store");
        // Rate limiting / upstream temporary downtime should not be cached
        // or misrepresented as a valid empty RSS page.
        if (response.status === 429 || response.status === 503) {
          res.setHeader("Retry-After", "3");
          return res.status(503).json({ error: "ndl_unavailable" });
        }
        return res.status(502).json({ error: "ndl_unavailable" });
      }
      const xml = await response.text();
      if (xml.length > 2000000) {
        return res.status(502).json({ error: "ndl_response_too_large" });
      }
      res.setHeader("Content-Type", "application/xml; charset=utf-8");
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=600");
      return res.status(200).send(xml);
    } catch (error) {
      res.setHeader("Cache-Control", "no-store");
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        res.setHeader("Retry-After", "3");
        return res.status(504).json({ error: "ndl_timeout" });
      }
      return res.status(502).json({ error: "ndl_unavailable" });
    }
  };
}
const handler = createHandler();
handler.createHandler = createHandler;
module.exports = handler;
