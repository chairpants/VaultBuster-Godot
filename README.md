# VaultBuster (Godot)

The video store from the web game, in Godot 4, to walk round and edit. There's no game here yet: no customers, no
register, nothing to pick up. It's the world.

Open `project.godot` in Godot 4.6 or later and press F5.

| Key | |
|---|---|
| WASD, mouse | Walk, look |
| Shift | Run |
| Space | Jump |
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
| `main.gd` | Makes the world solid: a collision shape from each mesh's own triangles, doors left out |
| `player.gd` | The first-person walker |

`godot --path . -- --shot` starts it, saves `shot.png` from where you spawn, and quits: a quick check that it still
loads and you land on the ground. Add `--at=x,y,z,yaw` (yaw in degrees) to look from somewhere else.
