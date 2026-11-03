// Renders icons/pairup.svg to PNGs with the PC's Edge through puppeteer-core.
// Usage: node render.mjs <icons-dir> [outDir for the 48 px ICO source]
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
const require = createRequire("file:///C:/Users/nicol/agent-work/tools/shot/package.json");
const puppeteer = require("puppeteer-core");

const iconsDir = process.argv[2];
const scratch = process.argv[3] || iconsDir;
const svgSrc = fs.readFileSync(path.join(iconsDir, "pairup.svg"), "utf8");

// Only 16 and 32 differ from the authored SVG: heavier stroke (px), and at 16 the mark is a bit wider.
// frac = mark width / icon width, sw = stroke in output pixels. Ring spacing keeps the authored ratio.
const variants = {
  256: null, 150: null, 70: null, 48: null,
  32: { frac: 0.62, swPx: 2.2 },
  16: { frac: 0.70, swPx: 1.3 },
};
const outName = (s) => (s === 48 ? path.join(scratch, "pairup-48.png") : path.join(iconsDir, `pairup-${s}.png`));

function svgFor(s) {
  const v = variants[s];
  if (!v) return svgSrc; // the file as authored
  const k = 256 / s, w = v.frac * 256, sw = v.swPx * k;
  const r = (w - sw) / 2.966, dx = 0.483 * r;
  const f = (n) => +n.toFixed(2);
  return svgSrc
    .replace(/cx="105.3"/, `cx="${f(128 - dx)}"`).replace(/cx="150.7"/, `cx="${f(128 + dx)}"`)
    .replace(/r="47"/g, `r="${f(r)}"`).replace(/stroke-width="14.3"/g, `stroke-width="${f(sw)}"`);
}

const exe = ["C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "C:/Program Files/Google/Chrome/Application/chrome.exe"].find((p) => fs.existsSync(p));
const browser = await puppeteer.launch({ executablePath: exe, headless: true, pipe: true });
try {
  const page = await browser.newPage();
  for (const s of Object.keys(variants).map(Number)) {
    await page.setViewport({ width: s, height: s, deviceScaleFactor: 1 });
    const svg = svgFor(s).replace(/width="256" height="256"/, `width="${s}" height="${s}"`);
    const html = `<!doctype html><html><head><style>html,body{margin:0;padding:0;background:transparent}svg{display:block}</style></head><body>${svg}</body></html>`;
    await page.goto("data:text/html;base64," + Buffer.from(html).toString("base64"));
    const buf = await page.screenshot({ clip: { x: 0, y: 0, width: s, height: s }, omitBackground: true, type: "png" });
    fs.writeFileSync(outName(s), buf);
    console.log("wrote", outName(s), buf.length);
  }
} finally {
  await browser.close();
}
