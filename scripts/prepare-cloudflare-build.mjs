import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const indexPath = path.join(root, "build/web/index.html");

if (!fs.existsSync(indexPath)) {
  throw new Error("build/web/index.html is missing; build Flutter Web first");
}

const source = fs.readFileSync(indexPath, "utf8");
const output = source.replace(
  /\s*<script\s+defer\s+src=["']\/_vercel\/speed-insights\/script\.js["']><\/script>\s*/g,
  "\n",
);

if (output.includes("/_vercel/")) {
  throw new Error("Cloudflare build still contains a Vercel runtime URL");
}

fs.writeFileSync(indexPath, output, "utf8");
console.log("Prepared Flutter Web output for Cloudflare Workers.");
