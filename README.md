# VaultBuster (Godot)

The video store from the web game, in Godot 4, to walk round and edit. The game's coming over a piece at a time,
each piece translated from the web game's own source (the file it came from is named at the top of each script), so
the numbers and the behaviour are the same. So far: the clock, the sky through the day and night, the day's clouds,
doors and seats, tapes (off the shelf, into the VCR, playing on every screen), the counter's pass-through, both
ladders to the roof, the light switches and lamps, the lighting itself, and the loose things (the stool, the
standee, the cooler, the deadbolt, the toilet, the cardboard bed, the movie on the roof), the weather, and the people
themselves: passers-by out front, customers who come in, browse, take tapes and queue at the counter, the checkout
(step by step, as the web game has it), and Dana on the register when you're not.

Open `project.godot` in Godot 4.6 or later and press F5.

| Key | |
|---|---|
| WASD, mouse | Walk, look |
| Shift | Run |
| Space | Jump |
| C (hold) | Crouch: lower, and slower |
| Mouse wheel | Sat down: zoom in and out (getting up resets it) |
| E | At the counter, the sale's next step: on the customer (their card, their tapes, the cash, the change, the receipt, the tapes back), on the register (tap the card, ring it up), on the pad (desensitize each tape), on the printer (tear off the receipt). Top left says what's next |
| E | Whatever the crosshair's on: a door, a seat, the counter's pass-through, a light switch, a lamp, a ladder (the closet's goes up through the hatch; the one out back has to be kicked down from the roof first); at the TV or the theater's screen, the tape in your hand goes in (E again: out it comes) |
| Hold E | On the stool or the standee: pick it up and carry it; E sets it down |
| Click | A tape on the shelf: off it comes, held up to look at (what you were holding goes into the inventory: up to 9). Again: it's in your hand. On its empty slot: back it goes. With one in hand: hold it up |
| 1-9, mouse wheel | Which of the tapes you're carrying is in your hand |
| E on a customer | At the counter: ring them up. Sneaking out with a tape under the jacket: stops them (keep the crosshair on one a moment and they may think better of it). Back with a tape that set the gates off: desensitizes it. Otherwise: hello |
| Q on a customer | At the late-fees step of a sale: waives them (E charges them) |
| 1-5 | With a shoplifter stopped: a week's ban, a month's, their membership cancelled, the police, or a warning |
| E on a mess | Picks it up; popcorn wants the carpet sweeper and a spilled soda the mop (E on either in the janitor's closet takes it, E on its spot puts it back) |
| E on a bin, the chute | Ties off the bin's bag (two at a time; right-click sets them down); E at the chute in the janitor's closet sends them down |
| E on the front doors | After close, with the customers gone: clocks you out. The shift's slip, then the next morning at 9:00, doors locked |
| E on the phone, 1 / 2 | Answers it when it rings; 1 or 2 is what you tell them |
| E on the holds tray | With a tape somebody's been promised: sets it aside for them. Empty-handed, with them at the counter for it: takes it down |
| E / Q on a customer asking | E hands them the tape in your hand (the one they asked for, something like it, their hold); Q tells them it's all out |
| E / Q on a post-it | By the phone, once an overdue member's been looked up in the register's messages (M): E rings them, Q throws the note out |
| E on a box, a cupboard | The morning's delivery, just inside the doors: E picks a box up (three at a time), E on a stock cupboard unpacks them |
| E at the popcorn machine | Once it's bought (the register's upgrades): a box, a scoop, butter, salt or sugar; click eats a handful; E on a bin throws the box out |
| Hold E on a rewinder, the desensitizer, the receipt printer | Picks it up to set down somewhere else on the counter: a see-through copy follows your aim (red where it won't fit), the mouse wheel turns it, a click sets it down; right-click, or walking off, puts it back where it was |
| E on a stock cupboard, a rack | Behind the counter: grabs what the racks are missing (drinks from one cupboard, snacks from the other). E on an empty spot on a rack puts one out |
| Esc | The menu: the store stops and saves. Three store files; settings for sound, TV volume, the mouse, how long a shift is |
| E at the register | Mid-sale: the step in hand. Otherwise: logs in to the terminal. Type a selection or a command (H for help) and Enter; Esc goes back; F10 logs off |
| E at the rewinder | With a tape in hand: in it goes, and winds back (up to ten seconds); E again takes it out. A tape shelved unrewound snaps back with a word about it |
| Click / E at Returns | Click takes a returned tape out of the bin (then put it away in its slot); E drops the one in your hand in |
| Right-click | While you're still looking at a tape you've just picked up: put it back |
| L | Skip an hour (not past midnight) |
| F | Fly, through walls too (Space up, Ctrl down) |
| Esc | Free the mouse (click to take it back) |
| F9 | Start over: a fresh store (it's otherwise saved every ten seconds and when you close it, and picked up next time) |

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
| `player.gd` | The first-person walker; sitting; your own body when you look down, in the uniform or (a customer) your own clothes (web: `store/player.js`, me) |
| `clock.gd` | The shift's clock: 9 AM start, open 10 to midnight, a store hour every 90 seconds, real time after close (web: `store/shift.js`, `store/clock.js`) |
| `sky.gd`, `sky.gdshader` | The sky for the hour, the sun and moon, stars, the day's clouds drifting, the same weather plan per day as the web game (web: `store/shift.js`, `exterior/sky.js`) |
| `weather.gd` | The day's weather: rain and snow falling (not indoors), the ground going wet or white, fog, wind and gusts (web: `exterior/sky.js`). Rain beads and runs on the storefront glass; snow drifts against the kerbs and the roof's parapet |
| `interact.gd` | E on things: hinged doors, push doors that swing out of your way, the storefront's door, every seat (web: `store/player.js`, `store/main.js`, `store/shoppers.js`, `store/tv.js`) |
| `fixtures.gd` | E on the fixed things: the counter's pass-through, light switches, lamps, both ladders (web: `store/player.js`, `store/clock.js`, `store/tv.js`, `store/roof.js`) |
| `things.gd` | The loose things: the stool (E sits, E again spins, WASD gets up), carrying it and the standee, the cooler's door, the front doors' deadbolt, the flush and the paper towels, sleeping on the cardboard bed (3 hours, or after close through to morning), the roof's projector, VCR and bedsheet (web: `store/player.js`, `store/tv.js`, `store/staff.js`, `store/chores.js`, `store/customer-mode.js`, `store/roof.js`) |
| `person.gd` | One of the TV-head people, posed every frame: the walk (feet that stay planted, a run over ~2 m/s, nine gaits), sitting, crouching, the arms' poses, the head, breathing, a face for every mood (web: `customers.js`). What the weather does to them (hunched, leaning on the wind, snow on the head and shoulders, an umbrella up or a hand over the head), slipping, shaking off, blinking, a thing held in the hand |
| `people.gd` | The cast, the people going by on the walk out front, and next door's customers: in to Tony's counter, out with a pizza box, on foot or by car (web: `store/shoppers.js`, walkerTick, pizzaRun, npcEnv) |
| `cars.gd` | The lot's cars for the day, the ones going by on the road (one under every pass you hear), and the ones that turn in, park and leave: customers' own, and next door's (web: `exterior/lot.js`). Not over: their engine sound turning in, alarms, crashes |
| `traffic.gd` | Who gives way to whom, people and cars alike. Everybody moving says where they are each frame; people ask it how to take their next step (round whoever's in the way: both step to their own right, the lower rank more, you never; out of a moving car's road, and never into it; parked cars are solid; no dithering where there's no room, they wait and then squeeze by), cars ask it whether anything's in their road (they brake for it), and a car that's waited to back out claims the space it needs. Rank: you, customers, people going by, staff. `godot --headless --path . --script tools/traffic_check.gd` checks it |
| `golf.gd` | Golf off the roof: the practice mat, aim and strike point, the three-click swing meter, the ball's flight (drag, spin, bounces off the parapets), and what it hits out there: car alarms, swerves, a car run off the road, somebody beaned on the walk (web: `store/roof.js`). A car's a box to it; no dents or cracks left behind; no downspouts. W/S pick where the club meets the ball (low on it, it climbs; high on it, it runs), where the web game slides the strike along the face |
| `arcade.gd` | Tony's two cabinets, Space Invaders and Asteroids, playable (E, a quarter as a customer) with their attract screens and high scores; and a slice at his counter, as a customer (web: `tonys/arcade.js`) |
| `pad.gd` | A gamepad, pressed as the keyboard and mouse: left stick walks, right stick looks, A jump, X use, Y Q, B crouch, RB/LB click, D-pad left/right what's in hand, Start the menu. Walking's all or nothing |
| `people/gaits/` | Walk cycles from the 100STYLE motion capture (CC BY 4.0: `CREDITS.txt`), one per gait. Off for now (`person.gd`: `mocap`): they looked goofy on this cast. Made by `tools/bvh2gait.py` from the dataset's BVH files: `python tools/bvh2gait.py Style_FW.bvh people/gaits/<name>.json`. `--shot --gaits --mocap` lines up one of each |
| `people/moves/` | One-off moves from the CMU mocap database (credit: `CREDITS.txt`), played by `person.gd` over its own poses: `kneel` for `crouch` (down to the floor, held while the hand reaches, back up). Made by `tools/bvh2move.py` (run it on a BVH alone to see when the hips drop, then with the start and end in seconds). `--shot --people` has someone kneeling |
| `shoppers.gd` | Customers: who each one is (taste, patience, pace), how busy the day is, the visit: in the door, shelves looked over, a tape taken or put back, the line, the wait, out (web: `store/shoppers.js`). Rentals come back through the Returns slot when they're due. Some drive (a member's car is their own, every visit) |
| `checkout.gd` | Ringing somebody up, a step at a time; what a tape rents for; how a sale's scored (web: `store/checkout.js`, `pos.js`). What each step puts in your hand is held out in front of you, the receipt feeds out of the printer, the drawer slides out. The pad can be skipped (E on the customer for the cash) and used any time till the tapes are handed back; a missed tag sets the gates off. The register beeps, the printer buzzes, and the sale's on the register's own monitor as it goes |
| `ambience.gd` | The store's sound, synthesized: the lights' hum, the vents, the road and cars passing, rain, wind, a crowd's murmur; footsteps, doors, the entry chime, the cooler, a flush, a tap. M mutes it (web: `ambience.js`) |
| `chores.gd` | Keeping the place clean: what customers drop, the mop and the carpet sweeper from the janitor's closet, the four bins filling through the day, bags to the chute (web: `store/chores.js`) |
| `shift.gd` | The day: two goals, the closing check, the store's reputation, the shift's slip when you clock out, and the next morning (web: `store/shift.js`, `store/title.js`) |
| `phone.gd` | The phone behind the counter: members asking after a title (and the holds you promise them), closing time, pranks, late fees, Dennis from district; and the overdue calls you make from a post-it (web: `store/phone.js`) |
| `snacks.gd` | The candy racks and the cooler: what customers pick up on the way to the register, restocking from the cupboards behind the counter, deliveries in boxes by the door, the cooler's temperature and warm drinks, the popcorn machine (web: `store/shoppers.js`, `store/checkout.js`, `store/chores.js`) |
| `menu.gd` | The main menu and pause screen: three store files (play, copy, delete), and the settings (web: `store/title.js`) |
| `pos.gd` | The register's terminal, POS/NET: title and member lookups, reports, messages, ordering supplies and replacement copies, the gate system; the staff's week (W) and their jobs (J) as grids (WASD or the arrows, ENTER sets and clears, G hands it to AUTO); the sale window while somebody's rung up; all of it on the register's monitor on the counter too; painted as the web game paints it, in VT323 (`fonts/`, under the Open Font License) (web: `pos.js`) |
| `customer.gd` | Customer mode: your wallet, paying the clerk, staff-only places and getting caught, what you rent and bring back, your day's slip (web: `store/customer-mode.js`) |
| `members.gd` | The three hundred locals in the register's system, the same numbers and names as the web game's: their address, the year they joined, a note on the account, what they owe, how they feel about the store, who's banned, and the incidents on their record (web: `pos.js`) |
| `staff.gd` | Dana: at her post ringing up whoever's waiting when you don't; and with nobody waiting, taking the returns round the shelves, an armful at a time, through the pass-through and back, then cleaning up (messes, bins to the chute). She works Wednesday to Sunday, 5 to 10 PM; the rest of the time the register's yours (web: `store/staff.js`). They take the phone, fetch what's asked for at the counter and holds promised on the phone, restock, and have lunch in the break room; the register's J and W set their jobs and week. With nothing to do they fetch the stool and sit by the register; unrewound returns go through a rewinder first; lunch is a sandwich; a bag of trash shows in the hand |
| `save.gd` | The store kept between sessions (`user://store.json`): the day and hour, where you are, lights, doors, what's rented and when it's due, the Returns bin, what you're carrying, the VCR, the till (web: `store/main.js`, saveState). Not whoever was in the store |
| `counter.gd` | Rearranging the counter: the rewinders, the desensitizer and the receipt printer, lifted and set down somewhere else on the worktop (web: `store/chores.js`, cmove) |
| `world/cars.glb`, `world/glass_N.png` | One car of each of the six styles (painted here, per car), and the three sheets of rain for the storefront glass: `node tests/export-glb.mjs --cars ../VaultBusterGodot/world/cars.glb` in the web game's repo, then `godot --headless --path . --import` |
| `world/extras.glb` | What a fresh store hasn't got out, and so the level hasn't either: the tapes of the library's locked sections (and the copies that were out on rental when the level was written), those sections' signs, the second rewinder, the rewinders as sports cars. `godot --path . -- --shot --bare` writes `world/bare.json` (which copies the level lacks); then `node tests/export-glb.mjs --extras ../VaultBusterGodot/world/extras.glb` in the web game's repo, and `godot --headless --path . --import` |
| `nav.gd` | Finding a way round the store: the web game's grid and A* over its own floor boxes (web: `store/shoppers.js`, navGrid, navPath) |
| `people/` | The cast: 24 customers, Dana, you twice (uniformed, and in your own clothes) and eight uniformed bodies for whoever's hired, as the web game builds them (`people.glb`), a face sheet each (every mood, open-eyed and mid-blink), and who they are. `node tests/export-glb.mjs --people ../VaultBusterGodot/people`. Tony, from next door, is beside them in what he wears (`tony.glb`, `tony.json`, `face_35.png`): `--tony` instead |
| `lights.gd` | The nine light zones and their switches, fluorescents stuttering as they strike; the side lamps (web: `store/lounge.js`) |
| `room.gd` | The lighting: a surface is lit by which room it's in and whether that room's switch is on, daylight through the glass, sun and moon outside. The web game's room shader, put into every lit material as the game starts (web: `store/core.js` ROOM_FRAG) |
| `data/interact.json` | Doors, seats, screens, the pass-through, ladders, switches, lamps and the rooms' boxes, from the web game (`node tests/export-glb.mjs --data ../VaultBusterGodot/data/interact.json`) |
| `hud.gd` | The day and time, the crosshair, the tip for what you're aiming at |
| `tapes.gd` | Tapes off the shelf and back, in your hand, into the VCR and onto the screens; episodes follow on (web: `store/tv.js`, `store/checkout.js`, `store/shelves.js`). One tape at a time: no inventory yet |
| `data/tapes.json` | Every copy on the shelves: its slot and its episodes, from the web game (written beside `interact.json`) |
| `video.gd` | Plays a tape's file from archive.org: picture onto a texture, sound beside it, with pause and seek. No screen of its own yet. Needs `ffmpeg` on the PATH (from SpaceLife's `wall_tv.gd`; which file a tape is, from web `store/tv.js`) |

`godot --path . -- --check` starts it, tries the clock, noon and night, a door and the couch, prints `check: ok` (or
what's off) and quits; it runs minimised and won't take the keyboard (`--show` to watch it). `godot --path . -- --shot` saves `shot.png` from where you spawn and quits; `--at=x,y,z,yaw,pitch`
(degrees) looks from somewhere else, `--hour=19.5` at another time of day, `--dark` with the store's lights off
(`--lamps-off` too), `--weather=rain` (or `snow`, `fog`), `--wait=8` first, `--cine` with the roof's projector on, `--people` with a line-up of the cast out front, `--street` with people going by, a pizza run and customers arriving, `--tool=mop` (or `sweeper`; `mop:scrub` at work) in your hands, `--snack` (or `--snack=drink`) in your hand, `--feet` stood there rather than flying (your own body and all), `--lit=theater` with a light zone switched on, `--sit=20` sat in that seat, `--co=8` mid-sale at the counter, that many steps in, `--own=rewinder2,rewinders` with those upgrades bought, `--library=0` with that many of the library's tiers in, `--move=printer` with one of the counter's things in the air, `--cooler=52` with the cooler's air at that, `--pos` with the register's terminal up (`--pos=login` its login, `--pos=4` with that typed in), `--take=0` with the first tape held up (`--carry`: in hand; `--play`: in the VCR and a few
seconds in; `--from=600`: wound on to there first). `godot --path . -- "--video=item|file|seconds"`
plays that archive.org file a few seconds from there, saves a frame as `video.png`, and says how long it took.

The lighting goes past the web game in two places, on purpose. Daylight comes in through the storefront as real
light with shadows (the web game fades it toward the back, evenly), so with the switches off the back of the store is
dark, and darker where something's in the way of the windows. And every screen lights the room with the average
colour of the frame on it: the TV and the theater's screen with shadows, the hung monitors with a small pool each.
The knobs are at the top of `lights.gd` (`DAYLIGHT`, `SCREEN_GAIN`, `SPILL`). A lit room spills through a doorway into a
dark one next to it. Outdoors the sun (the moon at night) throws shadows; corners and the undersides of things darken,
lit panels bloom, and the air's faintly hazy where a light crosses it. "Lighting effects" in the settings turns the
costly part of that off.
