// Vercel serverless function to return crawler-friendly HTML for Sharemarium.
// Policy: no Google APIs. Data source order is Rakuten first, then NDL fallback.

const { requestRakuten } = require("./_rakuten_request");
const { isSubstantivePublicReview } = require("./_home_ad_eligibility");
const {
  isIndexableProfileSummary,
  isIndexableReview,
} = require("./_seo_content_quality");

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const RAKUTEN_APP_ID = process.env.RAKUTEN_APP_ID || "";
const RAKUTEN_ACCESS_KEY = process.env.RAKUTEN_ACCESS_KEY || "";
const RAKUTEN_AFFILIATE_ID = (process.env.RAKUTEN_AFFILIATE_ID || "").trim();
const RAKUTEN_REFERER =
  process.env.RAKUTEN_REFERER || "https://www.sharemarium.com/";
const IS_PRODUCTION = process.env.VERCEL_ENV === "production";
const ENABLE_NDL_FALLBACK =
  String(process.env.SEO_ENABLE_NDL_FALLBACK || "false").toLowerCase() ===
  "true";

const RAKUTEN_BOOK_API =
  "https://openapi.rakuten.co.jp/services/api/BooksBook/Search/20170404";
const RAKUTEN_FOREIGN_BOOK_API =
  "https://openapi.rakuten.co.jp/services/api/BooksForeignBook/Search/20170404";
const NDL_OPENSEARCH_API = "https://ndlsearch.ndl.go.jp/api/opensearch";
const SITE_URL = "https://www.sharemarium.com";
const SITE_NAME = "Sharemarium";
const SITE_ALT_NAME = "シェアマリウム";
const SITE_BRAND = `${SITE_NAME}（${SITE_ALT_NAME}）`;
const SITE_TITLE = "Sharemarium（シェアマリウム） | 読書レビューSNS";
const TOP_DESCRIPTION =
  "Sharemarium（シェアマリウム）は、読んだ本を記録し、感想をみんなと共有できる読書レビューSNSです。自分用の読書記録にも、お友だちとの感想共有にも使えるSharemariumで、あなただけの本棚を作りましょう。";
