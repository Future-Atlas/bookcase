// Exact-ISBN jacket thumbnails through Google's documented keyless Dynamic Links.
// Keep a visible Google Books backlink with each image. No image rehosting.
const BASE = "https://books.google.com/books";
const MAX_ISBNS = 25;
const MAX_RESPONSE_BYTES = 256000;

function isbnList(raw) {
  if (typeof raw !== "string" || raw.length > 350) return null;
  const ids = raw.split(",").map(value => value.trim());
  if (!ids.length || ids.length > MAX_ISBNS ||
      ids.some(id => !/^(?:97[89]\d{10}|\d{9}[\dX])$/.test(id))) return null;
  return [...new Set(ids)];
}

function safeGoogleUrl(candidate, isImage = false) {
  if (typeof candidate !== "string" || candidate.length > 2048) return null;
  try {
    const url = new URL(candidate);
    if (url.username || url.password || url.port) return null;
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    if (isImage) {
      if (!["books.google.com", "books.googleusercontent.com"].includes(url.hostname)) return null;
    } else if (url.hostname !== "books.google.com") {
      return null;
    }
    url.protocol = "https:";
    return url.toString();
  } catch {
    return null;
  }
}

function parseDynamicLinks(body, requested) {
  if (typeof body !== "string" || body.length > MAX_RESPONSE_BYTES) {
    throw new Error("Invalid Google Books response size");
  }
  // JSONP is DATA, never code. Never eval a third-party response.
  const match = /^SharemariumBookCovers\(\s*([\s\S]*?)\s*\);?\s*$/.exec(body.trim());
  if (!match) throw new Error("Unexpected Google Books JSONP wrapper");
  const records = JSON.parse(match[1]);
  if (!records || typeof records !== "object" || Array.isArray(records)) {
    throw new Error("Invalid Google Books payload");
  }
  const covers = {};
  for (const isbn of requested) {
    const row = records["ISBN:" + isbn];
    if (!row || typeof row !== "object" ||
        row.bib_key !== "ISBN:" + isbn) continue;
    const coverUrl = safeGoogleUrl(row.thumbnail_url, true);
    const creditUrl = safeGoogleUrl(row.info_url);
    if (!coverUrl || !creditUrl) continue; // Never show an uncredited image.
    covers[isbn] = {coverUrl, creditUrl};
  }
  return covers;
}

function createHandler({ request = (...args) => fetch(...args) } = {}) {
  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({error: "method_not_allowed"});
    }
    const input = req.query || {};
    if (Object.keys(input).some(key => key !== "isbn")) {
      return res.status(400).json({error: "invalid_isbn_list"});
    }
    const ids = isbnList(input.isbn);
    if (!ids) return res.status(400).json({error: "invalid_isbn_list"});
    const query = new URLSearchParams({
      jscmd: "viewapi",
      bibkeys: ids.map(isbn => "ISBN:" + isbn).join(","),
      callback: "SharemariumBookCovers",
    });
    try {
      const upstream = await request(BASE + "?" + query, {
        headers: {Accept: "text/javascript, application/javascript, */*;q=0.5"},
        signal: AbortSignal.timeout(9000),
      });
      if (!upstream.ok) {
        res.setHeader("Cache-Control", "no-store");
        if (upstream.status === 429 || upstream.status === 503) {
          res.setHeader("Retry-After", "5");
          return res.status(503).json({error: "cover_lookup_unavailable"});
        }
        return res.status(502).json({error: "cover_lookup_unavailable"});
      }
      const data = parseDynamicLinks(await upstream.text(), ids);
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=300");
      return res.status(200).json({covers: data});
    } catch (error) {
      res.setHeader("Cache-Control", "no-store");
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        return res.status(504).json({error: "cover_lookup_timeout"});
      }
      return res.status(502).json({error: "cover_lookup_unavailable"});
    }
  };
}
const handler = createHandler();
handler.createHandler = createHandler;
handler.isbnList = isbnList;
handler.parseDynamicLinks = parseDynamicLinks;
module.exports = handler;
