// Reject release artifacts that would load Flutter's CanvasKit from gstatic.com.
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export function verifyLocalCanvasKit(buildDir = join(root, "build", "web")) {
  const files = [
    "index.html",
    "flutter_bootstrap.js",
    "canvaskit/canvaskit.js",
    "canvaskit/canvaskit.wasm",
    "canvaskit/chromium/canvaskit.js",
    "canvaskit/chromium/canvaskit.wasm",
  ];
  for (const name of files) {
    const file = join(buildDir, name);
    if (!existsSync(file) || !statSync(file).isFile() || statSync(file).size === 0) {
      throw new Error("Flutter Web build is missing a nonempty local asset: " + name);
    }
  }
  const bootstrap = readFileSync(join(buildDir, "flutter_bootstrap.js"), "utf8");
  if (!/["']?useLocalCanvasKit["']?\s*:\s*true/.test(bootstrap)) {
    throw new Error(
      "Flutter bootstrap is not configured for local CanvasKit. " +
      "Build with flutter build web --release --no-web-resources-cdn.",
    );
  }
  return files.length;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = verifyLocalCanvasKit();
  console.log("Verified " + files + " local Flutter CanvasKit assets and bootstrap configuration.");
}
