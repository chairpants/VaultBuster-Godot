extends SceneTree
## Turns the imported world/vaultbuster.glb (one sealed model, as far as the editor's concerned) into world/world.scn:
## an ordinary scene where every wall, shelf and chair is a node of its own, to select, move, hide or delete.
##   godot --headless --path . --script tools/make_world.gd
## Running it again starts over from the .glb: anything changed in world.scn since is gone.

func _init() -> void:
	var world: Node = (load("res://world/vaultbuster.glb") as PackedScene).instantiate()
	world.name = "World"
	world.scene_file_path = ""  # its own scene now, not an instance of the import
	var count := [0]
	_own(world, world, count)
	var packed := PackedScene.new()
	var err := packed.pack(world)
	if err == OK:
		err = ResourceSaver.save(packed, "res://world/world.scn")
	print("world.scn: %d nodes, %s" % [count[0], error_string(err)])
	for room in world.get_children():
		print("  %s: %d things" % [room.name, room.get_child_count()])
	world.free()
	quit(0 if err == OK else 1)


func _own(n: Node, root: Node, count: Array) -> void:
	for c in n.get_children():
		c.owner = root
		count[0] += 1
		_own(c, root, count)
