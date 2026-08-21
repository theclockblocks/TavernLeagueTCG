#!/usr/bin/env node
// Tavern League TCG - the build tool. One command does everything:
//
//   node tools/build.js
//
// 1. Downloads the item datasets into tools/cache/ (first run only)
// 2. Regenerates TavernLeagueTCG/CardPool.lua, applying tools/cards.csv,
//    and prints what changed vs the previous pool
// 3. Converts Art/*back*/*front* images into the addon's card textures
//    (skipped with a note if ffmpeg isn't installed)
//
// Requires Node.js. Art conversion also needs ffmpeg on PATH
// (`winget install ffmpeg`).

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const CACHE = path.join(__dirname, 'cache');
const CARDS_CSV = path.join(__dirname, 'cards.csv');
const OUT_LUA = path.join(ROOT, 'TavernLeagueTCG', 'CardPool.lua');
const ART_SRC = path.join(ROOT, 'Art');
const ART_OUT = path.join(ROOT, 'TavernLeagueTCG', 'art');

// =========================================================================
// Step 1: datasets. Pinned versions of the community wow-classic-items
// package: 0.8.2 was built in the Classic era (defines which items are
// Era), 1.0.0 in the TBC Classic era (adds TBC items, no WotLK).
// =========================================================================

const DATASETS = {
  era_data: 'https://registry.npmjs.org/wow-classic-items/-/wow-classic-items-0.8.2.tgz',
  tbc_data: 'https://registry.npmjs.org/wow-classic-items/-/wow-classic-items-1.0.0.tgz',
};

// Creature/NPC data comes from Questie's database (GPL, cmangos-derived),
// pinned to a commit for reproducible builds.
const QUESTIE_SHA = 'c51da22464665994eadeeb07043a6d094d35920b';
const QUESTIE_FILES = {
  era_npc: 'Database/Classic/classicNpcDB.lua',
  era_quest: 'Database/Classic/classicQuestDB.lua',
  era_item: 'Database/Classic/classicItemDB.lua',
  tbc_npc: 'Database/TBC/tbcNpcDB.lua',
  tbc_quest: 'Database/TBC/tbcQuestDB.lua',
  tbc_item: 'Database/TBC/tbcItemDB.lua',
};

async function ensureDatasets() {
  fs.mkdirSync(CACHE, { recursive: true });
  for (const [name, url] of Object.entries(DATASETS)) {
    const out = path.join(CACHE, `${name}.json`);
    if (fs.existsSync(out)) continue;
    console.log(`downloading ${url}`);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    fs.writeFileSync(path.join(CACHE, `${name}.tgz`), Buffer.from(await res.arrayBuffer()));
    const workDir = path.join(CACHE, `${name}_extract`);
    fs.mkdirSync(workDir, { recursive: true });
    // relative paths + cwd: GNU tar on Windows misreads "E:\..." as a host
    execFileSync('tar', ['-xzf', `${name}.tgz`, '-C', `${name}_extract`, 'package/data/json/data.json'],
      { cwd: CACHE });
    fs.copyFileSync(path.join(workDir, 'package', 'data', 'json', 'data.json'), out);
    fs.rmSync(workDir, { recursive: true, force: true });
    fs.unlinkSync(path.join(CACHE, `${name}.tgz`));
    console.log(`cached ${name}.json`);
  }
  for (const [name, repoPath] of Object.entries(QUESTIE_FILES)) {
    const out = path.join(CACHE, `${name}.lua`);
    if (fs.existsSync(out)) continue;
    const url = `https://raw.githubusercontent.com/Questie/Questie/${QUESTIE_SHA}/${repoPath}`;
    console.log(`downloading ${url}`);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    fs.writeFileSync(out, await res.text());
    console.log(`cached ${name}.lua`);
  }
}

// ---------------------------------------------------------------------------
// Minimal Lua-value parser: enough for Questie's generated data tables
// (numbers, strings, nil/true/false, and tables with positional and
// [key]= entries). Positional nils are kept so field indexes stay stable.
// ---------------------------------------------------------------------------

