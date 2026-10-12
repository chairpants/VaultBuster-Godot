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
	print("lights: ceiling panels by zone %s" % [$Lights._panels.keys().map(func(z: String) -> String: return "%s %d" % [z, $Lights._panels[z].size()])])
	var args := OS.get_cmdline_user_args()
	if "--check" in args:  # godot --path . -- --check: the clock, the sky, a door and a seat, then quits (non-zero if any's off)
		_check()
	elif args.size() and args[0].begins_with("--video="):  # godot --path . -- "--video=item|file|seconds in": plays it a few seconds, saves a frame as video.png, quits
		_video(args[0].trim_prefix("--video=").split("|"))
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
		elif a == "--dark":  # the store's lights off (the sales floor's and the hall's)
			for z in ["front", "aisles", "lounge", "hall"]:
				$Lights.set_zone(z, false)
			if "--lamps-off" in args:
				for l in $Lights.lamps:
					$Lights.set_lamp(l, false)
		elif a.begins_with("--weather="):  # rain | snow | fog | clear, straight to it
			var w := a.trim_prefix("--weather=")
			$Weather.set_now("clear" if w == "fog" else w, 0.9, 0.8 if w == "fog" else 0.0)
		elif a == "--people":  # a line-up out front: one standing, one walking on the spot, one running, one sat, one crouched, one at a counter
			var poses := [["idle", 0.0, "happy"], ["walk", 1.3, "neutral"], ["walk", 3.0, "alarm"], ["sit", 0.0, "love"], ["crouch", 0.0, "shifty"], ["wait", 0.0, "impatient"], ["hold", 1.2, "thanks"], ["read", 0.0, "browse"]]
			for i in poses.size():
				var c: Node3D = $People.spawn(i)
				c.position = Vector3(-3.5 + i * 1.0, -0.12, -8.0)
				c.rotation.y = PI
				c.set_pose(poses[i][0], { "hipY": 0.5 })
				c.set_mood(poses[i][2])
				if poses[i][0] == "hold":
					c.hold_tape(2)
				var sp: float = poses[i][1]
				get_tree().process_frame.connect(func() -> void: c.tick(get_process_delta_time(), sp))
		elif a == "--cine":  # the roof's projector on
			$Things.cine_on = true
		elif a.begins_with("--hour="):
			Clock.h = a.trim_prefix("--hour=").to_float()
		elif a.begins_with("--take="):  # a tape off the shelf, by its number in data/tapes.json: held up, or (with --carry) in hand
			for b in args:  # --from=seconds: wound on to there first
				if b.begins_with("--from="):
					$Tapes.tapes[a.trim_prefix("--take=").to_int()].at = b.trim_prefix("--from=").to_float()
			$Tapes.pickup($Tapes.tapes[a.trim_prefix("--take=").to_int()])
			$Tapes.inspecting = not "--carry" in args
			if "--play" in args:  # ...and into the VCR, and on a few seconds
				$Tapes.aim_tv = $Tapes.screens[0]
				$Tapes.vcr_use()
				var t0 := Time.get_ticks_msec()
				while $Video._shown < 90 and Time.get_ticks_msec() - t0 < 60000:
					await get_tree().process_frame
	for w in args:  # --wait=seconds first (for things that take a while: lamps warming up)
		if w.begins_with("--wait="):
			await get_tree().create_timer(w.trim_prefix("--wait=").to_float()).timeout
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	print("shot: %s, on the floor %s, at %s" % [Clock.fmt_clock(Clock.h), $Player.is_on_floor(), $Player.global_position])
	get_tree().quit()



