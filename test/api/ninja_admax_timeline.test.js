const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");

const read = (file) =>
  fs.readFileSync(path.join(__dirname, "../..", file), "utf8");

const issuedSyncTag =
  '<!-- admax -->\n' +
  '<script src="https://adm.shinobi.jp/s/234edc1d1284546b2d177ac7c5531101"></script>\n' +
  '<!-- admax -->';

function runtime({
  token = "",
  adFree = false,
  failEntitlement = false,
} = {}) {
  const markup = read("web/index.html");
  const start = markup.indexOf("    <script>\n      (() => {");
  const end = markup.indexOf("    </script>", start);
  assert.ok(start >= 0 && end > start);
  const listeners = new Map();
  const timers = [];
  const requests = [];
  const targets = [];
  const window = {
    location: { hostname: "www.sharemarium.com", pathname: "/", search: "" },
    localStorage: {
      length: token ? 1 : 0,
      key: () => token ? "sb-test-auth-token" : null,
      getItem: () => JSON.stringify({ access_token: token }),
    },
    addEventListener(name, fn) { listeners.set(name, fn); },
    setTimeout(fn) { timers.push(fn); return timers.length; },
    history: { pushState() {}, replaceState() {} },
  };
  const document = {
    readyState: "loading",
    hidden: false,
    body: {},
    head: {
      appendChild(node) { requests.push(node); if (node.onload) node.onload(); },
    },
    addEventListener(name, fn) { listeners.set(name, fn); },
    getElementById(id) {
      return requests.find(node => node.id === id && !node.removed) || null;
    },
    querySelectorAll() { return []; },
    createElement(tag) {
      assert.equal(tag, "script", "must not create a sandboxed iframe");
      return {
        tag, async: false, removed: false,
        remove() { this.removed = true; },
      };
    },
  };
  class MutationObserver {
    constructor(fn) { this.callback = fn; }
    observe() {}
  }
  const fetch = async () => {
    if (failEntitlement) throw new Error("entitlement_failure");
    return { ok: true, json: async () => ({ authenticated: true, adFree }) };
  };
  vm.runInNewContext(markup.slice(start + "    <script>".length, end),
    { window, document, MutationObserver, fetch, console });

  function emitSlot(index, id = "234edc1d1284546b2d177ac7c5531101", type = "banner") {
    const state = new Map([["data-admax-id", id]]);
    const target = {
      getAttribute(key) { return state.get(key) || null; },
      setAttribute(key, value) { state.set(key, value); },
      replaceChildren() { this.cleared = true; },
    };
    const root = {
      isConnected: true,
      getAttribute(key) {
        return {
          "data-sharemarium-admax-slot-index": String(index),
          "data-sharemarium-admax-async-id": id,
          "data-sharemarium-admax-async-type": type,
        }[key] || null;
      },
      querySelector(selector) {
        return selector === (type === "switch" ? ".admax-switch" : ".admax-ads")
          ? target : null;
      },
    };
    targets.push(target);
    listeners.get("sharemarium:admax-slot-ready")({ detail: root });
    return { root, target };
  }
  async function flush() {
    for (let i = 0; i < 6; i++) {
      await new Promise(resolve => setImmediate(resolve));
      const ready = timers.splice(0);
      for (const fn of ready) fn();
      if (!timers.length) break;
    }
    await new Promise(resolve => setImmediate(resolve));
  }
  return { window, document, requests, listeners, emitSlot, flush, targets };
}

test("the issued synchronous tag remains verbatim but inert", () => {
  const html = read("web/index.html");
  assert.ok(html.includes(
    '<template id="sharemarium-ninja-admax-official-tag">\n' +
    issuedSyncTag + '\n    </template>',
  ));
  assert.match(html, /https:\/\/adm\.shinobi\.jp\/st\/t\.js/);
  assert.doesNotMatch(html, /document\.createElement\("iframe"\)/);
  assert.doesNotMatch(read("lib/widgets/timeline_ad_slot_web.dart"),
    /IFrameElement|HtmlIFrameElement|srcdoc/);
});

