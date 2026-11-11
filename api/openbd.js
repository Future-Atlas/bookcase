// Same-origin proxy for ISBN-only openBD metadata enrichment.
// No permanent cache: the provider can update or withdraw records and covers.
const OPENBD_URL = "https://api.openbd.jp/v1/get";
function createHandler({ request = (...args) => fetch(...args) } = {}) {
  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method_not_allowed" });
    }
    const raw = req.query?.isbn;
    if (typeof raw !== "string" || raw.length > 350) {
      return res.status(400).json({ error: "invalid_isbn_list" });
    }
    const ids = raw.split(",").map(x => x.trim());
    if (!ids.length || ids.length > 25 ||
        ids.some(x => !/^\d{13}$/.test(x))) {
      return res.status(400).json({ error: "invalid_isbn_list" });
    }
    const unique = [...new Set(ids)];
    try {
      const response = await request(`${OPENBD_URL}?isbn=${unique.join(",")}`, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(12000),
      });
      if (!response.ok) {
        res.setHeader("Cache-Control", "no-store");
        return res.status(502).json({ error: "openbd_unavailable" });
      }
      const body = await response.text();
      if (body.length > 3000000) {
        return res.status(502).json({ error: "openbd_response_too_large" });
      }
      // Validate shape before exposing or caching arbitrary upstream data.
      const decoded = JSON.parse(body);
      if (!Array.isArray(decoded) || decoded.length !== unique.length) {
        throw new Error("Invalid openBD response");
      }
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=600");
      return res.status(200).send(body);
    } catch {
      res.setHeader("Cache-Control", "no-store");
      return res.status(502).json({ error: "openbd_unavailable" });
    }
  };
}
const handler = createHandler();
handler.createHandler = createHandler;
module.exports = handler;
