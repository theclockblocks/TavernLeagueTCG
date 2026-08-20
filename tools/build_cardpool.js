#!/usr/bin/env node
// Tavern League TCG - card pool builder.
//
// Reads the cached datasets (tools/cache/era_data.json + tbc_data.json,
// fetched by fetch_dataset.js) and emits TavernLeagueTCG/CardPool.lua.
// Pure transform: rerunning is instant, so pool rules can be iterated
// without re-downloading.
//
//   node tools/build_cardpool.js
//
// Also writes tools/report_included.csv and tools/report_excluded.csv for
// eyeballing the junk filter.

'use strict';

const fs = require('fs');
const path = require('path');

const CACHE = path.join(__dirname, 'cache');
const OUT_LUA = path.join(__dirname, '..', 'TavernLeagueTCG', 'CardPool.lua');
const OVERRIDES = path.join(__dirname, 'overrides.csv');

// item classes to include as cards (matched against the dataset's `class`)
const INCLUDE_CLASSES = new Set(['Weapon', 'Armor', 'Trade Goods']);

// Junk/internal items: any match excludes the item.
const JUNK_PATTERNS = [
  /deprecated/i,
  /^monster ?-/i,
  /^test\b/i,
  /\(test\)/i,
  /^qa\b/i,
  /\[ph\]/i,
  /\[dnt\]/i,
  /\bdo not use\b/i,
  /\bunused\b/i,
  /^zz/i,
  /^old\b/i,
  /\(old\)/i,
  /\bplaceholder\b/i,
  /^\d+ (green|blue|epic|test)\b/i,
  /^delete me/i,
  /^broken\b/i,
  /^dnd\b/i,
  /^gm only/i,
  /^game master/i,
  /^level \d+ test/i,
];

const QUALITY_TIER = {
  Poor: 1, Common: 1, Uncommon: 2, Rare: 3, Epic: 4, Legendary: 5, Artifact: 5, Heirloom: 5,
};

// ---------------------------------------------------------------------------

