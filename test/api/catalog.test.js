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

test('NDL proxy accepts the bounded Japan-related foreign bibliography without a keyword',async()=>{
  let upstream='';
  const handler=ndl.createHandler({request:async url=>{
    upstream=url;
    return {ok:true,text:async()=>'<rss><channel></channel></rss>'};
  }});
  const res=recorder();
  await handler({method:'GET',query:{dpid:'ndl-boj',mediatype:'books',cnt:'27',idx:'1'}},res);
  assert.equal(res.statusCode,200);
  const url=new URL(upstream);
  assert.equal(url.searchParams.get('dpid'),'ndl-boj');
  assert.equal(url.searchParams.get('mediatype'),'books');
  assert.equal(url.searchParams.get('cnt'),'27');
  assert.equal(url.searchParams.get('any'),null);
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
