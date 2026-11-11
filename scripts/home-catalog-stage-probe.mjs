// Staging-only, read-only smoke check of language-verified home JSON.
// Logs only counts, timing and cache status, never book titles/ISBN/user data.
// Does not fail a deployment on a transient third-party metadata outage.
const origin=process.env.HOME_CATALOG_STAGE_BASE;
if(!origin)process.exit(0);
const sources=[
  ["japanese","jpn","日本"],
  ["english","eng","Japan"],
];
for(const [label,lang,topic] of sources){
  const target=new URL("/api/home-catalog",origin);
  target.search=new URLSearchParams({lang,topic,page:"1"}).toString();
  const start=Date.now();
  try{
    const response=await fetch(target,{signal:AbortSignal.timeout(25000)});
    let count=0,strict=0,invalid=0;
    if(response.ok){
      const payload=await response.json();
      const books=Array.isArray(payload.books)?payload.books:[];
      count=books.length;
      for(const book of books){
        const language=book?.languageCode;
        const isbn=book?.isbn;
        const valid=language===lang && typeof isbn==="string" &&
          /^97[89]\d{10}$/.test(isbn) && typeof book?.title==="string";
        if(valid)strict++;else invalid++;
      }
    }
    console.log(JSON.stringify({
      section:label,status:response.status,ms:Date.now()-start,
      books:count,strict,invalid,
      cfCache:response.headers.get("cf-cache-status"),
      cacheControl:response.headers.get("cache-control"),
    }));
  }catch(e){
    console.log(JSON.stringify({section:label,
      error:e?.name||"network_error",ms:Date.now()-start}));
  }
  await new Promise(resolve=>setTimeout(resolve,1300));
}
