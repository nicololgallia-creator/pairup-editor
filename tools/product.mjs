// product.json for the fork, with Node instead of jq (the runner and this PC both have Node; neither needs jq).
//   node tools/product.mjs merge <product.json> <overrides.json>   merge the overrides in, drop DELETE_KEYS (env, JSON array)
//   node tools/product.mjs show  <product.json>                    print the name fields; exit 1 if updateUrl is still there
//   node tools/product.mjs name  <product.json>                    print nameShort
import { readFileSync, writeFileSync } from "node:fs";

const [mode, file, overridesFile] = process.argv.slice(2);
const product = JSON.parse(readFileSync(file, "utf8"));

if (mode === "merge") {
  const overrides = JSON.parse(readFileSync(overridesFile, "utf8"));
  const del = JSON.parse(process.env.DELETE_KEYS || "[]");
  const removed = del.filter((k) => k in product);
  for (const k of removed) delete product[k];
  const merged = { ...product, ...overrides };
  writeFileSync(file, JSON.stringify(merged, null, 2) + "\n");
  console.log(`removed from upstream product.json: ${removed.join(", ") || "none"}`);
} else if (mode === "show") {
  const p = product;
  console.log(`nameShort=${p.nameShort} nameLong=${p.nameLong} applicationName=${p.applicationName} dataFolderName=${p.dataFolderName} urlProtocol=${p.urlProtocol}`);
  console.log(`gallery=${p.extensionsGallery?.serviceUrl}`);
  if ("updateUrl" in p) {
    console.error("updateUrl is still in product.json");
    process.exit(1);
  }
  console.log("updateUrl: absent");
} else if (mode === "name") {
  process.stdout.write(String(product.nameShort));
} else {
  console.error("usage: product.mjs merge|show|name <product.json> [overrides.json]");
  process.exit(2);
}
