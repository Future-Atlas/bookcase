import { writeFileSync } from 'node:fs';

// One-time, read-only sample from the public staging app. Image URLs are
// counted as metadata, NOT proof of successful rendering in Chrome.
const base = 'https://sharemarium-staging.sharemarium.workers.dev';
const target = 100;
const sample = new Map();
const ndlWindows = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const cutoff = days => new Date(Date.now() - days*86400000).toISOString().slice(0,10);
const pct = (v,n) => n ? +(100*v/n).toFixed(1) : null;
const get = (url,opts={}) => fetch(url,{redirect:'follow',
  signal:AbortSignal.timeout(opts.timeout||28000),method:opts.method||'GET',
  headers:opts.method==='HEAD'?{}:{Accept:'application/json, application/xml, text/xml'}});
function isbnValid(id) {
  if(!/^97[89]\d{10}$/.test(id)) return false;
  let s=0;
  for(let i=0;i<12;i++)s+=Number(id[i])*(i%2?3:1);
  return ((10-s%10)%10)===Number(id[12]);
}
function parseIsbns(xml){
  const entries=[...xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)];
  const ids=[];
  for(const entry of entries){
    const matches=entry[1].matchAll(/<(?:[\w.-]+:)?identifier\b[^>]*>([\s\S]*?)<\/(?:[\w.-]+:)?identifier>/gi);
    for(const match of matches){
      const compact=match[1].replace(/<[^>]*>/g,'').replace(/[\s\u3000\u2010-\u2015\u2212-]/g,'');
      const isbn=(compact.match(/97[89]\d{10}/g)||[]).find(isbnValid);
      if(isbn){ids.push(isbn);break;}
    }
  }
  return { raw:entries.length, isbns:ids };
}
function isValidCover(input,hosts){
  if(typeof input!=='string'||!input||input.length>2048)return false;
  try{
    const u=new URL(input);
    return u.protocol==='https:'&&!!u.hostname&&!u.username&&!u.password&&
      !u.port&&(!hosts||hosts.includes(u.hostname));
  }catch{return false;}
}
async function cohort(name,dpid,days,goal,maxWindows=10){
  let idx=1,added=0;
  for(let i=0;i<maxWindows && idx+27<=501 && sample.size<target && added<goal;i++){
    const u=new URL('/api/ndl',base);
    u.search=new URLSearchParams({dpid,idx:String(idx),cnt:'27',mediatype:'books',from:cutoff(days)}).toString();
    let r;
    try{
      r=await get(u);
      if([429,502,503,504].includes(r.status)){
        await delay(1400);r=await get(u);
      }
    }catch{
      ndlWindows.push({name,idx,outcome:'network_error'});break;
    }
    if(!r.ok){ndlWindows.push({name,idx,outcome:'http_'+r.status});break;}
    let p;
    try{
      const xml=await r.text();
      if(xml.length>4000000)throw new Error('too long');
      p=parseIsbns(xml);
    }catch{ndlWindows.push({name,idx,outcome:'xml_error'});break;}
    let n=0;
    for(const isbn of p.isbns){
      if(sample.size>=target||added>=goal)break;
      if(!sample.has(isbn)){sample.set(isbn,{isbn,cohort:name});n++;added++;}
    }
    ndlWindows.push({name,idx,outcome:'ok',raw:p.raw,valid:p.isbns.length,added:n});
    console.log('COVER100_NDL '+JSON.stringify(ndlWindows.at(-1)));
    if(p.raw<27)break;
    idx+=27;
    await delay(750);
  }
}
const chunks=(a,n)=>Array.from({length:Math.ceil(a.length/n)},(_,i)=>a.slice(i*n,(i+1)*n));
async function openbd(books){
  for(const chunk of chunks(books,25)){
    const u=new URL('/api/openbd',base);
    u.searchParams.set('isbn',chunk.map(b=>b.isbn).join(','));
    try{
      const r=await get(u,{timeout:18000});
      if(r.status!==200)throw new Error('openbd status');
      const data=await r.json();
      if(!Array.isArray(data)||data.length!==chunk.length)throw new Error('openbd shape');
      chunk.forEach((book,i)=>{
        const rec=data[i];
        if(rec?.summary?.isbn&&String(rec.summary.isbn)!==book.isbn){
          book.openbd='unknown';return;
        }
        book.openbd=isValidCover(rec?.summary?.cover)?'cover':
          rec&&typeof rec==='object'?'no_cover':'no_record';
      });
    }catch{chunk.forEach(b=>b.openbd='unknown');}
    await delay(400);
  }
}
async function google(books){
  const missing=books.filter(b=>b.openbd!=='cover');
  for(const chunk of chunks(missing,10)){
    const u=new URL('/api/book-covers',base);
    u.searchParams.set('isbn',chunk.map(b=>b.isbn).join(','));
    try{
      let r=await get(u,{timeout:14000});
      if([502,503,504].includes(r.status)){
        await delay(3000);
        r=await get(u,{timeout:14000});
      }
      if(r.status!==200)throw new Error('http_'+r.status);
      const data=await r.json();
      if(!data?.covers||typeof data.covers!=='object')throw new Error('google shape');
      for(const b of chunk){
        const rec=data.covers[b.isbn];
        b.google=isValidCover(rec?.coverUrl,['books.google.com','books.googleusercontent.com'])&&
          isValidCover(rec?.creditUrl,['books.google.com'])?'cover':'no_cover';
      }
    }catch(error){
      chunk.forEach(b=>b.google='unknown');
      // A failed provider batch is NOT evidence that its jackets are absent.
      const code=String(error?.message||'network_error');
      console.log('COVER100_GOOGLE_BATCH '+JSON.stringify({size:chunk.length,issue:/^http_\d+$/.test(code)?code:'network_or_bad_response'}));
    }
    await delay(4000);
  }
  books.forEach(b=>{if(!b.google)b.google='not_needed';});
}
async function openlibrary(books){
  // Only ISBNs still without a provider cover. Polite sequential HEAD,
  // never download images, and do not classify 5xx as a missing jacket.
  for(const b of books){
    if(b.openbd==='cover'||b.google==='cover'){
      b.openlibrary='not_needed';continue;
    }
    const url='https://covers.openlibrary.org/b/isbn/'+b.isbn+'-M.jpg?default=false';
    try{
      const r=await get(url,{method:'HEAD',timeout:10000});
      b.openlibrary=r.status===200&&String(r.headers.get('content-type')).startsWith('image/')?
        'head_image':r.status===404?'not_found':'unknown';
    }catch{b.openlibrary='unknown';}
    await delay(950);
  }
}
function report(books){
  const n=books.length;
  const count=(field,v)=>books.filter(b=>b[field]===v).length;
  const coverOpenbd=count('openbd','cover');
  const coverGoogle=count('google','cover');
  const coverOl=count('openlibrary','head_image');
  const noImage=books.filter(b=>b.openbd!=='unknown'&&b.openbd!=='cover'&&
    b.google==='no_cover'&&b.openlibrary==='not_found').length;
  const undetermined=books.filter(b=>b.openbd!=='cover'&&b.google!=='cover'&&
    b.openlibrary!=='head_image'&&
    (b.openbd==='unknown'||b.google==='unknown'||b.openlibrary==='unknown')).length;
  return {
    requested:target,n,
    sampling:'NDL new-bibliography recent 90d and national bibliography recent 90d; first valid ISBN-13 per cohort, not a random sample',
    cohorts:Object.fromEntries([...new Set(books.map(b=>b.cohort))]
      .map(k=>[k,books.filter(b=>b.cohort===k).length])),
    openbd:{
      coverUrlCount:coverOpenbd,coverUrlPct:pct(coverOpenbd,n),
      recordsWithoutCover:count('openbd','no_cover'),
      recordsAbsent:count('openbd','no_record'),
      unknown:count('openbd','unknown')
    },
    googleForMissingOpenbd:{
      additionalCoverUrlCount:coverGoogle,additionalPct:pct(coverGoogle,n),
      unknown:count('google','unknown')
    },
    openLibraryForMissingBoth:{
      head200Image:coverOl,head404:count('openlibrary','not_found'),
      unknown:count('openlibrary','unknown')
    },
    combined:{
      metadataOrHeadAvailable:coverOpenbd+coverGoogle+coverOl,
      metadataOrHeadAvailablePct:pct(coverOpenbd+coverGoogle+coverOl,n),
      knownMissingAll:noImage,knownMissingAllPct:pct(noImage,n),
      undetermined,undeterminedPct:pct(undetermined,n),
      actuallyRenderedInBrowser:false
    }
  };
}
await cohort('inprocess_recent90','iss-ndl-opac-inprocess',90,50);
await cohort('national_recent90','iss-ndl-opac-national',90,50);
if(sample.size<target)await cohort('holdings_recent90_extra','iss-ndl-opac',90,
  target-sample.size,8);
const books=[...sample.values()].slice(0,target);
if(books.length){
  await openbd(books);await google(books);await openlibrary(books);
}
const summary=report(books);
console.log('COVER100_RESULT '+JSON.stringify({...summary,ndlWindowCount:ndlWindows.length}));
writeFileSync('cover-sample-100-result.json',JSON.stringify({
  at:new Date().toISOString(),summary,ndlWindows,books
},null,2)+'\n');
if(!books.length)process.exitCode=1;
