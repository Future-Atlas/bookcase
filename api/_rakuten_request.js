const http = require("node:http");
const https = require("node:https");

class RakutenResponse {
  constructor(status, body) {
    this.status = status;
    this.ok = status >= 200 && status < 300;
    this._body = body;
  }

  async text() {
    return this._body;
  }
}

function requestRakuten(
  url,
  { origin, userAgent, timeoutMs = 15000 } = {},
) {
  const target = new URL(url);
  const transport = target.protocol === "http:" ? http : https;
  const requestOrigin = new URL(String(origin || "").trim()).origin;

  return new Promise((resolve, reject) => {
    const request = transport.request(
      target,
      {
        method: "GET",
        headers: {
          Accept: "application/json",
          Origin: requestOrigin,
          "User-Agent": userAgent,
        },
      },
      (response) => {
        const chunks = [];

        response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        response.on("error", reject);
        response.on("end", () => {
          const status = response.statusCode || 502;
          const body = Buffer.concat(chunks).toString("utf8");
          resolve(new RakutenResponse(status, body));
        });
      },
    );

    request.setTimeout(timeoutMs, () => {
      request.destroy(new Error("Rakuten API request timed out."));
    });
    request.on("error", reject);
    request.end();
  });
}

module.exports = { requestRakuten };
