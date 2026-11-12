// Keeps data/tapes.json clear of episodes nobody can watch any more.
//
//   node tools/prune_tapes.mjs <library-health.json>
//
// VaultVision's scheduled "Library check" asks archive.org about every item
// the library points at and keeps the verdicts in library-health.json (at the
// root of that repo). This takes the episodes it lists as dead out of the
// tapes here, and puts them back when they stop being listed. Run on a
// schedule by .github/workflows/library-sync.yml.
//
// tapes.json is the level's data, written by the web game's exporter: each
// tape has a place on a shelf and a mesh in the world. So this only ever
// touches a tape's episode list ("e"):
//   * a tape with some episodes dead loses those episodes;
//   * a tape with every episode dead is left exactly as it is, and named in
//     the output. It's still an object on the shelf, and a tape with no
//     episodes isn't something the game has ever been handed.
//
// What's taken out is remembered in data/tapes-removed.json, per tape, with
// where in the list it came from. Each run first puts everything back and
// then removes what's dead now, so the result depends only on the two inputs
// and running it twice changes nothing. A fresh export of tapes.json needs no
// care: episodes it brought back whole are simply not put back a second time.
import fs from "node:fs";

const TAPES = "data/tapes.json", REMOVED = "data/tapes-removed.json";
const healthPath = process.argv[2];
if (!healthPath) { console.error("usage: node tools/prune_tapes.mjs <library-health.json>"); process.exit(2); }

const health = JSON.parse(fs.readFileSync(healthPath, "utf8"));
if (!health.deadItems || !health.deadEpisodes) { console.error(`${healthPath}: not a library health record`); process.exit(1); }
const deadItems = new Set(Object.keys(health.deadItems)), deadEpisodes = new Set(Object.keys(health.deadEpisodes));
const keyOf = ([item, , file]) => (file ? `${item}::${file}` : item);
const dead = ep => deadItems.has(ep[0]) || deadEpisodes.has(keyOf(ep));

const data = JSON.parse(fs.readFileSync(TAPES, "utf8"));
const removed = fs.existsSync(REMOVED) ? JSON.parse(fs.readFileSync(REMOVED, "utf8")) : {};

// put back everything taken out before, each at the place it came from
let restored = 0;
for (const tape of data.tapes) {
  const had = removed[tape.k];
  if (!had) continue;
  const present = new Set(tape.e.map(keyOf));
  for (const [at, ep] of [...had].sort((a, b) => a[0] - b[0])) {
    if (present.has(keyOf(ep))) continue;          // a fresh export already has it
    tape.e.splice(Math.min(at, tape.e.length), 0, ep);
    if (!dead(ep)) restored++;
  }
}

// take out what's dead now
const nowRemoved = {}, allDead = [];
let pruned = 0;
for (const tape of data.tapes) {
  const gone = tape.e.map((ep, at) => [at, ep]).filter(([, ep]) => dead(ep));
  if (!gone.length) continue;
  if (gone.length === tape.e.length) { allDead.push(tape.k); continue; }
  nowRemoved[tape.k] = gone;
  tape.e = tape.e.filter(ep => !dead(ep));
  pruned += gone.length;
}

fs.writeFileSync(TAPES, JSON.stringify(data));
if (Object.keys(nowRemoved).length) fs.writeFileSync(REMOVED, JSON.stringify(nowRemoved, null, 1) + "\n");
else fs.rmSync(REMOVED, { force: true });

const episodes = data.tapes.reduce((n, t) => n + t.e.length, 0);
console.log(`${data.tapes.length} tapes, ${episodes} episodes; ${pruned} dead episodes out of ${Object.keys(nowRemoved).length} tapes` +
  (restored ? `; ${restored} put back` : ""));
if (allDead.length) console.log(`${allDead.length} tapes are dead end to end and left alone: ${[...new Set(allDead.map(k => k.split("#")[0]))].join(", ")}`);
