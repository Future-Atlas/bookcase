async function requestRakuten(
  url,
  { origin, userAgent, timeoutMs = 15000 } = {},
) {
  const requestOrigin = new URL(String(origin || "").trim()).origin;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        Origin: requestOrigin,
        Referer: `${requestOrigin}/`,
        "User-Agent": userAgent,
      },
      signal: controller.signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") {
      throw new Error("Rakuten API request timed out.");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = { requestRakuten };
