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


test('SRU language proxy uses official bounded DC-NDL schema and requested provider', async () => {
  const sru = require('../../api/ndl-sru');
  let upstreamUrl = '';
  const handler = sru.createHandler({request:async url => {
    upstreamUrl = url;
    return {ok:true,text:async()=>'<searchRetrieveResponse><numberOfRecords>0</numberOfRecords></searchRetrieveResponse>'};
  }});
  const res=recorder();
  await handler({method:'GET',query:{
    dpid:'iss-ndl-opac-national',title:'日本',cnt:'27',idx:'1',
  }},res);
  assert.equal(res.statusCode,200);
  const url=new URL(upstreamUrl);
  assert.equal(url.pathname,'/api/sru');
  assert.equal(url.searchParams.get('recordSchema'),'dcndl');
  assert.equal(url.searchParams.get('recordPacking'),'xml');
  assert.equal(url.searchParams.get('onlyBib'),'true');
  assert.equal(url.searchParams.get('startRecord'),'1');
  assert.equal(url.searchParams.get('maximumRecords'),'27');
  assert.match(url.searchParams.get('query'),/dpid="iss-ndl-opac-national" AND title="日本"/);
});

test('SRU proxy rejects unsupported providers, bare requests and injected CQL', async () => {
  const sru = require('../../api/ndl-sru');
  const handler=sru.createHandler({request:async()=>{throw Error('must not fetch');}});
  for(const query of [
    {dpid:'jpro',title:'Japan'},
    {dpid:'ndl-boj'},
    {dpid:'ndl-boj',title:'Japan" OR isbn="123'},
    {dpid:'ndl-boj',title:'Japan',query:'isbn=123'},
  ]) {
    const res=recorder();
    await handler({method:'GET',query},res);
    assert.equal(res.statusCode,400);
    assert.equal(res.body.error,'invalid_catalog_query');
  }
});

test('SRU proxy preserves upstream timeout as a retryable uncached error', async () => {
  const sru = require('../../api/ndl-sru');
  const handler=sru.createHandler({request:async()=> {
    const e=new Error('timeout');e.name='TimeoutError';throw e;
  }});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'ndl-boj',title:'Japan'}},res);
  assert.equal(res.statusCode,504);
  assert.equal(res.body.error,'ndl_timeout');
  assert.equal(res.headers['Cache-Control'],'no-store');
  assert.equal(res.headers['Retry-After'],'3');
});

test('SRU proxy never caches a successful HTTP envelope with SRU diagnostics', async () => {
  const sru = require('../../api/ndl-sru');
  const handler=sru.createHandler({request:async()=>({
    ok:true,text:async()=>'<searchRetrieveResponse><diagnostics/></searchRetrieveResponse>'
  })});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'ndl-boj',title:'Japan'}},res);
  assert.equal(res.statusCode,502);
  assert.equal(res.headers['Cache-Control'],'no-store');
});
