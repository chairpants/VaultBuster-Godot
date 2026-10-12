extends Node3D
## The level (world/world.scn) made solid: everything you can see gets a collision shape of its own triangles. Not the
## doors you walk through (push doors, the storefront's: see interact.gd), and not things too small to bump into.

func _enter_tree() -> void:  # the store's sound (ambience.gd), there before anything that makes a noise
	var amb: Node = preload("res://ambience.gd").new()
	amb.name = "Ambience"
	add_child(amb)
	var chores: Node = preload("res://chores.gd").new()  # (and the cleaning up: chores.gd)
	chores.name = "Chores"
	add_child(chores)
	var shift: Node = preload("res://shift.gd").new()  # (and the day's goals and its end: shift.gd)
	shift.name = "Shift"
	add_child(shift)
	var phone: Node = preload("res://phone.gd").new()  # (and the phone and the holds: phone.gd)
	phone.name = "Phone"
	add_child(phone)
	var snacks: Node = preload("res://snacks.gd").new()  # (and the candy racks and the cooler: snacks.gd)
	snacks.name = "Snacks"
	add_child(snacks)
	var customer: Node = preload("res://customer.gd").new()  # (and the other side of the counter: customer.gd)
	customer.name = "Customer"
	add_child(customer)
	var menu: Node = preload("res://menu.gd").new()  # (and the main menu, which is also the pause screen: menu.gd)
	menu.name = "Menu"
	add_child(menu)
	var pos: Node = preload("res://pos.gd").new()  # (and the register's terminal: pos.gd. Last, so it has the keyboard first)
	pos.name = "POS"
	add_child(pos)


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
	var t0 := Time.get_ticks_msec()
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
		cu.returning = []
		cu.snack_done = true
		cu.thief = false
		S._next_stop(cu)  # (straight to a shelf: nothing to drop off, nothing to ask at the counter)
		t0 = Time.get_ticks_msec()
		while cu.state != "wait" and S.custs.has(cu) and Time.get_ticks_msec() - t0 < 25000:
			await get_tree().process_frame
		if cu.state != "wait" or cu.holding < 1:
			bad.append("a customer didn't get to the counter with a tape (%s, holding %d)" % [cu.state, cu.holding])
		else:
			var took: Dictionary = cu.tapes[0]
			var C := $Checkout
			$Staff._ring_t = -999.0  # (by hand, this one: Dana holds off)
			S.aim = cu
			S.on_e()
			if C.co == null or C.step()[0] != "tap":
				bad.append("E on the customer didn't start the sale (their card in hand)")
			for where in ["register", "customer", "customer", "pad", "customer", "register"]:
				C.act(where)
			await get_tree().create_timer(2.6).timeout
			for where in ["printer", "customer", "customer", "customer"]:
				C.act(where)
			if C.co != null or not cu.paid or cu.get("tagged", true) or C.served != 1 or C.take < 1.9:
				bad.append("the checkout didn't run through (step %s, paid %s, served %d)" % [C.step(), cu.paid, C.served])
			t0 = Time.get_ticks_msec()
			while S.custs.has(cu) and Time.get_ticks_msec() - t0 < 25000:
				await get_tree().process_frame
			if S.custs.has(cu) or not took.off or S.member_of(took) != cu.member:
				bad.append("a rung-up customer didn't leave with their tape")
			var c2: Dictionary = S.spawn()  # ...and one for Dana
			c2.c.position = Vector3(S._counter.x, 0, S._counter.z)
			c2.path = []
			c2.tapes = [S._spots[1].copies.filter(func(t: Dictionary) -> bool: return not t.off and not $Tapes._corners(t).is_empty())[0]]
			$Tapes.set_on_shelf(c2.tapes[0], false)
			c2.holding = 1
			S.line.append(c2)
			c2.state = "counter"
			$Staff._ring_t = 0.0
			t0 = Time.get_ticks_msec()
			while not c2.paid and S.custs.has(c2) and Time.get_ticks_msec() - t0 < 40000:
				await get_tree().process_frame
			if $Staff.dana == null or not c2.paid or C.served < 2:
				bad.append("Dana didn't ring the next one up (she's %s, served %d)" % ["there" if $Staff.dana else "not there", C.served])
			Clock.day += 6  # past due: somebody brings it back, through the slot, into the bin
			var back := false
			for n in 40:
				var r: Dictionary = S.spawn(S.member_of(took))
				if r.returning.has(took):
					back = true
					r.c.position = Vector3(S._door.x, 0, S._door.y)
					r.path = []
					r.state = "boot"
					r.t = 0.0
					r.who.speed = 9.0
					t0 = Time.get_ticks_msec()
					while not $Tapes.return_bin.has(took) and Time.get_ticks_msec() - t0 < 25000:
						await get_tree().process_frame
					break
				S._gone(r)
			Clock.day -= 6
			if back and cu.member.owed <= 0.0:
				bad.append("a tape back late didn't put a fee on their account")
			cu.member.owed = 0.0
			if not back or not $Tapes.return_bin.has(took):
				bad.append("a rental past due didn't come back through the Returns slot (found one bringing it: %s; out: %d; states: %s)" % [back, S.rented.size(), S.custs.map(func(k: Dictionary) -> String: return "%s/%d/%.1f,%.1f" % [k.state, k.returning.size(), k.c.position.x, k.c.position.z])])
			else:
				$Staff.state = "post"  # (Dana: not this one)
				$Staff._path = []
				$Tapes.aim_returns = true
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				$Tapes._unhandled_input(click)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if $Tapes.held == null or $Tapes.return_bin.has($Tapes.held):
					bad.append("a click on Returns didn't take a tape out of the bin")
				else:
					$Tapes.put_back()
					if took.off and $Tapes.held == null and not $Tapes.return_bin.has(took) and $Tapes.inv.is_empty():
						bad.append("the returned tape didn't go back on the shelf")
	# a store saved and picked up again: the state turned over, then put back from the snapshot
	var Tp := $Tapes
	var out_tape: Dictionary = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not Tp._corners(t).is_empty())[0]
	Tp.pickup(out_tape)
	Tp.inspecting = false
	$Shoppers.rented.append([Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not Tp._corners(t).is_empty())[0], Clock.day, Clock.day + 2])
	Tp.set_on_shelf($Shoppers.rented[-1][0], false)
	$Lights.set_zone("lounge", false)
	$Fixtures.flap_open = true
	var snap: Dictionary = JSON.parse_string(JSON.stringify($Save.snapshot()))  # (through text, as the file would be)
	var was_h := Clock.h
	Tp.put_back()
	Tp.set_on_shelf($Shoppers.rented[-1][0], true)
	var lent: Dictionary = $Shoppers.rented.pop_back()[0]
	$Lights.set_zone("lounge", true)
	$Fixtures.flap_open = false
	Clock.h = 11.0
	$Save.apply(snap)
	if Tp.held != out_tape or not out_tape.off or not lent.off or $Shoppers.rented.is_empty() or $Lights.zone_on.lounge or not $Fixtures.flap_open or absf(Clock.h - was_h) > 0.01:
		bad.append("a saved store didn't come back as it was (held %s, rental out %s, lounge lights %s, pass-through %s)" % [Tp.held == out_tape, lent.off, $Lights.zone_on.lounge, $Fixtures.flap_open])
	Tp.put_back()
	Tp.set_on_shelf(lent, true)
	$Shoppers.rented.clear()
	$Lights.set_zone("lounge", true)
	$Fixtures.flap_open = false
	S._arrive = 99999.0  # (nobody new in from here on, and no calls: what walk-ins do would muddy what's being checked)
	$Phone.next = 99999.0
	# the rewinder, and Dana's round of the shelves
	var wound: Dictionary = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not Tp._corners(t).is_empty())[0]
	Tp.pickup(wound)
	Tp.set_wind_frac(wound, 0.2)
	if Tp.is_rewound(wound) or absf(Tp.wind_frac(wound) - 0.2) > 0.01:
		bad.append("winding a tape on didn't take")
	Tp.rewinder_use()
	await get_tree().create_timer(2.6).timeout
	if Tp.held != null or not Tp.rewinder.done or not Tp.is_rewound(wound):
		bad.append("the rewinder didn't rewind it (%.2f)" % Tp.wind_frac(wound))
	Tp.rewinder_use()
	if Tp.held != wound:
		bad.append("the rewound tape didn't come back out")
	Tp.drop_in_returns()
	var St := $Staff
	t0 = Time.get_ticks_msec()
	while (wound.off or St.state != "post") and Time.get_ticks_msec() - t0 < 150000:
		await get_tree().process_frame
	print("check: Dana's round took %d s" % ((Time.get_ticks_msec() - t0) / 1000))
	if wound.off or not St.carry.is_empty() or St.dana.position.distance_to(Vector3(St._post.x, 0, St._post.z)) > 0.3:
		bad.append("Dana didn't put the return away and come home (she's %s, carrying %d, at %s)" % [St.state, St.carry.size(), St.dana.position])
	# a shoplifter: under the jacket, out through the gates, gone with it; the register shuts the alarm off
	var loot: Dictionary = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not Tp._corners(t).is_empty())[0]
	for stopped: bool in [false, true]:
		var th: Dictionary = S.spawn()
		th.c.position = Vector3(0, 0, 6.0)
		th.who.speed = 9.0
		Tp.set_on_shelf(loot, false)
		th.tapes = [loot]
		th.holding = 1
		S._sneak(th)
		if stopped:  # ...and another, stopped at the door
			S.aim = th
			S.on_e()
			if th.sneaking or not Tp.return_bin.has(loot) or th.state != "caught":
				bad.append("E on a shoplifter didn't stop them (%s)" % th.state)
			Tp.return_bin.erase(loot)
		else:
			var rang := false
			t0 = Time.get_ticks_msec()
			while S.custs.has(th) and Time.get_ticks_msec() - t0 < 45000:
				rang = rang or S.alarm_on  # (Dana shuts it off after a few seconds)
				await get_tree().process_frame
			S.start_alarm()
			if not rang or not loot.get("lost", false) or not loot.off:
				bad.append("a shoplifter didn't set the gates off and get away with it (alarm %s, %s)" % [S.alarm_on, th.state])
			$Checkout.aim = "register"
			$Checkout.on_e()
			var logged_in: bool = $POS.open
			$POS.type("A")
			$POS.type("Y")
			$POS.log_off()
			if S.alarm_on or not logged_in:
				bad.append("E on the register didn't shut the gate alarm off")
			S.silence_alarm()
			loot.lost = false
		Tp.set_on_shelf(loot, true)
	# chores: a mess wants its tool; a bin's bag goes down the chute. (Nobody new in meanwhile: what walk-ins drop and
	# buy would muddy the count)
	S._arrive = 99999.0
	var Ch := $Chores
	Ch.mess_add("wrapper", 0.0, 8.0)
	var wrapper: Dictionary = Ch.messes[-1]
	Ch.mess_add("spill", 0.5, 8.0)
	var soda: Dictionary = Ch.messes[-1]
	Ch.aim = { "mess": soda }
	Ch.on_e()
	if not Ch.messes.has(soda):
		bad.append("a spilled soda came up without the mop")
	Ch.aim = { "mess": wrapper }
	Ch.on_e()
	if Ch.tools.mop.nodes.is_empty() or Ch.tools.sweeper.nodes.is_empty():
		bad.append("the mop (%d) or the sweeper (%d) isn't in the janitor's closet" % [Ch.tools.mop.nodes.size(), Ch.tools.sweeper.nodes.size()])
	else:
		Ch.tool_take("mop")
		Ch.aim = { "mess": soda }
		Ch.on_e()
		await get_tree().create_timer(2.8).timeout
		Ch.tool_return()
		if Ch.messes.has(wrapper) or Ch.messes.has(soda) or Ch.tools.mop.nodes.any(func(n: Node3D) -> bool: return not n.visible):
			bad.append("the wrapper and the soda didn't both get cleaned up")
	Ch.bins[0].n = 3
	Ch.aim = { "bin": Ch.bins[0] }
	Ch.on_e()
	var bagged: int = Ch.bag_carry.size()
	Ch.aim = { "chute": true }
	Ch.on_e()
	if Ch.bins[0].n != 0 or bagged != 1 or not Ch.bag_carry.is_empty():
		bad.append("a bin's bag didn't go down the chute")
	# a tape shoved in anywhere: pulled out, it's in your hand to put back where it goes
	var crooked: Dictionary = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not Tp._corners(t).is_empty())[3]
	Tp.set_on_shelf(crooked, false)
	Ch.misshelve(crooked, S._spots[2])
	Ch.aim = { "stray": Ch.strays[-1] }
	Ch.on_e()
	if Tp.held != crooked or Ch.strays.any(func(s: Dictionary) -> bool: return s.copy == crooked):
		bad.append("a misshelved tape didn't come out into your hand")
	Tp.put_back()
	if crooked.off:
		bad.append("the misshelved tape didn't go back in its slot")
	# Dana tidies up when there's nothing else to do
	Ch.mess_add("cup", -1.0, 8.0)
	var cup: Dictionary = Ch.messes[-1]
	t0 = Time.get_ticks_msec()
	while Ch.messes.has(cup) and Time.get_ticks_msec() - t0 < 150000:
		await get_tree().process_frame
	if Ch.messes.has(cup):
		bad.append("Dana didn't clean up a cup left on the floor (she's %s)" % St.state)
	# her shift over, she goes home; the next one, she's back
	St._on_always = false  # (the check's clock is at an hour she doesn't work)
	t0 = Time.get_ticks_msec()
	while St.dana != null and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	if St.dana != null:
		bad.append("Dana didn't go home off shift (she's %s, on duty %s)" % [St.state, St.on_duty()])
	St._on_always = true
	t0 = Time.get_ticks_msec()
	while (St.dana == null or St.state != "post" or not St._path.is_empty()) and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	if St.dana == null or St.dana.position.distance_to(Vector3(St._post.x, 0, St._post.z)) > 0.3:
		bad.append("Dana didn't come in for her shift and get to her post")
	# snacks: one off the rack with a customer, rung up by itself; the spot restocked from the cupboard
	var Sn := $Snacks
	if Sn.units.size() < 100 or Sn.spots.is_empty() or Sn.units.any(func(u: Dictionary) -> bool: return u.node == null):
		bad.append("the snacks aren't all found in the level (%d of %d; %d places to stand)" % [Sn.units.filter(func(u: Dictionary) -> bool: return u.node != null).size(), Sn.units.size(), Sn.spots.size()])
	else:
		$Staff._ring_t = -999.0  # (by hand, this one)
		for k: Dictionary in S.custs.duplicate():  # (and the floor to ourselves: nobody ahead in the line)
			if not k.paid:
				for t: Dictionary in k.tapes:
					Tp.set_on_shelf(t, true)
				k.tapes = []
			k.tagged = false
			S._gone(k)
		var sc: Dictionary = S.spawn()
		sc.c.position = Vector3(Sn.spots[0].x, 0, Sn.spots[0].z)
		sc.path = []
		sc.spot = Sn.spots[0]
		sc.state = "snack"
		sc.snack_done = true
		sc.returning = []
		sc.thief = false
		sc.who.speed = 9.0
		t0 = Time.get_ticks_msec()
		while sc.state != "wait" and S.custs.has(sc) and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
		if sc.state != "wait" or sc.snacks.size() != 1 or not sc.snacks[0].out or sc.snacks[0].node.visible:
			bad.append("a customer didn't bring a snack to the counter (%s, %d)" % [sc.state, sc.snacks.size()])
		else:
			var bar: Dictionary = sc.snacks[0]
			S.aim = sc
			S.on_e()
			$Checkout.act("register")
			await get_tree().create_timer(2.6).timeout
			for where in ["printer", "customer", "customer", "customer"]:
				$Checkout.act(where)
			if not sc.paid or $Shift.stats.snack_take < 0.9:
				bad.append("a snack didn't ring up by itself (step %s, $%.2f)" % [$Checkout.step(), $Shift.stats.snack_take])
			var empty0: int = Sn.units.filter(func(u: Dictionary) -> bool: return u.out).size()  # (a walk-in may have had one too)
			Sn.aim = { "cupboard": "drinks" if bar.k != "" else "food" }
			Sn.on_e()
			var carried: int = Sn.carry.size()
			Sn.aim = { "spot": bar }
			Sn.on_e()
			if carried < 1 or Sn.carry.size() != carried - 1 or Sn.units.filter(func(u: Dictionary) -> bool: return u.out).size() != empty0 - 1 or Sn.backstock[bar.n] != 11:
				bad.append("the empty spot didn't get restocked from the cupboard (carried %d, %d of %d still empty)" % [carried, Sn.units.filter(func(u: Dictionary) -> bool: return u.out).size(), empty0])
			Sn.aim = { "cupboard": "drinks" if bar.k != "" else "food" }  # (and whatever else was grabbed goes out too)
			for u: Dictionary in Sn.carry.duplicate():
				Sn.aim = { "spot": u }
				Sn.on_e()
		$Staff._ring_t = 0.0
	# a parent and their kid: in together, out together
	var mum: Dictionary = S.spawn()
	var kid: Dictionary = S.spawn(mum.member, mum)
	S._beside(kid, mum)
	for k: Dictionary in [mum, kid]:
		k.who.speed = 9.0
		k.who.dwell = 0.05
		k.stops_left = 1
		k.thief = false
		k.returning = []
		k.snack_done = true
	if not kid.kid or kid.c.scale.y > 0.8 or mum.party != kid.party or mum.party.size() != 2:
		bad.append("a kid didn't come in with their parent")
	t0 = Time.get_ticks_msec()
	var tagged := false
	while (S.custs.has(mum) or S.custs.has(kid)) and Time.get_ticks_msec() - t0 < 120000:
		tagged = tagged or kid.state == "tagAlong" or mum.state == "tagAlong"  # (whoever's done first waits on the other)
		await get_tree().process_frame
	if S.custs.has(mum) or S.custs.has(kid) or not tagged:
		bad.append("a parent and kid didn't see their visit through together (parent %s, kid %s, tagged along %s)" % [mum.state, kid.state, tagged])
	# the phone: a call answered right; a hold promised, set aside, and handed over when they come in for it
	var Ph := $Phone
	var caller: Dictionary = S.members.all[5]
	Ph.ring = { "kind": "hours", "member": caller, "film": [], "prank": "", "t": 0.0, "rang": 99.0 }
	Ph.answer()
	var pts0: int = $Checkout.score
	Ph.call_answer(1)
	if Ph.on_line != null or $Checkout.score != pts0 + 5:
		bad.append("answering the phone right didn't count")
	Ph.on_line = { "member": caller, "title": loot.t, "cat": loot.c, "t": 30.0 }
	var held_for = Ph.call_answer(1)
	Tp.pickup(loot)
	Ph.aim = "holds"
	Ph.on_e()
	if held_for == null or held_for.copy != loot or Tp.held != null:
		bad.append("a tape didn't go on the holds shelf for the caller")
	else:
		held_for.coming = true
		var pk: Dictionary = S.spawn(caller)
		pk.pickup = held_for
		pk.returning = []
		pk.c.position = Vector3(S._door.x, 0, S._door.y)
		pk.path = []
		pk.state = "boot"
		pk.t = 0.0
		pk.who.speed = 9.0
		t0 = Time.get_ticks_msec()
		while pk.state != "asking" and S.custs.has(pk) and Time.get_ticks_msec() - t0 < 25000:
			await get_tree().process_frame
		Ph.aim = "holds"
		Ph.on_e()
		S.aim = pk
		S.on_e()
		if pk.state == "asking" or not pk.tapes.has(loot) or Ph.holds.has(held_for) or not S.line.has(pk):
			bad.append("the caller didn't get their hold at the counter (%s, %d holds)" % [pk.state, Ph.holds.size()])
		S._gone(pk)
	Tp.set_on_shelf(loot, true)
	# the menu's up: the store stops; and goes again
	var Mn := $Menu
	Mn.open()
	var stopped: bool = get_tree().paused and Mn.visible
	Mn.resume()
	if not stopped or get_tree().paused or Mn.visible or Mn.info(3) != "" and not "day" in Mn.info(3):
		bad.append("the menu didn't stop the store and let it go again")
	# the register's terminal: a title looked up; supplies and a replacement tape ordered, here in the morning
	var Po := $POS
	Po.log_in()
	Po.type("find " + loot.t.left(5))
	var found: String = Po._screen.title
	Po.type("1")
	await get_tree().process_frame
	await get_tree().process_frame
	if not found.begins_with("TITLE SEARCH") or not Po._screen.title.begins_with("TITLE INQUIRY") or not "STOCK....:" in Po._text.text:
		bad.append("the terminal didn't look a title up (%s / %s)" % [found, Po._screen.title])
	Po.log_off()
	Po.log_in()
	var budget0: float = $Shift.budget
	var stock0: Dictionary = Sn.backstock.duplicate()
	Po.type("O")
	Po.type("1")
	Po.type("2")
	loot.lost = true
	Tp.set_on_shelf(loot, false)
	Po.type("B")
	Po.type("1")
	Po.type("Y")
	Po.log_off()
	var ordered: Array = Sn.orders.keys()
	if ordered.size() != 1 or Sn.orders[ordered[0]] != 24 or loot.lost or not Po.replacements.has(loot) or $Shift.budget > budget0 - 30.0:
		bad.append("ordering on the terminal didn't take (%s, replacements %d, $%.2f spent)" % [Sn.orders, Po.replacements.size(), budget0 - $Shift.budget])
	else:
		Po.deliver()
		if Sn.backstock[ordered[0]] != stock0[ordered[0]] + 24 or not Tp.return_bin.has(loot):
			bad.append("the morning's delivery didn't come")
	Tp.return_bin.erase(loot)
	loot.lost = false
	Tp.set_on_shelf(loot, true)
	# an upgrade bought on the terminal; a section the store doesn't carry comes off the shelves, and back with its upgrade
	Po.log_in()
	budget0 = $Shift.budget
	Po.type("upgrades")
	Po.type(str($Shift.UPGRADES.map(func(u: Array) -> String: return u[0]).find("sign") + 1))
	Po.type("Y")
	Po.log_off()
	if not $Shift.owned("sign") or absf(budget0 - 60.0 - $Shift.budget) > 0.01:
		bad.append("an upgrade didn't buy on the terminal ($%.2f spent)" % (budget0 - $Shift.budget))
	var on0: int = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off).size()
	$Shift.upg.library = 2
	$Shift.stock_library()
	var on1: int = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off).size()
	var why: String = $Shift.buy("lib3")
	if on1 >= on0 or why != "" or Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off).size() != on0:
		bad.append("the library's last tier didn't come off the shelves and back (%d, %d, %s)" % [on0, on1, why])
	# the theater: bought, its door's unchained and somebody finds a seat; a feature set on the terminal sells a ticket
	var chained: Array = $Interact.doors.filter(func(d: Dictionary) -> bool: return d.push and d.locked)
	$Shift.upg.theater = true
	$Shift.open_theater()
	var goer: Dictionary = S.spawn()
	goer.c.position = Vector3(S._door.x, 0, S._door.y)
	goer.path = []
	goer.who.speed = 9.0
	goer.thief = false
	goer.returning = []
	if chained.size() != 1 or chained[0].locked or not S._pick_theater_seat(goer):
		bad.append("the theater didn't open (%d chained doors)" % chained.size())
	else:
		t0 = Time.get_ticks_msec()
		while goer.state != "thWatch" and S.custs.has(goer) and Time.get_ticks_msec() - t0 < 40000:
			await get_tree().process_frame
		if goer.state != "thWatch" or goer.c.position.distance_to(Vector3(goer.th_seat.x, goer.th_seat.y, goer.th_seat.z)) > 0.1:
			bad.append("nobody got to a seat in the theater (%s at %s)" % [goer.state, goer.c.position])
		goer.t = 0.0
		t0 = Time.get_ticks_msec()
		while S.custs.has(goer) and goer.state in ["thWatch", "thRowOut"] and Time.get_ticks_msec() - t0 < 40000:
			await get_tree().process_frame
		if S.custs.has(goer) and goer.state in ["thWatch", "thRowOut"]:
			bad.append("the moviegoer didn't find their way back out (%s at %s)" % [goer.state, goer.c.position])
	var noon_was := Clock.h
	Clock.h = 12.0
	Po.log_in()
	Po.type("T")
	Po.type("1")
	Po.log_off()
	if $Shift.show.title == "" or $Shift.show.day != Clock.day or $Shift.ticket_chance() <= 0.0:
		bad.append("the terminal didn't set tonight's feature")
	Clock.h = noon_was
	$Shift.show.title = ""
	# walking at a curb steps you up onto it; and Tony is behind his counter, alive
	$Player.global_position = Vector3(6.0, 0.3, -3.2)
	$Player.rotation.y = PI
	await get_tree().create_timer(0.6).timeout
	var low: float = $Player.global_position.y
	var walk := InputEventKey.new()
	walk.physical_keycode = KEY_W
	walk.pressed = true
	Input.parse_input_event(walk)
	await get_tree().create_timer(1.2).timeout
	walk = InputEventKey.new()
	walk.physical_keycode = KEY_W
	walk.pressed = false
	Input.parse_input_event(walk)
	await get_tree().create_timer(0.2).timeout
	if $Player.global_position.y < low + 0.06 or $Player.global_position.z < -1.7:
		bad.append("walking at the curb didn't step up onto it (from %.2f to %s)" % [low, $Player.global_position])
	if $People.tony == null or $People.tony.position.distance_to(Vector3(16.2, 0, 8.3)) > 0.1:
		bad.append("Tony isn't behind his counter")
	# somebody new signs up at the counter: their form, into the computer, their card
	for k: Dictionary in S.custs.duplicate():  # (the counter to ourselves)
		if not k.paid:
			for t: Dictionary in k.tapes:
				Tp.set_on_shelf(t, true)
			k.tapes = []
		k.tagged = false
		S._gone(k)
	$Checkout.co = null
	var newbie: Dictionary = S.members.all[9]
	newbie.active = false
	$Staff._ring_t = -999.0
	var pr: Dictionary = S.spawn(newbie)
	pr.prospect = true
	pr.returning = []
	pr.c.position = Vector3(S._counter.x, 0, S._counter.z)
	pr.path = []
	S.line.append(pr)
	pr.state = "counter"
	await get_tree().create_timer(0.3).timeout
	S.aim = pr
	S.on_e()
	$Checkout.act("register")
	$Checkout.act("customer")
	if not newbie.active or pr.state != "signedUp" or $Shift.stats.signups != 1 or $Checkout.co != null:
		bad.append("signing somebody up didn't go through (%s, active %s)" % [pr.state, newbie.active])
	$Staff._ring_t = 0.0
	S._gone(pr)
	# the other side of the counter: pay the clerk for a tape, bring it back; get caught behind the counter
	var Cu := $Customer
	$Shift.mode = "customer"
	Tp.pickup(loot)
	var owe: float = Cu.total()
	Cu.pay()
	if owe < 1.9 or not Cu.rented.has(loot.k) or absf(Cu.wallet - (40.0 - owe)) > 0.01 or not loot.get("desens", false):
		bad.append("paying the clerk for a tape didn't take ($%.2f, wallet $%.2f)" % [owe, Cu.wallet])
	Tp.drop_in_returns()
	Cu._check_t = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if Cu.rented.has(loot.k) or Cu.day.returned != 1:
		bad.append("a rental dropped in Returns didn't count as back")
	Cu.caught("staff")
	if Cu.today != 1 or $Player.global_position.distance_to(Cu.FLOOR) > 1.0 or Cu.banned == Clock.day:
		bad.append("being caught in back the first time wasn't a warning and a walk to the floor")
	Cu.caught("staff")
	if Cu.banned != Clock.day:
		bad.append("being caught again didn't get you thrown out")
	if not "YOUR DAY" in "\n".join(Cu.slip()):
		bad.append("a customer's day didn't make a slip")
	Cu.banned = 0
	$Shift.mode = "sandbox"
	$HUD.call_box("")
	$Things._block.get_child(0).disabled = not $Things.locked
	Tp.return_bin.erase(loot)
	Tp.set_on_shelf(loot, true)
	# skills, and a second pair of hands: XP levels a stat; an applicant hired on the terminal is on the roster with a week of their own
	St.xp("you", "dex", 200.0)
	if St.lv("you", "dex") < 2 or not "DEX" in St._sheet_text():
		bad.append("doing the work didn't level a skill")
	Po.log_in()
	budget0 = $Shift.budget
	Po.type("upgrades")
	Po.type(str($Shift.UPGRADES.map(func(u: Array) -> String: return u[0]).find("hire") + 1))
	Po.type("2")
	Po.type("W")
	Po.type("2 MON 12-17")
	Po.log_off()
	if St.roster.size() != 2 or St.crew.size() != 2 or absf(budget0 - 250.0 - $Shift.budget) > 0.01 or St.hours(St.roster[1], 1) != 5 or St.crew[1].first != St.roster[1].first:
		bad.append("hiring on the terminal didn't put somebody on the roster (%d on it, %d nodes, $%.2f spent)" % [St.roster.size(), St.crew.size(), budget0 - $Shift.budget])
	# the end of the day: the slip, then the next morning with the doors locked
	var Sh := $Shift
	var was_day := Clock.day
	var was_hour := Clock.h
	var was_at: Vector3 = $Player.global_position
	Sh.stats.visitors = 4
	Sh.clock_out()
	if not Sh.report or not "SHIFT GRADE" in Sh._slip.text or not "DAY GOALS" in Sh._slip.text:
		bad.append("clocking out didn't print the shift's slip")
	Sh.next_shift()
	await get_tree().process_frame
	if Sh.report or Clock.day != was_day + 1 or absf(Clock.h - 9.0) > 0.05 or not $Things.locked or not S.custs.is_empty() or Sh.goals.size() != 2 or $Checkout.served != 0:
		bad.append("the next morning didn't start right (day %d, %.2f, locked %s, %d in)" % [Clock.day, Clock.h, $Things.locked, S.custs.size()])
	Clock.day = was_day
	Clock.h = was_hour
	$Player.global_position = was_at
	$Things.aim = "lock"
	$Things.on_e()
	$Things.aim = ""
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
