const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");

const read = (file) =>
  fs.readFileSync(path.join(__dirname, "../..", file), "utf8");

const adMarkup =
  '<!-- admax -->\n' +
  '<script src="https://adm.shinobi.jp/s/234edc1d1284546b2d177ac7c5531101"></script>\n' +
  '<!-- admax -->';

function createWebController({
  token = "",
  adFree = false,
  failEntitlement = false,
} = {}) {
  const html = read("web/index.html");
  const start = html.indexOf("    <script>\n      (() => {");
  const end = html.indexOf("    </script>", start);
  assert.ok(start >= 0 && end > start, "controller must exist");

  const listeners = new Map();
  const frames = [];
  const win = {
    location: { hostname: "www.sharemarium.com", pathname: "/", search: "" },
    localStorage: {
      length: token ? 1 : 0,
      key: () => (token ? "sb-share-auth-token" : null),
      getItem: () => JSON.stringify({ access_token: token }),
    },
    addEventListener: (name, callback) => listeners.set(name, callback),
    setTimeout: (callback) => callback(),
    history: { pushState() {}, replaceState() {} },
  };
  const doc = {
    hidden: false,
    getElementById: (id) =>
      id === "sharemarium-ninja-admax-official-tag"
        ? { innerHTML: adMarkup }
        : null,
    createElement: (tagName) => {
      assert.equal(tagName, "iframe");
      const frame = {
        style: {},
        attributes: {},
        setAttribute(name, value) { this.attributes[name] = value; },
        removeAttribute(name) { delete this.attributes[name]; },
        remove() { this.removed = true; },
      };
      frames.push(frame);
      return frame;
    },
    addEventListener: (name, callback) => listeners.set("document:" + name, callback),
  };
  const fakeFetch = async () => {
    if (failEntitlement) throw Error("entitlement_failed");
    return { ok: true, json: async () => ({ authenticated: true, adFree }) };
  };
  vm.runInNewContext(html.slice(start + "    <script>".length, end), {
    window: win,
    document: doc,
    fetch: fakeFetch,
  });

  function emitSlot(index) {
    const target = {
      replaceChildren(frame) { this.frame = frame; },
    };
    const root = {
      isConnected: true,
      getAttribute: (attribute) =>
        attribute === "data-sharemarium-admax-slot-index"
          ? String(index)
          : null,
      querySelector: (selector) =>
        selector === ".admax-inline-target" ? target : null,
    };
    listeners.get("sharemarium:admax-slot-ready")({ detail: root });
    return { root, target };
  }
  const flush = () => new Promise((resolve) => setImmediate(resolve));
  return { win, frames, emitSlot, flush, listeners };
}

test("official synchronous tag stays identical inside an inert template", () => {
  const html = read("web/index.html");
  assert.ok(
    html.includes(
      '<template id="sharemarium-ninja-admax-official-tag">\n' +
      adMarkup + '\n    </template>',
    ),
  );
  assert.doesNotMatch(
    html.slice(0, html.indexOf("  <body>")),
    /src="https:\/\/adm\.shinobi\.jp\/s\//,
  );
  assert.equal((html.match(/234edc1d1284546b2d177ac7c5531101/g) || []).length, 1);
});

test("timeline placement is two real posts per ad, capped at three", () => {
  const screen = read("lib/screens/book_list_screen.dart");
  const policy = read("lib/widgets/timeline_ad_policy.dart");
  assert.match(screen, /isTimelineAdItem\(index, postCount\)/);
  assert.match(screen, /timelinePostIndexForItem\(index, postCount\)/);
  assert.match(screen, /kIsWeb && timelineAdEnabled/);
  assert.match(policy, /defaultValue: 2/);
  assert.match(policy, /timelineMaximumAdsPerPage = 3/);
  assert.match(policy, /NINJA_ADMAX_POSTS_PER_AD/);
});

test("only Flutter Web can mount ads and they are disabled by default", () => {
  const platform = read("lib/widgets/timeline_ad_slot.dart");
  const stub = read("lib/widgets/timeline_ad_slot_stub.dart");
  const web = read("lib/widgets/timeline_ad_slot_web.dart");
  assert.match(platform, /if \(dart\.library\.html\) 'timeline_ad_slot_web\.dart'/);
  assert.match(stub, /SizedBox\.shrink/);
  assert.match(web, /HtmlElementView/);
  assert.match(web, /'広告'/);
  assert.match(web, /data-sharemarium-admax-slot-index/);
  assert.match(web, /admax-inline-target/);
  assert.match(read("lib/widgets/timeline_ad_policy.dart"), /defaultValue: false/);
});

test("guest mounts at most three isolated frames, with no extra requests on remount", async () => {
  const runtime = createWebController();
  const root0 = runtime.emitSlot(0);
  runtime.emitSlot(1);
  runtime.emitSlot(2);
  runtime.emitSlot(3);
  await runtime.flush();
  assert.equal(runtime.frames.length, 3);
  assert.ok(root0.target.frame.srcdoc.includes(adMarkup));
  for (const frame of runtime.frames) {
    assert.match(frame.attributes.sandbox, /allow-scripts/);
    assert.match(frame.srcdoc, /<script src="https:\/\/adm\.shinobi\.jp\/s\//);
  }
  const replacement = runtime.emitSlot(0);
  await runtime.flush();
  assert.equal(runtime.frames.length, 3);
  assert.strictEqual(replacement.target.frame, runtime.frames[0]);

  runtime.win.location.pathname = "/login";
  runtime.win.history.pushState({}, "", "/login");
  await runtime.flush();
  assert.ok(runtime.frames.every((frame) => frame.removed));
  runtime.emitSlot(0);
  await runtime.flush();
  assert.equal(runtime.frames.length, 3);
});

test("ad-free users and failed entitlement checks never execute the tag", async () => {
  for (const options of [
    { token: "valid-token", adFree: true },
    { token: "valid-token", failEntitlement: true },
  ]) {
    const runtime = createWebController(options);
    runtime.emitSlot(0);
    await runtime.flush();
    assert.equal(runtime.frames.length, 0);
  }
});

test("only an eligible home route can mount the vendor script", async () => {
  const runtime = createWebController();
  runtime.win.location.hostname = "random.example";
  runtime.emitSlot(0);
  await runtime.flush();
  assert.equal(runtime.frames.length, 0);
  runtime.win.location.hostname = "www.sharemarium.com";
  runtime.win.location.search = "?seo_preview=1";
  runtime.emitSlot(0);
  await runtime.flush();
  assert.equal(runtime.frames.length, 0);
});

test("retired AdSense and the obsolete global switch loader are absent", () => {
  const html = read("web/index.html");
  const seo = read("api/seo.js");
  assert.doesNotMatch(html, /googlesyndication|adsbygoogle|ca-pub-/);
  assert.doesNotMatch(seo, /googlesyndication|adsbygoogle|ca-pub-/);
  assert.doesNotMatch(html, /window\.admaxads|publisherLoader|adRequested/);
  assert.match(html, /window\.location\.hostname === expectedHost/);
  assert.match(html, /entitlementState !== "ads_allowed"/);
});

test("Terms and subscription visibility remain unchanged", () => {
  const flags = read("lib/config/feature_flags.dart");
  assert.match(flags, /subscriptionUiEnabled = false/);
});
