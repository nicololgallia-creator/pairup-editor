# Icons

- `pairup.ico` replaces `code.ico` in the build (16, 32, 48 and 256 px, PNG inside). `pairup-150.png` and `pairup-70.png` are the Windows tile images, and `pairup-256.png` and `pairup-32.png` and `pairup-16.png` are the other sizes for docs and the web.
- `pairup.svg` is the source: the Gallia rooster (gallia-redesign/shared/logo/rooster.svg) on a rounded square, `#000` and `#ededed`. One mark, no wordmark. His call 2026-11-03: the two rings "looked very AI generated".
- To regenerate, edit the SVG, then render each size with Edge headless (puppeteer-core, transparent outside corner, `omitBackground`) and pack 16, 32, 48 and 256 into an ICO (6-byte header, one 16-byte entry per image, then the PNG bytes). The 32 and 16 px images use a heavier stroke (2.2 px and 1.3 px) and the 16 px mark is 70% wide instead of 60%, so the rings stay two rings.
