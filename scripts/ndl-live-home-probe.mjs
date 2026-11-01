// Temporary live regression probe; remove from the release diff.
const base = "https://sharemarium-staging.sharemarium.workers.dev/api/ndl";
const date = new Date(Date.now() - 90*86400000).toISOString().slice(0,10);
for (const provider of ["iss-ndl-opac-inprocess", "iss-ndl-opac-national"]) {
  const url = new URL(base);
  url.search = new URLSearchParams({
    dpid:provider, idx:"1", cnt:"27", mediatype:"books", from:date,
  }).toString();
  const t=Date.now();
  try {
    const response=await fetch(url,{signal:AbortSignal.timeout(23000)});
    const xml=await response.text();
    const start=xml.indexOf("<item>");
    const end=xml.indexOf("</item>",start);
    const item=start>=0 && end>start?xml.slice(start,end+7):"";
    console.log(JSON.stringify({
      provider,status:response.status,ms:Date.now()-t,
      bytes:xml.length,items:(xml.match(/<item(?:\s|>)/g)||[]).length,
      isbnTextCount:(xml.match(/isbn/gi)||[]).length,
      firstItem:item.slice(0,1700).replace(/[\r\n]+/g," "),
      error:response.ok?null:xml.slice(0,120)
    }));
  } catch(e) {
    console.log(JSON.stringify({provider,error:e.name,detail:String(e.message).slice(0,85),ms:Date.now()-t}));
  }
}