test("placement remains after 2, 4, 6 real posts and never exceeds 3", () => {
  const src = read("lib/screens/book_list_screen.dart");
  const policy = read("lib/widgets/timeline_ad_policy.dart");
  assert.match(src, /isTimelineAdItem\(index, postCount\)/);
  assert.match(src, /timelinePostIndexForItem\(index, postCount\)/);
  assert.match(src, /kIsWeb && timelineAdReady/);
  assert.match(policy, /defaultValue: 2/);
  assert.match(policy, /timelineMaximumAdsPerPage = 3/);
  assert.match(policy, /NINJA_ADMAX_POSTS_PER_AD/);
});

test("ad configuration fails closed without an actual async publisher ID", () => {
  const policy = read("lib/widgets/timeline_ad_policy.dart");
  const widget = read("lib/widgets/timeline_ad_slot_web.dart");
  assert.match(policy, /NINJA_ADMAX_ASYNC_ID/);
  assert.match(policy, /defaultValue: ''/);
  assert.match(policy, /timelineAdReady/);
  assert.match(widget, /ninjaAdmaxAsyncId/);
  assert.match(widget, /'admax-switch' : 'admax-ads'/);
  assert.match(widget, /data-admax-id/);
  assert.match(widget, /'728px'/);
  assert.match(widget, /'90px'/);
});

test("three eligible native slots request the async SDK only once", async () => {
  const r = runtime();
  r.emitSlot(0);
  r.emitSlot(1);
  r.emitSlot(2);
  r.emitSlot(3);
  await r.flush();
  assert.equal(r.requests.length, 1);
  assert.equal(r.requests[0].src, "https://adm.shinobi.jp/st/t.js");
  assert.equal(r.requests[0].async, true);
  const queue = Array.from(r.window.admaxads);
  assert.equal(queue.length, 3);
  for (const item of queue) {
    assert.equal(item.admax_id, "234edc1d1284546b2d177ac7c5531101");
    assert.equal(item.type, "banner");
  }
  for (const target of r.targets.slice(0, 3)) {
    assert.equal(target.getAttribute("data-admax-load"), "sdk-loaded");
  }
});

test("ad-free members and entitlement errors never load SDK", async () => {
  for (const options of [
    { token: "user", adFree: true },
    { token: "user", failEntitlement: true },
  ]) {
    const r = runtime(options);
    r.emitSlot(0);
    await r.flush();
    assert.equal(r.requests.length, 0);
  }
});

test("routes, invalid IDs and other hosts never load SDK", async () => {
  const r = runtime();
  r.window.location.hostname = "other.example";
  r.emitSlot(0);
  r.window.location.hostname = "www.sharemarium.com";
  r.window.location.search = "?seo_preview=1";
  r.emitSlot(0);
  r.window.location.search = "";
  r.emitSlot(0, "");
  r.emitSlot(1, "invalid/id");
  r.emitSlot(2, "valid-async-id", "unsupported");
  await r.flush();
  assert.equal(r.requests.length, 0);
});

test("route navigation removes SDK and resets native slots", async () => {
  const r = runtime();
  const slot = r.emitSlot(0);
  await r.flush();
  assert.equal(r.requests.length, 1);
  r.window.location.pathname = "/profile";
  r.window.history.pushState({}, "", "/profile");
  await r.flush();
  assert.equal(r.requests[0].removed, true);
  assert.equal(slot.target.cleared, true);
  assert.equal(r.window.admaxads.length, 0);
});

test("the old AdSense integration and paid feature promotion stay disabled", () => {
  assert.doesNotMatch(read("web/index.html"), /adsbygoogle|ca-pub-|googlesyndication/);
  assert.match(read("lib/config/feature_flags.dart"), /subscriptionUiEnabled = false/);
});
