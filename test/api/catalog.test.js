const test = require('node:test');
const assert = require('node:assert/strict');
const ndl = require('../../api/ndl');
const openbd = require('../../api/openbd');

function recorder() {
  return { statusCode: 200, headers: {}, body: '',
    setHeader(k,v){this.headers[k]=v;},
    status(v){this.statusCode=v;return this;},
    json(v){this.body=v;return this;},
    send(v){this.body=v;return this;}
  };
}

test('NDL proxy uses documented provider and 1-based index', async () => {
  let upstream = '';
  const handler = ndl.createHandler({request: async url => {
    upstream = url;
    return {ok:true,text:async()=>'<rss><channel></channel></rss>'};
  }});
  const res=recorder();
  await handler({method:'GET',query:{title:'文学',dpid:'iss-ndl-opac-national',cnt:'20',idx:'21'}},res);
  assert.equal(res.statusCode,200);
  const url = new URL(upstream);
  assert.equal(url.searchParams.get('idx'),'21');
  assert.equal(url.searchParams.get('dpid'),'iss-ndl-opac-national');
  assert.equal(url.searchParams.get('title'),'文学');
});

test('NDL proxy allows NDL-owned foreign-book catalog records',async()=>{
  const handler = ndl.createHandler({request:async url => ({
    ok:true,text:async()=>'<rss><channel></channel></rss>'
  })});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'iss-ndl-opac',title:'Pride and Prejudice'}},res);
  assert.equal(res.statusCode,200);
});

test('NDL proxy requires a search term even for Japan-related foreign bibliography',async()=>{
  let upstream='';
  const handler=ndl.createHandler({request:async url=>{
    upstream=url;
    return {ok:true,text:async()=>'<rss><channel></channel></rss>'};
  }});
  const missing=recorder();
  await handler({method:'GET',query:{dpid:'ndl-boj',mediatype:'books',cnt:'27',idx:'1'}},missing);
  assert.equal(missing.statusCode,400);
  assert.equal(missing.body.error,'missing_catalog_search');
  assert.equal(upstream,'', 'blank query must not reach NDL');

  const res=recorder();
  await handler({method:'GET',query:{dpid:'ndl-boj',mediatype:'books',title:'Japan',cnt:'27',idx:'1'}},res);
  assert.equal(res.statusCode,200);
  const url=new URL(upstream);
  assert.equal(url.searchParams.get('dpid'),'ndl-boj');
  assert.equal(url.searchParams.get('mediatype'),'books');
  assert.equal(url.searchParams.get('cnt'),'27');
  assert.equal(url.searchParams.get('title'),'Japan');
});

test('NDL proxy rejects provider injection and missing search fields',async()=>{
  const handler=ndl.createHandler({request:async()=>{throw Error('unexpected');}});
  const invalid=recorder();
  await handler({method:'GET',query:{dpid:'jpro',title:'文学'}},invalid);
  assert.equal(invalid.statusCode,400);
  const empty=recorder();
  await handler({method:'GET',query:{dpid:'iss-ndl-opac-national'}},empty);
  assert.equal(empty.statusCode,400);
});

test('NDL proxy maps a slow upstream timeout to 504 without caching it', async()=>{
  let requestSignal;
  const handler=ndl.createHandler({request:async (url,options)=>{
    requestSignal=options.signal;
    const error=new Error('upstream timed out');
    error.name='TimeoutError';
    throw error;
  }});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'iss-ndl-opac-national',from:'2026-08-01',cnt:'27',idx:'28'}},res);
  assert.equal(res.statusCode,504);
  assert.equal(res.body.error,'ndl_timeout');
  assert.equal(res.headers['Retry-After'],'3');
  assert.equal(res.headers['Cache-Control'],'no-store');
  assert.equal(requestSignal instanceof AbortSignal,true);
});

test('NDL proxy preserves overload response as retryable 503', async()=>{
  const handler=ndl.createHandler({request:async()=>({ok:false,status:429})});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'iss-ndl-opac-inprocess',from:'2026-08-01',cnt:'27',idx:'28'}},res);
  assert.equal(res.statusCode,503);
  assert.equal(res.body.error,'ndl_unavailable');
  assert.equal(res.headers['Retry-After'],'3');
  assert.equal(res.headers['Cache-Control'],'no-store');
});

test('NDL proxy does not cache other upstream gateway failures', async()=>{
  const handler=ndl.createHandler({request:async()=>({ok:false,status:500})});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'iss-ndl-opac-national',from:'2026-08-01'}},res);
  assert.equal(res.statusCode,502);
  assert.equal(res.body.error,'ndl_unavailable');
  assert.equal(res.headers['Cache-Control'],'no-store');
});

test('openBD accepts ISBN list only and preserves null entries',async()=>{
  let url='';
  const handler=openbd.createHandler({request:async req=>{
    url=req;
    return {ok:true,text:async()=>JSON.stringify([null,{summary:{isbn:'9784101010014'}}])};
  }});
  const res=recorder();
  await handler({method:'GET',query:{isbn:'9784065281499,9784101010014'}},res);
  assert.equal(res.statusCode,200);
  assert.match(url,/isbn=9784065281499,9784101010014/);
  assert.equal(JSON.parse(res.body).length,2);
});

test('openBD rejects non-ISBN input',async()=>{
  const handler=openbd.createHandler({request:async()=>{throw Error('must not fetch');}});
  const res=recorder();
  await handler({method:'GET',query:{isbn:'../../../private'}},res);
  assert.equal(res.statusCode,400);
});


