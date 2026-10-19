const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");

const read = (file) =>
  fs.readFileSync(path.join(__dirname, "../..", file), "utf8").replace(/\r\n/g, "\n");

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
  const sdkBatches = [];
  const entitlementEvents = [];
  const targets = [];
  class CustomEvent {
    constructor(type, options = {}) {
      this.type = type;
      this.detail = options.detail;
    }
  }
  const window = {
    location: { hostname: "www.sharemarium.com", pathname: "/", search: "" },
    localStorage: {
      length: token ? 1 : 0,
      key: () => token ? "sb-test-auth-token" : null,
      getItem: () => JSON.stringify({ access_token: token }),
    },
    addEventListener(name, fn) { listeners.set(name, fn); },
    dispatchEvent(event) {
      if (event.type === "sharemarium:admax-entitlement-changed") {
        entitlementEvents.push(event.detail);
      }
      listeners.get(event.type)?.(event);
      return true;
    },
    setTimeout(fn) { timers.push(fn); return timers.length; },
    setInterval() { return 1; },
    history: { pushState() {}, replaceState() {} },
  };
  const document = {
    readyState: "loading",
    hidden: false,
    body: {},
    head: {
      appendChild(node) {
        requests.push(node);
        sdkBatches.push(Array.from(window.admaxads || [], (item) => ({ ...item })));
        if (node.onload) node.onload();
      },
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
    { window, document, MutationObserver, CustomEvent, fetch, console });

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
  return {
    window,
    document,
    requests,
    sdkBatches,
    entitlementEvents,
    listeners,
    emitSlot,
    flush,
    targets,
  };
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

test("timeline has no application-imposed slot cap", () => {
  const src = read("lib/screens/book_list_screen.dart");
  const policy = read("lib/widgets/timeline_ad_policy.dart");
  const slot = read("lib/widgets/timeline_ad_slot_web.dart");
  const html = read("web/index.html");

  assert.match(src, /timelineAdSlotCount\(postCount\)/);
  assert.match(src, /isTimelineAdItem\(index, postCount\)/);
  assert.match(src, /timelinePostIndexForItem\(index, postCount\)/);
  assert.match(src, /kIsWeb && timelineAdDisplayReady/);
  assert.match(policy, /defaultValue: 5/);
  assert.match(policy, /NINJA_ADMAX_POSTS_PER_AD/);
  assert.match(policy, /return \(postCount - 1\) ~\/ postsPerAd;/);
  assert.doesNotMatch(policy, /timelineMaximumAdsPerPage|homeTimelineMaximumAds|maximumSlots/);
  assert.doesNotMatch(slot, /timelineMaximumAdsPerPage|slotIndex >=/);
  assert.doesNotMatch(html, /maxAdsPerPage|renderedSlots\.size >= maxAdsPerPage/);
  assert.match(html, /Number\.isSafeInteger\(index\)/);
});

test("two home book-genre separators and repeated timeline slots have unique indices", () => {
  const home = read("lib/screens/book_list_screen.dart");
  const policy = read("lib/widgets/timeline_ad_policy.dart");
  const html = read("web/index.html");

  const anchors = [
    "title: '人気作品'",
    "home-ad-between-popular-new",
    "title: '新着'",
    "home-ad-between-new-western",
    "title: '洋書'",
    "sectionHeading: true",
    "_buildTimeline()",
  ];
  let previous = -1;
  const indexes = anchors.map((anchor) => {
    previous = home.indexOf(anchor, previous + 1);
    return previous;
  });
  assert.ok(indexes.every((at) => at >= 0), "all home section anchors exist");
  for (let i = 1; i < indexes.length; i++) {
    assert.ok(indexes[i - 1] < indexes[i], "genre ad follows preceding section");
  }

  assert.match(home, /if \(kIsWeb &&\s+timelineAdDisplayReady &&\s+widget\.initialGenre == null &&\s+_controller\.popularBooks\.isNotEmpty &&\s+_controller\.recommendedBooks\.isNotEmpty\)\s+const TimelineAdSlot\(\s+key: ValueKey\('home-ad-between-popular-new'\),\s+slotIndex: 0,/);
  assert.match(home, /if \(kIsWeb &&\s+timelineAdDisplayReady &&\s+widget\.initialGenre == null &&\s+_controller\.recommendedBooks\.isNotEmpty &&\s+_controller\.westernBooks\.isNotEmpty\)\s+const TimelineAdSlot\(\s+key: ValueKey\('home-ad-between-new-western'\),\s+slotIndex: 1,/);
  assert.match(home, /if \(_controller\.searchQuery\.isNotEmpty\)\s+_buildSearchResults\(\)\s+else/);
  assert.match(policy, /homeGenreAdSlotCount = 2/);
  assert.match(policy, /homeTimelineAdSlotStart = homeGenreAdSlotCount/);
  assert.match(home, /slotIndex:\s+homeTimelineAdSlotStart \+\s+index ~\/ \(timelinePostsPerAd \+ 1\)/);
  assert.match(html, /if \(sdkScheduled\) return/);
  assert.doesNotMatch(html, /const maxAdsPerPage/);
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

test("simultaneous eligible native slots queue ads and share one async SDK", async () => {
  const r = runtime();
  for (let index = 0; index < 3; index++) r.emitSlot(index);
  await r.flush();
  assert.equal(r.requests.length, 1);
  assert.equal(r.requests[0].src, "https://adm.shinobi.jp/st/t.js");
  assert.equal(r.requests[0].async, true);
  assert.equal(r.sdkBatches[0].length, 3);
  for (const item of r.sdkBatches[0]) {
    assert.equal(item.admax_id, "234edc1d1284546b2d177ac7c5531101");
    assert.equal(item.type, "banner");
  }
  assert.equal(r.window.admaxads.length, 0, "processed entries are discarded");
  for (const target of r.targets) {
    assert.equal(target.getAttribute("data-admax-load"), "sdk-loaded");
  }

  // A later-scrolled slot gets its own request. Previously the stale queue was
  // replayed here, duplicating iframes in already-rendered desktop slots.
  r.emitSlot(3);
  await r.flush();
  assert.equal(r.window.admaxads.length, 0);
  assert.equal(r.requests.length, 2, "SPA SDK reload handles late-mounted slot");
  assert.equal(r.sdkBatches[1].length, 1, "only the new slot is requested");
  assert.equal(r.sdkBatches[1][0].admax_id, "234edc1d1284546b2d177ac7c5531101");
  assert.equal(r.targets[3].getAttribute("data-admax-load"), "sdk-loaded");
});

test("public timeline mounts ads but post detail pages do not", async () => {
  for (const pathname of ["/posts", "/posts/"]) {
    const r = runtime();
    r.window.location.pathname = pathname;
    r.emitSlot(2);
    await r.flush();
    assert.equal(r.requests.length, 1);
  }
  const r = runtime();
  r.window.location.pathname = "/posts/11111111-1111-4111-8111-111111111111";
  r.emitSlot(2);
  await r.flush();
  assert.equal(r.requests.length, 0);
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
    assert.equal(r.entitlementEvents.at(-1), false);
  }
});

test("Flutter hides the complete advertising frame until ads are allowed", async () => {
  const widget = read("lib/widgets/timeline_ad_slot_web.dart");
  assert.match(widget, /sharemarium:admax-entitlement-changed/);
  assert.match(widget, /ValueListenableBuilder<bool>/);
  assert.match(widget, /if \(!allowed\) return const SizedBox\.shrink\(\)/);

  const r = runtime();
  await r.flush();
  assert.equal(r.entitlementEvents.at(-1), true);
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
