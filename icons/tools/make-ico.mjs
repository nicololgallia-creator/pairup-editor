// Packs PNG files into one .ico (PNG-compressed entries, Vista and later).
// Usage: node make-ico.mjs <out.ico> <png> <png> ...   (each PNG must be square, 256 or less)
import fs from "node:fs";

const [out, ...files] = process.argv.slice(2);
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const images = files.map((f) => {
  const png = fs.readFileSync(f);
  if (!png.subarray(0, 8).equals(PNG_SIG)) throw new Error(f + " is not a PNG");
  const w = png.readUInt32BE(16), h = png.readUInt32BE(20); // IHDR width and height
  if (w !== h || w > 256) throw new Error(`${f} is ${w}x${h}; need a square of 256 or less`);
  return { w, png };
}).sort((a, b) => a.w - b.w);

const head = Buffer.alloc(6);
head.writeUInt16LE(0, 0); // reserved
head.writeUInt16LE(1, 2); // type 1 = icon
head.writeUInt16LE(images.length, 4);

let offset = 6 + 16 * images.length;
const dir = images.map(({ w, png }) => {
  const e = Buffer.alloc(16);
  e.writeUInt8(w === 256 ? 0 : w, 0); // width, 0 means 256
  e.writeUInt8(w === 256 ? 0 : w, 1); // height
  e.writeUInt8(0, 2); // palette colours
  e.writeUInt8(0, 3); // reserved
  e.writeUInt16LE(1, 4); // colour planes
  e.writeUInt16LE(32, 6); // bits per pixel
  e.writeUInt32LE(png.length, 8); // bytes of image data
  e.writeUInt32LE(offset, 12); // offset of image data
  offset += png.length;
  return e;
});

fs.writeFileSync(out, Buffer.concat([head, ...dir, ...images.map((i) => i.png)]));
console.log("wrote", out, offset, "bytes,", images.length, "images");