function parseLua(text) {
  let i = 0;
  function skipWs() {
    for (;;) {
      const c = text[i];
      if (c === ' ' || c === '\t' || c === '\n' || c === '\r') i++;
      else if (c === '-' && text[i + 1] === '-') {
        while (i < text.length && text[i] !== '\n') i++;
      } else break;
    }
  }
  function parseString(q) {
    i++;
    let out = '';
    while (i < text.length && text[i] !== q) {
      if (text[i] === '\\') { out += text[i + 1]; i += 2; }
      else { out += text[i]; i++; }
    }
    i++;
    return out;
  }
  function parseTable() {
    i++; // consume {
    const arr = [];
    const map = {};
    let hasKeys = false;
    for (;;) {
      skipWs();
      if (text[i] === '}') { i++; break; }
      if (text[i] === '[') {
        i++;
        const key = parseValue();
        skipWs(); i++; // ]
        skipWs(); i++; // =
        map[key] = parseValue();
        hasKeys = true;
      } else {
        arr.push(parseValue());
      }
      skipWs();
      if (text[i] === ',' || text[i] === ';') i++;
    }
    return hasKeys ? map : arr;
  }
  function parseValue() {
    skipWs();
    const c = text[i];
    if (c === '{') return parseTable();
    if (c === "'" || c === '"') return parseString(c);
    if (text.startsWith('nil', i)) { i += 3; return null; }
    if (text.startsWith('true', i)) { i += 4; return true; }
    if (text.startsWith('false', i)) { i += 5; return false; }
    let j = i;
    while (j < text.length && /[-+0-9.eExA-Fa-f]/.test(text[j])) j++;
    const n = Number(text.slice(i, j));
    i = j;
    return n;
  }
  skipWs();
  if (text.startsWith('return', i)) i += 6;
  return parseValue();
}

function loadQuestieTable(name) {
  const txt = fs.readFileSync(path.join(CACHE, `${name}.lua`), 'utf8');
  const a = txt.indexOf('[[return');
  const b = txt.lastIndexOf(']]');
  if (a < 0 || b < 0) throw new Error(`${name}.lua: unexpected format`);
  return parseLua(txt.slice(a + 2, b));
}

// =========================================================================
// Step 2: the card pool.
// =========================================================================

// item classes that become cards
const INCLUDE_CLASSES = new Set(['Weapon', 'Armor', 'Trade Goods']);

// junk/internal items: any match excludes the item
const JUNK_PATTERNS = [
  /deprecated/i, /^monster ?-/i, /^test\b/i, /\(test\)/i, /^qa\b/i,
  /\[ph\]/i, /\[dnt\]/i, /\bdo not use\b/i, /\bunused\b/i, /^zz/i,
  /^old\b/i, /\(old\)/i, /\bplaceholder\b/i, /^\d+ (green|blue|epic|test)\b/i,
  /^delete me/i, /^broken\b/i, /^dnd\b/i, /^gm only/i, /^game master/i,
  /^level \d+ test/i,
];

const QUALITY_TIER = {
  Poor: 1, Common: 1, Uncommon: 2, Rare: 3, Epic: 4, Legendary: 5, Artifact: 5, Heirloom: 5,
};

// tools/cards.csv - the community's one card-edits file.
// itemId,action[,tier[,tbcOnly,name]]  action: exclude | tier | add
function loadCardEdits() {
  const edits = { exclude: new Set(), tier: new Map(), add: [] };
  if (!fs.existsSync(CARDS_CSV)) return edits;
  for (const line of fs.readFileSync(CARDS_CSV, 'utf8').split(/\r?\n/)) {
    const t = line.split('#')[0].trim();
    if (!t || t.toLowerCase().startsWith('itemid')) continue;
    const parts = t.split(',');
    const id = parseInt(parts[0], 10);
    const action = (parts[1] || '').trim().toLowerCase();
    if (!id || !action) {
      console.warn(`cards.csv: skipping malformed line: ${t}`);
      continue;
    }
    if (action === 'exclude') {
      edits.exclude.add(id);
    } else if (action === 'tier') {
      const tier = parseInt(parts[2], 10);
      if (tier >= 1 && tier <= 5) edits.tier.set(id, tier);
      else console.warn(`cards.csv: bad tier on line: ${t}`);
    } else if (action === 'add') {
      const tier = Math.min(5, Math.max(1, parseInt(parts[2], 10) || 1));
      const x = parseInt(parts[3], 10) === 1 ? 1 : 0;
      const name = parts.slice(4).join(',').trim();
      if (name) edits.add.push({ i: id, r: tier, x, n: name });
      else console.warn(`cards.csv: add without a name: ${t}`);
    } else {
      console.warn(`cards.csv: unknown action "${action}" on line: ${t}`);
    }
  }
  return edits;
}

