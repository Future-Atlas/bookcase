// Compare NDL ISBN-bearing RSS records with existing openBD ONIX language data.
// Read-only. No book titles/ISBNs/user data are logged.
const base = "https://sharemarium-staging.sharemarium.workers.dev";
const searches = [
  ["japanese-national", "iss-ndl-opac-national", "日本"],
  ["english-boj", "ndl-boj", "Japan"],
];
function onixLanguageCodes(record) {
  const found = [];
  function visit(value) {
    if (Array.isArray(value)) return value.forEach(visit);
    if (value == null || typeof value !== "object") return;
    if ("LanguageCode" in value) {
      found.push({
        role: String(value.LanguageRole ?? ""),
        code: String(value.LanguageCode ?? "").toLowerCase(),
      });
    }
    Object.values(value).forEach(visit);
  }
  visit(record?.onix?.DescriptiveDetail);
  return found;
}
for (const [name, provider, title] of searches) {
  const url = new URL("/api/ndl", base);
  url.search = new URLSearchParams({
    dpid: provider, title, idx: "1", cnt: "27", mediatype: "books",
  }).toString();
  const started = Date.now();
  try {
    const r = await fetch(url, {signal:AbortSignal.timeout(20000)});
    if (!r.ok) {
      console.log(JSON.stringify({name,ndlStatus:r.status}));continue;
    }
    const xml = await r.text();
    const items = [...xml.matchAll(/<item\b[^>]*>[\s\S]*?<\/item>/gi)].map(m=>m[0]);
    const allIsbns = [];
    for (const item of items) {
      for (const [, attributes, inner] of item.matchAll(/<[\w:-]*identifier\b([^>]*)>([\s\S]*?)<\/[\w:-]*identifier>/gi)) {
        if (!/isbn/i.test(attributes)) continue;
        const value = inner.replace(/<[^>]*>/g, "").replace(/[^0-9Xx]/g, "");
        if (/^97[89][0-9]{10}$/.test(value) && !allIsbns.includes(value)) {
          allIsbns.push(value); break;
        }
      }
    }
    const isbns=allIsbns.slice(0,20);
    if(!isbns.length){
      console.log(JSON.stringify({name,ndlItems:items.length,validIsbns:0}));
      continue;
    }
    const enrichment = new URL("/api/openbd",base);
    enrichment.search=new URLSearchParams({isbn:isbns.join(",")}).toString();
    const e=await fetch(enrichment,{signal:AbortSignal.timeout(20000)});
    if(!e.ok){
      console.log(JSON.stringify({name,ndlItems:items.length,validIsbns:isbns.length,openbdStatus:e.status,elapsedMs:Date.now()-started}));
      continue;
    }
    const data=await e.json();
    let found=0, records=0;
    const textCodes={};
    const allCodes={};
    for(const record of Array.isArray(data)?data:[]){
      if(!record)continue;
      records++;
      const languages=onixLanguageCodes(record);
      if(languages.length)found++;
      for(const {role,code} of languages){
        const k=role+":"+code;
        allCodes[k]=(allCodes[k]??0)+1;
        if(role==="01")textCodes[code]=(textCodes[code]??0)+1;
      }
    }
    console.log(JSON.stringify({
      name, ndlItems:items.length, validIsbns:isbns.length,
      openbdRecords:records, withLanguage:found,
      textLanguages:textCodes, allLanguageCodes:allCodes,
      elapsedMs:Date.now()-started,
    }));
  }catch(error){
    console.log(JSON.stringify({name,error:error?.name||"error",elapsedMs:Date.now()-started}));
  }
}
