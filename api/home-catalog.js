// Low-volume, same-origin book discovery without a Supabase catalogue.
// A work can contain editions in many languages: verify the selected edition
// and its ISBN via ONE batched Open Library Books request, never by inference.
// No Open Library cover images are requested or stored.
const SEARCH_URL = "https://openlibrary.org/search.json";
const DETAILS_URL = "https://openlibrary.org/api/books.json";
const WINDOW = 27;
const TOPICS = Object.freeze({
  jpn: new Set(["日本", "物語", "文学"]),
  eng: new Set(["Japan", "Tokyo"]),
});
const SEARCH_FIELDS = [
  "key", "title", "author_name", "editions", "editions.key",
  "editions.title", "editions.language",
].join(",");
const HEADERS = {
  Accept: "application/json",
  "User-Agent": "Sharemarium book discovery (https://www.sharemarium.com/contact)",
};

function isbn13Valid(value) {
  if (typeof value !== "string" || !/^97[89]\d{10}$/.test(value)) return false;
  let sum = 0;
  for (let i = 0; i < 12; i++) {
    sum += Number(value[i]) * (i % 2 ? 3 : 1);
  }
  return (10 - sum % 10) % 10 === Number(value[12]);
}

function toIsbn13(isbn10) {
  if (typeof isbn10 !== "string" || !/^\d{9}[\dXx]$/.test(isbn10)) {
    return null;
  }
  let sum = 0;
  for (let i = 0; i < 10; i++) {
    const digit = isbn10[i].toUpperCase() === "X" ? 10 : Number(isbn10[i]);
    sum += digit * (10 - i);
  }
  if (sum % 11 !== 0) return null;
  const first = "978" + isbn10.slice(0, 9);
  let sum13 = 0;
  for (let i = 0; i < 12; i++) {
    sum13 += Number(first[i]) * (i % 2 ? 3 : 1);
  }
  return first + String((10 - sum13 % 10) % 10);
}

function editionIsbn(details) {
  for (const value of Array.isArray(details?.isbn_13) ? details.isbn_13 : []) {
    if (isbn13Valid(value)) return value;
  }
  for (const value of Array.isArray(details?.isbn_10) ? details.isbn_10 : []) {
    const converted = toIsbn13(value);
    if (converted) return converted;
  }
  return null;
}

function hasOnlyLanguage(details, code) {
  if (!Array.isArray(details?.languages)) return false;
  const codes = [...new Set(details.languages.map(entry => {
    const path = typeof entry === "string" ? entry : entry?.key;
    return typeof path === "string" ? path.split("/").pop()?.toLowerCase() : "";
  }).filter(Boolean))];
  return codes.length === 1 && codes[0] === code;
}

function selectBooks(searchData, detailsData, language) {
  const books = [];
  const seen = new Set();
  const works = Array.isArray(searchData?.docs) ? searchData.docs : [];
  for (const work of works) {
    const edition = work?.editions?.docs?.[0];
    const match = /^\/books\/(OL\d+M)$/.exec(edition?.key || "");
    if (!match) continue;
    const key = "OLID:" + match[1];
    const details = detailsData?.[key]?.details;
    if (!details || !hasOnlyLanguage(details, language)) continue;
    // Require a verified, edition-specific ISBN. Never borrow an ISBN from
    // the work, which can include translations in other languages.
    const isbn = editionIsbn(details);
    if (!isbn || !seen.add(isbn)) continue;
    const title = String(details.title || edition.title || "").trim();
    if (!title) continue;
    const author = Array.isArray(work.author_name) &&
      typeof work.author_name[0] === "string"
      ? work.author_name[0].slice(0, 180) : "";
    const publisher = Array.isArray(details.publishers) &&
      typeof details.publishers[0] === "string"
      ? details.publishers[0].slice(0, 180) : "";
    books.push({
      isbn, id: isbn, title: title.slice(0, 250),
      author, publisher, pubDate: String(details.publish_date || "").slice(0, 60),
      languageCode: language, catalogSource: "openlibrary",
      catalogUrl: "https://openlibrary.org/books/" + match[1],
    });
  }
  return books;
}

