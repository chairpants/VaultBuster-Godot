extends Node3D
## The level (world/world.scn) made solid: everything you can see gets a collision shape of its own triangles. Not the
## doors you walk through (push doors, the storefront's: see interact.gd), and not things too small to bump into.

func _ready() -> void:
	var solid := 0
	for m: MeshInstance3D in $World.find_children("*", "MeshInstance3D", true, false):
		var size := m.get_aabb().size
		if size.x > 100.0 and m.global_position.y + m.get_aabb().position.y > 8.0:
			m.queue_free()  # the web game's clouds, caught mid-drift by an older export: sky.gd has the real ones
			continue
		if _walk_through(m) or m.get_aabb().get_longest_axis_size() < 0.2:
			continue
		m.create_trimesh_collision()  # ponytail: built at every start (a few seconds); bake it into the level if that gets old
		solid += 1
	print("world: %d meshes solid" % solid)
	var args := OS.get_cmdline_user_args()
	if "--check" in args:  # godot --path . -- --check: the clock, the sky, a door and a seat, then quits (non-zero if any's off)
		_check()
	elif "--shot" in args:  # godot --path . -- --shot [--at=x,y,z,yaw] [--hour=h]: shot.png from there, then quits
		_shot(args)


func _walk_through(n: Node) -> bool:
	while n and n != self:
		if n in $Interact.no_collide:
			return true
		n = n.get_parent()
	return false


func _shot(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--at="):  # x,y,z,yaw (degrees): flying, so nothing's in the way
			var v := a.trim_prefix("--at=").split_floats(",")
			$Player.fly = true
			$Player.global_position = Vector3(v[0], v[1], v[2])
			$Player.rotation.y = deg_to_rad(v[3])
			if v.size() > 4:
				$Player/Camera.rotation.x = deg_to_rad(v[4])
		elif a.begins_with("--hour="):
			Clock.h = a.trim_prefix("--hour=").to_float()
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	print("shot: %s, on the floor %s, at %s" % [Clock.fmt_clock(Clock.h), $Player.is_on_floor(), $Player.global_position])
	get_tree().quit()


func _check() -> void:
	var bad: Array[String] = []
	var I := $Interact
	var P := $Player
	await get_tree().create_timer(0.5).timeout
	if not P.is_on_floor():
		bad.append("not standing on the lot")
	var h0 := Clock.h
	Clock.skip_hour()
	await get_tree().create_timer(3.0).timeout
	if absf(Clock.h - (h0 + 1.0)) > 0.1:
		bad.append("L didn't skip an hour: %s -> %s" % [h0, Clock.h])
	Clock.h = 12.0
	await get_tree().process_frame
	await get_tree().process_frame
	if $Sky.level < 0.99 or $Sun.light_energy < 0.5:
		bad.append("noon isn't bright")
	Clock.h = 23.0
	await get_tree().process_frame
	await get_tree().process_frame
	if $Sky.level > 0.01 or $Sun.light_energy > 0.3:
		bad.append("11 PM isn't dark")
	if I.doors.size() != 5 or I.front.is_empty():
		bad.append("doors: found %d of 5, the front door %s" % [I.doors.size(), not I.front.is_empty()])
	for d in I.doors:
		if not d.push and not d.locked:
			P.global_position = Vector3(0, 0, 10)  # (out of its way)
			I.toggle_door(d)
			await get_tree().create_timer(1.2).timeout
			if absf(d.a - d.openA) > 0.1:
				bad.append("a door didn't swing open")
			break
	var couch: Dictionary = I.seats[1]
	P.global_position = Vector3(couch.x, 0, couch.z + 1.6)
	P.rotation.y = 0.0  # facing -z, at the couch
	$Player/Camera.rotation.x = -0.45
	await get_tree().create_timer(0.3).timeout
	if I.aim_seat == null or I.aim_seat.kind != "couch":
		bad.append("not aiming at the couch from in front of it")
	I.on_e()
	if P.seat == null:
		bad.append("E didn't sit you down")
	I.on_e()
	if P.seat != null:
		bad.append("E didn't stand you up")
	print("check: %s" % ("ok" if bad.is_empty() else "; ".join(bad)))
	get_tree().quit(0 if bad.is_empty() else 1)
