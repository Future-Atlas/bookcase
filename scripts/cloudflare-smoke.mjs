import { writeFileSync } from "node:fs";

const baseUrl = String(process.env.SMOKE_BASE_URL || "").replace(/\/+$/, "");
const expectNoindex = process.env.EXPECT_NOINDEX === "true";
const diagnosticPath = process.env.SMOKE_DIAGNOSTIC_FILE || "";
const diagnostics = [];

// This file contains only predetermined check labels, outcome codes, and HTTP status.
// Never record URL strings, response headers, bodies, exception messages, or credentials.
function record(checkName, outcome, httpStatus) {
  const entry = { check: checkName, outcome };
  if (Number.isInteger(httpStatus)) entry.http_status = httpStatus;
  diagnostics.push(entry);
  if (diagnosticPath) writeFileSync(diagnosticPath, `${JSON.stringify(diagnostics, null, 2)}\n`, "utf8");
}

function validateBaseUrl() {
  try {
    const parsed = new URL(baseUrl);
    if (
      parsed.protocol !== "https:" ||
      parsed.username ||
      parsed.password ||
      parsed.pathname !== "/" ||
      parsed.search ||
      parsed.hash ||
      parsed.origin !== baseUrl
    ) throw new Error("invalid");
  } catch {
    record("base_url", baseUrl ? "invalid" : "missing");
    throw new Error("Cloudflare smoke base URL is missing or invalid");
  }
  record("base_url", "ok");
}

async function check(name, pathname, { bot = false, htmlNavigation = false, contentType, staticAsset = false } = {}) {
  let response;
  try {
    response = await fetch(`${baseUrl}${pathname}`, {
      redirect: "manual",
      headers: {
        ...(bot ? { "User-Agent": "Googlebot/2.1" } : {}),
        ...(htmlNavigation ? { Accept: "text/html" } : {}),
      },
    });
  } catch {
    record(name, "network_error");
    throw new Error(`Cloudflare smoke check ${name} failed: network_error`);
  }
  if (response.status !== 200) {
    record(name, "http_status", response.status);
    throw new Error(`Cloudflare smoke check ${name} returned HTTP ${response.status}`);
  }
  if (contentType && !String(response.headers.get("content-type")).includes(contentType)) {
    record(name, "content_type_mismatch", response.status);
    throw new Error(`Cloudflare smoke check ${name} has unexpected content type`);
  }
  if (expectNoindex && !staticAsset && !String(response.headers.get("x-robots-tag") || "").includes("noindex")) {
    record(name, "missing_noindex", response.status);
    throw new Error(`Cloudflare smoke check ${name} lacks noindex`);
  }
  record(name, "ok", response.status);
}

validateBaseUrl();
await check("home", "/", { contentType: "text/html" });
 // These files are served by Cloudflare's static asset binding, without
 // Worker-injected X-Robots-Tag. The site's staging robots.txt still blocks crawlers.
 // Check MIME types so a 200 OK SPA HTML fallback cannot pass as a JS/Wasm file.
await check("flutter_bootstrap", "/flutter_bootstrap.js", { contentType: "javascript", staticAsset: true });
await check("canvaskit_chromium_js", "/canvaskit/chromium/canvaskit.js", { contentType: "javascript", staticAsset: true });
await check("canvaskit_chromium_wasm", "/canvaskit/chromium/canvaskit.wasm", { contentType: "application/wasm", staticAsset: true });
// A clean Flutter path must be served as an SPA navigation, not a 404.
await check("login_path", "/login", { htmlNavigation: true, contentType: "text/html" });
await check("settings_path", "/settings", { htmlNavigation: true, contentType: "text/html" });
await check("posts_human", "/posts", { htmlNavigation: true, contentType: "text/html" });
await check("api", "/api/home-ad-eligibility", { contentType: "application/json" });
await check("sitemap", "/sitemap.xml", { contentType: "application/xml" });
await check("privacy", "/privacy?seo_preview=1", { contentType: "text/html" });
await check("posts_crawler", "/posts", { bot: true, contentType: "text/html" });

console.log("Cloudflare smoke checks passed.");
