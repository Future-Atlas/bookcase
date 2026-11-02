// One-shot, read-only check for an official single-record NDL metadata path.
// The home screen is NOT changed by this probe. Keep the NDL load bounded:
// one cached OpenSearch read and at most one GetRecord call, no retries.
// Log only status, timing and presence of language and ISBN.
const base = "https://sharemarium-staging.sharemarium.workers.dev";
const url = new URL("/api/ndl",base);
url.search = new URLSearchParams({
  dpid:"iss-ndl-opac",idx:"1",cnt:"27",mediatype:"books",title:"Tokyo",
}).toString();
try {
  const started=Date.now();
  const rssResponse=await fetch(url,{signal:AbortSignal.timeout(20000)});
  const xml=await rssResponse.text();
  console.log(JSON.stringify({
    step:"opensearch",status:rssResponse.status,ms:Date.now()-started,
    edgeCache:rssResponse.headers.get("cf-cache-status"),
    items:(xml.match(/<item\b/g)||[]).length,
  }));
  if(!rssResponse.ok)process.exit(0);
  const itemMatches=[...xml.matchAll(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/gi)]
    .map(m=>m[0]);
  const typedIsbnItem=itemMatches.find(item=>
    /<[\w:-]*identifier\b[^>]*isbn[^>]*>/i.test(item));
  const id=(typedIsbnItem||itemMatches[0]||"")
    .match(/\bR\d{6,}-I\d{5,}\b/)?.[0];
  if(!id){console.log(JSON.stringify({step:"oai",status:"missing-record-id"}));process.exit(0)}
  const api=new URL("https://ndlsearch.ndl.go.jp/api/oaipmh");
  api.search=new URLSearchParams({
    verb:"GetRecord",metadataPrefix:"dcndl",
    identifier:"oai:ndlsearch.ndl.go.jp:"+id,
  }).toString();
  const start=Date.now();
  const response=await fetch(api,{signal:AbortSignal.timeout(12000)});
  const payload=await response.text();
  const langs=[...payload.matchAll(/<[\w:-]*language\b[^>]*>([\s\S]*?)<\/[\w:-]*language>/gi)]
    .map(m=>m[1].replace(/<[^>]*>/g,"").trim().toLowerCase());
  const isbn=(payload.match(/<[\w:-]*identifier\b[^>]*isbn[^>]*>/gi)||[]).length;
  console.log(JSON.stringify({
    step:"oai",status:response.status,ms:Date.now()-start,bytes:payload.length,
    hasGetRecord:!!payload.match(/<GetRecord[\s>]/),
    hasOaiError:!!payload.match(/<error[\s>]/),
    languages:langs.slice(0,8),isbnElements:isbn
  }));
}catch(error){console.log(JSON.stringify({error:error?.name||"network_error"}))}