function loadItems(file) {
  const p = path.join(CACHE, file);
  if (!fs.existsSync(p)) {
    console.error(`missing ${p} - run: node tools/fetch_dataset.js`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function loadOverrides() {
  const map = new Map();
  if (!fs.existsSync(OVERRIDES)) return map;
  for (const line of fs.readFileSync(OVERRIDES, 'utf8').split(/\r?\n/)) {
    const t = line.split('#')[0].trim();
    if (!t || t.toLowerCase().startsWith('itemid')) continue;
    const [id, action, tier] = t.split(',').map((s) => s.trim());
    map.set(parseInt(id, 10), {
      action: (action || '').toLowerCase(),
      tier: tier ? parseInt(tier, 10) : null,
    });
  }
  return map;
}

// Community additions the datasets lack: tools/custom_cards.csv
// Format: itemId,tier,tbcOnly,name  (name last - it may contain commas)
function loadCustomCards() {
  const file = path.join(__dirname, 'custom_cards.csv');
  const rows = [];
  if (!fs.existsSync(file)) return rows;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const t = line.split('#')[0].trim();
    if (!t || t.toLowerCase().startsWith('itemid')) continue;
    const parts = t.split(',');
    if (parts.length < 4) {
      console.warn(`custom_cards.csv: skipping malformed line: ${t}`);
      continue;
    }
    const id = parseInt(parts[0], 10);
    const tier = Math.min(5, Math.max(1, parseInt(parts[1], 10) || 1));
    const x = parseInt(parts[2], 10) === 1 ? 1 : 0;
    const name = parts.slice(3).join(',').trim();
    if (id && name) rows.push({ i: id, r: tier, x, n: name });
  }
  return rows;
}

// Read the item ids out of the previously generated CardPool.lua so a
// rebuild can print what changed - makes pool PRs reviewable at a glance.
function loadPreviousPoolIds() {
  if (!fs.existsSync(OUT_LUA)) return null;
  const ids = new Set();
  for (const m of fs.readFileSync(OUT_LUA, 'utf8').matchAll(/^\{i=(\d+),/gm)) {
    ids.add(parseInt(m[1], 10));
  }
  return ids;
}

const isJunk = (name) => JUNK_PATTERNS.some((re) => re.test(name));
const csvName = (name) => '"' + name.replace(/"/g, "'") + '"';

function main() {
  const era = loadItems('era_data.json');
  const tbc = loadItems('tbc_data.json');
  const overrides = loadOverrides();

  const eraIds = new Set(era.map((i) => i.itemId));
  // prefer the era record for era items (era-accurate quality/class);
  // TBC-only items come from the TBC dataset
  const byId = new Map();
  for (const item of tbc) byId.set(item.itemId, item);
  for (const item of era) byId.set(item.itemId, item);

  console.log(`datasets: ${era.length} era items, ${tbc.length} tbc-era items, ` +
    `${byId.size} combined, ${overrides.size} overrides`);

  const rows = [];
  const included = [];
  const excluded = [];

  for (const id of [...byId.keys()].sort((a, b) => a - b)) {
    const item = byId.get(id);
    const isTbcOnly = !eraIds.has(id);
    const ov = overrides.get(id);

    let reason = null;
    if (ov && ov.action === 'exclude') reason = 'override';
    else if (!INCLUDE_CLASSES.has(item.class)) reason = `class ${item.class}`;
    else if (!item.name || isJunk(item.name)) reason = 'junk name';

    if (reason) {
      excluded.push(`${id},${csvName(item.name || '?')},${item.class},${item.quality},${reason}`);
      continue;
    }

    let tier = QUALITY_TIER[item.quality] || 1;
    if (ov && ov.tier && (ov.action === 'tier' || ov.action === 'promote' || ov.action === 'demote')) {
      tier = Math.min(5, Math.max(1, ov.tier));
    }

    rows.push({ i: id, r: tier, x: isTbcOnly ? 1 : 0, n: item.name });
    included.push(`${id},${csvName(item.name)},${item.class},${item.quality},${tier},${isTbcOnly ? 1 : 0}`);
  }

  // community custom cards (skip ids the datasets already provide)
  const datasetIds = new Set(rows.map((r) => r.i));
  for (const c of loadCustomCards()) {
    if (datasetIds.has(c.i)) {
      console.warn(`custom_cards.csv: item ${c.i} (${c.n}) already in the pool - ` +
        `use overrides.csv to re-tier it instead`);
      continue;
    }
    rows.push(c);
    included.push(`${c.i},${csvName(c.n)},custom,custom,${c.r},${c.x}`);
  }
  rows.sort((a, b) => a.i - b.i);

  const byRarity = {};
  const byRarityTbc = {};
  let tbcCount = 0;
  for (const r of rows) {
    byRarity[r.r] = (byRarity[r.r] || 0) + 1;
    if (r.x) {
      tbcCount++;
      byRarityTbc[r.r] = (byRarityTbc[r.r] || 0) + 1;
    }
  }
  console.log(`pool: ${rows.length} cards (${tbcCount} TBC-gated), excluded ${excluded.length}`);
  console.log('rarity spread (all):', byRarity);
  console.log('rarity spread (tbc-only):', byRarityTbc);

  // diff vs the previous CardPool.lua so pool PRs are reviewable
  const prevIds = loadPreviousPoolIds();
  if (prevIds) {
    const newIds = new Set(rows.map((r) => r.i));
    const added = rows.filter((r) => !prevIds.has(r.i));
    const removed = [...prevIds].filter((id) => !newIds.has(id));
    if (added.length === 0 && removed.length === 0) {
      console.log('diff vs previous pool: no card additions/removals');
    } else {
      console.log(`diff vs previous pool: +${added.length} added, -${removed.length} removed`);
      for (const r of added.slice(0, 10)) console.log(`  + ${r.i} ${r.n}`);
      if (added.length > 10) console.log(`  + ...and ${added.length - 10} more`);
      for (const id of removed.slice(0, 10)) console.log(`  - ${id}`);
      if (removed.length > 10) console.log(`  - ...and ${removed.length - 10} more`);
    }
  }

  const lines = [];
  lines.push('-- Tavern League TCG card pool. GENERATED by tools/build_cardpool.js -');
  lines.push('-- do not edit by hand. Regenerate:');
  lines.push('--   node tools/fetch_dataset.js && node tools/build_cardpool.js');
  lines.push('--');
  lines.push(`-- ${rows.length} cards (${tbcCount} TBC-gated). i = itemId, r = rarity tier 1-5,`);
  lines.push('-- n = name (bundled so the binder never waits on the item cache),');
  lines.push('-- x = 1 marks TBC-only items (skipped on Classic Era clients).');
  lines.push('');
  lines.push('local ADDON, TT = ...');
  lines.push('');
  lines.push('TT.pool = {');
  const luaName = (s) => '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
  for (const r of rows) {
    lines.push(`{i=${r.i},r=${r.r},n=${luaName(r.n)}${r.x ? ',x=1' : ''}},`);
  }
  lines.push('}');
  lines.push('');
  fs.writeFileSync(OUT_LUA, lines.join('\n'));
  console.log(`wrote ${OUT_LUA}`);

  fs.writeFileSync(path.join(__dirname, 'report_included.csv'),
    'itemId,name,class,quality,tier,tbcOnly\n' + included.join('\n'));
  fs.writeFileSync(path.join(__dirname, 'report_excluded.csv'),
    'itemId,name,class,quality,reason\n' + excluded.join('\n'));
  console.log('wrote report_included.csv / report_excluded.csv');
}

main();
