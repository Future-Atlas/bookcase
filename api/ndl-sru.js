// Same-origin, bounded SRU/DC-NDL proxy for home language-labelled books.
// OpenSearch RSS omits the language field on actual NDL records. Only the
// richer official DC-NDL data is suitable for exact jpn/eng filtering.
const SRU_URL = "https://ndlsearch.ndl.go.jp/api/sru";
const PROVIDERS = new Set(["iss-ndl-opac-national", "iss-ndl-opac", "ndl-boj"]);
const SRU_TIMEOUT_MS = 18000;

function createHandler({ request = (...args) => fetch(...args) } = {}) {
  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method_not_allowed" });
    }
    const input = req.query || {};
    const provider = String(input.dpid || "");
    const title = input.title;
    const count = Number(input.cnt || 27);
    const start = Number(input.idx || 1);
    const from = input.from == null ? "" : input.from;
    if (!PROVIDERS.has(provider) || typeof title !== "string" ||
        !title.trim() || title.length > 80 || /["\\\r\n]/.test(title) ||
        !Number.isInteger(count) || count < 1 || count > 50 ||
        !Number.isInteger(start) || start < 1 || start + count > 501 ||
        typeof from !== "string" ||
        (from && !/^\d{4}(?:-\d{2}(?:-\d{2})?)?$/.test(from))) {
      return res.status(400).json({ error: "invalid_catalog_query" });
    }
    // Reject unknown query fields; the client only needs bounded title
    // searches, not arbitrary CQL or unbounded catalogue scans.
    const allowed = new Set(["dpid", "title", "cnt", "idx", "from"]);
    if (Object.keys(input).some(key => !allowed.has(key))) {
      return res.status(400).json({ error: "invalid_catalog_query" });
    }
    const cql = 'dpid="' + provider + '" AND title="' + title.trim() + '"' +
      (from ? ' AND from="' + from + '"' : "");
    const query = new URLSearchParams({
      operation: "searchRetrieve",
      version: "1.2",
      recordSchema: "dcndl",
      recordPacking: "xml",
      onlyBib: "true",
      query: cql,
      startRecord: String(start),
      maximumRecords: String(count),
    });
    try {
      const response = await request(SRU_URL + "?" + query, {
        headers: { Accept: "application/xml" },
        signal: AbortSignal.timeout(SRU_TIMEOUT_MS),
      });
      if (!response.ok) {
        res.setHeader("Cache-Control", "no-store");
        if (response.status === 429 || response.status === 503) {
          res.setHeader("Retry-After", "3");
          return res.status(503).json({ error: "ndl_unavailable" });
        }
        return res.status(502).json({ error: "ndl_unavailable" });
      }
      const xml = await response.text();
      if (xml.length > 4000000 ||
          !/<(?:[a-zA-Z]+:)?searchRetrieveResponse\b/i.test(xml) ||
          /<(?:[a-zA-Z]+:)?diagnostics\b/i.test(xml)) {
        res.setHeader("Cache-Control", "no-store");
        return res.status(502).json({ error: "ndl_sru_invalid_response" });
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
