const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const test = require("node:test");

async function loadSmokeModule() {
  const moduleUrl = pathToFileURL(
    path.resolve(__dirname, "../../scripts/production-smoke.mjs"),
  ).href;
  return import(moduleUrl);
}

test("production smoke profile keeps public SEO and AdSense endpoints", async () => {
  const { smokeChecksForProfile } = await loadSmokeModule();
  const paths = smokeChecksForProfile("production").map((check) => check.path);

  assert.deepEqual(paths, ["/", "/robots.txt", "/sitemap.xml", "/ads.txt"]);
});

test("staging smoke profile validates the app asset and Vercel API runtime", async () => {
  const { smokeChecksForProfile } = await loadSmokeModule();
  const paths = smokeChecksForProfile("staging").map((check) => check.path);

  assert.deepEqual(paths, [
    "/",
    "/flutter_bootstrap.js",
    "/api/home-ad-eligibility",
  ]);
  assert.equal(paths.includes("/ads.txt"), false);
  assert.equal(paths.includes("/sitemap.xml"), false);
});

test("unknown smoke profiles fail closed", async () => {
  const { smokeChecksForProfile } = await loadSmokeModule();

  assert.throws(
    () => smokeChecksForProfile("unknown"),
    /Unsupported SMOKE_PROFILE: unknown/,
  );
});

test("manual Vercel staging fallback uploads Flutter output and API source instead of a preview prebuild", () => {
  const root = path.resolve(__dirname, "../..");
  const workflow = fs.readFileSync(
    path.join(root, ".github/workflows/deploy-staging.yaml"),
    "utf8",
  );
  const vercelIgnore = fs.readFileSync(
    path.join(root, ".vercelignore"),
    "utf8",
  );

  assert.match(workflow, /npm install --global vercel@59\.18\.0/);
  assert.doesNotMatch(workflow, /vercel@58\.7\.1/);
  assert.match(workflow, /VERCEL_TOKEN: \$\{\{ secrets\.VERCEL_TOKEN \}\}/);
  assert.doesNotMatch(workflow, /--token/);
  assert.match(workflow, /vercel deploy \. --force/);
  assert.doesNotMatch(workflow, /vercel deploy --prebuilt/);
  assert.doesNotMatch(workflow, /--prod/);
  assert.match(workflow, /test -s build\/web\/flutter_bootstrap\.js/);
  assert.match(workflow, /vercel deploy \. --dry --format=json/);
  assert.match(workflow, /grep -q 'build\/web\/flutter_bootstrap\.js'/);
  assert.match(workflow, /grep -q 'api\/home-ad-eligibility\.js'/);
  assert.match(workflow, /bash scripts\/staging-smoke\.sh/);

  assert.match(vercelIgnore, /^\/\*/m);
  assert.match(vercelIgnore, /^!api$/m);
  assert.match(vercelIgnore, /^!build$/m);
  assert.match(vercelIgnore, /^!lib$/m);
  assert.match(vercelIgnore, /^!vercel\.json$/m);
});

test("staging smoke uses Vercel env auth with the full preview URL", () => {
  const script = fs.readFileSync(
    path.resolve(__dirname, "../../scripts/staging-smoke.sh"),
    "utf8",
  );

  assert.match(script, /VERCEL_TOKEN:\?VERCEL_TOKEN is required/);
  assert.match(script, /base_url="\$\{DEPLOYMENT_URL%\/\}"/);
  assert.match(script, /local url="\$\{base_url\}\$\{path\}"/);
  assert.match(script, /vercel curl "\$url"/);
  assert.match(script, /--location/);
  assert.match(script, /--fail/);
  assert.match(script, /--silent/);
  assert.match(script, /--show-error/);
  assert.match(script, /--dump-header "\$headers"/);
  assert.match(script, /--output "\$body"/);
  assert.doesNotMatch(script, /--token/);
  assert.doesNotMatch(script, /--scope/);
  assert.doesNotMatch(script, /--deployment/);
  assert.match(script, /\/flutter_bootstrap\.js/);
  assert.match(script, /\/api\/home-ad-eligibility/);
});


test("Vercel production workflow is manual fallback only after Cloudflare migration", () => {
  const workflow = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/deploy.yaml"), "utf8");
  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /\n\s*push:/);
  assert.match(workflow, /inputs\.confirmation == 'ROLLBACK'/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /SMOKE_BASE_URL: \$\{\{ steps\.deploy_fallback\.outputs\.url \}\}/);
  assert.doesNotMatch(workflow, /--token=/);
  assert.match(workflow, /vercel deploy --prebuilt --prod/);
});

test("Cloudflare is the default staging deploy while Vercel remains a manual fallback", () => {
  const cloudflare = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/deploy-cloudflare-staging.yaml"), "utf8");
  const vercel = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/deploy-staging.yaml"), "utf8");
  assert.match(cloudflare, /on:\n  push:\n    branches:\n      - develop/);
  assert.match(cloudflare, /workflow_dispatch:/);
  assert.match(cloudflare, /github\.ref == 'refs\/heads\/develop'/);
  assert.match(cloudflare, /name: staging/);
  assert.match(cloudflare, /command: deploy --env staging/);
  assert.match(cloudflare, /EXPECT_NOINDEX: "true"/);
  assert.match(cloudflare, /SMOKE_BASE_URL: \$\{\{ steps\.deploy\.outputs\.deployment-url \}\}/);
  assert.match(vercel, /workflow_dispatch:/);
  assert.doesNotMatch(vercel, /\n\s*push:/);
  assert.match(vercel, /inputs\.confirmation == 'ROLLBACK'/);
  assert.match(vercel, /github\.ref == 'refs\/heads\/develop'/);
  assert.match(vercel, /vercel deploy \. --force/);
  assert.doesNotMatch(vercel, /vercel deploy .*--prod/);
});

test("Wrangler action uploads secrets to the same Cloudflare Worker environment as deploy", () => {
  const staging = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/deploy-cloudflare-staging.yaml"), "utf8");
  const production = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/deploy-cloudflare-production.yaml"), "utf8");
  for (const [workflow, environment] of [[staging, "staging"], [production, "production"]]) {
    // GitHub job.environment only selects the GitHub secrets scope.
    // The action's with.environment is separately required for wrangler secret bulk --env.
    const expected = `          wranglerVersion: "4.151.1"\n          environment: ${environment}\n          command: deploy --env ${environment}`;
    assert.ok(workflow.includes(expected), `wrangler-action must scope secrets to ${environment}`);
  }
});
