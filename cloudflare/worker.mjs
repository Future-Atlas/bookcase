import adEntitlement from "../api/ad-entitlement.js";
import homeAdEligibility from "../api/home-ad-eligibility.js";
import legalSeo from "../api/legal-seo.js";
import postSeo from "../api/post-seo.js";
import postsSeo from "../api/posts-seo.js";
import rakuten from "../api/rakuten.js";
import seo from "../api/seo.js";
import seoHome from "../api/seo-home.js";
import seoRouter from "../api/seo-router.js";
import sitemap from "../api/sitemap.js";

const BOT_PATTERN =
  /(googlebot|mediapartners-google|google-display-ads-bot|bingbot|yandexbot|duckduckbot|baiduspider|twitterbot|facebookexternalhit|facebot|linkedinbot|embedly|quora|slackbot)/i;
const SEO_PATH_PATTERN =
  /^\/(?:featured-books|genre\/.*|book\/.*|user\/.*|users\/.*|profile\/.*|privacy|terms|community-guidelines|infringement-policy|external-transmission|contact|about)$/;
const LEGAL_PATH_PATTERN =
  /^\/(privacy|terms|community-guidelines|infringement-policy|external-transmission)$/;

class VercelResponseAdapter {
  constructor() {
    this.statusCode = 200;
    this.headers = new Headers();
    this.body = "";
  }

  status(code) {
    this.statusCode = Number(code) || 200;
    return this;
  }

  setHeader(name, value) {
    this.headers.set(name, String(value));
    return this;
  }

  json(value) {
    if (!this.headers.has("Content-Type")) {
      this.headers.set("Content-Type", "application/json; charset=utf-8");
    }
    this.body = JSON.stringify(value);
    return this;
  }

  send(value) {
    this.body = value == null ? "" : value;
    return this;
  }

  toResponse() {
    return new Response(this.body, {
      status: this.statusCode,
      headers: this.headers,
    });
  }
}

function queryFromUrl(url) {
  const query = {};
  for (const [key, value] of url.searchParams) {
    if (query[key] == null) {
      query[key] = value;
    } else if (Array.isArray(query[key])) {
      query[key].push(value);
    } else {
      query[key] = [query[key], value];
    }
  }
  return query;
}

function requestHeaders(request) {
  const headers = Object.fromEntries(
    [...request.headers.entries()].map(([key, value]) => [
      key.toLowerCase(),
      value,
    ]),
  );
  const connectingIp = request.headers.get("cf-connecting-ip");
  if (connectingIp) {
    headers["x-real-ip"] ||= connectingIp;
    headers["x-forwarded-for"] ||= connectingIp;
  }
  return headers;
}

async function invoke(handler, request, extraQuery = {}) {
  const url = new URL(request.url);
  const req = {
    method: request.method,
    headers: requestHeaders(request),
    query: { ...queryFromUrl(url), ...extraQuery },
    url: `${url.pathname}${url.search}`,
  };
  const res = new VercelResponseAdapter();
  await handler(req, res);
  return res.toResponse();
}

function redirect(request, pathname, status = 308) {
  const target = new URL(request.url);
  target.pathname = pathname;
  return Response.redirect(target, status);
}

function withEnvironmentHeaders(response, env, request) {
  const headers = new Headers(response.headers);
  headers.set("X-Content-Type-Options", "nosniff");
  const hostname = new URL(request.url).hostname;
  if (env.APP_ENV !== "production" || hostname.endsWith(".workers.dev")) {
    headers.set("X-Robots-Tag", "noindex, nofollow");
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function routeRequest(request, env) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/{2,}/g, "/");

  if (env.APP_ENV !== "production" && path === "/robots.txt") {
    return new Response("User-agent: *\nDisallow: /\n", {
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  if (path === "/sitemap") return redirect(request, "/sitemap.xml");
  if (path === "/user") return redirect(request, "/users");
  if (path.startsWith("/user/")) {
    return redirect(request, `/users/${path.slice("/user/".length)}`);
  }
  if (path === "/profile") return redirect(request, "/users");
  if (path.startsWith("/profile/")) {
    return redirect(request, `/users/${path.slice("/profile/".length)}`);
  }

  if (path === "/sitemap.xml" || path === "/api/sitemap") {
    return invoke(sitemap, request);
  }
  if (path === "/api/rakuten") return invoke(rakuten, request);
  if (path === "/api/ad-entitlement") {
    return invoke(adEntitlement, request);
  }
  if (path === "/api/home-ad-eligibility") {
    return invoke(homeAdEligibility, request);
  }
  if (path === "/api/posts-seo") return invoke(postsSeo, request);
  if (path === "/api/post-seo") return invoke(postSeo, request);
  if (path === "/api/legal-seo") return invoke(legalSeo, request);
  if (path === "/api/seo-home") return invoke(seoHome, request);
  if (path === "/api/seo") return invoke(seo, request);
  if (path === "/api/seo-router") return invoke(seoRouter, request);

  const userAgent = request.headers.get("user-agent") || "";
  const isCrawler = BOT_PATTERN.test(userAgent);
  if (path === "/posts" && isCrawler) {
    return invoke(postsSeo, request);
  }
  const postMatch = /^\/posts\/([^/]+)$/.exec(path);
  if (postMatch && isCrawler) {
    return invoke(postSeo, request, {
      post_id: decodeURIComponent(postMatch[1]),
    });
  }

  if (url.searchParams.get("seo_preview") === "1") {
    return invoke(seoRouter, request, { path });
  }
  if (isCrawler && (path === "/" || SEO_PATH_PATTERN.test(path))) {
    if (LEGAL_PATH_PATTERN.test(path)) {
      return invoke(legalSeo, request, { path: path.slice(1) });
    }
    return invoke(seoRouter, request, { path });
  }

  return env.ASSETS.fetch(request);
}

export default {
  async fetch(request, env) {
    try {
      return withEnvironmentHeaders(
        await routeRequest(request, env),
        env,
        request,
      );
    } catch {
      return withEnvironmentHeaders(
        new Response("Internal Server Error", { status: 500 }),
        env,
        request,
      );
    }
  },
};

export const _test = {
  BOT_PATTERN,
  SEO_PATH_PATTERN,
  VercelResponseAdapter,
  queryFromUrl,
  routeRequest,
};
