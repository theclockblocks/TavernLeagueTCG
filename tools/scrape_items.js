#!/usr/bin/env node
// Tavern League TCG - Wowhead item scraper.
//
// Scans item IDs against Wowhead's XML endpoint per game flavor and caches
// the parsed results in shard files under tools/cache/. The cache is the
// only output; all filtering/pool logic lives in build_cardpool.js so pool
// rules can change without re-scraping.
//
//   node tools/scrape_items.js                 # full scan, both flavors
//   node tools/scrape_items.js --flavor era    # one flavor
//   node tools/scrape_items.js --from 1 --to 4000   # pilot range
//
// Endpoints (validated 2026-08-19):
//   https://www.wowhead.com/classic/item={id}&xml   (Classic Era data)
//   https://www.wowhead.com/tbc/item={id}&xml       (TBC Classic data)
// Missing items return: <error>Item not found!</error>
//
// Resumable: completed 1000-id shards are skipped on rerun.

'use strict';

const fs = require('fs');
const path = require('path');

const FLAVORS = {
  era: { urlBase: 'https://www.wowhead.com/classic/item=', maxId: 24500 },
  tbc: { urlBase: 'https://www.wowhead.com/tbc/item=', maxId: 35200 },
};

const SHARD_SIZE = 1000;
const CONCURRENCY = 4;
const DELAY_MS = 150;          // per-worker pause between requests
const RETRIES = 5;
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TavernLeagueTCG-pool-builder/0.1 (personal addon project; low rate)';

const CACHE_DIR = path.join(__dirname, 'cache');

// ---------------------------------------------------------------------------

function parseArgs() {
  const args = { flavor: 'both', from: 1, to: null };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--flavor') args.flavor = argv[++i];
    else if (argv[i] === '--from') args.from = parseInt(argv[++i], 10);
    else if (argv[i] === '--to') args.to = parseInt(argv[++i], 10);
  }
  return args;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function parseItemXml(xml) {
  if (xml.includes('<error>')) return 0; // item does not exist in this flavor
  const grab = (re) => {
    const m = xml.match(re);
    return m ? m[1] : null;
  };
  const name = grab(/<name><!\[CDATA\[([\s\S]*?)\]\]><\/name>/);
  if (!name) return 0;
  return {
    n: name,
    q: parseInt(grab(/<quality id="(-?\d+)"/) || '0', 10),
    c: parseInt(grab(/<class id="(-?\d+)"/) || '-1', 10),
    sc: parseInt(grab(/<subclass id="(-?\d+)"/) || '-1', 10),
    sl: parseInt(grab(/<inventorySlot id="(-?\d+)"/) || '0', 10),
    ic: grab(/<icon displayId="\d+">([^<]+)<\/icon>/) || '',
  };
}

async function fetchItem(urlBase, id) {
  let backoff = 2000;
  for (let attempt = 1; attempt <= RETRIES; attempt++) {
    try {
      const res = await fetch(`${urlBase}${id}&xml`, {
        headers: { 'User-Agent': USER_AGENT },
        redirect: 'follow',
      });
      if (res.status === 429 || res.status === 403 || res.status >= 500) {
        process.stdout.write(`\n[${res.status}] backing off ${backoff}ms (id ${id})\n`);
        await sleep(backoff);
        backoff = Math.min(backoff * 2, 60000);
        continue;
      }
      const text = await res.text();
      return parseItemXml(text);
    } catch (err) {
      await sleep(backoff);
      backoff = Math.min(backoff * 2, 60000);
    }
  }
  return 'e'; // persistent error: builder skips, a rescan can retry
}

async function scrapeShard(flavor, cfg, shardIdx, fromId, toId) {
  const dir = path.join(CACHE_DIR, flavor);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `shard-${shardIdx}.json`);
  if (fs.existsSync(file)) return { skipped: true };

  const lo = Math.max(fromId, shardIdx * SHARD_SIZE + 1);
  const hi = Math.min(toId, (shardIdx + 1) * SHARD_SIZE);
  const ids = [];
  for (let id = lo; id <= hi; id++) ids.push(id);

  const out = {};
  let cursor = 0;
  let found = 0;

  async function worker() {
    while (cursor < ids.length) {
      const id = ids[cursor++];
      const item = await fetchItem(cfg.urlBase, id);
      out[id] = item;
      if (item && item !== 'e') found++;
      await sleep(DELAY_MS);
    }
  }

  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  // Partial shards (range-limited pilot runs) get a marker so a full run
  // knows to redo them.
  const complete = lo === shardIdx * SHARD_SIZE + 1 && hi === (shardIdx + 1) * SHARD_SIZE;
  const payload = { complete, items: out };
  fs.writeFileSync(file, JSON.stringify(payload));
  return { found, total: ids.length };
}

async function scrapeFlavor(flavor, fromId, toId) {
  const cfg = FLAVORS[flavor];
  const to = toId || cfg.maxId;
  const firstShard = Math.floor((fromId - 1) / SHARD_SIZE);
  const lastShard = Math.floor((to - 1) / SHARD_SIZE);
  console.log(`[${flavor}] scanning ids ${fromId}..${to} (shards ${firstShard}..${lastShard})`);

  const started = Date.now();
  for (let s = firstShard; s <= lastShard; s++) {
    // redo shards that were written by a narrower pilot range
    const file = path.join(CACHE_DIR, flavor, `shard-${s}.json`);
    if (fs.existsSync(file)) {
      try {
        const prev = JSON.parse(fs.readFileSync(file, 'utf8'));
        const shardLo = s * SHARD_SIZE + 1;
        const shardHi = (s + 1) * SHARD_SIZE;
        if (!prev.complete && fromId <= shardLo && to >= shardHi) {
          fs.unlinkSync(file); // this run covers the whole shard: redo it
        }
      } catch {
        fs.unlinkSync(file);
      }
    }
    const r = await scrapeShard(flavor, cfg, s, fromId, to);
    if (r.skipped) {
      console.log(`[${flavor}] shard ${s}: cached, skipping`);
    } else {
      const mins = ((Date.now() - started) / 60000).toFixed(1);
      console.log(`[${flavor}] shard ${s}: ${r.found}/${r.total} items (${mins}m elapsed)`);
    }
  }
  console.log(`[${flavor}] done.`);
}

async function main() {
  const args = parseArgs();
  const flavors = args.flavor === 'both' ? ['era', 'tbc'] : [args.flavor];
  for (const flavor of flavors) {
    if (!FLAVORS[flavor]) {
      console.error(`Unknown flavor "${flavor}" (use era, tbc or both)`);
      process.exit(1);
    }
  }
  for (const flavor of flavors) {
    await scrapeFlavor(flavor, args.from, args.to);
  }
}

main();
