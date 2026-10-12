extends Node3D
## The web game's world (world/vaultbuster.glb, written by its tests/export-glb.mjs), made solid: everything you can
## see gets a collision shape of its own triangles. Not doors (they don't open yet, so you walk through them), and not
## things too small to bump into.

func _ready() -> void:
	var solid := 0
	for m: MeshInstance3D in $World.find_children("*", "MeshInstance3D", true, false):
		if _is_door(m) or m.get_aabb().get_longest_axis_size() < 0.2:
			continue
		m.create_trimesh_collision()  # ponytail: built at every start (a few seconds); bake it into the import if that gets old
		solid += 1
	print("world: %d meshes solid" % solid)
	if "--shot" in OS.get_cmdline_user_args():  # the check: godot --path . -- --shot  -> shot.png, then quits
		_shot()


func _is_door(n: Node) -> bool:
	while n and n != self:
		if n.name.begins_with("door"):
			return true
		n = n.get_parent()
	return false


func _shot() -> void:
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	print("shot: on the floor %s, at %s" % [$Player.is_on_floor(), $Player.global_position])
	get_tree().quit()