func _video(p: PackedStringArray) -> void:
	var V := $Video
	var at := p[2].to_float() if p.size() > 2 else 0.0
	V.failed.connect(func(why: String) -> void:
		print("video: failed: ", why)
		get_tree().quit(1))
	var t0 := Time.get_ticks_msec()
	V.play_episode([p[0], "", p[1] if p.size() > 1 and p[1] != "" else null], at)
	while V.position < at + 4.0 and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	V.texture.get_image().save_png("res://video.png")
	print("video: %s, %.1f s in (asked for %.1f), of %.0f s; first frame after %.1f s; sound %s; %s" % ["ok" if V.position >= at + 4.0 else "nothing in 90 s", V.position, at, V.duration, (Time.get_ticks_msec() - t0) / 1000.0 - (V.position - at), V.audio.playing, V.url])
	V.stop()
	get_tree().quit(0 if V.position >= at + 4.0 else 1)


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
	if $Sky.level < 0.99:
		bad.append("noon isn't bright")
	Clock.h = 23.0
	await get_tree().process_frame
	await get_tree().process_frame
	if $Sky.level > 0.01:
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
	var F := $Fixtures
	if F._flap_pivot == null or F._flap_gate == null or F._lid == null or F._slide == null:
		bad.append("not every fixture was found in the level")
	else:
		P.global_position = Vector3(0, 0, 10)
		F.aim = "flap"
		F.on_e()
		await get_tree().create_timer(1.2).timeout
		if absf(F._flap_pivot.rotation.z - F.flap.openA) > 0.1:
			bad.append("the counter's leaf didn't lift")
		F.aim = "hatch"
		F.on_e()
		await get_tree().create_timer(F.ladders.dur + 0.6).timeout
		if not F.on_roof() or P.climb != null:
			bad.append("the closet ladder didn't get you onto the roof (y %.1f)" % P.global_position.y)
		F.aim = "back"
		F.on_e()
		await get_tree().create_timer(1.2).timeout
		if not F.back_down or F._slide.position.y > 0.0:
			bad.append("the back ladder didn't come down when kicked")
		F.aim = "back"
		F.on_e()
		await get_tree().create_timer(F.ladders.dur + 0.6).timeout
		if F.on_roof() or absf(P.global_position.x - F.ladders.back.climb.down.x) > 0.5:
			bad.append("the back ladder didn't get you down (at %s)" % P.global_position)
	var Th := $Things
	if Th._stool == null or Th._stool_top == null or Th._cooler == null or Th._turn == null:
		bad.append("not every loose thing was found in the level (stool %s, its seat %s, cooler %s, deadbolt %s, standee %s)" % [Th._stool != null, Th._stool_top != null, Th._cooler != null, Th._turn != null, Th._cutout != null])
	else:
		P.global_position = Vector3(-4.5, 0, 3.2)
		P.rotation.y = 0.0
		Th.aim = "stool"
		I.on_e()
		I.on_e()
		await get_tree().create_timer(0.4).timeout
		if not Th.on_stool or Th._vel <= 0.0 or Th._angle == 0.0:
			bad.append("the stool: not sat on it and spinning")
		Th._stool_stand()
		if Th.on_stool or P.seat != null:
			bad.append("didn't get up off the stool")
		Th.aim = "stool"
		Th.pick_up()
		await get_tree().create_timer(0.3).timeout
		if Th.carrying != "stool" or Th._stool.global_position.distance_to(P.global_position) > 1.5:
			bad.append("the stool isn't being carried")
		P.global_position = Vector3(0, 0, 10)
		P.rotation.y = 0.0
		await get_tree().create_timer(0.3).timeout
		I.on_e()
		if Th.carrying != "" or Th._stool.global_position.distance_to(Vector3(0, 0, 10 - 0.95)) > 0.3:
			bad.append("the stool wasn't set down ahead of you (%s, room %s)" % [Th._stool.global_position, Th._spot_ok])
		Th.aim = "cooler"
		Th.on_e()
		Th.aim = "lock"
		Th.on_e()
		Th.aim = "flush"
		Th.on_e()
		await get_tree().create_timer(1.0).timeout
		if absf(Th._cooler.rotation.y - 1.75) > 0.1 or not Th.locked or Th.flush_t <= 0.0:
			bad.append("the cooler, the deadbolt or the flush didn't take")
		Th.aim = "lock"
		Th.on_e()
		Clock.h = 12.0
		Clock.warp = 0.0
		Th.aim = "bed"
		Th.on_e()
		await get_tree().create_timer(8.5).timeout
		if absf(Clock.h - 15.0) > 0.2 or Th._wake >= 0.0:
			bad.append("three hours on the cardboard came to %s" % Clock.fmt_clock(Clock.h))
	P.global_position = Vector3(0, 0, 10)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_C
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.8).timeout
	if not P.crouched or $Player/Camera.position.y > 1.1:
		bad.append("C didn't crouch you (camera at %.2f)" % $Player/Camera.position.y)
	ev = InputEventKey.new()
	ev.physical_keycode = KEY_C
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.8).timeout
	if P.crouched or $Player/Camera.position.y < 1.55:
		bad.append("letting go of C didn't stand you up")
	P.sit(I.seats[1])
	P.seat_fov = 40.0
	await get_tree().create_timer(0.8).timeout
	var zoomed: float = $Player/Camera.fov
	P.stand(Vector3(0, 0, 10), 0.0)
	await get_tree().create_timer(0.8).timeout
	if zoomed > 45.0 or $Player/Camera.fov < 68.0:
		bad.append("the seat's zoom: %.0f sat down, %.0f stood up" % [zoomed, $Player/Camera.fov])
	$Weather.set_now("rain")
	await get_tree().create_timer(0.5).timeout
	if not $Weather._rain[0].visible or $Sky.wx_k < 0.5 or $Weather._ground.size() < 3:
		bad.append("rain: not falling, or the ground's not found (%d of its materials)" % $Weather._ground.size())
	$Weather.set_now("clear")
	var someone: Node3D = $People.spawn(0)
	if someone == null:
		bad.append("the cast isn't there (people/people.glb not imported?)")
	else:
		for n in 30:
			someone.tick(0.033, 1.3)
		var hip: Node3D = someone._legs[0][0]
		var head: Node3D = someone._head
		if hip == null or head == null or absf(hip.rotation.x) < 0.01 or absf(head.position.y - 1.63 * someone.height) > 0.2:
			bad.append("a person isn't walking right (hip %.2f, head at %.2f)" % [hip.rotation.x, head.position.y])
		someone.queue_free()
	var S := $Shoppers
	if S._spots.size() < 20:
		bad.append("only %d stretches of shelf for customers to browse" % S._spots.size())
	else:
		var way: Array = S._nav.path(S._door.x, S._door.y, S._spots[0].x, S._spots[0].z)
		var far: Array = S._nav.path(S._door.x, S._door.y, S._counter.x, S._counter.z)
		if way.size() < 2 or far.size() < 2:
			bad.append("no way from the door to a shelf (%d) or the counter (%d)" % [way.size(), far.size()])
		var cu: Dictionary = S.spawn()  # a visit, hurried along: in the door, to a shelf, a tape, the counter, rung up, out
		cu.c.position = Vector3(S._door.x, 0, S._door.y)
		cu.path = []
		cu.state = "boot"
		cu.t = 0.0
		cu.who.speed = 9.0
		cu.who.dwell = 0.05
		cu.who.stops = 1
		cu.stops_left = 1
		cu.who.picky = 5.0
		cu.who.cats = [S._spots[0].copies[0].c]
		var t0 := Time.get_ticks_msec()
		while cu.state != "wait" and S.custs.has(cu) and Time.get_ticks_msec() - t0 < 25000:
			await get_tree().process_frame
		if cu.state != "wait" or cu.holding < 1:
			bad.append("a customer didn't get to the counter with a tape (%s, holding %d)" % [cu.state, cu.holding])
		else:
			var took: Dictionary = cu.tapes[0]
			S.aim = cu
			S.on_e()
			t0 = Time.get_ticks_msec()
			while S.custs.has(cu) and Time.get_ticks_msec() - t0 < 25000:
				await get_tree().process_frame
			if S.custs.has(cu) or not took.off or S.rented.is_empty():
				bad.append("a rung-up customer didn't leave with their tape")
			Clock.day += 1
			await get_tree().process_frame
			await get_tree().process_frame
			if took.off:
				bad.append("yesterday's rental didn't come back in the morning")
			Clock.day -= 1
	var Li := $Lights
	Li.flip_switch("front")
	if Li.zone_on.front or Li.zone_lvl.front > 0.0:
		bad.append("the front lights didn't go off")
	Li.flip_switch("front")
	await get_tree().create_timer(2.0).timeout
	if Li.zone_lvl.front < 1.0:
		bad.append("the front lights didn't come back on")
	var T := $Tapes
	var tape: Dictionary = T.tapes[0]
	var second: Dictionary = T.tapes[1]
	for t2: Dictionary in T.tapes:
		if t2 != tape and T._corners(t2).size() >= 20:
			second = t2
			break
	var n: int = T._corners(tape).size()
	if n < 20:
		bad.append("the first tape has %d corners in the shelves (22: a cover and a case)" % n)
	T.pickup(tape)
	if T.held != tape or not tape.off or tape.mesh.get_surface_count() < 2:
		bad.append("a tape didn't come off the shelf whole")
	T.pickup(second)
	if T.inv.size() != 2 or T.held != second:
		bad.append("a second tape didn't join the first in the inventory")
	T.inv_select(0)
	if T.held != tape:
		bad.append("1 didn't bring the first tape back to hand")
	T.put_back()
	if T.held != second or tape.off or T.inv.size() != 1:
		bad.append("shelving the one in hand didn't bring the other out")
	T.put_back()
	if T.held != null or second.off or not T.inv.is_empty():
		bad.append("a tape didn't go back")
	$Lights.flip_plate("front")
	if $Lights.zone_on.front or $Lights.zone_on.lounge or $Lights.zone_on.hall:
		bad.append("the whole plate didn't go off together")
	$Lights.flip_plate("front")
	Clock.h = 22.0
	await get_tree().create_timer(9.0).timeout
	if $Lights._night.is_empty() or $Lights._night[0].light.light_energy <= 0.0:
		bad.append("the lot's lamps didn't come on after dark (%d of them)" % $Lights._night.size())
	print("check: %s" % ("ok" if bad.is_empty() else "; ".join(bad)))
	get_tree().quit(0 if bad.is_empty() else 1)
