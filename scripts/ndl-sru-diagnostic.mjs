// Inspect the official NDL SRU DC-NDL response without printing book data.
// This is a temporary stage diagnosis, not a production data harvester.
const probes = [
  ["jpn-national-sru", "iss-ndl-opac-national", "日本"],
  ["eng-holdings-sru", "iss-ndl-opac", "Tokyo"],
  ["eng-boj-sru", "ndl-boj", "Japan"],
];
for (const [name, provider, title] of probes) {
  const url = new URL("https://ndlsearch.ndl.go.jp/api/sru");
  url.search = new URLSearchParams({
    operation: "searchRetrieve", version: "1.2",
    query: `dpid="${provider}" AND title="${title}"`,
    recordSchema: "dcndl", recordPacking: "xml", onlyBib: "true",
    startRecord: "1", maximumRecords: "5",
  }).toString();
  const started = Date.now();
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(22000) });
    const xml = await response.text();
    const records = [...xml.matchAll(/<record(?:\\s[^>]*)?>([\\s\\S]*?)<\\/record>/gi)].map(m=>m[1]);
    const languageValues = [...xml.matchAll(/<dcterms:language\\b[^>]*>([\\s\\S]*?)<\\/dcterms:language>/gi)]
      .map(m => m[1].replace(/<[^>]*>/g,"").trim().toLowerCase());
    const exampleTags = records[0] ?
      [...new Set([...records[0].matchAll(/<([\\w:-]+)\\b/g)].map(m => m[1]))].filter(x=>/language|identifier|title|recordData/.test(x)).slice(0,12) : [];
    console.log(JSON.stringify({
      name, status: response.status, ms: Date.now()-started, bytes:xml.length,
      numberOfRecords:xml.match(/<numberOfRecords>([^<]*)<\\/numberOfRecords>/)?.[1],
      sruRecords: records.length, languageValues:languageValues.slice(0,20),
      languageTags:languageValues.length, isbnTypeAttributes:
        [...xml.matchAll(/rdf:datatype="[^"]*ISBN"/g)].length,
      firstRecordRelevantTags:exampleTags, responseIsError:!response.ok,
    }));
  } catch (error) {
    console.log(JSON.stringify({name, error:error?.name || "network-error", ms:Date.now()-started}));
  }
}
