// Temporary live sample probe, removed before merge.
const isbns=["9784488402327","9784413299084","9784101010014"];
async function probe(label,url,mode="json"){
  const t=Date.now();
  try{
    const res=await fetch(url,{method:mode==="head"?"HEAD":"GET",signal:AbortSignal.timeout(12000),headers:{Accept:mode==="json"?"application/json":"*/*"}});
    let details={};
    if(mode==="json"&&res.ok){
      const body=await res.json();
      if(Array.isArray(body)){
        details={count:body.length,entries:body.map((rec,i)=>{
          const links=JSON.stringify(rec?.onix?.CollateralDetail||{}).match(/https?:[^",}]+/g)||[];
          return {isbn:isbns[i],present:!!rec,summaryCover:!!rec?.summary?.cover,
            coverHost:rec?.summary?.cover?new URL(rec.summary.cover).host:null,
            onixLinks:links.length};
        })};
      } else if(body&&typeof body==="object"){
        details={totalItems:body.totalItems,matched:(body.items||[]).map(v=>({
          ids:(v.volumeInfo?.industryIdentifiers||[]).map(x=>x.identifier),
          hasCover:!!v.volumeInfo?.imageLinks?.thumbnail,
          urlHost:v.volumeInfo?.imageLinks?.thumbnail?
            new URL(v.volumeInfo.imageLinks.thumbnail.replace(/^http:/,"https:")).host:null
        })).slice(0,4)};
      }
    }
    console.log(JSON.stringify({label,status:res.status,timeMs:Date.now()-t,type:res.headers.get("content-type"),...details}));
  }catch(e){console.log(JSON.stringify({label,error:e.name,message:String(e.message).slice(0,100),timeMs:Date.now()-t}));}
}
await probe("staging-openbd","https://sharemarium-staging.sharemarium.workers.dev/api/openbd?isbn="+isbns.join(","));
await probe("upstream-openbd","https://api.openbd.jp/v1/get?isbn="+isbns.join(","));
await probe("google-books-2026a","https://www.googleapis.com/books/v1/volumes?q=isbn%3A"+isbns[0]+"&maxResults=3");
await probe("google-books-2026b","https://www.googleapis.com/books/v1/volumes?q=isbn%3A"+isbns[1]+"&maxResults=3");
for(const isbn of [isbns[0],isbns[1],"9780140328721"]){
 await probe("openlibrary-"+isbn,"https://covers.openlibrary.org/b/isbn/"+isbn+"-M.jpg?default=false","head");
}

for(const key of ["9784488402327","9784413299084","9780140328721"]){
 const query=new URLSearchParams({bibkeys:"ISBN:"+key,jscmd:"viewapi",callback:"SharemariumProbe"});
 const t=Date.now();
 try{
  const r=await fetch("https://books.google.com/books?"+query,{signal:AbortSignal.timeout(9000)});
  const body=await r.text();
  console.log(JSON.stringify({label:"google-dynamic-"+key,status:r.status,ms:Date.now()-t,bytes:body.length,
    thumbnailMention:body.includes("thumbnail_url"),head:body.slice(0,100).replace(/[\r\n]/g," ")}));
 }catch(e){console.log(JSON.stringify({label:"google-dynamic-"+key,error:e.name,ms:Date.now()-t}));}
}