function createHandler({
  request = (...args) => fetch(...args),
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
} = {}) {
  return async (req, res) => {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method_not_allowed" });
    }
    const params = req.query || {};
    const lang = params.lang;
    const topic = params.topic;
    const page = Number(params.page);
    const allowed = new Set(["lang", "topic", "page"]);
    if (typeof lang !== "string" || typeof topic !== "string" ||
        !TOPICS[lang]?.has(topic) || !Number.isInteger(page) ||
        page < 1 || page > 5 ||
        Object.keys(params).some(k => !allowed.has(k))) {
      res.setHeader("Cache-Control", "no-store");
      return res.status(400).json({ error: "invalid_home_catalog_query" });
    }
    const started = Date.now();
    const query = new URLSearchParams({
      q: "language:" + lang + " AND isbn:* AND title:" + topic,
      page: String(page),
      limit: String(WINDOW),
      fields: SEARCH_FIELDS,
    });
    try {
      const searchResponse = await request(SEARCH_URL + "?" + query, {
        headers: HEADERS,
        signal: AbortSignal.timeout(9000),
      });
      if (!searchResponse.ok) {
        res.setHeader("Cache-Control", "no-store");
        if (searchResponse.status === 429 || searchResponse.status === 503) {
          res.setHeader("Retry-After", "5");
          return res.status(503).json({ error: "catalog_source_busy" });
        }
        return res.status(502).json({ error: "catalog_source_unavailable" });
      }
      const data = await searchResponse.json();
      if (!Array.isArray(data?.docs)) throw new Error("invalid_search_response");
      const lookupIds = [...new Set(data.docs
        .map(work => /^\/books\/(OL\d+M)$/.exec(work?.editions?.docs?.[0]?.key || "")?.[1])
        .filter(Boolean))];
      let books = [];
      if (lookupIds.length) {
        // Open Library's unidentified default is 1 req/s. Keep searches
        // small and ensure this sequential batch is not sent too quickly.
        await sleep(Math.max(0, 1150 - (Date.now() - started)));
        const query = new URLSearchParams({
          bibkeys: lookupIds.map(id => "OLID:" + id).join(","),
          jscmd: "details",
        });
        const detailResponse = await request(DETAILS_URL + "?" + query, {
          headers: HEADERS,
          signal: AbortSignal.timeout(9000),
        });
        if (!detailResponse.ok) {
          res.setHeader("Cache-Control", "no-store");
          if (detailResponse.status === 429 || detailResponse.status === 503) {
            res.setHeader("Retry-After", "5");
            return res.status(503).json({ error: "catalog_source_busy" });
          }
          return res.status(502).json({ error: "catalog_source_unavailable" });
        }
        const details = await detailResponse.json();
        if (!details || Array.isArray(details) || typeof details !== "object") {
          throw new Error("invalid_details_response");
        }
        books = selectBooks(data, details, lang);
      }
      const total = Number(data.numFound ?? data.num_found ?? 0);
      res.setHeader("Cache-Control", "public, max-age=0, s-maxage=600");
      return res.status(200).json({
        books, rawCount: data.docs.length,
        hasMore: Number.isFinite(total) && page * WINDOW < total &&
          data.docs.length === WINDOW,
        catalogSource: "openlibrary",
      });
    } catch (error) {
      res.setHeader("Cache-Control", "no-store");
      if (error?.name === "TimeoutError" || error?.name === "AbortError") {
        res.setHeader("Retry-After", "5");
        return res.status(504).json({ error: "catalog_source_timeout" });
      }
      return res.status(502).json({ error: "catalog_source_unavailable" });
    }
  };
}

const handler = createHandler();
handler.createHandler = createHandler;
handler._test = { isbn13Valid, toIsbn13, editionIsbn, hasOnlyLanguage, selectBooks };
module.exports = handler;