test('home catalogue rejects arbitrary providers and unbounded searches', async () => {
  const home = require('../../api/home-catalog');
  const handler = home.createHandler({request:async()=>{throw Error('not called');}});
  for (const query of [
    {}, {lang:'fra',topic:'Japan',page:'1'},
    {lang:'eng',topic:'日本',page:'1'},
    {lang:'jpn',topic:'日本',page:'0'},
    {lang:'jpn',topic:'日本',page:'50'},
    {lang:'eng',topic:'Japan',page:'1',q:'arbitrary'},
  ]) {
    const res=recorder();
    await handler({method:'GET',query},res);
    assert.equal(res.statusCode,400);
    assert.equal(res.body.error,'invalid_home_catalog_query');
  }
});

test('home catalogue ISBN conversion validates checksums and exact edition language', () => {
  const home = require('../../api/home-catalog');
  const {isbn13Valid,toIsbn13,selectBooks}=home._test;
  assert.equal(toIsbn13('0140328726'),'9780140328721');
  assert.equal(toIsbn13('0140328720'),null);
  assert.equal(isbn13Valid('9780140328721'),true);
  assert.equal(isbn13Valid('9780140328720'),false);
  const works={docs:[
    {title:'Work includes many translations',isbn:['9780000000000'],
      author_name:['Writer'],editions:{docs:[{key:'/books/OL123M',title:'Japanese edition'}]}},
    {title:'Other work',editions:{docs:[{key:'/books/OL124M'}]}},
    {title:'Not a book',editions:{docs:[{key:'/books/OL125M'}]}},
    {title:'Non ISBN edition',editions:{docs:[{key:'/books/OL126M'}]}},
  ]};
  const details={
    'OLID:OL123M':{details:{key:'/books/OL123M',title:'Japanese edition',
      languages:[{key:'/languages/jpn'}],isbn_10:['0140328726'],
      publishers:['Publisher']}},
    'OLID:OL124M':{details:{title:'Bilingual',languages:[
      {key:'/languages/jpn'},{key:'/languages/eng'}
    ],isbn_13:['9780140328721']}},
    'OLID:OL125M':{details:{title:'English only',languages:[
      {key:'/languages/eng'}
    ],isbn_13:['9780140328721']}},
    'OLID:OL126M':{details:{title:'Unknown ISBN',languages:[
      {key:'/languages/jpn'}
    ],isbn_13:['9780140328720']}},
  };
  const books=selectBooks(works,details,'jpn');
  assert.equal(books.length,1);
  assert.equal(books[0].isbn,'9780140328721');
  assert.equal(books[0].title,'Japanese edition');
  assert.equal(books[0].languageCode,'jpn');
  assert.equal(books[0].coverUrl,undefined,
    'Open Library cover URLs are never shipped to the client');
});

test('home catalogue batches selected editions and caches only a successful page', async () => {
  const home = require('../../api/home-catalog');
  const urls=[];
  const handler=home.createHandler({
    sleep:async()=>{},
    request:async url=>{
      const u=new URL(url);urls.push(u);
      if(u.pathname==='/search.json')return {
        ok:true,status:200,json:async()=>({
          numFound:61,docs:[{
            author_name:['Writer'],
            editions:{docs:[{key:'/books/OL123M',title:'English edition',
              language:['eng']}]}
          }]
        }),
      };
      if(u.pathname==='/api/books.json')return {
        ok:true,status:200,json:async()=>({
          'OLID:OL123M':{details:{title:'English edition',
            languages:[{key:'/languages/eng'}],
            isbn_10:['0140328726'],publishers:['Publisher']}}
        }),
      };
      throw Error('unexpected URL');
    },
  });
  const res=recorder();
  await handler({method:'GET',query:{lang:'eng',topic:'Japan',page:'1'}},res);
  assert.equal(res.statusCode,200);
  assert.equal(res.headers['Cache-Control'],'public, max-age=0, s-maxage=600');
  assert.equal(res.body.catalogSource,'openlibrary');
  assert.equal(res.body.books[0].isbn,'9780140328721');
  assert.equal(res.body.books[0].languageCode,'eng');
  assert.equal(res.body.books.length,1);
  assert.equal(res.body.hasMore,false);
  assert.equal(urls.length,2);
  assert.equal(urls[0].hostname,'openlibrary.org');
  assert.match(urls[0].searchParams.get('q'),/language:eng AND isbn:\* AND title:Japan/);
  assert.equal(urls[1].searchParams.get('bibkeys'),'OLID:OL123M');
  assert.equal(urls[1].searchParams.get('jscmd'),'details');
});

test('home catalogue does not cache provider throttling or transient timeouts', async () => {
  const home = require('../../api/home-catalog');
  const busy=home.createHandler({request:async()=>({ok:false,status:429})});
  let res=recorder();
  await busy({method:'GET',query:{lang:'eng',topic:'Japan',page:'1'}},res);
  assert.equal(res.statusCode,503);
  assert.equal(res.headers['Cache-Control'],'no-store');
  assert.equal(res.headers['Retry-After'],'5');
  const timeout=home.createHandler({request:async()=>{
    const e=new Error('timed out');e.name='TimeoutError';throw e;
  }});
  res=recorder();
  await timeout({method:'GET',query:{lang:'jpn',topic:'日本',page:'1'}},res);
  assert.equal(res.statusCode,504);
  assert.equal(res.headers['Cache-Control'],'no-store');
});
