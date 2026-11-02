// Read-only deploy smoke for the restored *staging-only* Rakuten catalog.
// Never print book payloads, credentials or full upstream URLs.
const base = process.env.RAKUTEN_STAGE_BASE;
if (!base || !/^https:\/\//.test(base)) {
  throw new Error("RAKUTEN_STAGE_BASE must be an HTTPS staging Worker URL");
}
const sections = [
  { section: "japanese-books", endpoint: "book", booksGenreId: "001" },
  { section: "foreign-books", endpoint: "foreign", booksGenreId: "005" },
];
let failures = 0;
for (const sample of sections) {
  const uri = new URL("/api/rakuten", base);
  uri.searchParams.set("endpoint", sample.endpoint);
  uri.searchParams.set("booksGenreId", sample.booksGenreId);
  uri.searchParams.set("hits", "3");
  uri.searchParams.set("page", "1");
  const start = Date.now();
  try {
    const response = await fetch(uri, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(22000),
    });
    let count = 0;
    if (response.ok) {
      const json = await response.json();
      if (!Array.isArray(json.Items)) throw new Error("invalid_items");
      count = json.Items.length;
    } else {
      failures++;
    }
    console.log(JSON.stringify({
      section: sample.section,
      status: response.status,
      books: count,
      ms: Date.now() - start,
    }));
  } catch {
    failures++;
    console.log(JSON.stringify({
      section: sample.section,
      status: "unavailable",
      books: 0,
      ms: Date.now() - start,
    }));
  }
}
if (failures > 0) process.exitCode = 1;
