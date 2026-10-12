const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const projectRoot = path.join(__dirname, "../..");
const read = (relativePath) =>
  fs.readFileSync(path.join(projectRoot, relativePath), "utf8").replace(/\r\n/g, "\n");

test("Ninja AdMax loads in production Flutter Web builds only", () => {
  const production = read(".github/workflows/deploy.yaml");
  const staging = read(".github/workflows/deploy-staging.yaml");
  const policy = read("lib/widgets/timeline_ad_policy.dart");
  const tag = read("web/index.html");
  const target =
    '<!-- admax -->\n' +
    '<script src="https://adm.shinobi.jp/s/234edc1d1284546b2d177ac7c5531101"></script>\n' +
    '<!-- admax -->';

  assert.match(production, /flutter build web --release[^\n]*--dart-define=NINJA_ADMAX_ENABLED=true/);
  assert.match(production, /flutter build web --release[^\n]*--dart-define=NINJA_ADMAX_POSTS_PER_AD=2/);
  assert.doesNotMatch(staging, /--dart-define=NINJA_ADMAX_ENABLED=true/);
  assert.match(policy, /defaultValue: false/);
  assert.match(production, /NINJA_ADMAX_ASYNC_ID/);
  assert.match(production, /NINJA_ADMAX_ASYNC_TYPE/);
  assert.match(production, /NINJA_ADMAX_ASYNC_ID: "234edc1d1284546b2d177ac7c5531101"/);
  assert.match(production, /NINJA_ADMAX_ASYNC_TYPE: "banner"/);
  assert.match(production, /--dart-define=NINJA_ADMAX_ASYNC_ID=/);
  assert.match(production, /--dart-define=NINJA_ADMAX_ASYNC_TYPE=/);
  assert.match(policy, /timelineAdReady/);
  assert.match(policy, /NINJA_ADMAX_ASYNC_ID/);
  assert.ok(tag.includes(target), "the original issued synchronous tag must remain verbatim");

  const asyncTag = [
    '<!-- admax -->',
    '<div class="admax-ads" data-admax-id="234edc1d1284546b2d177ac7c5531101" style="display:inline-block;width:728px;height:90px;"></div>',
    '<script type="text/javascript">(admaxads = window.admaxads || []).push({admax_id: "234edc1d1284546b2d177ac7c5531101",type: "banner"});</script>',
    '<script type="text/javascript" charset="utf-8" src="https://adm.shinobi.jp/st/t.js" async></script>',
    '<!-- admax -->',
  ].join("\n");
  assert.ok(tag.includes(asyncTag), "the issuer's asynchronous tag must remain verbatim");

  const slot = read("lib/widgets/timeline_ad_slot_web.dart");
  assert.match(slot, /'728px'/);
  assert.match(slot, /'90px'/);
  assert.match(slot, /'admax-switch' : 'admax-ads'/);
});
