// Read-only staging diagnosis for the home Japanese/English catalogue.
// Print structural counts only, not book titles or user data.
// Run manually with: node scripts/ndl-stage-diagnostic.mjs
const origin = process.env.NDL_STAGE_ORIGIN ||
  "https://sharemarium-staging.sharemarium.workers.dev";
const cases = [
  ["japanese-national", "iss-ndl-opac-national", "日本"],
  ["english-holdings", "iss-ndl-opac", "Tokyo"],
  ["english-bibliography", "ndl-boj", "Japan"],
];
for (const [name, provider, title] of cases) {
  const url = new URL("/api/ndl", origin);
  url.search = new URLSearchParams({
    dpid: provider, idx: "1", cnt: "27", mediatype: "books", title,
  }).toString();
  const started = Date.now();
  try {
    const response = await fetch(url, {
      headers: { Accept: "application/xml" },
      signal: AbortSignal.timeout(23000),
    });
    const xml = await response.text();
    const items = [...xml.matchAll(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/gi)]
      .map(match => match[0]);
    const withIsbn = [];
    const languageCounts = new Map();
    let noLanguage = 0;
    let onlyJapanese = 0;
    let onlyEnglish = 0;
    for (const item of items) {
      // Match the same evidence as the Dart filter: identifier typed as ISBN
      // and exactly one explicit language code after de-duplication.
      const identifiers = [...item.matchAll(/<([\w:-]*identifier)\b([^>]*)>([\s\S]*?)<\/\1>/gi)];
      const isbn = identifiers.some(([full, _tag, attrs, inner]) => {
        const simple = inner.replace(/<[^>]+>/g, "").replace(/[\s\u3000\-‐-‒–—―−]/g, "");
        return /^(?:97[89][0-9]{10}|[0-9]{9}[0-9Xx])$/.test(simple) ||
          (/isbn/i.test(attrs + inner) && /(?:97[89][0-9]{10}|[0-9]{9}[0-9Xx])/.test(simple));
      });
      const languages = [...new Set(
        [...item.matchAll(/<[\w:-]*language\b[^>]*>([\s\S]*?)<\/[\w:-]*language>/gi)]
          .map(m => m[1].replace(/<[^>]*>/g, "").trim().toLowerCase())
          .filter(Boolean),
      )];
      if (!languages.length) noLanguage++;
      const normalized = languages.join(" ");
      languageCounts.set(normalized || "(missing)", (languageCounts.get(normalized || "(missing)") || 0) + 1);
      if (isbn) {
        withIsbn.push(true);
        if (["jpn", "ja"].includes(normalized)) onlyJapanese++;
        if (normalized === "eng") onlyEnglish++;
      }
    }
    const tagExample = items[0] ?
      [...new Set([...items[0].matchAll(/<([\w:-]+)\b/g)].map(m => m[1]))].slice(0, 18) : [];
    console.log(JSON.stringify({
      name, status: response.status, ms: Date.now() - started,
      cfCache: response.headers.get("cf-cache-status"),
      age: response.headers.get("age"),
      contentType: response.headers.get("content-type"),
      bytes: xml.length, rssItems: items.length, withIsbn: withIsbn.length,
      noLanguage, eligibleJapanese: onlyJapanese, eligibleEnglish: onlyEnglish,
      languageCounts: Object.fromEntries([...languageCounts].slice(0, 12)),
      firstItemTags: tagExample,
      errorCode: !response.ok ? xml.slice(0, 120) : undefined,
    }));
  } catch (error) {
    console.log(JSON.stringify({name, error: error?.name || "fetch_error", ms: Date.now() - started}));
  }
}
