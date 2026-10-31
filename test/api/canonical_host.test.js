const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.join(__dirname, "../..");
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), "utf8");

const BARE_ORIGIN_RE = /https:\/\/sharemarium\.com(?=\/|["'`\s])/;

test("all crawler-facing production SEO surfaces use the www canonical origin", () => {
  const files = [
    "api/seo.js",
    "api/legal-seo.js",
    "api/sitemap.js",
    "api/posts-seo.js",
    "api/post-seo.js",
    "web/index.html",
    "web/robots.txt",
  ];

  for (const file of files) {
    const source = read(file);
    assert.doesNotMatch(
      source,
      BARE_ORIGIN_RE,
      `${file} must not emit the redirecting bare origin`,
    );
  }

  assert.match(
    read("web/index.html"),
    /rel="canonical" href="https:\/\/www\.sharemarium\.com\/"/,
  );
  assert.match(
    read("web/robots.txt"),
    /Sitemap: https:\/\/www\.sharemarium\.com\/sitemap\.xml/,
  );
});

test("legacy Vercel production host permanently redirects to the canonical www host", () => {
  const config = JSON.parse(read("vercel.json"));
  const redirects = config.routes?.filter(
    (route) => route.status === 308 && route.headers?.Location,
  );
  const redirect = redirects.find(
    (route) =>
      route.src === "/(.*)" &&
      route.has?.[0]?.value === "book-case-u9uq.vercel.app",
  );

  assert.equal(redirect?.src, "/(.*)");
  assert.deepEqual(redirect?.has, [
    {
      type: "host",
      value: "book-case-u9uq.vercel.app",
    },
  ]);
  assert.equal(redirect?.status, 308);
  assert.equal(
    redirect?.headers?.Location,
    "https://www.sharemarium.com/$1",
  );
  assert.ok(
    redirects.some(
      (route) => route.has?.[0]?.value === "sharemariumbookcase.vercel.app",
    ),
  );

  const legacyBookRedirect = redirects.find(
    (route) =>
      route.src === "/book/nanji-hoshi-no-gotoku" &&
      route.has?.[0]?.value === "book-case-u9uq.vercel.app",
  );
  assert.equal(
    legacyBookRedirect?.headers?.Location,
    "https://www.sharemarium.com/book/9784065281499",
  );
});

test("staging sends a noindex response header", () => {
  const config = JSON.parse(read("vercel.json"));
  const staging = config.headers.find(
    (entry) => entry.has?.[0]?.value === "staging.sharemarium.com",
  );
  assert.ok(staging);
  assert.deepEqual(staging.headers, [
    { key: "X-Robots-Tag", value: "noindex, nofollow" },
  ]);
});

test("canonical production smoke default stays www but Vercel fallback uses its own URL", () => {
  assert.match(
    read("scripts/production-smoke.mjs"),
    /DEFAULT_BASE_URL = "https:\/\/www\.sharemarium\.com"/,
  );
  const vercelRollback = read(".github/workflows/deploy.yaml");
  assert.match(
    vercelRollback,
    /SMOKE_BASE_URL: \$\{\{ steps\.deploy_fallback\.outputs\.url \}\}/,
  );
  assert.doesNotMatch(
    vercelRollback,
    /SMOKE_BASE_URL: https:\/\/www\.sharemarium\.com/,
  );
  const cloudflareDeploy = read(".github/workflows/deploy-cloudflare-production.yaml");
  assert.match(cloudflareDeploy, /EXPECT_NOINDEX: "true"/);
});
