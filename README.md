# VaultBuster (Godot)

The video store from the web game, in Godot 4, to walk round and edit. The game's coming over a piece at a time,
each piece translated from the web game's own source (the file it came from is named at the top of each script), so
the numbers and the behaviour are the same. So far: the clock, the sky through the day and night, the day's clouds,
doors and seats. No customers, no register, nothing to pick up yet.

Open `project.godot` in Godot 4.6 or later and press F5.

| Key | |
|---|---|
| WASD, mouse | Walk, look |
| Shift | Run |
| Space | Jump |
| E | Whatever the crosshair's on: open or close a door, sit down, stand up |
| L | Skip an hour (not past midnight) |
| F | Fly, through walls too (Space up, Ctrl down). The ladders don't climb yet, so this is the way onto the roof |
| Esc | Free the mouse (click to take it back) |

## The level

`world/world.scn` is the level: open it and every wall, shelf, chair and sign is a node of its own, under the room
it's in (`out`, `store`, `boh`, `lobby`, `theater`, and `between_rooms` for what sits across two, walls mostly; the
roof and everything on it is `out/roof`). Click something in the 3D view to select it; move it, hide it, delete it, save. Things are named for their
shape and size ("box 1.20 x 0.90 x 0.05"), since the web game never named them. Whatever's there when the game
starts is made solid then, so there's no collision to keep in step.

## Where it comes from

A tool in the web game's repo writes out everything the web game builds as `world/vaultbuster.glb`, and a script here
turns that import into `world.scn`:

```sh
cd ../VaultBuster
node tests/export-glb.mjs ../VaultBusterGodot/world/vaultbuster.glb
cd ../VaultBusterGodot
godot --headless --path . --import
godot --headless --path . --script tools/make_world.gd
```

Close the editor first: it and the command line trip over each other importing. And it only goes one way: this
rebuilds `world.scn` from the web game, so anything changed in it by hand is gone. Do it to start over, not to
update. People, lights, the sky and the weather aren't exported: the scene here has its own sun and sky.

## What's what

| File | |
|---|---|
| `main.tscn` | The level (`world/world.scn`), the sun and sky, the player |
| `world/world.scn` | The level, a node per object |
| `tools/make_world.gd` | Builds `world.scn` from the imported `.glb` |
| `main.gd` | Makes the world solid: a collision shape from each mesh's own triangles (not the doors you walk through) |
| `player.gd` | The first-person walker; sitting |
| `clock.gd` | The shift's clock: 9 AM start, open 10 to midnight, a store hour every 90 seconds, real time after close (web: `store/shift.js`, `store/clock.js`) |
| `sky.gd`, `sky.gdshader` | The sky for the hour, the sun and moon, stars, the day's clouds drifting, the same weather plan per day as the web game (web: `store/shift.js`, `exterior/sky.js`). Rain, snow and fog aren't over yet |
| `interact.gd` | E on things: hinged doors, push doors that swing out of your way, the storefront's door, every seat (web: `store/player.js`, `store/main.js`, `store/shoppers.js`, `store/tv.js`) |
| `data/interact.json` | The doors and seats, from the web game (`node tests/export-glb.mjs --data ../VaultBusterGodot/data/interact.json`) |
| `hud.gd` | The day and time, the crosshair, the tip for what you're aiming at |
| `video.gd` | Plays a tape's file from archive.org: picture onto a texture, sound beside it, with pause and seek. No screen of its own yet. Needs `ffmpeg` on the PATH (from SpaceLife's `wall_tv.gd`; which file a tape is, from web `store/tv.js`) |

`godot --path . -- --check` starts it, tries the clock, noon and night, a door and the couch, prints `check: ok` (or
what's off) and quits. `godot --path . -- --shot` saves `shot.png` from where you spawn and quits; `--at=x,y,z,yaw,pitch`
(degrees) looks from somewhere else, `--hour=19.5` at another time of day. `godot --path . -- "--video=item|file|seconds"`
plays that archive.org file a few seconds from there, saves a frame as `video.png`, and says how long it took.

Not carried over, and noticeable: the lights. The web game lights its rooms in its own shaders, by zone, with
switches; here it's a grid of plain lights under each ceiling, always on, and the lot's lamps don't light at night.