const OG_IMAGE_URL = `${SITE_URL}/icons/Icon-512.png`;

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function parseJsonSafe(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function errorCodeFromText(bodyText) {
  const parsed = parseJsonSafe(bodyText);
  if (!parsed) return "unparseable";
  return (
    parsed?.errors?.errorCode ||
    parsed?.error?.code ||
    parsed?.errorCode ||
    "unknown"
  );
}

function supabaseHeaders() {
  return {
    apikey: SUPABASE_ANON_KEY,
    Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
  };
}

async function supabaseGet(pathAndQuery) {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return null;

  const response = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
    headers: supabaseHeaders(),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Supabase request failed: ${response.status} ${body}`);
  }

  return parseJsonSafe(body) || [];
}

async function fetchFeaturedBooks() {
  const rows =
    (await supabaseGet(
      "featured_books?select=book_id,book_title,book_author,book_publisher,book_cover_url,book_description,related_screen_titles,priority,starts_at,ends_at&order=priority.asc,created_at.desc",
    )) || [];
  return rows.filter(
    (row) => row && row.book_id && row.book_title,
  );
}

function renderFeaturedBookList(books) {
  if (!books.length) return "<p>現在、公開中の注目書籍はありません。</p>";
  return books
    .map(
      (book) => `<article class="book-item">
        <div class="book-details">
          <h3 class="book-title"><a href="/book/${encodeURIComponent(book.book_id)}">${escapeHtml(book.book_title)}</a></h3>
          ${book.book_author ? `<p class="book-author">著者：${escapeHtml(book.book_author)}</p>` : ""}
          <p><a href="/book/${encodeURIComponent(book.book_id)}">作品概要・レビューを見る</a></p>
        </div>
      </article>`,
    )
    .join("");
}

function rakutenEnabled() {
  return RAKUTEN_APP_ID !== "" && RAKUTEN_ACCESS_KEY !== "";
}

function rakutenBaseParams() {
  return `format=json&applicationId=${encodeURIComponent(
    RAKUTEN_APP_ID,
  )}&accessKey=${encodeURIComponent(RAKUTEN_ACCESS_KEY)}${RAKUTEN_AFFILIATE_ID ? `&affiliateId=${encodeURIComponent(RAKUTEN_AFFILIATE_ID)}` : ""}`;
}

async function rakutenFetch(url, request = requestRakuten) {
  return request(url, {
    origin: RAKUTEN_REFERER,
    userAgent: "Sharemarium-SEO-Bot/1.0 (+https://www.sharemarium.com)",
  });
}

// Only a genuine, HTTPS Rakuten book-product link can be paired with the
// API-provided description / cover on publicly crawled catalog pages.
function validRakutenProductUrl(item) {
  const validProduct = (value) => {
    try {
      const url = new URL(value);
      return url.protocol === "https:" && url.hostname === "books.rakuten.co.jp" &&
        !url.username && !url.password && !url.port &&
        /^\/rb\/\d+\/?$/.test(url.pathname);
    } catch {
      return false;
    }
  };
  try {
    const affiliate = new URL(item?.affiliateUrl || "");
    if (affiliate.protocol === "https:" && affiliate.hostname === "hb.afl.rakuten.co.jp" &&
        !affiliate.username && !affiliate.password && !affiliate.port &&
        affiliate.pathname.startsWith("/hgc/") &&
        validProduct(affiliate.searchParams.get("pc"))) {
      return affiliate.toString();
    }
  } catch { /* Missing affiliate URL: a verified direct product URL is possible. */ }
  return validProduct(item?.itemUrl) ? item.itemUrl : "";
}

function normalizeRakutenBooks(items, sectionTitle) {
  return (items || []).map((item) => {
    const data = item?.Item || {};
    const rakutenUrl = validRakutenProductUrl(data);
    return {
      title: data.title || "不明なタイトル",
      author: data.author || "不明な著者",
      coverUrl: rakutenUrl ? (data.largeImageUrl || "") : "",
      genre: sectionTitle,
      description: rakutenUrl ? (data.itemCaption || "") : "",
      rakutenUrl,
    };
  });
}

function decodeXmlEntities(text) {
  return String(text || "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function extractXmlTag(block, tags) {
  for (const tag of tags) {
    const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i");
    const match = block.match(re);
    if (match && match[1]) {
      return decodeXmlEntities(match[1].trim());
    }
  }
  return "";
}

function normalizeNdlBooks(xmlText, sectionTitle) {
  const items = xmlText.match(/<item>[\s\S]*?<\/item>/gi) || [];
  return items.slice(0, 6).map((itemBlock) => {
    const title = extractXmlTag(itemBlock, ["title", "dc:title"]);
    const author = extractXmlTag(itemBlock, ["author", "dc:creator"]);
    const description = extractXmlTag(itemBlock, ["dc:description"]);
    return {
      title: title || "不明なタイトル",
      author: author || "不明な著者",
      coverUrl: "",
      genre: sectionTitle,
      description,
    };
  });
}

async function fetchRakutenSection(sectionTitle, diagnostics, request = requestRakuten) {
  if (!rakutenEnabled()) {
    diagnostics.rakutenSectionFailures.push(`${sectionTitle}:disabled`);
    return [];
  }

  let endpoint = RAKUTEN_BOOK_API;
  let extra = "page=1&hits=6";

  if (sectionTitle === "おすすめの本") {
    extra += "&booksGenreId=001004";
  } else if (sectionTitle === "洋書") {
    endpoint = RAKUTEN_FOREIGN_BOOK_API;
    extra += "&booksGenreId=005";
  } else if (sectionTitle === "人気作品") {
    extra +=
      "&booksGenreId=001&keyword=%E3%83%99%E3%82%B9%E3%83%88%E3%82%BB%E3%83%A9%E3%83%BC";
  } else {
    return [];
  }

  const url = `${endpoint}?${rakutenBaseParams()}&${extra}`;
  const response = await rakutenFetch(url, request);
  const body = await response.text();
  if (!response.ok) {
    diagnostics.rakutenSectionFailures.push(
      `${sectionTitle}:${response.status}:${errorCodeFromText(body)}`,
    );
    return [];
  }

  const json = parseJsonSafe(body);
  return normalizeRakutenBooks(json?.Items, sectionTitle);
}

async function fetchNdlSection(sectionTitle, diagnostics) {
  let queryParams = "cnt=6&startPage=1&mediatype=1";

  if (sectionTitle === "おすすめの本") {
    queryParams += "&any=%E8%A9%B1%E9%A1%8C%20%E6%9C%AC";
  } else if (sectionTitle === "洋書") {
    queryParams += "&any=English";
  } else if (sectionTitle === "人気作品") {
    queryParams +=
      "&any=%E3%83%99%E3%82%B9%E3%83%88%E3%82%BB%E3%83%A9%E3%83%BC";
  } else {
    return [];
  }

  const url = `${NDL_OPENSEARCH_API}?${queryParams}`;
  const response = await fetch(url);
  const body = await response.text();
  if (!response.ok) {
    diagnostics.ndlSectionFailures.push(`${sectionTitle}:${response.status}`);
    return [];
  }

  const books = normalizeNdlBooks(body, sectionTitle);
  if (books.length === 0) {
    diagnostics.ndlSectionFailures.push(`${sectionTitle}:empty`);
  }
  return books;
}

async function fetchRakutenBookByIsbn(isbn, diagnostics, request = requestRakuten) {
  if (!rakutenEnabled()) return null;
  if (!isbn) return null;

  const compact = String(isbn).replace(/[^0-9Xx]/g, "");
  if (compact.length !== 10 && compact.length !== 13) return null;

  const url = `${RAKUTEN_BOOK_API}?${rakutenBaseParams()}&isbn=${encodeURIComponent(
    compact,
  )}&hits=1&page=1`;
  const response = await rakutenFetch(url, request);
  const body = await response.text();
  if (!response.ok) {
    diagnostics.rakutenIsbnFailures += 1;
    return null;
  }

  const json = parseJsonSafe(body);
  const first = json?.Items?.[0]?.Item;
  if (!first) return null;

  return {
    title: first.title || compact,
    author: first.author || "",
    coverUrl: first.largeImageUrl || "",
    description: first.itemCaption || "",
    publisher: first.publisherName || "",
    isbn: compact,
    rakutenUrl: validRakutenProductUrl(first),
  };
}

async function fetchNdlBookByIsbn(isbn, diagnostics) {
  if (!isbn) return null;

  const compact = String(isbn).replace(/[^0-9Xx]/g, "");
  if (compact.length !== 10 && compact.length !== 13) return null;

  const url = `${NDL_OPENSEARCH_API}?cnt=1&startPage=1&mediatype=1&any=${encodeURIComponent(
    compact,
  )}`;
  const response = await fetch(url);
  const body = await response.text();
  if (!response.ok) {
    diagnostics.ndlIsbnFailures += 1;
    return null;
  }

  const books = normalizeNdlBooks(body, "isbn");
  if (!books.length) {
    diagnostics.ndlIsbnFailures += 1;
    return null;
  }

  return {
    title: books[0].title,
    author: books[0].author,
    coverUrl: "",
  };
}

async function resolveBookByIsbn(isbn, diagnostics, request = requestRakuten) {
  const rakuten = await fetchRakutenBookByIsbn(isbn, diagnostics, request);
  if (rakuten) return rakuten;
  if (!ENABLE_NDL_FALLBACK) return null;
  return fetchNdlBookByIsbn(isbn, diagnostics);
}

function isEligiblePublicBookReview(post) {
  // PostgREST's regular embed is a LEFT join. Require a matching public,
  // non-suspended profile here too, even when the SQL relationship changes.
  return post?.profiles?.is_private === false &&
    post?.profiles?.is_suspended === false && isIndexableReview(post);
}

async function fetchPublicReviewsForBook(bookId, diagnostics) {
  try {
    return (
      (await supabaseGet(
        `posts?book_id=eq.${encodeURIComponent(bookId)}&select=id,comment,is_spoiler,created_at,profiles:profiles!posts_profile_id_fkey!inner(username,is_private,is_suspended)&profiles.is_private=eq.false&profiles.is_suspended=eq.false&order=created_at.desc&limit=50`,
      )) || []
    );
  } catch (err) {
    // Review data is optional for a book overview. A temporary PostgREST or
    // relationship error must not turn a valid catalog page into a 503.
    diagnostics.supabaseBookReviewsError =
      err instanceof Error ? err.message.slice(0, 80) : "unknown";
    return [];
  }
}

function renderBookList(books) {
  if (!books.length) {
    return "<p>現在、表示できる本情報がありません。</p>";
  }

  return books
    .map(
      (book) => `
    <div class="book-item">
      ${book.coverUrl ? `<img class="book-cover" src="${escapeHtml(book.coverUrl)}" alt="${escapeHtml(book.title)} Cover">` : ""}
      <div class="book-details">
        <h4 class="book-title">${escapeHtml(book.title)}</h4>
        <p class="book-author">著者: ${escapeHtml(book.author)}</p>
        ${book.description && book.rakutenUrl ? `<p style="font-size:0.9em; color:#555;">${escapeHtml(book.description)}</p>` : ""}
        ${book.rakutenUrl ? `<p>楽天ブックス提供の情報 <a href="${escapeHtml(book.rakutenUrl)}" target="_blank" rel="sponsored noopener noreferrer">楽天ブックスの商品ページを見る</a></p>` : ""}
      </div>
    </div>
  `,
    )
    .join("");
}

function setDiagnosticsHeader(res, diagnostics) {
  const asciiToken = (value) =>
    encodeURIComponent(String(value || "none")).replace(/%20/g, "+");

  const rakutenDetail = diagnostics.rakutenSectionFailures
    .slice(0, 3)
    .join("|")
    .replace(/\s+/g, "_")
    .replace(/;/g, ",");
  const ndlDetail = diagnostics.ndlSectionFailures
    .slice(0, 3)
    .join("|")
    .replace(/\s+/g, "_")
    .replace(/;/g, ",");

  res.setHeader(
    "X-SEO-Diagnostics",
    [
      `rakuten_section_fail=${diagnostics.rakutenSectionFailures.length}`,
      `rakuten_section_detail=${asciiToken(rakutenDetail)}`,
      `rakuten_isbn_fail=${diagnostics.rakutenIsbnFailures}`,
      `ndl_section_fail=${diagnostics.ndlSectionFailures.length}`,
      `ndl_section_detail=${asciiToken(ndlDetail)}`,
      `ndl_isbn_fail=${diagnostics.ndlIsbnFailures}`,
      `ndl_fallback=${ENABLE_NDL_FALLBACK ? "on" : "off"}`,
      `supabase_index_err=${diagnostics.supabaseIndexError === "none" ? "no" : "yes"}`,
      `supabase_profile_err=${diagnostics.supabaseProfileError === "none" ? "no" : "yes"}`,
      `supabase_book_reviews_err=${diagnostics.supabaseBookReviewsError === "none" ? "no" : "yes"}`,
    ].join(";"),
  );
}

function toAbsoluteUrl(pathname) {
  const normalized = String(pathname || "/").startsWith("/")
    ? String(pathname || "/")
    : `/${String(pathname || "")}`;
  return `${SITE_URL}${normalized}`;
}

function canonicalProfilePath(profileId) {
  const rawId = String(profileId || "").trim();
  if (!rawId) return "/users";
  return `/users/${encodeURIComponent(rawId)}`;
}

function looksLikeUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    String(value || "").trim(),
  );
}

function faqStructuredData() {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: [
      {
        "@type": "Question",
        name: "シェアマリウムとは何ですか？",
        acceptedAnswer: {
          "@type": "Answer",
          text: "シェアマリウムは英字でSharemariumと表記する、読書記録・本管理・レビュー共有のためのWebサービスです。",
        },
      },
      {
        "@type": "Question",
        name: "Sharemariumでは何ができますか？",
        acceptedAnswer: {
          "@type": "Answer",
          text: "本の検索、レビュー投稿、読書記録の管理、タイムライン閲覧ができます。",
        },
      },
      {
        "@type": "Question",
        name: "レビューは誰でも投稿できますか？",
        acceptedAnswer: {
          "@type": "Answer",
          text: "アプリ内アカウントでログインしたユーザーがレビュー投稿できます。",
        },
      },
      {
        "@type": "Question",
        name: "ネタバレを含む感想は投稿できますか？",
        acceptedAnswer: {
          "@type": "Answer",
          text: "投稿時にネタバレを含むことを設定でき、閲覧者が意図せず内容を読まないように配慮しています。",
        },
      },
    ],
  };
}

function organizationStructuredData() {
  return {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: SITE_NAME,
    alternateName: SITE_ALT_NAME,
    url: `${SITE_URL}/`,
    logo: `${SITE_URL}/icons/Icon-192.png`,
  };
}

function breadcrumbStructuredData(items) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      item: item.url,
    })),
  };
}

function itemListStructuredData(sectionTitle, books, pagePath) {
  return {
    "@context": "https://schema.org",
    "@type": "ItemList",
    name: `${sectionTitle}一覧`,
    url: toAbsoluteUrl(pagePath),
    numberOfItems: books.length,
    itemListElement: books.map((book, index) => ({
      "@type": "ListItem",
      position: index + 1,
      item: {
        "@type": "Book",
        name: book.title,
        author: book.author,
        description: book.description || "",
      },
    })),
  };
}

function webApplicationStructuredData() {
  return {
    "@context": "https://schema.org",
    "@type": "WebApplication",
    name: SITE_NAME,
    alternateName: SITE_ALT_NAME,
    url: `${SITE_URL}/`,
    applicationCategory: "LifestyleApplication",
    operatingSystem: "Web",
    inLanguage: "ja",
    description:
      "Sharemarium（シェアマリウム）は、読んだ本、読みたい本、読書履歴、蔵書をまとめて管理できる読書記録Webアプリです。",
  };
}

function siteNavigationStructuredData() {
  const navItems = [
    { name: "ホーム", url: `${SITE_URL}/` },
    { name: "公開レビュー", url: `${SITE_URL}/posts` },
    { name: "運営者情報", url: `${SITE_URL}/about` },
    { name: "お問い合わせ", url: `${SITE_URL}/contact` },
    { name: "プライバシーポリシー", url: `${SITE_URL}/privacy` },
    { name: "利用規約", url: `${SITE_URL}/terms` },
  ];

  return navItems.map((item) => ({
    "@context": "https://schema.org",
    "@type": "SiteNavigationElement",
    name: item.name,
    url: item.url,
  }));
}

function sectionByGenrePath(pathname) {
  const map = {
    "/genre/recommended": "おすすめの本",
    "/genre/western": "洋書",
    "/genre/popular": "人気作品",
  };
  return map[pathname] || "";
}

function genrePathBySection(sectionTitle) {
  const map = {
    おすすめの本: "/genre/recommended",
    洋書: "/genre/western",
    人気作品: "/genre/popular",
  };
  return map[sectionTitle] || "/";
}

function truncateForMeta(text, maxLength = 110) {
  const value = String(text || "")
    .replace(/\s+/g, " ")
    .trim();
  if (!value) return "";
  if (value.length <= maxLength) return value;
  return `${value.slice(0, maxLength - 1)}…`;
}

function buildProfileDescription(username, stats) {
  return truncateForMeta(
    `${username}さんのプロフィールページ。読了数${stats.read}冊、フォロワー${stats.followers}人、フォロー${stats.following}人。書評やお気に入り本をチェックできます。`,
  );
}

function buildGenreDescription(sectionTitle, books) {
  const titles = (books || [])
    .slice(0, 3)
    .map((book) => book?.title)
    .filter(Boolean)
    .join("、");
  if (!titles) {
    return truncateForMeta(
      `Sharemariumの${sectionTitle}ページです。注目タイトルや著者情報、作品概要をまとめて確認できます。`,
    );
  }
  return truncateForMeta(
    `Sharemariumの${sectionTitle}ページです。${titles} などの注目タイトルを一覧で確認できます。`,
  );
}

function buildBookDescription(book) {
  const base = `${book.title}（${book.author}）の紹介ページです。`;
  const detail = book.description
    ? `${book.description} ${book.section}ジャンルの関連作品も確認できます。`
    : `${book.section}ジャンルの関連作品も確認できます。`;
  return truncateForMeta(`${base}${detail}`);
}

module.exports = async (req, res) => {
  const { path } = req.query;
  // Only Cloudflare's bound coordinator may make outbound Rakuten calls.
  // Legacy Vercel requests fail closed rather than bypassing the app-ID quota.
  const rakutenRequest = typeof req.rakutenRequest === "function"
    ? req.rakutenRequest
    : async () => ({
        ok: false,
        status: 503,
        text: async () => '{"error":"rakuten_quota_unavailable"}',
      });
  // Vercel may forward the original query string together with the rewritten
  // path. It is not part of the canonical route and must not become part of an
  // ISBN/profile slug.
  const decodedPath = decodeURIComponent(String(path || "").split("?")[0]);
  const diagnostics = {
    rakutenSectionFailures: [],
    rakutenIsbnFailures: 0,
    ndlSectionFailures: [],
    ndlIsbnFailures: 0,
    supabaseIndexError: "none",
    supabaseProfileError: "none",
    supabaseBookReviewsError: "none",
  };

  if (!IS_PRODUCTION) {
    res.setHeader("X-Robots-Tag", "noindex, nofollow");
  }

  const renderPage = ({
    title,
    description,
    content,
    jsonLd,
    robots,
    pagePath = "/",
    extraJsonLd = [],
    ogImageUrl = OG_IMAGE_URL,
    ogType = "website",
  }) => {
    const absoluteUrl = toAbsoluteUrl(pagePath);
    const fullTitle = title.includes(SITE_NAME)
      ? title.includes(SITE_ALT_NAME)
        ? title
        : title.replace(SITE_NAME, SITE_BRAND)
      : `${title} | ${SITE_BRAND}`;
    const jsonLdList = [
      organizationStructuredData(),
      jsonLd,
      ...extraJsonLd,
    ].filter(Boolean);
    return `
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>${escapeHtml(fullTitle)}</title>
      <meta name="description" content="${escapeHtml(description)}">
            <meta name="robots" content="${IS_PRODUCTION ? robots || "index,follow" : "noindex,nofollow"}">
      <link rel="canonical" href="${absoluteUrl}">
        <meta property="og:title" content="${escapeHtml(fullTitle)}">
      <meta property="og:description" content="${escapeHtml(description)}">
            <meta property="og:site_name" content="${SITE_BRAND}">
      <meta property="og:type" content="${escapeHtml(ogType)}">
            <meta property="og:locale" content="ja_JP">
      <meta property="og:url" content="${absoluteUrl}">
            <meta property="og:image" content="${escapeHtml(ogImageUrl)}">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="${escapeHtml(fullTitle)}">
      <meta name="twitter:description" content="${escapeHtml(description)}">
            <meta name="twitter:image" content="${escapeHtml(ogImageUrl)}">
      <link rel="icon" type="image/png" sizes="48x48" href="${SITE_URL}/favicon.png">
      <link rel="icon" type="image/png" sizes="192x192" href="${SITE_URL}/icons/Icon-192.png">
      <link rel="icon" type="image/svg+xml" sizes="any" href="${SITE_URL}/favicon.svg">
      <link rel="shortcut icon" href="${SITE_URL}/favicon.png">
      <link rel="apple-touch-icon" sizes="192x192" href="${SITE_URL}/icons/Icon-192.png">
      ${jsonLdList
        .map(
          (item) =>
            `<script type="application/ld+json">${JSON.stringify(item).replace(/</g, "\\u003c")}</script>`,
        )
        .join("")}
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px; }
        header { border-bottom: 2px solid #ff3b30; padding-bottom: 10px; margin-bottom: 20px; }
        h1 { color: #ff3b30; margin: 0; }
        h2 { border-bottom: 1px solid #ddd; padding-bottom: 5px; margin-top: 30px; }
        .book-item { display: flex; margin-bottom: 15px; border: 1px solid #eee; border-radius: 8px; padding: 10px; }
        .book-cover { width: 60px; height: 90px; object-fit: cover; margin-right: 15px; border-radius: 4px; }
        .book-details { flex: 1; }
        .book-title { font-weight: bold; font-size: 1.1em; margin: 0; }
        .book-author { color: #666; font-size: 0.9em; margin: 5px 0; }
        .post-card { border: 1px solid #eee; border-radius: 8px; padding: 15px; margin-bottom: 15px; background: #fafafa; }
        .post-header { display: flex; justify-content: space-between; margin-bottom: 10px; }
        .post-rating { color: #ffcc00; font-weight: bold; }
        .post-comment { font-style: italic; color: #555; }
        footer { margin-top: 50px; text-align: center; font-size: 0.8em; color: #999; border-top: 1px solid #eee; padding-top: 20px; }
      </style>
    </head>
    <body>
            <header>
                <h1>${SITE_BRAND}</h1>
        <p>本のレビューと読書記録を管理できるアプリ</p>
      </header>
      <main>
                <nav style="margin: 0 0 16px 0; font-size: 0.95em;">
                    <a href="${SITE_URL}/">ホーム</a> |
                    <a href="${SITE_URL}/posts">公開レビュー</a> |
                    <a href="${SITE_URL}/about">運営者情報</a> |
                    <a href="${SITE_URL}/contact">お問い合わせ</a>
                </nav>
        ${content}
      </main>
      <footer>
        <p><a href="${SITE_URL}/about">運営者情報</a> | <a href="${SITE_URL}/contact">お問い合わせ</a></p>
        <p>© 2026 ${SITE_BRAND}. All rights reserved.</p>
        <!-- Rakuten Web Services Attribution Snippet FROM HERE -->
        <a href="https://webservice.rakuten.co.jp/" target="_blank"><img src="https://webservice.rakuten.co.jp/img/credit/200709/credit_22121.gif" border="0" alt="Rakuten Web Service Center" title="Rakuten Web Service Center" width="221" height="21"/></a>
        <!-- Rakuten Web Services Attribution Snippet TO HERE -->
      </footer>
    </body>
    </html>
  `;
  };

  if (decodedPath.includes("user") || decodedPath.includes("profile")) {
    let username = "ユーザー";
    let bio = "プロフィール情報を準備中です。";
    let stats = { read: 0, followers: 0, following: 0 };
    let posts = [];
    let favorites = [];
    let profileSummaryIndexable = false;
    let profileHasIndexableReview = false;
    let user = null;
    const isbnCache = new Map();
    const requestedProfileId = (() => {
      const match = decodedPath.match(
        /(?:\/users\/|\/user\/|\/profile\/)([^/?#]+)/i,
      );
      return match ? decodeURIComponent(match[1]) : "";
    })();
    const canonicalProfileUrl = canonicalProfilePath(requestedProfileId || "");

    try {
      if (requestedProfileId) {
        const profileFilter = looksLikeUuid(requestedProfileId)
          ? `id=eq.${encodeURIComponent(requestedProfileId)}`
          : `user_id=eq.${encodeURIComponent(requestedProfileId.toLowerCase())}`;
        const profiles = await supabaseGet(
          `profiles?${profileFilter}&select=id,username,user_id,bio,read_count,followers_count,following_count,is_private,is_suspended`,
        );
        user = Array.isArray(profiles) ? profiles[0] : null;
        if (user) {
          const isPublic =
            user.is_private !== true && user.is_suspended !== true;
          if (!isPublic) {
            const forbiddenHtml = renderPage({
              title: "プロフィールは非公開です",
              description:
                "指定されたプロフィールは公開範囲の条件を満たしていません。",
              content: `<h2>プロフィールは非公開です</h2><p>このユーザーの公開プロフィールは表示できません。</p>`,
              jsonLd: {
                "@context": "https://schema.org",
                "@type": "WebPage",
                name: "プロフィールは非公開です",
                description:
                  "指定されたプロフィールは公開範囲の条件を満たしていません。",
                url: toAbsoluteUrl(canonicalProfileUrl),
              },
              pagePath: canonicalProfileUrl,
              robots: "noindex,nofollow",
            });
            res.setHeader("Content-Type", "text/html; charset=utf-8");
            setDiagnosticsHeader(res, diagnostics);
            return res.status(404).send(forbiddenHtml);
          }

          profileSummaryIndexable = isIndexableProfileSummary(user);
          username = user.username;
          bio = user.bio || bio;
          stats.read = user.read_count || stats.read;
          stats.followers = user.followers_count || stats.followers;
          stats.following = user.following_count || stats.following;

          const fetchedPosts = await supabaseGet(
            `posts?profile_id=eq.${user.id}&select=id,book_id,rating,comment,created_at,is_spoiler&order=created_at.desc&limit=10`,
          );

          if (Array.isArray(fetchedPosts) && fetchedPosts.length > 0) {
            profileHasIndexableReview = fetchedPosts.some(isIndexableReview);
            posts = await Promise.all(
              fetchedPosts.map(async (p) => {
                const rawBookId = p.book_id || "書籍ID未設定";
                let resolved = isbnCache.get(rawBookId);
                if (resolved === undefined) {
                  resolved = await resolveBookByIsbn(rawBookId, diagnostics, rakutenRequest);
                  isbnCache.set(rawBookId, resolved || null);
                }

                return {
                  id: p.id,
                  username,
                  book_title: resolved?.title || rawBookId,
                  rating: p.rating,
                  comment:
                    p.is_spoiler === true
                      ? "ネタバレを含む投稿です。詳細画面で内容を確認できます。"
                      : p.comment,
                  date: p.created_at
                    ? new Date(p.created_at).toLocaleDateString("ja-JP")
                    : "",
                };
              }),
            );
          }

          const favoriteRows = await supabaseGet(
            `favorites?profile_id=eq.${user.id}&select=book_id&limit=20`,
          );

          if (Array.isArray(favoriteRows) && favoriteRows.length > 0) {
            favorites = await Promise.all(
              favoriteRows.map(async (row) => {
                const rawBookId = row.book_id || "書籍ID未設定";
                let resolved = isbnCache.get(rawBookId);
                if (resolved === undefined) {
                  resolved = await resolveBookByIsbn(rawBookId, diagnostics, rakutenRequest);
                  isbnCache.set(rawBookId, resolved || null);
                }

                return {
                  title: resolved?.title || rawBookId,
                  author: resolved?.author || "著者情報なし",
                  rating_avg: "-",
                };
              }),
            );
          }
        } else {
          const notFoundHtml = renderPage({
            title: "ユーザーが見つかりません",
            description: "指定されたユーザーは存在しません。",
            content: `<h2>ユーザーが見つかりません</h2><p>指定されたURLに対応するプロフィールは存在しません。</p>`,
            jsonLd: {
              "@context": "https://schema.org",
              "@type": "WebPage",
              name: "ユーザーが見つかりません",
              description: "指定されたユーザーは存在しません。",
              url: toAbsoluteUrl(canonicalProfileUrl),
            },
            pagePath: canonicalProfileUrl,
            robots: "noindex,nofollow",
          });
          res.setHeader("Content-Type", "text/html; charset=utf-8");
          setDiagnosticsHeader(res, diagnostics);
          return res.status(404).send(notFoundHtml);
        }
      }
    } catch (err) {
      diagnostics.supabaseProfileError =
        err instanceof Error ? err.message.slice(0, 80) : "unknown";
    }

    const postsHtml = posts
      .map(
        (p) => `
      <div class="post-card">
        <div class="post-header">
          <strong>${escapeHtml(p.book_title)}</strong>
          <span class="post-rating">★ ${p.rating}/5</span>
        </div>
        <p class="post-comment">"${escapeHtml(p.comment)}"</p>
        <small style="color:#888;">投稿日: ${escapeHtml(p.date)}</small>
        <p><a href="${SITE_URL}/posts/${encodeURIComponent(String(p.id || ""))}">レビュー詳細を読む</a></p>
      </div>
    `,
      )
      .join("");

    const favoritesHtml = favorites
      .map(
        (b) => `
      <div class="book-item">
        <div class="book-details">
          <p class="book-title">${escapeHtml(b.title)}</p>
          <p class="book-author">著者: ${escapeHtml(b.author)} | 評価: ★ ${escapeHtml(b.rating_avg)}</p>
        </div>
      </div>
    `,
      )
      .join("");

    const canonicalPath = canonicalProfilePath(
      user?.user_id || user?.username || requestedProfileId || "",
    );
    const canIndexProfile =
      profileSummaryIndexable || profileHasIndexableReview;
    const html = renderPage({
      title: `${escapeHtml(username)} のプロフィール`,
      description: buildProfileDescription(username, stats),
      content: `
        <h2>ユーザー情報</h2>
        <div style="background:#eee; padding:15px; border-radius:8px; margin-bottom:20px;">
          <h3>${escapeHtml(username)}</h3>
          <p>${escapeHtml(bio)}</p>
          <p><strong>読了:</strong> ${stats.read} 冊 | <strong>フォロワー:</strong> ${stats.followers} 人 | <strong>フォロー:</strong> ${stats.following} 人</p>
        </div>

        <h2>投稿した書評</h2>
        <div>${postsHtml.length > 0 ? postsHtml : "<p>現在、表示できる投稿がありません。</p>"}</div>

        <h2>お気に入りの本</h2>
        <div>${favoritesHtml.length > 0 ? favoritesHtml : "<p>現在、表示できるお気に入り情報がありません。</p>"}</div>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "ProfilePage",
        name: escapeHtml(username),
        description: escapeHtml(bio),
      },
      pagePath: canonicalPath,
      robots: canIndexProfile ? "index,follow" : "noindex,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    if (!canIndexProfile) {
      res.setHeader("X-Robots-Tag", "noindex, follow");
    }
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/privacy") {
    const html = renderPage({
      title: "プライバシーポリシー",
      description:
        "Sharemariumのプライバシーポリシーです。読書記録アプリにおける個人情報の取り扱い方針を説明しています。",
      content: `
        <section>
          <h2>プライバシーポリシー</h2>
          <p>Sharemariumは、読書記録アプリの提供に必要な範囲で情報を取り扱います。</p>
          <h3>収集する情報</h3>
          <p>ログイン情報、読書記録、感想、アプリ利用時に必要な技術情報を収集する場合があります。</p>
          <h3>利用目的</h3>
          <p>本管理アプリ機能の提供、読書履歴表示、サービス改善、不正利用防止のために利用します。</p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "プライバシーポリシー | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description:
          "Sharemariumのプライバシーポリシーです。個人情報の取り扱い方針を説明しています。",
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          {
            name: "プライバシーポリシー",
            url: toAbsoluteUrl(decodedPath),
          },
        ]),
      ],
      pagePath: decodedPath,
      robots: "index,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/terms") {
    const html = renderPage({
      title: "利用規約",
      description:
        "Sharemariumの利用規約です。読書記録・本管理アプリの利用条件を掲載しています。",
      content: `
        <section>
          <h2>利用規約</h2>
          <p>Sharemariumをご利用いただく際の条件を定めたものです。</p>
          <h3>サービス内容</h3>
          <p>Sharemariumは、読んだ本の記録、読みたい本の管理、読書履歴の保存などを提供します。</p>
          <h3>禁止事項</h3>
          <p>不正アクセス、第三者への迷惑行為、法令違反につながる行為は禁止します。</p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "利用規約 | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description:
          "Sharemariumの利用規約です。読書記録・本管理アプリの利用条件を掲載しています。",
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          { name: "利用規約", url: toAbsoluteUrl(decodedPath) },
        ]),
      ],
      pagePath: decodedPath,
      robots: "index,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/community-guidelines") {
    const html = renderPage({
      title: "コミュニティガイドライン",
      description:
        "Sharemariumのコミュニティガイドラインです。安心して使える読書コミュニティのためのルールを掲載しています。",
      content: `
        <section>
          <h2>コミュニティガイドライン</h2>
          <p>Sharemariumでは、他の利用者への敬意と安全性を重視しています。</p>
          <h3>主な方針</h3>
          <p>誹謗中傷、差別、スパム、不正行為、権利侵害につながる投稿は禁止します。</p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "コミュニティガイドライン | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description:
          "Sharemariumのコミュニティガイドラインです。安心して使える読書コミュニティのためのルールを掲載しています。",
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          {
            name: "コミュニティガイドライン",
            url: toAbsoluteUrl(decodedPath),
          },
        ]),
      ],
      pagePath: decodedPath,
      robots: "index,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/infringement-policy") {
    const html = renderPage({
      title: "権利侵害・通報ポリシー",
      description:
        "Sharemariumの権利侵害・通報ポリシーです。著作権侵害や不適切な投稿への対応方針を説明しています。",
      content: `
        <section>
          <h2>権利侵害・通報ポリシー</h2>
          <p>著作権、肖像権、商標権など第三者の権利を侵害する投稿は禁止しています。</p>
          <h3>通報への対応</h3>
          <p>通報内容を確認し、必要に応じて投稿の削除やアカウント制限を行います。</p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "権利侵害・通報ポリシー | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description:
          "Sharemariumの権利侵害・通報ポリシーです。著作権侵害や不適切な投稿への対応方針を説明しています。",
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          {
            name: "権利侵害・通報ポリシー",
            url: toAbsoluteUrl(decodedPath),
          },
        ]),
      ],
      pagePath: decodedPath,
      robots: "index,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/external-transmission") {
    const html = renderPage({
      title: "外部送信に関する公表事項",
      description:
        "Sharemariumの外部送信に関する公表事項です。第三者サービスへの情報送信内容と目的を掲載しています。",
      content: `
        <section>
          <h2>外部送信に関する公表事項</h2>
          <p>本サービスでは、機能提供・分析・広告配信のために必要な範囲で外部事業者へ情報を送信する場合があります。</p>
          <h3>主な目的</h3>
          <p>ログイン維持、サービス改善、広告配信と効果測定、不正利用防止のために利用します。</p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "外部送信に関する公表事項 | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description:
          "Sharemariumの外部送信に関する公表事項です。第三者サービスへの情報送信内容と目的を掲載しています。",
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          {
            name: "外部送信に関する公表事項",
            url: toAbsoluteUrl(decodedPath),
          },
        ]),
      ],
      pagePath: decodedPath,
      robots: "index,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/about") {
    const description =
      "Sharemarium（シェアマリウム）は、伊能 龍之介が企画・開発・運営する読書記録Webサービスです。";
    const html = renderPage({
      title: "運営者情報",
      description,
      content: `
        <section>
          <h2>運営者情報</h2>
          <h3>Sharemariumについて</h3>
          <p>Sharemarium（シェアマリウム）は、伊能 龍之介が企画・開発・運営する読書記録Webサービスです。</p>
          <p>読んだ本を記録し、感想をみんなと共有できる読書レビューSNSです。自分用の読書記録にも、お友だちとの感想共有にも使えるSharemariumで、あなただけの本棚を作りましょう。</p>
          <h3>サービスの目的</h3>
          <p>Sharemariumは、読んだ本の記録を残すだけでなく、同じ本を読んだ人の感想に触れ、新しい本との出会いや読書の振り返りにつなげることを目的としています。</p>
          <h3>掲載コンテンツについて</h3>
          <p>書籍のタイトル・著者・書影などの書籍情報は外部サービスから提供される場合があります。一方、レビューや読書記録などSharemarium上の投稿は、利用者自身の読書体験にもとづいて作成されるコンテンツです。</p>
          <h3>運営方針</h3>
          <p>公開・非公開設定、ネタバレ表示、通報・ブロックなどの機能を用意し、安心して読書体験を共有できる場を目指しています。公開情報や機能は継続的に確認し、必要に応じて改善します。</p>
          <h3>企画・開発・運営</h3>
          <p style="display:flex;flex-wrap:wrap;align-items:center;gap:12px;">伊能 龍之介 <a href="https://www.instagram.com/ryunosukeino/" target="_blank" rel="noopener noreferrer">Instagram</a></p>
          <h3>お問い合わせ</h3>
          <p>サービスに関するお問い合わせは、お問い合わせフォームからご連絡ください。</p>
          <p><a href="/contact">お問い合わせフォーム</a></p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "AboutPage",
        name: "運営者情報 | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description,
        about: {
          "@type": "WebSite",
          name: SITE_NAME,
          alternateName: SITE_ALT_NAME,
          url: `${SITE_URL}/`,
          creator: {
            "@type": "Person",
            name: "伊能 龍之介",
            sameAs: ["https://www.instagram.com/ryunosukeino/"],
          },
        },
      },
      extraJsonLd: [breadcrumbStructuredData([
        { name: "ホーム", url: `${SITE_URL}/` },
        { name: "運営者情報", url: toAbsoluteUrl(decodedPath) },
      ])],
      pagePath: decodedPath,
      robots: "index,follow",
    });
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/contact") {
    const html = renderPage({
      title: "お問い合わせ",
      description:
        "Sharemariumへのお問い合わせページです。ご意見・不具合報告・権利侵害の申告を受け付けています。",
      content: `
        <section>
          <h2>お問い合わせ</h2>
          <p>サービスに関するご質問、不具合報告、権利侵害申告などを受け付けています。</p>
          <p>アプリ内のお問い合わせフォームからご連絡ください。</p>
        </section>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "ContactPage",
        name: "お問い合わせ | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        description:
          "Sharemariumへのお問い合わせページです。ご意見・不具合報告・権利侵害の申告を受け付けています。",
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          { name: "お問い合わせ", url: toAbsoluteUrl(decodedPath) },
        ]),
      ],
      pagePath: decodedPath,
      robots: "index,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath === "/featured-books") {
    let featuredBooks = [];
    try {
      featuredBooks = await fetchFeaturedBooks();
    } catch (err) {
      diagnostics.supabaseIndexError =
        err instanceof Error ? err.message.slice(0, 80) : "unknown";
    }
    const html = renderPage({
      title: "注目の書籍",
      description:
        "Sharemarium運営者が選んだ注目の書籍です。作品概要と読者レビューを確認できます。",
      content: `<section>
        <h1>注目の書籍</h1>
        <p>Sharemarium運営者が、実在する書籍情報を確認して選んだ作品です。</p>
        ${renderFeaturedBookList(featuredBooks)}
      </section>`,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "CollectionPage",
        name: "注目の書籍 | Sharemarium",
        url: toAbsoluteUrl(decodedPath),
        mainEntity: {
          "@type": "ItemList",
          itemListElement: featuredBooks.map((book, index) => ({
            "@type": "ListItem",
            position: index + 1,
            url: toAbsoluteUrl(`/book/${encodeURIComponent(book.book_id)}`),
            name: book.book_title,
          })),
        },
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          { name: "注目の書籍", url: toAbsoluteUrl(decodedPath) },
        ]),
      ],
      pagePath: decodedPath,
      robots: featuredBooks.length ? "index,follow" : "noindex,follow",
    });
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    if (!featuredBooks.length) {
      res.setHeader("X-Robots-Tag", "noindex, follow");
    }
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  const genreSection = sectionByGenrePath(decodedPath);
  if (genreSection) {
    let books = [];
    try {
      books = await fetchRakutenSection(genreSection, diagnostics, rakutenRequest);
    } catch {
      books = [];
    }

    const detailLinks = "";

    const html = renderPage({
      title: `${genreSection}一覧`,
      description: buildGenreDescription(genreSection, books),
      enableAds: false,
      content: `
        <h2>${genreSection}について</h2>
        <p>Sharemariumが注目する${genreSection}を一覧で紹介します。</p>
        <div>${renderBookList(books)}</div>
        <h2>${genreSection}の詳細ページ</h2>
        <ul>${detailLinks}</ul>
      `,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "CollectionPage",
        name: `${genreSection}一覧 | Sharemarium`,
        description: buildGenreDescription(genreSection, books),
        url: toAbsoluteUrl(decodedPath),
      },
      extraJsonLd: [
        breadcrumbStructuredData([
          { name: "ホーム", url: `${SITE_URL}/` },
          { name: genreSection, url: toAbsoluteUrl(decodedPath) },
        ]),
        itemListStructuredData(genreSection, books, decodedPath),
      ],
      pagePath: decodedPath,
      // Genre pages are primarily third-party catalog data. Keep them out of
      // search until Sharemarium adds substantial manually curated content.
      robots: "noindex,follow",
    });

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(200).send(html);
  }

  if (decodedPath.startsWith("/book/")) {
    const slug = decodedPath.replace("/book/", "").split("/")[0];
    if (/^(\d{13}|\d{9}[\dXx])$/.test(slug)) {
      try {
        // Reviews are independent user content. A temporary Rakuten outage
        // must not hide already-public reviews, or force us to persist catalog
        // text just to keep this page available.
        let book = rakutenEnabled()
          ? await resolveBookByIsbn(slug, diagnostics, rakutenRequest)
          : null;
        if (!book) {
          const fallbackRows = await fetchPublicReviewsForBook(slug, diagnostics);
          const fallbackReviews = fallbackRows.filter(isEligiblePublicBookReview);
          if (fallbackReviews.length > 0) {
            const fallbackHtml = renderPage({
              title: `ISBN ${slug}｜読者レビュー｜Sharemarium`,
              description: `ISBN ${slug}の公開レビュー。Sharemariumのユーザーが書いた感想を紹介しています。`,
              pagePath: `/book/${slug}`,
              robots: "index,follow",
              jsonLd: {
                "@context": "https://schema.org",
                "@type": "Book",
                isbn: slug,
                url: toAbsoluteUrl(`/book/${slug}`),
              },
              content: `<h1>書籍 ISBN ${escapeHtml(slug)}</h1>
                <p>書誌情報は一時的に取得できませんが、公開されている読者の感想は閲覧できます。</p>
                <h2>読者の感想</h2>
                ${fallbackReviews.map(p => `<article><h3>${escapeHtml(p.profiles?.username || "読者")}さんの感想</h3><p>${escapeHtml(p.comment)}</p><a href="/posts/${encodeURIComponent(p.id)}">投稿を見る</a></article>`).join("")}
                <p><a href="/">Sharemariumで本を探す</a></p>`,
            });
            res.setHeader("Content-Type", "text/html; charset=utf-8");
            res.setHeader("Cache-Control", "no-store");
            setDiagnosticsHeader(res, diagnostics);
            return res.status(200).send(fallbackHtml);
          }
          if (!rakutenEnabled() || diagnostics.rakutenIsbnFailures > 0) {
            throw new Error("book_api_unavailable");
          }
        }
        if (book && !book.rakutenUrl) {
          // Do not surface unlinked third-party catalog text when the API
          // returns a record without a verified Rakuten product destination.
          book = { ...book, title: `書籍 ISBN ${slug}`, author: "",
            publisher: "", coverUrl: "", description: "", rakutenUrl: "" };
        }
        if (book) {
          let featured = null;
          try {
            const featuredRows = await fetchFeaturedBooks();
            featured =
              featuredRows.find(
                (item) => String(item.book_id) === String(slug),
              ) || null;
          } catch (_) {
            // A missing optional editorial table must not hide book pages.
          }
          const rows = await fetchPublicReviewsForBook(slug, diagnostics);
          const reviews = rows.filter(isEligiblePublicBookReview);
          const authorText = book.author ? `（${book.author}）` : "";
          const description = `${book.title}${authorText}の作品概要・読者レビュー。Sharemariumで読書記録を共有しましょう。`;
          const relatedScreenTitles = Array.isArray(
            featured?.related_screen_titles,
          )
            ? featured.related_screen_titles.filter(Boolean)
            : [];
          const html = renderPage({
            title: `${book.title}｜作品概要・レビュー｜Sharemarium`,
            description, pagePath: `/book/${slug}`,
            // Editorially selected books and books with an original public
            // review are indexable. Catalog-only pages stay out of the index.
            robots: reviews.length || (featured && book.rakutenUrl) ? "index,follow" : "noindex,follow",
            ogType: "book",
            ogImageUrl: book.coverUrl || OG_IMAGE_URL,
            content: `<h1>${escapeHtml(book.title)}</h1>
              ${book.author ? `<p>著者：${escapeHtml(book.author)}</p>` : ""}
              <p>${book.publisher ? `出版社：${escapeHtml(book.publisher)} ／ ` : ""}ISBN：${escapeHtml(slug)}</p>
              ${book.coverUrl && book.rakutenUrl ? `<img width="150" src="${escapeHtml(book.coverUrl)}" alt="${escapeHtml(book.title)}の表紙">` : ""}
              <h2>書籍紹介</h2><p>${escapeHtml(book.rakutenUrl ? (book.description || "紹介文は準備中です。") : "書籍情報を確認できませんでした。")}</p>
              ${book.rakutenUrl ? `<p>楽天ブックス提供の情報：<a href="${escapeHtml(book.rakutenUrl)}" target="_blank" rel="sponsored noopener noreferrer">楽天ブックスの商品ページを見る</a></p>` : ""}
              ${relatedScreenTitles.length ? `<h2>関連する映像化作品</h2><ul>${relatedScreenTitles.map((title) => `<li>${escapeHtml(title)}</li>`).join("")}</ul>` : ""}
              <h2>読者の感想</h2>
              ${reviews.length ? reviews.map(p => `<article><h3>${escapeHtml(p.profiles?.username || "読者")}さんの感想</h3><p>${escapeHtml(p.comment)}</p><a href="/posts/${encodeURIComponent(p.id)}">投稿を見る</a></article>`).join("") : "<p>公開されている感想はまだありません。</p>"}
              <p><a href="/">Sharemariumで本を探す</a></p>`,
            jsonLd: {
              "@context": "https://schema.org",
              "@type": "Book",
              name: book.title,
              isbn: slug,
              ...(book.author
                ? { author: { "@type": "Person", name: book.author } }
                : {}),
              ...(book.publisher
                ? { publisher: { "@type": "Organization", name: book.publisher } }
                : {}),
              ...(book.description && book.rakutenUrl ? { description: book.description } : {}),
              ...(book.coverUrl && book.rakutenUrl ? { image: book.coverUrl } : {}),
              url: toAbsoluteUrl(`/book/${slug}`),
            },
            extraJsonLd: [
              breadcrumbStructuredData([
                { name: "ホーム", url: `${SITE_URL}/` },
                { name: book.title, url: toAbsoluteUrl(`/book/${slug}`) },
              ]),
            ],
          });
          res.setHeader("Content-Type", "text/html; charset=utf-8");
          setDiagnosticsHeader(res, diagnostics);
          return res.status(200).send(html);
        }
      } catch (_) {
        res.setHeader("Cache-Control", "no-store");
        res.setHeader("Retry-After", "300");
        setDiagnosticsHeader(res, diagnostics);
        return res.status(503).send(renderPage({
          title: "書籍情報を取得できませんでした", description: "時間をおいて再度お試しください。",
          content: "<h1>書籍情報を取得できませんでした</h1>", pagePath: `/book/${slug}`,
          robots: "noindex,nofollow",
        }));
      }
    }
    const notFoundHtml = renderPage({
      title: "書籍ページが見つかりません",
      description: "指定された書籍ページは見つかりませんでした。",
      content: `<h2>書籍ページが見つかりません</h2><p>URLをご確認ください。</p>`,
      jsonLd: {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "書籍ページが見つかりません",
        description: "指定された書籍ページは見つかりませんでした。",
        url: toAbsoluteUrl(decodedPath),
      },
      pagePath: decodedPath,
      robots: "noindex,nofollow",
    });
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    setDiagnosticsHeader(res, diagnostics);
    return res.status(404).send(notFoundHtml);
  }

  let featuredForHome = [];
  try {
    featuredForHome = await fetchFeaturedBooks();
  } catch (err) {
    diagnostics.supabaseIndexError =
      err instanceof Error ? err.message.slice(0, 80) : "unknown";
  }

  let recentPosts = [];
  try {
    const rawPosts =
      (await supabaseGet(
        "posts?select=id,profile_id,book_id,rating,comment,created_at,is_spoiler,profiles(username)&order=created_at.desc&limit=100",
      )) || [];

    const substantivePosts = rawPosts
      .filter(isSubstantivePublicReview)
      .slice(0, 8);

    if (substantivePosts.length > 0) {
      const isbnCache = new Map();
      recentPosts = await Promise.all(
        substantivePosts.map(async (p) => {
          const rawBookId = p.book_id || "書籍ID未設定";
          let resolved = isbnCache.get(rawBookId);
          if (resolved === undefined) {
            resolved = await resolveBookByIsbn(rawBookId, diagnostics, rakutenRequest);
            isbnCache.set(rawBookId, resolved || null);
          }

          return {
            id: p.id,
            username: p.profiles?.username || "匿名ユーザー",
            book_title: resolved?.title || rawBookId,
            rating: p.rating,
            comment: p.comment,
            date: p.created_at
              ? new Date(p.created_at).toLocaleDateString("ja-JP")
              : "",
          };
        }),
      );
    }
  } catch (err) {
    diagnostics.supabaseIndexError =
      err instanceof Error ? err.message.slice(0, 80) : "unknown";
  }

  const timelineHtml = recentPosts
    .map(
      (p) => `
    <article class="post-card">
      <div class="post-header">
        <strong>${escapeHtml(p.username)} さん のレビュー - 『${escapeHtml(p.book_title)}』</strong>
        <span class="post-rating">★ ${p.rating}/5</span>
      </div>
      <p class="post-comment">"${escapeHtml(p.comment)}"</p>
      <small style="color:#888;">投稿日: ${escapeHtml(p.date)}</small>
      <p><a href="${SITE_URL}/posts/${encodeURIComponent(String(p.id || ""))}">レビュー詳細を読む</a></p>
    </article>
  `,
    )
    .join("");
  const faqHtml = `
            <h2>よくある質問</h2>
            <div class="post-card">
                <strong>シェアマリウムとは何ですか？</strong>
                <p>シェアマリウムは、英字でSharemariumと表記する、読書記録・本管理・レビュー共有のためのWebサービスです。</p>
            </div>
            <div class="post-card">
                <strong>Sharemariumでは何ができますか？</strong>
                <p>本の検索、レビュー投稿、読書記録の管理、タイムライン閲覧ができます。</p>
            </div>
            <div class="post-card">
                <strong>レビューは誰でも投稿できますか？</strong>
                <p>アプリ内アカウントでログインしたユーザーがレビュー投稿できます。</p>
            </div>
            <div class="post-card">
                <strong>ネタバレを含む感想は投稿できますか？</strong>
                <p>投稿時にネタバレを含むことを設定でき、閲覧者が意図せず内容を読まないように配慮しています。</p>
            </div>
        `;
  const primaryLinksHtml = `
            <h2>主要ページ</h2>
            <ul>
                <li><a href="${SITE_URL}/posts">公開レビュー一覧</a></li>
                ${featuredForHome.length ? `<li><a href="${SITE_URL}/featured-books">注目の書籍</a></li>` : ""}
                <li><a href="${SITE_URL}/about">運営者情報</a></li>
                <li><a href="${SITE_URL}/privacy">プライバシーポリシー</a></li>
                <li><a href="${SITE_URL}/terms">利用規約</a></li>
                <li><a href="${SITE_URL}/community-guidelines">コミュニティガイドライン</a></li>
                <li><a href="${SITE_URL}/infringement-policy">権利侵害・通報ポリシー</a></li>
                <li><a href="${SITE_URL}/external-transmission">外部送信に関する公表事項</a></li>
                <li><a href="${SITE_URL}/contact">お問い合わせ</a></li>
            </ul>
        `;

  const html = renderPage({
    title: SITE_TITLE,
    description: TOP_DESCRIPTION,
    content: `
            <section>
            <h2>Sharemarium（シェアマリウム）でできること</h2>
            <p>Sharemarium（シェアマリウム）は、読んだ本、読書中の本、これから読みたい本をまとめて管理できる読書記録・本管理アプリです。読書履歴、感想、蔵書管理を一つのWeb本棚で行えます。</p>
            <h3>主な機能</h3>
            <ul>
                <li>読んだ本の登録と読書履歴の保存</li>
                <li>読みたい本の管理</li>
                <li>レビュー・読書メモの記録</li>
                <li>自分の本棚の一覧表示</li>
                <li>書籍情報の検索とお気に入り管理</li>
            </ul>
            <p>読んだ本を忘れずに記録したい方、所有している本を整理したい方、読書習慣を振り返りたい方に向けたサービスです。</p>
            <p><a href="${SITE_URL}/">Sharemariumを始める</a> / <a href="${SITE_URL}/contact">お問い合わせ</a></p>
            </section>
      ${featuredForHome.length ? `<section>
        <h2><a href="${SITE_URL}/featured-books">注目の書籍</a></h2>
        <p>Sharemarium運営者が選んだ作品です。各作品の概要と公開レビューを確認できます。</p>
        ${renderFeaturedBookList(featuredForHome)}
      </section>` : ""}
      <section>
        <h2>Sharemariumで公開された最新レビュー</h2>
        <p>実際にSharemariumの利用者が投稿した読書レビューです。書籍カタログの転載ではなく、読書体験にもとづく感想を掲載しています。</p>
        <div>${timelineHtml.length > 0 ? timelineHtml : "<p>現在、検索公開基準を満たすレビューを準備中です。</p>"}</div>
        <p><a href="${SITE_URL}/posts">公開レビュー一覧を見る</a></p>
      </section>

            ${primaryLinksHtml}
      ${faqHtml}
    `,
    jsonLd: {
      "@context": "https://schema.org",
      "@type": "WebSite",
      name: SITE_NAME,
      alternateName: SITE_ALT_NAME,
      description: TOP_DESCRIPTION,
      url: `${SITE_URL}/`,
      potentialAction: {
        "@type": "SearchAction",
        target: `${SITE_URL}/?seo_preview=1&path={search_term_string}`,
        "query-input": "required name=search_term_string",
      },
    },
    extraJsonLd: [
      faqStructuredData(),
      webApplicationStructuredData(),
      ...siteNavigationStructuredData(),
    ],
    pagePath: decodedPath || "/",
    // The product landing page is publisher-authored and remains indexable.
    robots: "index,follow",
  });

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  setDiagnosticsHeader(res, diagnostics);
  return res.status(200).send(html);
};
