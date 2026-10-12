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

## Where the world comes from

`world/vaultbuster.glb` is everything the web game builds, written out by a tool in the web game's repo:

```sh
cd ../VaultBuster
node tests/export-glb.mjs ../VaultBusterGodot/world/vaultbuster.glb
```

It's grouped by room (`out`, `store`, `boh`, `lobby`, `theater`, `roof`). People, lights, the sky and the weather
aren't in it: the scene here has its own sun and sky.

It only goes one way. Running the export again replaces the file, so changes made to the world inside Godot want
saving somewhere else first: open the `.glb`, choose *New Inherited Scene* (or make it local), and save that as its
own scene.

## What's what

| File | |
|---|---|
| `main.tscn` | The world, the sun and sky, the player |
| `main.gd` | Makes the world solid: a collision shape from each mesh's own triangles, doors left out |
| `player.gd` | The first-person walker |

`godot --path . -- --shot` starts it, saves `shot.png` from where you spawn, and quits: a quick check that it still
loads and you land on the ground.
