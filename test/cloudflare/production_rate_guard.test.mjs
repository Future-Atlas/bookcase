import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import worker from "../../cloudflare/worker.mjs";
import { guardRequest } from "../../cloudflare/request-guard.mjs";

test("production rate limits exist and use distinct namespaces", () => {
  const cfg=JSON.parse(readFileSync(new URL("../../wrangler.jsonc",import.meta.url),"utf8"));
  assert.equal(cfg.env.production.ratelimits.length,2);
  assert.equal(cfg.env.production.ratelimits.find(x=>x.name==="API_RATE_LIMIT").simple.limit,120);
  assert.equal(cfg.env.production.ratelimits.find(x=>x.name==="CATALOG_RATE_LIMIT").simple.limit,24);
  assert.notEqual(cfg.env.production.ratelimits[0].namespace_id,cfg.env.staging.ratelimits[0].namespace_id);
});

test("one IP cannot bypass catalog quota by changing the upstream query", async () => {
  const calls=[];
  const env={
    API_RATE_LIMIT:{async limit(o){calls.push(["api",o.key]);return {success:true};}},
    CATALOG_RATE_LIMIT:{async limit(o){calls.push(["catalog",o.key]);return {success:false};}},
  };
  const req=new Request("https://www.sharemarium.com/api/rakuten?keyword=arbitrary",{
    headers:{"cf-connecting-ip":"198.51.100.7"},
  });
  const denied=await guardRequest(req,env);
  assert.equal(denied.status,429);
  assert.equal(denied.headers.get("Cache-Control"),"no-store");
  assert.equal(denied.headers.get("Retry-After"),"60");
  assert.deepEqual(calls,[["api","198.51.100.7:api"],["catalog","198.51.100.7:catalog"]]);
});

test("production API blocks excess traffic but serves static assets without counters", async () => {
  let assets=0,apiChecks=0;
  const env={
    APP_ENV:"production",
    API_RATE_LIMIT:{async limit(){apiChecks++;return {success:false};}},
    CATALOG_RATE_LIMIT:{async limit(){throw Error("should not contact other limiter");}},
    ASSETS:{async fetch(){assets++;return new Response("SPA")}},
  };
  const bad=await worker.fetch(new Request("https://www.sharemarium.com/api/seo"),env);
  assert.equal(bad.status,429);
  const app=await worker.fetch(new Request("https://www.sharemarium.com/settings"),env);
  assert.equal(app.status,200);
  assert.equal(assets,1);
  assert.equal(apiChecks,1);
});

test("a missing rate limit binding fails closed before upstream cost",async()=>{
  const result=await worker.fetch(
    new Request("https://www.sharemarium.com/api/rakuten?keyword=test"),
    {APP_ENV:"production"},
  );
  assert.equal(result.status,503);
  assert.equal(result.headers.get("Cache-Control"),"no-store");
});
