const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  MIN_SUBSTANTIVE_REVIEW_CHARS,
  MIN_SUBSTANTIVE_PUBLIC_REVIEWS,
  MIN_DISTINCT_PUBLIC_REVIEW_AUTHORS,
  evaluatePublisherContent,
  fetchHomeAdEligibility,
} = require("../../api/_home_ad_eligibility");

function review({
  id,
  profileId,
  length = MIN_SUBSTANTIVE_REVIEW_CHARS,
  spoiler = false,
}) {
  return {
    id,
    profile_id: profileId,
    comment: "あ".repeat(length),
    is_spoiler: spoiler,
  };
}

test("home ads require multiple substantive reviews from multiple authors", () => {
  assert.equal(MIN_SUBSTANTIVE_REVIEW_CHARS, 120);
  assert.equal(MIN_SUBSTANTIVE_PUBLIC_REVIEWS, 5);
  assert.equal(MIN_DISTINCT_PUBLIC_REVIEW_AUTHORS, 3);

  const tooFewReviews = [
    review({ id: "1", profileId: "author-a" }),
    review({ id: "2", profileId: "author-b" }),
    review({ id: "3", profileId: "author-c" }),
    review({ id: "4", profileId: "author-a" }),
  ];
  assert.equal(evaluatePublisherContent(tooFewReviews).eligible, false);

  const tooFewAuthors = Array.from({ length: 5 }, (_, index) =>
    review({
      id: String(index + 1),
      profileId: index % 2 === 0 ? "author-a" : "author-b",
    }),
  );
  assert.equal(evaluatePublisherContent(tooFewAuthors).eligible, false);

  const enoughPublisherContent = [
    review({ id: "1", profileId: "author-a" }),
    review({ id: "2", profileId: "author-b" }),
    review({ id: "3", profileId: "author-c" }),
    review({ id: "4", profileId: "author-a" }),
    review({ id: "5", profileId: "author-b" }),
  ];
  assert.deepEqual(evaluatePublisherContent(enoughPublisherContent), {
    eligible: true,
    substantiveReviewCount: 5,
    distinctAuthorCount: 3,
  });

  const withThinAndSpoiler = [
    ...enoughPublisherContent.slice(0, 4),
    review({
      id: "thin",
      profileId: "author-c",
      length: MIN_SUBSTANTIVE_REVIEW_CHARS - 1,
    }),
    review({
      id: "spoiler",
      profileId: "author-c",
      spoiler: true,
    }),
  ];
  assert.equal(evaluatePublisherContent(withThinAndSpoiler).eligible, false);
});

test("home ad eligibility is fail-closed without enough original public content", async () => {
  const baseEnv = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_ANON_KEY: "anon-key",
  };

  const noReviews = await fetchHomeAdEligibility({
    env: baseEnv,
    request: async () => ({
      ok: true,
      status: 200,
      json: async () => [],
    }),
  });
  assert.deepEqual(noReviews, {
    eligible: false,
    diagnostic: "ok;reviews=0;authors=0",
  });

  const insufficientDiversity = await fetchHomeAdEligibility({
    env: baseEnv,
    request: async (url) => {
      const requested = new URL(String(url));
      assert.equal(requested.searchParams.get("is_spoiler"), "is.false");
      assert.equal(
        requested.searchParams.get("select"),
        "id,profile_id,comment,is_spoiler",
      );
      assert.equal(requested.searchParams.get("limit"), "100");
      return {
        ok: true,
        status: 200,
        json: async () =>
          Array.from({ length: 5 }, (_, index) =>
            review({
              id: String(index + 1),
              profileId: index % 2 === 0 ? "author-a" : "author-b",
            }),
          ),
      };
    },
  });
  assert.deepEqual(insufficientDiversity, {
    eligible: false,
    diagnostic: "ok;reviews=5;authors=2",
  });

  const enoughPublisherContent = await fetchHomeAdEligibility({
    env: baseEnv,
    request: async () => ({
      ok: true,
      status: 200,
      json: async () => [
        review({ id: "1", profileId: "author-a" }),
        review({ id: "2", profileId: "author-b" }),
        review({ id: "3", profileId: "author-c" }),
        review({ id: "4", profileId: "author-a" }),
        review({ id: "5", profileId: "author-b" }),
      ],
    }),
  });
  assert.deepEqual(enoughPublisherContent, {
    eligible: true,
    diagnostic: "ok;reviews=5;authors=3",
  });
});

test("crawler renderer cannot inject legacy AdSense or new Ninja AdMax", () => {
  const seoHome = fs.readFileSync(
    path.join(__dirname, "../../api/seo-home.js"),
    "utf8",
  );
  const seo = fs.readFileSync(
    path.join(__dirname, "../../api/seo.js"),
    "utf8",
  );
  assert.doesNotMatch(seoHome + seo, /googlesyndication|adsbygoogle|ca-pub-/);
  assert.doesNotMatch(seoHome + seo, /adm\.shinobi\.jp/);
  assert.match(seoHome, /path: "\/"/);
});

test("crawler and SEO preview home requests pass through seo-router", () => {
  const vercel = JSON.parse(
    fs.readFileSync(path.join(__dirname, "../../vercel.json"), "utf8"),
  );
  const rootCrawler = vercel.routes.find(
    (route) => route.src === "/" && route.has?.some((entry) => entry.key === "user-agent"),
  );
  const preview = vercel.routes.find(
    (route) => route.src === "/(.*)" && route.has?.some((entry) => entry.key === "seo_preview"),
  );

  assert.equal(rootCrawler?.dest, "/api/seo-router?path=/");
  assert.equal(preview?.dest, "/api/seo-router?path=/$1");

  const router = fs.readFileSync(
    path.join(__dirname, "../../api/seo-router.js"),
    "utf8",
  );
  assert.match(router, /normalizedPath === "\/"/);
  assert.match(router, /return seoHome/);
});
