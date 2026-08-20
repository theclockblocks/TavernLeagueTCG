#!/usr/bin/env node
// Tavern League TCG - art builder.
//
// Converts source images from Art/ into the addon's texture files. Drop a
// PNG/JPG into Art/ with "back" or "front" in the filename, run this, and
// the newest matching file becomes the in-game texture:
//
//   Art/*back*.png  -> TavernLeagueTCG/art/cardback.tga
//   Art/*front*.png -> TavernLeagueTCG/art/cardfront.tga
//
//   node tools/build_art.js
//
// Textures are written as 512x1024 uncompressed 32-bit TGA (power-of-two,
// loads on both Classic Era and TBC Anniversary clients). The art is
// stretched to the texture; in-game card frames stretch it back, so keep
// sources roughly card-shaped (~0.55-0.65 width:height).
//
// If the icon window moved in new front art, re-measure it and update
// TT.LAYOUT in TavernLeagueTCG/Data.lua (fractions are documented there).
//
// Requires ffmpeg on PATH (https://ffmpeg.org - `winget install ffmpeg`).

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ART_DIR = path.join(__dirname, '..', 'Art');
const OUT_DIR = path.join(__dirname, '..', 'TavernLeagueTCG', 'art');

const TEXTURES = {
  cardback: /back/i,
  cardfront: /front/i,
};

const SOURCE_EXT = /\.(png|jpe?g|webp|bmp)$/i;

function newestMatch(files, pattern) {
  let best = null;
  for (const f of files) {
    if (!SOURCE_EXT.test(f) || !pattern.test(f)) continue;
    const mtime = fs.statSync(path.join(ART_DIR, f)).mtimeMs;
    if (!best || mtime > best.mtime) best = { file: f, mtime };
  }
  return best && best.file;
}

function main() {
  try {
    execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' });
  } catch {
    console.error('ffmpeg not found on PATH. Install it: winget install ffmpeg');
    process.exit(1);
  }
  if (!fs.existsSync(ART_DIR)) {
    console.error(`missing ${ART_DIR}`);
    process.exit(1);
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const files = fs.readdirSync(ART_DIR);
  let built = 0;
  for (const [name, pattern] of Object.entries(TEXTURES)) {
    const src = newestMatch(files, pattern);
    if (!src) {
      console.log(`${name}: no source matching ${pattern} in Art/ - skipped`);
      continue;
    }
    const out = path.join(OUT_DIR, `${name}.tga`);
    execFileSync('ffmpeg', [
      '-y', '-v', 'error',
      '-i', path.join(ART_DIR, src),
      '-vf', 'scale=512:1024',
      '-pix_fmt', 'bgra',
      '-rle', '0',
      out,
    ]);
    console.log(`${name}: ${src} -> art/${name}.tga`);
    built++;
  }
  console.log(built > 0
    ? 'Done. Deploy the addon and /reload to see it in-game.'
    : 'Nothing built.');
}

main();
