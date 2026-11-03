// Writes out/updates.json: the feed the PairUp server serves at /api/update/<platform>/<quality>/<commit>
// (pairup-cloud docs/HOSTING.md, "Updates"). version is the build id the packaged product.json carries.
// Usage: node tools/update-feed.mjs <packaged product.json> <out dir> <tag> [release base url]
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const [productFile, outDir, tag, baseArg] = process.argv.slice(2);
if (!productFile || !outDir || !tag) { console.error("usage: update-feed.mjs <product.json> <out dir> <tag> [base url]"); process.exit(2); }
const base = baseArg || `https://github.com/nicololgallia-creator/pairup-editor/releases/download/${tag}`;
const p = JSON.parse(readFileSync(productFile, "utf8"));
if (!p.commit || !p.version) { console.error("product.json has no commit or version"); process.exit(1); }

const sums = {};
for (const line of readFileSync(path.join(outDir, "SHA256SUMS"), "utf8").split("\n")) {
  const [hash, file] = line.trim().split(/\s+/);
  if (hash && file) sums[file.replace(/^\*/, "")] = hash;
}
const entry = (file) => ({ url: `${base}/${file}`, version: p.commit, productVersion: p.version, name: p.version, sha256hash: sums[file], timestamp: Date.now() });
const find = (re) => Object.keys(sums).find((f) => re.test(f));
const quality = p.quality || "stable";
const feed = { [quality]: {} };
const setup = find(/Setup.*\.exe$/i);
const zip = find(/\.zip$/i);
if (setup) feed[quality]["win32-x64-user"] = entry(setup);
if (zip) feed[quality]["win32-x64-archive"] = entry(zip);
writeFileSync(path.join(outDir, "updates.json"), JSON.stringify(feed, null, 2) + "\n");
console.log(`updates.json: ${Object.keys(feed[quality]).join(" ") || "nothing"} version ${p.commit}`);
