# Installer images

Wizard images for the Windows installer (Inno Setup), one mark, no text. They replace `resources/win32/inno-big-*.bmp` and `inno-small-*.bmp`.
Regenerate with `node tools/make-bmp.mjs <icons-dir> inno` after editing `pairup.svg`. The mark is drawn from the SVG at each size.
Big (left panel): 164x314, 192x386, 246x459, 273x556, 328x604, 355x700, 410x797 at 100 to 250%. Small (header): 55x55, 64x68, 83x80, 92x97, 110x106, 119x123, 138x140.
