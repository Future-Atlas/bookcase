const baseUrl = String(process.env.SMOKE_BASE_URL || "").replace(/\/+$/, "");
const expectNoindex = process.env.EXPECT_NOINDEX === "true";

if (!baseUrl.startsWith("https://")) {
  throw new Error("SMOKE_BASE_URL must be an https URL");
}

async function check(pathname, { bot = false, contentType } = {}) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    redirect: "manual",
    headers: bot ? { "User-Agent": "Googlebot/2.1" } : {},
  });
  if (response.status !== 200) {
    throw new Error(`${pathname} returned ${response.status}`);
  }
  if (contentType && !String(response.headers.get("content-type")).includes(contentType)) {
    throw new Error(`${pathname} did not return ${contentType}`);
  }
  if (expectNoindex) {
    const robots = String(response.headers.get("x-robots-tag") || "");
    if (!robots.includes("noindex")) {
      throw new Error(`${pathname} is missing the staging noindex header`);
    }
  }
  return response;
}

await check("/", { contentType: "text/html" });
await check("/api/home-ad-eligibility", { contentType: "application/json" });
await check("/sitemap.xml", { contentType: "application/xml" });
await check("/privacy?seo_preview=1", { contentType: "text/html" });
await check("/posts", { bot: true, contentType: "text/html" });

console.log(`Cloudflare smoke checks passed: ${baseUrl}`);
