// Same-origin, read-only NDL OpenSearch proxy. Never accept arbitrary upstream URLs
// or provider IDs: partner-supplied records can have different reuse terms.
const NDL_URL = "https://ndlsearch.ndl.go.jp/api/opensearch";
const PROVIDERS = new Set([
  "iss-ndl-opac-national", "iss-ndl-opac-inprocess",
]);
const SEARCH_KEYS = ["any", "title", "creator", "publisher", "ndc", "from", "until", "isbn"];

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
    const query = new URLSearchParams({ dpid: provider, cnt: String(cnt), idx: String(idx) });
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
    if (!SEARCH_KEYS.some(key => query.has(key))) {
      return res.status(400).json({ error: "missing_catalog_search" });
    }
    try {
      const response = await request(`${NDL_URL}?${query}`, {
        headers: { Accept: "application/rss+xml, application/xml;q=0.9" },
        signal: AbortSignal.timeout(12000),
      });
      if (!response.ok) {
        res.setHeader("Cache-Control", "no-store");
        return res.status(502).json({ error: "ndl_unavailable" });
      }
      const xml = await response.text();
      if (xml.length > 2000000) {
        return res.status(502).json({ error: "ndl_response_too_large" });
      }
      res.setHeader("Content-Type", "application/xml; charset=utf-8");
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=600");
      return res.status(200).send(xml);
    } catch {
      res.setHeader("Cache-Control", "no-store");
      return res.status(502).json({ error: "ndl_unavailable" });
    }
  };
}
const handler = createHandler();
handler.createHandler = createHandler;
module.exports = handler;
