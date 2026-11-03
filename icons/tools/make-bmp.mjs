// Draws the Inno Setup wizard images (24-bit BMP) from icons/pairup.svg with the PC's Edge.
// Usage: node make-bmp.mjs <icons-dir> <out-dir>
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
const require = createRequire("file:///C:/Users/nicol/agent-work/tools/shot/package.json");
const puppeteer = require("puppeteer-core");

const [iconsDir, outDir] = process.argv.slice(2);
const svg = fs.readFileSync(path.join(iconsDir, "pairup.svg"), "utf8");
fs.mkdirSync(outDir, { recursive: true });

// Sizes of Microsoft's files (VS Code 1.144.0), width x height.
const big = { 100: [164, 314], 125: [192, 386], 150: [246, 459], 175: [273, 556], 200: [328, 604], 225: [355, 700], 250: [410, 797] };
const small = { 100: [55, 55], 125: [64, 68], 150: [83, 80], 175: [92, 97], 200: [110, 106], 225: [119, 123], 250: [138, 140] };
const jobs = [];
for (const [s, [w, h]] of Object.entries(big)) jobs.push({ name: `inno-big-${s}`, w, h, kind: "big" });
for (const [s, [w, h]] of Object.entries(small)) jobs.push({ name: `inno-small-${s}`, w, h, kind: "small" });

// Runs in the page: draw the SVG at its final pixel size, return RGBA as base64.
async function draw({ w, h, kind, svgText }) {
  const img = new Image();
  img.src = "data:image/svg+xml;base64," + btoa(svgText);
  await img.decode();
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  const ctx = c.getContext("2d");
  let bg, size, cx, cy;
  if (kind === "big") {
    bg = "#000000"; size = Math.round(w * 0.5); cx = w * 0.46; cy = h * 0.38;
  } else {
    bg = "#ffffff"; size = Math.round(Math.min(w, h) * 0.8); cx = w / 2; cy = h / 2;
  }
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, w, h);
  ctx.drawImage(img, Math.round(cx - size / 2), Math.round(cy - size / 2), size, size);
  const d = ctx.getImageData(0, 0, w, h).data;
  let bin = "";
  for (let i = 0; i < d.length; i += 8192) bin += String.fromCharCode.apply(null, d.subarray(i, i + 8192));
  return btoa(bin);
}

// 24-bit BI_RGB, bottom-up, rows padded to 4 bytes, BGR.
function bmp(w, h, rgba) {
  const row = Math.ceil((w * 3) / 4) * 4;
  const out = Buffer.alloc(54 + row * h);
  out.write("BM", 0);
  out.writeUInt32LE(out.length, 2);
  out.writeUInt32LE(54, 10);
  out.writeUInt32LE(40, 14);
  out.writeInt32LE(w, 18);
  out.writeInt32LE(h, 22);
  out.writeUInt16LE(1, 26);
  out.writeUInt16LE(24, 28);
  out.writeUInt32LE(row * h, 34);
  out.writeInt32LE(2835, 38);
  out.writeInt32LE(2835, 42);
  for (let y = 0; y < h; y++) {
    let o = 54 + (h - 1 - y) * row;
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      out[o++] = rgba[i + 2]; out[o++] = rgba[i + 1]; out[o++] = rgba[i];
    }
  }
  return out;
}

const exe = ["C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "C:/Program Files/Google/Chrome/Application/chrome.exe"].find((p) => fs.existsSync(p));
const browser = await puppeteer.launch({ executablePath: exe, headless: true, pipe: true });
try {
  const page = await browser.newPage();
  await page.goto("data:text/html;base64," + Buffer.from("<!doctype html><html><body></body></html>").toString("base64"));
  for (const j of jobs) {
    const b64 = await page.evaluate(draw, { ...j, svgText: svg });
    const file = path.join(outDir, j.name + ".bmp");
    fs.writeFileSync(file, bmp(j.w, j.h, Buffer.from(b64, "base64")));
    console.log("wrote", file, `${j.w}x${j.h}`);
  }
} finally {
  await browser.close();
}
