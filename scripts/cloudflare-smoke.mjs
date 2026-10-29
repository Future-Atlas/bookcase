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

async function check(name, pathname, { bot = false, htmlNavigation = false, contentType, checkFlutterCsp = false, noindex = expectNoindex } = {}) {
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
  if (noindex && !String(response.headers.get("x-robots-tag") || "").includes("noindex")) {
    record(name, "missing_noindex", response.status);
    throw new Error(`Cloudflare smoke check ${name} lacks noindex`);
  }
  if (checkFlutterCsp) {
    const policy = response.headers.get("content-security-policy") || "";
    if (!/script-src[^;]*https:\/\/www\.gstatic\.com\/flutter-canvaskit\//.test(policy)) {
      record(name, "flutter_canvas_kit_blocked", response.status);
      throw new Error("Cloudflare smoke check detected an incompatible Flutter CSP");
    }
  }
  record(name, "ok", response.status);
}

validateBaseUrl();
await check("home", "/", { contentType: "text/html", checkFlutterCsp: true });
// A healthy HTML response is not sufficient: the Flutter bootstrap and entrypoint
// must be served as JavaScript, not as an HTML SPA fallback.
await check("flutter_bootstrap", "/flutter_bootstrap.js", { contentType: "javascript", noindex: false });
await check("flutter_entrypoint", "/main.dart.js", { contentType: "javascript", noindex: false });
// A clean Flutter path must be served as an SPA navigation, not a 404.
await check("login_path", "/login", { htmlNavigation: true, contentType: "text/html" });
await check("settings_path", "/settings", { htmlNavigation: true, contentType: "text/html" });
await check("posts_human", "/posts", { htmlNavigation: true, contentType: "text/html" });
await check("api", "/api/home-ad-eligibility", { contentType: "application/json" });
await check("sitemap", "/sitemap.xml", { contentType: "application/xml" });
await check("privacy", "/privacy?seo_preview=1", { contentType: "text/html" });
await check("posts_crawler", "/posts", { bot: true, contentType: "text/html" });

console.log("Cloudflare smoke checks passed.");
