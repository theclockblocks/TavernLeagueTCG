#!/usr/bin/env node
// Tavern League TCG - dataset fetcher.
//
// Downloads two pinned versions of the community `wow-classic-items` npm
// package (github.com/nexus-devs/wow-classic-items) into tools/cache/:
//
//   v0.8.2 (built 2020, Classic era)      -> cache/era_data.json
//   v1.0.0 (built 2021, TBC Classic era)  -> cache/tbc_data.json
//
// The Era file defines which items are Classic; anything only in the TBC
// file is tagged x=1 by build_cardpool.js. Pinned versions = reproducible
// pool. (The original plan scraped Wowhead's XML endpoint directly, but
// Cloudflare rate-bans bulk scans; scrape_items.js remains for low-volume
// spot verification only.)
//
//   node tools/fetch_dataset.js

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const CACHE = path.join(__dirname, 'cache');
const SOURCES = {
  era_data: 'https://registry.npmjs.org/wow-classic-items/-/wow-classic-items-0.8.2.tgz',
  tbc_data: 'https://registry.npmjs.org/wow-classic-items/-/wow-classic-items-1.0.0.tgz',
};

async function main() {
  fs.mkdirSync(CACHE, { recursive: true });
  for (const [name, url] of Object.entries(SOURCES)) {
    const out = path.join(CACHE, `${name}.json`);
    if (fs.existsSync(out)) {
      console.log(`${name}.json already cached, skipping`);
      continue;
    }
    console.log(`downloading ${url}`);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    const buf = Buffer.from(await res.arrayBuffer());
    const tgz = path.join(CACHE, `${name}.tgz`);
    fs.writeFileSync(tgz, buf);

    const workDir = path.join(CACHE, `${name}_extract`);
    fs.mkdirSync(workDir, { recursive: true });
    // relative paths + cwd: GNU tar on Windows misreads "E:\..." as a host
    execFileSync('tar', ['-xzf', `${name}.tgz`, '-C', `${name}_extract`, 'package/data/json/data.json'],
      { cwd: CACHE });
    fs.copyFileSync(path.join(workDir, 'package', 'data', 'json', 'data.json'), out);
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.unlinkSync(tgz);
    console.log(`wrote ${out}`);
  }
  console.log('done. Now run: node tools/build_cardpool.js');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
