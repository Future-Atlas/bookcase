// Temporary, bounded read-only check of work->edition language/ISBN coverage.
// One request per language, no retries. No book titles or ISBNs in CI logs.
const queries = [
  ["japanese", "language:jpn AND isbn:* AND title:日本", "jpn"],
  ["english", "language:eng AND isbn:* AND title:Japan", "eng"],
];
for (const [label, q, lang] of queries) {
  const url = new URL("https://openlibrary.org/search.json");
  url.search = new URLSearchParams({
    q, limit:"20", page:"1", fields:[
      "key","title","author_name","editions","editions.key",
      "editions.title","editions.language","editions.isbn_13",
      "editions.isbn_10","editions.publish_date","editions.publisher",
    ].join(","),
  }).toString();
  const started = Date.now();
  try {
    const response = await fetch(url, {
      headers:{Accept:"application/json",
        "User-Agent":"Sharemarium book discovery / low-volume evaluation (https://www.sharemarium.com)"},
      signal:AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      console.log(JSON.stringify({label,status:response.status,
        ms:Date.now()-started}));continue;
    }
    const data=await response.json();
    let editions=0,matchingLanguage=0,validIsbn=0,strictBoth=0;
    const languages={};
    const docs=Array.isArray(data.docs)?data.docs:[];
    let keys=[];
    for(const work of docs){
      const options=work.editions?.docs??[];
      if(!keys.length && options.length)keys=Object.keys(options[0]);
      for(const edition of options){
        editions++;
        const codes=Array.isArray(edition.language)?edition.language:[];
        for(const code of codes)languages[String(code)]=(languages[String(code)]??0)+1;
        const exact= codes.length===1 && codes[0]===lang;
        if(exact)matchingLanguage++;
        const isbn13=(edition.isbn_13??[]).find(x=>/^97[89]\d{10}$/.test(x));
        if(isbn13)validIsbn++;
        if(isbn13&&exact)strictBoth++;
      }
    }
    // Batch edition detail lookup: one request for all selected OL edition IDs.
    const selected = docs.map(work=>work.editions?.docs?.[0]?.key)
      .filter(value=>typeof value==="string" && /^\/books\/OL\d+M$/.test(value))
      .slice(0,20);
    let detailStatus = null, detailCount=0, detailLanguageMatch=0;
    let detailISBN13=0, detailISBN10=0, detailEligible=0;
    let detailKeys=[], detailLanguageShapes=[];
    if(selected.length) {
      await new Promise(resolve=>setTimeout(resolve,1450));
      const detailUrl=new URL("https://openlibrary.org/api/books.json");
      detailUrl.search=new URLSearchParams({
        bibkeys:selected.map(key=>"OLID:"+key.split("/").pop()).join(","),
        jscmd:"details",
      }).toString();
      const detailResponse=await fetch(detailUrl,{
        headers:{Accept:"application/json",
          "User-Agent":"Sharemarium book discovery / low-volume evaluation (https://www.sharemarium.com)"},
        signal:AbortSignal.timeout(15000),
      });
      detailStatus=detailResponse.status;
      if(detailResponse.ok) {
        const all=await detailResponse.json();
        detailCount=Object.keys(all).length;
        for(const [name, value] of Object.entries(all)){
          const detail=value?.details??value??{};
          if(!detailKeys.length)detailKeys=Object.keys(detail).slice(0,30);
          const languages=Array.isArray(detail.languages)?detail.languages:[];
          if(!detailLanguageShapes.length&&languages.length)
            detailLanguageShapes=languages.slice(0,3);
          const codes=languages.map(v=>typeof v==="string"?v:v?.key??"")
             .map(v=>v.split("/").pop().toLowerCase()).filter(Boolean);
          const match=codes.length===1&&codes[0]===lang;
          if(match)detailLanguageMatch++;
          const hasIsbn=(detail.isbn_13??[]).some(x=>/^97[89]\d{10}$/.test(x));
          if(hasIsbn)detailISBN13++;
          const hasIsbn10=(detail.isbn_10??[]).some(x=>/^\d{9}[\dXx]$/.test(x));
          if(hasIsbn10)detailISBN10++;
          if(match&&(hasIsbn||hasIsbn10))detailEligible++;
        }
      }
    }
    console.log(JSON.stringify({label,status:response.status,
      ms:Date.now()-started,works:docs.length,
      declaredMatches:data.numFound??data.num_found,
      editions,matchingLanguage,validIsbn,strictBoth,
      languages,editionKeys:keys,
      detailStatus,detailCount,detailLanguageMatch,detailISBN13,detailISBN10,detailEligible,
      detailKeys,detailLanguageShapes}));
  }catch(e){console.log(JSON.stringify({label,error:e?.name||"network_error",ms:Date.now()-started}));}
  await new Promise(resolve=>setTimeout(resolve,1500));
}
