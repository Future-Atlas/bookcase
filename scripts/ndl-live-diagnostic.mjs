// Temporary, low-volume NDL diagnostics. No API keys or personal data.
const base = "https://ndlsearch.ndl.go.jp/api/opensearch";
const staging = "https://sharemarium-staging.sharemarium.workers.dev/api/ndl";
const recent = new URLSearchParams({
  dpid:"iss-ndl-opac-national",idx:"1",cnt:"10",mediatype:"books",from:"2026-08-03",
});
const title = new URLSearchParams({
  dpid:"iss-ndl-opac-national",idx:"1",cnt:"10",mediatype:"books",title:"文学",
});
const oai = new URLSearchParams({
  verb:"ListRecords", metadataPrefix:"oai_dc",set:"iss-ndl-opac-national",
  from:"2026-10-29",until:"2026-10-30",
});
const cases = [
  ["staging-recent", staging+"?"+recent],
  ["ndl-recent",base+"?"+recent],
  ["ndl-title",base+"?"+title],
  ["ndl-oai", "https://ndlsearch.ndl.go.jp/api/oaipmh?"+oai],
];
for (const [name,url] of cases) {
  const start=Date.now();
  try {
    const response=await fetch(url,{signal:AbortSignal.timeout(22000),headers:{Accept:"application/xml,text/xml;q=0.9"}});
    const text=await response.text();
    const count=(text.match(/<item(?:\s|>)/g)||[]).length;
    const records=(text.match(/<record(?:\s|>)/g)||[]).length;
    const isbn=(text.match(/isbn/gi)||[]).length;
    const total=text.match(/<[^>]*totalResults>(\d+)<\//);
    console.log(JSON.stringify({name,status:response.status,ms:Date.now()-start,bytes:text.length,
      contentType:response.headers.get("content-type"),itemCount:count,recordCount:records,
      isbnMentions:isbn,total:total?.[1]??null,
      error:response.ok?null:text.slice(0,110).replace(/[\r\n]/g," ")}));
  } catch(error) {
    console.log(JSON.stringify({name,error:error.name,ms:Date.now()-start,detail:String(error.message).slice(0,90)}));
  }
}