function loadPreviousPoolIds() {
  if (!fs.existsSync(OUT_LUA)) return null;
  const ids = new Set();
  for (const line of fs.readFileSync(OUT_LUA, 'utf8').split('\n')) {
    const m = line.match(/^\{i=(\d+),/);
    if (m) ids.add((line.includes('kind="npc"') ? 'npc:' : 'item:') + m[1]);
  }
  return ids;
}

const isJunk = (name) => JUNK_PATTERNS.some((re) => re.test(name));
const csvName = (name) => '"' + name.replace(/"/g, "'") + '"';

// ---------------------------------------------------------------------------
// Creature cards. Curation rules (this is the whole point - no card for
// "Forest Spider #7"):
//   worldboss rank (3)            -> boss,     legendary
//   rare / rare-elite rank (4/2)  -> rare,     rare
//   mobs that are quest OBJECTIVES-> mob,      uncommon (elite: rare)
//   quest givers/enders           -> questnpc, common (elite: uncommon)
// Everything else is skipped. Names are deduped (first id wins).
// npcDB fields (0-based): 0 name, 3 minLevel, 4 maxLevel, 5 rank,
// 9 questStarts, 10 questEnds
// ---------------------------------------------------------------------------

const NPC_JUNK = [
  /only gm/i, /^\[/, /unused/i, /trigger/i, /waypoint/i, /spawn point/i,
  /dummy/i, /\btest\b/i, /invisible/i, /placeholder/i, /credit\b/i,
  /bunny/i, /marker/i, /controller/i, /^visual/i, /deprecated/i,
  /^emote/i, /^summon/i, /\(old\)/i, /^old\b/i,
];

const isNpcJunk = (name) => NPC_JUNK.some((re) => re.test(name));

// Kill objectives name the mob directly; "collect X" quests name an item,
// which the item DB maps back to its droppers.
function collectQuestMobs(questTable, intoMobs, intoItems) {
  for (const q of Object.values(questTable)) {
    const objectives = q && q[9];
    if (!objectives) continue;
    const creatureObjectives = objectives[0];
    if (creatureObjectives) {
      for (const co of creatureObjectives) {
        if (co && typeof co[0] === 'number') intoMobs.add(co[0]);
      }
    }
    const itemObjectives = objectives[2];
    if (itemObjectives) {
      for (const io of itemObjectives) {
        if (io && typeof io[0] === 'number') intoItems.add(io[0]);
      }
    }
  }
}

// Items a quest collects -> the NPCs that drop them ("Wanted: Hogger" is
// an item objective). Widely-farmed items (>10 droppers) are skipped so
// "collect 10 Linen Cloth" doesn't flag every humanoid in the game.
function addQuestItemDroppers(itemTable, questItems, intoMobs) {
  for (const id of questItems) {
    const entry = itemTable[id];
    const droppers = entry && entry[1];
    if (droppers && droppers.length > 0 && droppers.length <= 10) {
      for (const npcId of droppers) {
        if (typeof npcId === 'number') intoMobs.add(npcId);
      }
    }
  }
}

function classifyNpc(fields, questMobs, id) {
  const name = fields[0];
  if (typeof name !== 'string' || name === '' || isNpcJunk(name)) return null;
  const rank = fields[5] || 0;
  const givesQuests = (fields[9] && fields[9].length) || (fields[10] && fields[10].length);
  if (rank === 3) return { set: 'boss', tier: 5 };
  if (rank === 2 || rank === 4) return { set: 'rare', tier: 3 };
  if (questMobs.has(id)) return { set: 'mob', tier: rank === 1 ? 3 : 2 };
  if (givesQuests) return { set: 'questnpc', tier: rank === 1 ? 2 : 1 };
  return null;
}

function buildCreatureRows() {
  const eraNpcs = loadQuestieTable('era_npc');
  const tbcNpcs = loadQuestieTable('tbc_npc');
  const questMobs = new Set();
  const questItems = new Set();
  collectQuestMobs(loadQuestieTable('era_quest'), questMobs, questItems);
  collectQuestMobs(loadQuestieTable('tbc_quest'), questMobs, questItems);
  addQuestItemDroppers(loadQuestieTable('era_item'), questItems, questMobs);
  addQuestItemDroppers(loadQuestieTable('tbc_item'), questItems, questMobs);

  const eraIds = new Set(Object.keys(eraNpcs).map(Number));
  const byId = new Map();
  for (const [id, f] of Object.entries(tbcNpcs)) byId.set(Number(id), f);
  for (const [id, f] of Object.entries(eraNpcs)) byId.set(Number(id), f);

  const rows = [];
  const seenNames = new Set();
  const setCounts = {};
  for (const id of [...byId.keys()].sort((a, b) => a - b)) {
    const fields = byId.get(id);
    const cls = classifyNpc(fields, questMobs, id);
    if (!cls) continue;
    const nameKey = fields[0].toLowerCase();
    if (seenNames.has(nameKey)) continue;
    seenNames.add(nameKey);
    rows.push({
      i: id, r: cls.tier, x: eraIds.has(id) ? 0 : 1,
      n: fields[0], kind: 'npc', s: cls.set,
    });
    setCounts[cls.set] = (setCounts[cls.set] || 0) + 1;
  }
  console.log('creature sets:', setCounts);
  return rows;
}

function buildPool() {
  const era = JSON.parse(fs.readFileSync(path.join(CACHE, 'era_data.json'), 'utf8'));
  const tbc = JSON.parse(fs.readFileSync(path.join(CACHE, 'tbc_data.json'), 'utf8'));
  const edits = loadCardEdits();

  const eraIds = new Set(era.map((i) => i.itemId));
  // prefer the era record for era items (era-accurate quality/class)
  const byId = new Map();
  for (const item of tbc) byId.set(item.itemId, item);
  for (const item of era) byId.set(item.itemId, item);

  const rows = [];
  const included = [];
  const excluded = [];

  for (const id of [...byId.keys()].sort((a, b) => a - b)) {
    const item = byId.get(id);
    const isTbcOnly = !eraIds.has(id);

    let reason = null;
    if (edits.exclude.has(id)) reason = 'cards.csv exclude';
    else if (!INCLUDE_CLASSES.has(item.class)) reason = `class ${item.class}`;
    else if (!item.name || isJunk(item.name)) reason = 'junk name';

    if (reason) {
      excluded.push(`${id},${csvName(item.name || '?')},${item.class},${item.quality},${reason}`);
      continue;
    }

    const tier = edits.tier.get(id) || QUALITY_TIER[item.quality] || 1;
    rows.push({ i: id, r: tier, x: isTbcOnly ? 1 : 0, n: item.name });
    included.push(`${id},${csvName(item.name)},${item.class},${item.quality},${tier},${isTbcOnly ? 1 : 0}`);
  }

  // community-added cards the datasets lack
  const datasetIds = new Set(rows.map((r) => r.i));
  for (const c of edits.add) {
    if (datasetIds.has(c.i)) {
      console.warn(`cards.csv: item ${c.i} (${c.n}) already in the pool - use a "tier" line instead`);
      continue;
    }
    rows.push(c);
    included.push(`${c.i},${csvName(c.n)},custom,custom,${c.r},${c.x}`);
  }
  rows.sort((a, b) => a.i - b.i);

  // creature/NPC cards, after the items (binder shows them grouped)
  for (const c of buildCreatureRows()) {
    rows.push(c);
    included.push(`${c.i},${csvName(c.n)},npc:${c.s},npc,${c.r},${c.x}`);
  }

  const byRarity = {};
  let tbcCount = 0;
  let creatureCount = 0;
  for (const r of rows) {
    byRarity[r.r] = (byRarity[r.r] || 0) + 1;
    if (r.x) tbcCount++;
    if (r.kind === 'npc') creatureCount++;
  }
  console.log(`pool: ${rows.length} cards (${creatureCount} creatures, ${tbcCount} TBC-gated), ` +
    `excluded ${excluded.length}`);
  console.log('rarity spread:', byRarity);

  // diff vs the previous CardPool.lua so pool PRs are reviewable
  const rowKey = (r) => (r.kind === 'npc' ? 'npc:' : 'item:') + r.i;
  const prevIds = loadPreviousPoolIds();
  if (prevIds) {
    const newIds = new Set(rows.map(rowKey));
    const added = rows.filter((r) => !prevIds.has(rowKey(r)));
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

  const luaName = (s) => '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
  const lines = [];
  lines.push('-- Tavern League TCG card pool. GENERATED by tools/build.js -');
  lines.push('-- do not edit by hand. Edit tools/cards.csv, then: node tools/build.js');
  lines.push('--');
  lines.push(`-- ${rows.length} cards (${creatureCount} creatures, ${tbcCount} TBC-gated).`);
  lines.push('-- i = itemId/npcId, r = rarity tier 1-5, n = name (bundled),');
  lines.push('-- kind="npc" + s=set (questnpc/mob/rare/boss) marks creature cards,');
  lines.push('-- x = 1 marks TBC-only entries (skipped on Classic Era clients).');
  lines.push('');
  lines.push('local ADDON, TT = ...');
  lines.push('');
  lines.push('TT.pool = {');
  for (const r of rows) {
    const extra = (r.kind === 'npc' ? `,kind="npc",s="${r.s}"` : '') + (r.x ? ',x=1' : '');
    lines.push(`{i=${r.i},r=${r.r},n=${luaName(r.n)}${extra}},`);
  }
  lines.push('}');
  lines.push('');
  fs.writeFileSync(OUT_LUA, lines.join('\n'));
  console.log(`wrote TavernLeagueTCG/CardPool.lua`);

  fs.writeFileSync(path.join(__dirname, 'report_included.csv'),
    'itemId,name,class,quality,tier,tbcOnly\n' + included.join('\n'));
  fs.writeFileSync(path.join(__dirname, 'report_excluded.csv'),
    'itemId,name,class,quality,reason\n' + excluded.join('\n'));
}

// =========================================================================
// Step 3: art. Newest Art/*back* and Art/*front* images become the card
// textures (512x1024 uncompressed TGA - loads on both game clients).
// =========================================================================

const ART_TEXTURES = { cardback: /back/i, cardfront: /front/i };
const ART_EXT = /\.(png|jpe?g|webp|bmp)$/i;

function buildArt() {
  try {
    execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' });
  } catch {
    console.log('art: ffmpeg not found - skipping (install: winget install ffmpeg)');
    return;
  }
  if (!fs.existsSync(ART_SRC)) {
    console.log('art: no Art/ folder - skipping');
    return;
  }
  fs.mkdirSync(ART_OUT, { recursive: true });
  const files = fs.readdirSync(ART_SRC);
  for (const [name, pattern] of Object.entries(ART_TEXTURES)) {
    let best = null;
    for (const f of files) {
      if (!ART_EXT.test(f) || !pattern.test(f)) continue;
      const mtime = fs.statSync(path.join(ART_SRC, f)).mtimeMs;
      if (!best || mtime > best.mtime) best = { file: f, mtime };
    }
    if (!best) {
      console.log(`art: no source matching ${pattern} in Art/ - skipped ${name}`);
      continue;
    }
    execFileSync('ffmpeg', [
      '-y', '-v', 'error',
      '-i', path.join(ART_SRC, best.file),
      '-vf', 'scale=512:1024', '-pix_fmt', 'bgra', '-rle', '0',
      path.join(ART_OUT, `${name}.tga`),
    ]);
    console.log(`art: ${best.file} -> art/${name}.tga`);
  }
}

// =========================================================================

async function main() {
  await ensureDatasets();
  buildPool();
  buildArt();
  console.log('\nDone. Deploy the addon and /reload to see changes in-game.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
