# VaultBuster (Godot)

The video store from the web game, in Godot 4, to walk round and edit. The game's coming over a piece at a time,
each piece translated from the web game's own source (the file it came from is named at the top of each script), so
the numbers and the behaviour are the same. So far: the clock, the sky through the day and night, the day's clouds,
doors and seats, tapes (off the shelf, into the VCR, playing on every screen), the counter's pass-through, both
ladders to the roof, the light switches and lamps, the lighting itself, and the loose things (the stool, the
standee, the cooler, the deadbolt, the toilet, the cardboard bed, the movie on the roof). No customers, no register yet.

Open `project.godot` in Godot 4.6 or later and press F5.

| Key | |
|---|---|
| WASD, mouse | Walk, look |
| Shift | Run |
| Space | Jump |
| C (hold) | Crouch: lower, and slower |
| Mouse wheel | Sat down: zoom in and out (getting up resets it) |
| E | Whatever the crosshair's on: a door, a seat, the counter's pass-through, a light switch, a lamp, a ladder (the closet's goes up through the hatch; the one out back has to be kicked down from the roof first); at the TV or the theater's screen, the tape in your hand goes in (E again: out it comes) |
| Hold E | On the stool or the standee: pick it up and carry it; E sets it down |
| Click | A tape on the shelf: off it comes, held up to look at. Again: it's in your hand. On its empty slot: back it goes. With one in hand: hold it up |
| Right-click | While you're still looking at a tape you've just picked up: put it back |
| L | Skip an hour (not past midnight) |
| F | Fly, through walls too (Space up, Ctrl down) |
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
| `fixtures.gd` | E on the fixed things: the counter's pass-through, light switches, lamps, both ladders (web: `store/player.js`, `store/clock.js`, `store/tv.js`, `store/roof.js`) |
| `things.gd` | The loose things: the stool (E sits, E again spins, WASD gets up), carrying it and the standee, the cooler's door, the front doors' deadbolt, the flush and the paper towels, sleeping on the cardboard bed (3 hours, or after close through to morning), the roof's projector, VCR and bedsheet (web: `store/player.js`, `store/tv.js`, `store/staff.js`, `store/chores.js`, `store/customer-mode.js`, `store/roof.js`) |
| `lights.gd` | The nine light zones and their switches, fluorescents stuttering as they strike; the side lamps (web: `store/lounge.js`) |
| `room.gd` | The lighting: a surface is lit by which room it's in and whether that room's switch is on, daylight through the glass, sun and moon outside. The web game's room shader, put into every lit material as the game starts (web: `store/core.js` ROOM_FRAG) |
| `data/interact.json` | Doors, seats, screens, the pass-through, ladders, switches, lamps and the rooms' boxes, from the web game (`node tests/export-glb.mjs --data ../VaultBusterGodot/data/interact.json`) |
| `hud.gd` | The day and time, the crosshair, the tip for what you're aiming at |
| `tapes.gd` | Tapes off the shelf and back, in your hand, into the VCR and onto the screens; episodes follow on (web: `store/tv.js`, `store/checkout.js`, `store/shelves.js`). One tape at a time: no inventory yet |
| `data/tapes.json` | Every copy on the shelves: its slot and its episodes, from the web game (written beside `interact.json`) |
| `video.gd` | Plays a tape's file from archive.org: picture onto a texture, sound beside it, with pause and seek. No screen of its own yet. Needs `ffmpeg` on the PATH (from SpaceLife's `wall_tv.gd`; which file a tape is, from web `store/tv.js`) |

`godot --path . -- --check` starts it, tries the clock, noon and night, a door and the couch, prints `check: ok` (or
what's off) and quits. `godot --path . -- --shot` saves `shot.png` from where you spawn and quits; `--at=x,y,z,yaw,pitch`
(degrees) looks from somewhere else, `--hour=19.5` at another time of day, `--dark` with the store's lights off
(`--lamps-off` too), `--take=0` with the first tape held up (`--carry`: in hand; `--play`: in the VCR and a few
seconds in; `--from=600`: wound on to there first). `godot --path . -- "--video=item|file|seconds"`
plays that archive.org file a few seconds from there, saves a frame as `video.png`, and says how long it took.

The lighting goes past the web game in two places, on purpose. Daylight comes in through the storefront as real
light with shadows (the web game fades it toward the back, evenly), so with the switches off the back of the store is
dark, and darker where something's in the way of the windows. And every screen lights the room with the average
colour of the frame on it: the TV and the theater's screen with shadows, the hung monitors with a small pool each.
The knobs are at the top of `lights.gd` (`DAYLIGHT`, `SCREEN_GAIN`). Not over yet: light spilling through a doorway
into a dark room, the lot's lamps at night, and the closet bulb's pull (so the closet stays dark).