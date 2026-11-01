// Bounded OAI-PMH harvester for NDL's dedicated new-bibliography set.
// Unlike OpenSearch publication-date searches, OAI date fields are datestamps.
const ENDPOINT = "https://ndlsearch.ndl.go.jp/api/oaipmh";
const SETS = new Set(["iss-ndl-opac-inprocess", "iss-ndl-opac-national"]);
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIMEOUT_MS = 18000;
const MAX_RESPONSE = 2500000;
const NO_STORE = "no-store";

function parseDate(text) {
  if (typeof text !== "string" || !DATE_PATTERN.test(text)) return null;
  const date = new Date(text + "T00:00:00Z");
  return Number.isFinite(date.getTime()) &&
    date.toISOString().slice(0, 10) === text ? date : null;
}

function buildOaiUrl(params, clock = () => Date.now()) {
  const provider = params.set || "iss-ndl-opac-inprocess";
  if (!SETS.has(provider)) return null;
  const token = params.token;
  const query = new URLSearchParams({verb: "ListRecords"});
  if (token != null) {
    // The continuation token is opaque and exclusive, per OAI-PMH.
    if (typeof token !== "string" || token.length < 1 || token.length > 1024 ||
        !/^[\x21-\x7e]+$/.test(token)) return null;
    if (params.from || params.until) return null;
    query.set("resumptionToken", token);
  } else {
    const from = parseDate(params.from);
    const until = parseDate(params.until);
    if (!from || !until || from > until) return null;
    const now = clock();
    if (from.getTime() < now - 1000 * 86400 * 90 ||
        until.getTime() > now + 1000 * 86400 * 2 ||
        until.getTime() - from.getTime() > 1000 * 86400 * 14) return null;
    query.set("metadataPrefix", "oai_dc");
    query.set("set", provider);
    query.set("from", params.from);
    query.set("until", params.until);
  }
  return ENDPOINT + "?" + query;
}

function createHandler({ request = (...args) => fetch(...args), clock = () => Date.now() } = {}) {
  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({error: "method_not_allowed"});
    }
    const input = req.query || {};
    const keys = Object.keys(input);
    if (keys.some(key => !["set", "from", "until", "token"].includes(key)) ||
        keys.some(key => Array.isArray(input[key]))) {
      return res.status(400).json({error: "invalid_new_arrivals_query"});
    }
    const url = buildOaiUrl(input, clock);
    if (!url) return res.status(400).json({error: "invalid_new_arrivals_query"});
    try {
      const upstream = await request(url, {
        headers: {Accept: "application/xml, text/xml;q=0.9"},
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (!upstream.ok) {
        res.setHeader("Cache-Control", NO_STORE);
        if (upstream.status === 429 || upstream.status === 503) {
          res.setHeader("Retry-After", "3");
          return res.status(503).json({error: "ndl_unavailable"});
        }
        return res.status(502).json({error: "ndl_unavailable"});
      }
      const xml = await upstream.text();
      if (xml.length > MAX_RESPONSE ||
          !/<(?:[\w-]+:)?OAI-PMH(?:\s|>)/.test(xml)) {
        res.setHeader("Cache-Control", NO_STORE);
        return res.status(502).json({error: "invalid_ndl_oai_response"});
      }
      res.setHeader("Content-Type", "application/xml; charset=utf-8");
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=900");
      return res.status(200).send(xml);
    } catch (error) {
      res.setHeader("Cache-Control", NO_STORE);
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        res.setHeader("Retry-After", "3");
        return res.status(504).json({error: "ndl_timeout"});
      }
      return res.status(502).json({error: "ndl_unavailable"});
    }
  };
}
const handler = createHandler();
handler.createHandler = createHandler;
handler.buildOaiUrl = buildOaiUrl;
module.exports = handler;
