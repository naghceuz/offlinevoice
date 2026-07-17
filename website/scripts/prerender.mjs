// Injects the server-rendered app markup into dist/index.html so crawlers
// see the full page content without executing JavaScript.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const indexPath = path.join(root, "dist", "index.html");

const { render } = await import(path.join(root, "dist-ssr", "entry-server.js"));

const template = readFileSync(indexPath, "utf8");
const marker = '<div id="root"></div>';
if (!template.includes(marker)) {
  throw new Error(`prerender: marker ${marker} not found in dist/index.html`);
}
writeFileSync(indexPath, template.replace(marker, `<div id="root">${render()}</div>`));
console.log("prerender: injected app markup into dist/index.html");
