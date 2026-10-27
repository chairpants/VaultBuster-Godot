extends Node3D
## The level (world/world.scn) made solid: everything you can see gets a collision shape of its own triangles. Not the
## doors you walk through (push doors, the storefront's: see interact.gd), and not things too small to bump into.

const SMALL := 1.0  # things no bigger than this corner to corner throw no shadow: over half the level's meshes, each drawn again for every light with shadows, for shadows too small to see

func _enter_tree() -> void:  # the store's sound (ambience.gd), there before anything that makes a noise
	# what a fresh store hasn't got out, and so the level hasn't either (world/extras.glb: the library's locked sections'
	# tapes, the second rewinder, the rewinders as sports cars). In with the level before anything looks through it:
	# tapes.gd finds the tapes by their slots and takes off the shelves what the store doesn't carry yet
	if not OS.get_cmdline_user_args().is_empty():  # (--check and --shot: a window that can't take the keyboard, so nothing typed elsewhere lands in it: an Esc and an Enter there is the menu's QUIT)
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
		get_tree().auto_accept_quit = false  # (...and one that isn't shut by being asked to: it says so, and carries on)
		if "--check" in OS.get_cmdline_user_args() and not "--show" in OS.get_cmdline_user_args():
			get_window().mode = Window.MODE_MINIMIZED  # (--check runs out of the way, on the taskbar: --show to watch it)
	if ResourceLoader.exists("res://world/extras.glb") and not "--bare" in OS.get_cmdline_user_args():
		var extras: Node = load("res://world/extras.glb").instantiate()
		extras.name = "Extras"
		$World.add_child(extras)
		_cut_extras(extras)
	for n: Node in $World.find_children("*", "Node3D", true, false):  # the cars the level was written with, stood where they were that day: out (cars.gd parks the day's own)
		if is_instance_valid(n) and n.get_child_count() >= 20 and absf(n.position.y + 0.12) < 0.005 and n.position.z < -8.0 and n.position.z > -20.0:
			n.free()
	var cooler_dz: float = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.cooler.get("moved", 0.0)
	for n: Node in $World.find_children("*", "Node3D", true, false):  # the drinks cooler, moved along the wall clear of the counter gate's swing (data/interact.json has it there: cooler.moved)
		if not n is MeshInstance3D and n.get_child_count() > 100 and Vector2(n.position.x + 7.26, n.position.z - 5.25).length() < 0.02:  # (its own position: nothing's in the tree yet to have a global one)
			n.position.z += cooler_dz
	var cars: Node = preload("res://cars.gd").new()  # (the lot's cars and the road's: cars.gd)
	cars.name = "Cars"
	add_child(cars)
	var decor: Node = preload("res://decor.gd").new()  # (balloons, and the season's decorations: decor.gd)
	decor.name = "Decor"
	add_child(decor)
	var golf: Node = preload("res://golf.gd").new()  # (golf off the roof: golf.gd)
	golf.name = "Golf"
	add_child(golf)
	var pad: Node = preload("res://pad.gd").new()  # (a gamepad, as the keyboard and mouse: pad.gd)
	pad.name = "Pad"
	add_child(pad)
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
	var trail: Node = preload("res://trail.gd").new()  # (and what a customer can find: trail.gd)
	trail.name = "Trail"
	add_child(trail)
	var menu: Node = preload("res://menu.gd").new()  # (and the main menu, which is also the pause screen: menu.gd)
	menu.name = "Menu"
	add_child(menu)
	var pos: Node = preload("res://pos.gd").new()  # (and the register's terminal: pos.gd. Last, so it has the keyboard first)
	pos.name = "POS"
	add_child(pos)
	var arcade: Node = preload("res://arcade.gd").new()  # (Tony's cabinets: arcade.gd. Late: at the machine it has the keyboard first)
	arcade.name = "Arcade"
	add_child(arcade)
	var counter: Node = preload("res://counter.gd").new()  # (and rearranging the counter: counter.gd. After the terminal: a click's its first while something's being moved)
	counter.name = "Counter"
	add_child(counter)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not OS.get_cmdline_user_args().is_empty():
		print("check: the window was asked to close (left open: the run's not done)")


func _ready() -> void:
	var solid := 0
	# the level's collision, kept from the last start (it takes a few seconds to work out): user://, by when the level and its extras were last changed
	var stamp := "%d_%d" % [FileAccess.get_modified_time("res://world/world.scn"), FileAccess.get_modified_time("res://world/extras.glb") if FileAccess.file_exists("res://world/extras.glb") else 0]
	var cache_path := "user://collision_%s.res" % stamp
	var cache: Resource = ResourceLoader.load(cache_path) if ResourceLoader.exists(cache_path) else null
	var shapes: Dictionary = cache.get_meta("shapes", {}) if cache != null else {}
	var made := 0
	for m: MeshInstance3D in $World.find_children("*", "MeshInstance3D", true, false):
		var size := m.get_aabb().size
		if size.x > 100.0 and m.global_position.y + m.get_aabb().position.y > 8.0:
			m.queue_free()  # the web game's clouds, caught mid-drift by an older export: sky.gd has the real ones
			continue
		if (m.global_transform * m.get_aabb()).size.length() < SMALL:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _walk_through(m) or m.has_meta("walk_through") or m.get_aabb().get_longest_axis_size() < 0.2:  # (walk_through: set in the level, the theater's seats, whose backs have colliders of their own)
			continue
		var key := str($World.get_path_to(m))
		if shapes.has(key):
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			col.shape = shapes[key]
			body.add_child(col)
			m.add_child(body)
		else:
			m.create_trimesh_collision()
			for b in m.get_children():
				if b is StaticBody3D and b.get_child_count() and b.get_child(0) is CollisionShape3D:
					shapes[key] = b.get_child(0).shape
			made += 1
		solid += 1
	if made > 0:  # (worked out afresh: kept for next time)
		var keep := Resource.new()
		keep.set_meta("shapes", shapes)
		ResourceSaver.save(keep, cache_path)
		for f in DirAccess.get_files_at("user://"):  # (and the ones from an older level go)
			if f.begins_with("collision_") and f != cache_path.get_file():
				DirAccess.remove_absolute("user://" + f)
	print("world: %d meshes solid, %d of them hiding what's behind them" % [solid, _occluders()])
	print("lights: ceiling panels by zone %s" % [$Lights._panels.keys().map(func(z: String) -> String: return "%s %d" % [z, $Lights._panels[z].size()])])
	var args := OS.get_cmdline_user_args()
	if "--check" in args:  # godot --path . -- --check: the clock, the sky, a door and a seat, then quits (non-zero if any's off)
		_check()
	elif args.size() and args[0].begins_with("--video="):  # godot --path . -- "--video=item|file|seconds in": plays it a few seconds, saves a frame as video.png, quits
		_video(args[0].trim_prefix("--video=").split("|"))
	elif "--shot" in args:  # godot --path . -- --shot [--at=x,y,z,yaw] [--hour=h]: shot.png from there, then quits
		_shot(args)


const EXTRAS_CUT := [Vector3(3.8, -0.1, 26.9), Vector3(5.5, 2.7, 28.0)]  # the back wall's shelf unit the hall's new way in goes through (tools/remodel.gd's DOORWAY): the locked sections' copies there too


func _cut_extras(extras: Node) -> void:  # (before anything looks through it: tapes.gd keeps the shelves' vertices by their slots. Not in the tree yet: the transforms put together by hand)
	var lo: Vector3 = EXTRAS_CUT[0]
	var hi: Vector3 = EXTRAS_CUT[1]
	for m: MeshInstance3D in extras.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != self:
			if n is Node3D:
				xf = n.transform * xf
			n = n.get_parent()
		if not (xf * m.get_aabb()).intersects(AABB(lo, hi - lo)):
			continue
		var mesh := ArrayMesh.new()
		for s in m.mesh.get_surface_count():
			var a := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var tri: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			var keep := PackedInt32Array()
			for k in range(0, tri.size() - 2, 3):
				var inside := true
				for j in 3:
					var p := xf * vs[tri[k + j]]
					inside = inside and p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z
				if not inside:
					keep.append_array([tri[k], tri[k + 1], tri[k + 2]])
			if keep.is_empty():
				continue
			a[Mesh.ARRAY_INDEX] = keep
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mesh.surface_set_material(mesh.get_surface_count() - 1, m.mesh.surface_get_material(s))
		m.mesh = mesh


func _occluders() -> int:  # what's behind a wall isn't drawn: the store's back rooms from the sales floor, the outside from them, and so on (JellyVault's).
	# Only the solid slabs: walls, floors and ceilings that are one piece (their triangles cover the whole of their box: nothing cut out of them), opaque, and don't move
	get_viewport().use_occlusion_culling = true
	var doors := {}
	for d: Dictionary in $Interact.doors:
		doors[d.pivot] = true
	var n := 0
	for m: MeshInstance3D in $World.find_children("*", "MeshInstance3D", true, false):
		if m.is_queued_for_deletion() or m.mesh == null or _walk_through(m):
			continue
		var up := m.get_parent()
		while up != $World and not doors.has(up):
			up = up.get_parent()
		if up != $World:
			continue  # (a door)
		var b := m.get_aabb()
		var dims := [b.size.x, b.size.y, b.size.z]
		dims.sort()
		if dims[0] > 0.35 or dims[1] < 1.0 or dims[1] * dims[2] < 2.0:
			continue  # (not a slab, or too small to hide much)
		var see_through := false
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is ShaderMaterial and mat.shader and ("blend_mix" in mat.shader.code or "ALPHA =" in mat.shader.code) or mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				see_through = true
		if see_through:
			continue
		var faces := m.mesh.get_faces()
		var area := 0.0
		for i in range(0, faces.size(), 3):
			area += (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length() / 2.0
		var whole: float = dims[1] * dims[2] * (1.0 if dims[0] < 0.005 else 2.0) + 2.0 * dims[0] * (dims[1] + dims[2])  # (a plane: one face; a box: all six)
		if area < whole * 0.98:
			continue  # (something cut out of it: a window, a doorway)
		var o := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		box.size = b.size.max(Vector3.ONE * 0.01)
		o.occluder = box
		o.position = b.get_center()
		m.add_child(o)
		n += 1
	return n


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
			$Player.fly = not "--feet" in args  # (--feet: stood there, your own body and all)
			$Player.global_position = Vector3(v[0], v[1], v[2])
			$Player.rotation.y = deg_to_rad(v[3])
			if v.size() > 4:
				$Player/Camera.rotation.x = deg_to_rad(v[4])
		elif a.begins_with("--tool="):  # the mop or the sweeper in your hands (--tool=mop:scrub: at work on a spill in front of you)
			await get_tree().create_timer(0.6).timeout
			$Chores.tool_take(a.trim_prefix("--tool=").get_slice(":", 0))
			if a.ends_with(":scrub"):
				var at: Vector3 = $Player.global_position - $Player.global_basis.z * 1.3
				$Chores.mess_add("spill", at.x, at.z)
				$Chores._scrub = { "m": $Chores.messes[-1], "t": 0.0, "dur": 2.4 }
		elif a.begins_with("--snack"):  # one off the rack, in your hand
			await get_tree().create_timer(0.6).timeout
			var u: Dictionary = $Snacks.units.filter(func(u: Dictionary) -> bool: return u.node != null and (u.k != "") == a.ends_with("=drink"))[0]
			$Snacks.set_out(u, true)
			$Snacks.held = { "u": u, "left": 4, "total": 4, "paid": true }
		elif a == "--overdue":  # somebody with a tape six days late (the register's message center has them to call)
			await get_tree().create_timer(0.6).timeout
			var late_t: Dictionary = $Tapes.tapes.filter(func(t: Dictionary) -> bool: return not t.off)[0]
			$Tapes.set_on_shelf(late_t, false)
			$Shoppers.rented.append([late_t, Clock.day - 11, Clock.day - 6, $Shoppers.members.all[3].num])
		elif a == "--missed":  # a call that rang out: in the message center, to be rung back
			await get_tree().create_timer(0.6).timeout
			$Phone.ring = { "member": $Shoppers.members.all[5], "title": "Alien", "cat": "Sci-Fi & Fantasy", "t": 25.0, "rang": 99.0 }
			await get_tree().create_timer(0.3).timeout
		elif a == "--quiet":  # nobody in and nobody coming: what the staff do with themselves (--quiet=stool, --quiet=floor: that one, now)
			await get_tree().create_timer(0.6).timeout
			$Shoppers._arrive = 99999.0
			for k: Dictionary in $Shoppers.custs.duplicate():
				$Shoppers._gone(k)
		elif a.begins_with("--quiet="):
			await get_tree().create_timer(0.6).timeout
			$Shoppers._arrive = 99999.0
			for k: Dictionary in $Shoppers.custs.duplicate():
				$Shoppers._gone(k)
			if a.ends_with("stool"):
				$Staff._stool_fetch()
			else:
				$Staff._wander_start()
		elif a == "--postit":  # a couple of overdue-call notes by the phone
			await get_tree().create_timer(0.6).timeout
			for m: Dictionary in $Shoppers.members.all.slice(0, 2):
				$Phone.postit_add(m, true)
			if "--peel" in args:  # (...one of them peeled off, in your hand)
				$Phone.aim = "postit"
				$Phone.aim_note = $Phone.postits[0]
				$Phone.peel()
		elif a == "--hands":  # a full-ish inventory: two tapes, a drink, a candy bar, then back to the first tape and to the drink
			await get_tree().create_timer(0.6).timeout
			var T2 := $Tapes
			var Sn2 := $Snacks
			for t: Dictionary in T2.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not T2._corners(t).is_empty()).slice(0, 2):
				T2.pickup(t)
				T2.inspecting = false
			for drink in [true, false]:
				Sn2.aim = { "take": Sn2.units.filter(func(u: Dictionary) -> bool: return not u.out and u.node != null and (u.k != "") == drink)[0] }
				Sn2.on_e()
				await get_tree().process_frame
			T2.inv_select(0)
			await get_tree().process_frame
			var ok0: bool = T2.held != null and Sn2.held == null
			T2.inv_select(2)
			await get_tree().process_frame
			print("hands: %d carried, tape back in hand %s, drink back in hand %s, snack bar shows %s" % [T2.inv.size(), ok0, Sn2.held != null and Sn2.held.u.k != "" and T2.held == null, T2.inv.map(func(e: Dictionary) -> String: return T2._slot(e).name)])
		elif a == "--street":  # out front: a few people going by (one of them with a pizza), somebody driving in next door, a customer or two on their way in
			for i in 4:
				var w: Dictionary = $People.walker([Vector2(-5.0 + i * 2.2, -1.0 - 0.1 * i), Vector2(24.0 if i % 2 else -24.0, -1.0)])
				w.umb_own = i < 2
				if i == 3:
					$People._box(w, true)
			$People.pizza_run()
			for i in 3:
				$Shoppers.spawn()
		elif a.begins_with("--co="):  # mid-sale at the counter, that many steps in (two tapes; you're ringing it up)
			$Shoppers.drives = false
			var cu: Dictionary = $Shoppers.spawn()
			cu.returning = []
			cu.thief = false
			cu.path = []
			cu.c.position = Vector3($Shoppers._counter.x, 0, $Shoppers._counter.z)
			cu.c.rotation.y = PI
			for t: Dictionary in $Tapes.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not $Tapes._corners(t).is_empty()).slice(0, 2):
				$Tapes.set_on_shelf(t, false)
				cu.tapes.append(t)
			cu.holding = 2
			$Staff._ring_t = -999.0
			$Checkout.start("player", cu)
			for i in a.trim_prefix("--co=").to_int():
				$Checkout._printing = 0.0
				$Checkout.act($Checkout.step()[1])
			if $Checkout._led_t > 0.0:
				$Checkout._led_t = 5.0  # (the pad's light, held green for the picture)
		elif a == "--hire":  # two more on staff, at their posts
			for i in 2:
				$Staff.hire($Staff.applicant())
		elif a == "--bare":  # the level without its extras: which copies it has nothing on the shelf for (world/bare.json: what the web game's --extras export goes by)
			var bare: Array = $Tapes.tapes.filter(func(t: Dictionary) -> bool: return $Tapes._corners(t).is_empty()).map(func(t: Dictionary) -> String: return t.k)
			FileAccess.open("res://world/bare.json", FileAccess.WRITE).store_string(JSON.stringify(bare))
			print("bare: %d copies the level has nothing on the shelf for" % bare.size())
		elif a.begins_with("--move="):  # one of the counter's things in the air, its ghost where you're looking (rewinder0, desens, printer); --move=printer:place sets it down there
			await get_tree().create_timer(0.6).timeout
			var which := a.trim_prefix("--move=").get_slice(":", 0)
			$Counter.aim = $Counter.items.filter(func(it: Dictionary) -> bool: return it.id == which)[0]
			$Counter.start()
			$Counter.move.ry += PI / 6.0
			await get_tree().process_frame
			await get_tree().process_frame
			if a.ends_with(":place"):
				$Counter.place()
		elif a.begins_with("--cooler="):  # the cooler's air at that many degrees
			$Snacks.air = a.trim_prefix("--cooler=").to_float()
		elif a.begins_with("--own="):  # with these upgrades bought (their ids, with commas)
			for id in a.trim_prefix("--own=").split(","):
				$Shift.upg[id] = true
		elif a.begins_with("--library="):  # with that many of the library's tiers in (0: a new store's shelves)
			await get_tree().create_timer(0.5).timeout  # (once the store's own start has had its say)
			$Shift.upg.library = a.trim_prefix("--library=").to_int()
			$Shift.stock_library()
		elif a.begins_with("--lit="):  # a light zone switched on (the theater's start off)
			$Lights.set_zone(a.trim_prefix("--lit="), true)
		elif a.begins_with("--sit="):  # in one of the seats, by its number in data/interact.json
			$Player.sit($Interact.seats[a.trim_prefix("--sit=").to_int()])
		elif a == "--dark":  # the store's lights off (the sales floor's and the hall's)
			for z in ["front", "aisles", "lounge", "hall"]:
				$Lights.set_zone(z, false)
			if "--lamps-off" in args:
				for l in $Lights.lamps:
					$Lights.set_lamp(l, false)
		elif a.begins_with("--weather="):  # rain | snow | fog | clear, straight to it (rain,1: a thunderstorm; snow,1: a blizzard)
			var wx := a.trim_prefix("--weather=").split(",")
			var w := wx[0]
			$Weather.set_now("clear" if w == "fog" else w, 0.9, 0.8 if w == "fog" else 0.0, wx[1].to_float() if wx.size() > 1 else 0.0)
		elif a == "--gaits":  # one of each gait, walking on the spot side-on, at the pace they'd walk (--gaits --mocap: the 100STYLE captures, to compare)
			var gaits: Array = preload("res://person.gd").GAITS.keys()
			for i in gaits.size():
				var c: Node3D = $People.spawn(i)
				c.gait = gaits[i]
				c.mocap = "--mocap" in args
				c.position = Vector3(-4.8 + i * 1.2, -0.12, -8.0)
				c.rotation.y = PI / 2.0
				c.set_mood("neutral")
				var lbl := Label3D.new()
				lbl.text = gaits[i]
				lbl.font_size = 48
				lbl.pixel_size = 0.004
				lbl.position = Vector3(-4.8 + i * 1.2, 2.15, -8.0)
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				add_child(lbl)
				get_tree().process_frame.connect(func() -> void: c.tick(get_process_delta_time(), 1.3))
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
		elif a.begins_with("--pos"):  # the register's terminal up: --pos (the main menu), --pos=login, --pos=4 (that typed in; more with commas)
			$POS.log_in()
			$POS._login = 0.5 if a == "--pos=login" else -1.0
			for cmd in (a.trim_prefix("--pos=").split(",", false) if a.begins_with("--pos=") and a != "--pos=login" else []):
				if cmd.begins_with("!"):  # (a key on a screen with keys of its own: !G on the schedule is AUTO)
					$POS._frame()
					$POS._screen.keys.call(OS.find_keycode_from_string(cmd.substr(1)), false)
				else:
					$POS.type(cmd)
			if a == "--pos=login":
				set_process(false)
				$POS.set_process(false)
				$POS._process(0.0)
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
	for w in args:  # --walk=seconds: walk forward that long (with --feet: solid, up stairs and all), and say where it got to
		if w.begins_with("--walk="):  # (as W held: a key pressed from here doesn't stay down in a window that can't take the keyboard)
			$Player.walking = true
			var t0 := Time.get_ticks_msec()
			var said := 0
			while Time.get_ticks_msec() - t0 < w.trim_prefix("--walk=").to_float() * 1000.0:
				await get_tree().physics_frame
				if (Time.get_ticks_msec() - t0) / 1000 > said:
					said = (Time.get_ticks_msec() - t0) / 1000
					print("walk: %d s, at %s" % [said, $Player.global_position])
			$Player.walking = false
			print("walk: got to %s, the view %.2f over your feet" % [$Player.global_position, $Player.cam.position.y])
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	print("shot: %s, on the floor %s, at %s" % [Clock.fmt_clock(Clock.h), $Player.is_on_floor(), $Player.global_position])
	print("shot: %d on the roster, %d staff nodes (%s), %d customers, %d going by, %d bodies" % [$Staff.roster.size(), $Staff.crew.size(), $Staff.crew.map(func(e: Node) -> String: return e.state), $Shoppers.custs.size(), $People.walkers.size(), $People.get_child_count()])
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
	$Shoppers.drives = false  # (its customers are timed from the sidewalk; the ones by car get their own look, below)
	$Staff.sits = false  # (and nobody goes for the stool mid-scene: that has its own look too)
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
	if I.doors.size() != 6 or I.front.is_empty():  # (the sixth: the booth's stairs, tools/remodel.gd)
		bad.append("doors: found %d of 6, the front door %s" % [I.doors.size(), not I.front.is_empty()])
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
		P.fly = false
		P.global_position = Vector3(-6.8, 0.05, 4.6)  # in the counter's gap from the lobby side: the gate swings in behind the counter
		await get_tree().create_timer(0.8).timeout
		var swung: float = F._flap_gate.rotation.y
		P.global_position = Vector3(0, 0, 10)
		await get_tree().create_timer(3.0).timeout
		if swung < 1.0 or absf(F._flap_gate.rotation.y) > 0.05 or F._flap_pivot.visible:
			bad.append("the counter's gate didn't swing in as you came through and shut behind you (%.2f, then %.2f), or the leaf's still over it" % [swung, F._flap_gate.rotation.y])
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
			var in_hand: Array = [C.co.get("hand", "") if C.co != null else ""]  # what each step leaves you holding out
			for where in ["register", "customer", "customer"]:
				C.act(where)
			in_hand.append(C.co.hand)
			C.act("customer")  # past the pad, for the cash: the tapes can still go over it, out of order
			in_hand.append(C.co.hand)
			var skipped: bool = C.step()[0] == "ring" and C.pad_target() == took
			C.pad_use()
			C.act("register")
			await get_tree().process_frame
			await get_tree().process_frame
			var printing: bool = C._strip.visible and C.drawer_open == 1.0 and C._hand_key == "" and not C._hand.visible
			await get_tree().create_timer(2.6).timeout
			if not skipped or not took.get("desens", false) or not printing or C._strip.scale.y < 0.24 or in_hand != ["card", "tapes", "cash"]:
				bad.append("the sale's hands, pad, printer or drawer were off (in hand %s; the pad skipped then used %s, %s; printing %s, %.2f m of receipt)" % [in_hand, skipped, took.get("desens", false), printing, C._strip.scale.y])
			C.act("printer")
			if C._strip.visible or not C.co.hand in ["change", "receipt"]:
				bad.append("the receipt didn't tear off into your hand (%s)" % C.co.hand)
			for where in ["customer", "customer", "customer"]:
				C.act(where)
			await get_tree().process_frame
			if C.drawer_open != 0.0 or C._hand.visible:
				bad.append("the drawer or your hand was left out after the sale")
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
		bad.append("Dana didn't clean up a cup left on the floor (she's %s, carrying %d, %d in the bin, %d strays, %d steps to go, at %s)" % [St.state, St.carry.size(), Tp.return_bin.size(), Ch.strays.size(), St._path.size(), St.dana.position])
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
	# the cooler: its door left open, the air warms and the drinks follow; shut, it comes back down
	$Things.cooler_open = true
	for i in 400:
		$Snacks._process(1.0)
	var warm_air: float = $Snacks.air
	var went_warm: bool = $Snacks.any_warm()
	$Things.cooler_open = false
	for i in 900:
		$Snacks._process(1.0)
	if warm_air < 60.0 or not went_warm or $Snacks.air > 37.0 or $Snacks.any_warm():
		bad.append("the cooler didn't warm with its door open and chill again shut (%.1f°F open, %.1f°F shut, warm drinks then %s, now %s)" % [warm_air, $Snacks.air, went_warm, $Snacks.any_warm()])
	# popcorn: nothing till the machine's bought; then a box, a scoop, butter, and eight handfuls
	var Pc: Node = $Snacks
	var had_pop: bool = $Shift.upg.get("popcorn", false)
	$Shift.upg.popcorn = false
	var no_box: bool = not Pc.popcorn_step("boxes", true)
	$Shift.upg.popcorn = true
	for part in ["boxes", "corn", "butter", "butter"]:
		Pc.popcorn_step(part, true)
	if not no_box or Pc.popcorn == null or Pc.popcorn.fill != 8 or Pc.popcorn.toppings != ["butter"] or not "Buttered" in Pc.holding():
		bad.append("the popcorn machine didn't fill a box (%s)" % [Pc.popcorn])
	Pc.popcorn = null
	$Shift.upg.popcorn = had_pop
	# floor help: somebody's been asking at the counter a while; she fetches it from the shelf and hands it over
	var fk: Dictionary = S.spawn(S.members.all[9])
	fk.returning = []
	fk.path = []
	fk.c.position = Vector3(S._counter.x + 1.2, 0, S._counter.z + 0.1)
	fk.want = { "kind": "title", "title": wound.t, "cat": wound.c }
	fk.tries = 0
	fk.state = "asking"
	fk.t = 999.0
	fk.ask_at = Time.get_ticks_msec() / 1000.0 - 30.0
	S.asks.append(fk)
	t0 = Time.get_ticks_msec()
	while fk.tapes.is_empty() and S.custs.has(fk) and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	if fk.tapes.is_empty() or fk.tapes[0].t != wound.t:
		bad.append("Dana didn't fetch what was asked for at the counter (she's %s, they're %s)" % [St.state, fk.state])
	for ft: Dictionary in fk.tapes:
		Tp.set_on_shelf(ft, true)
	fk.tapes = []
	S.asks.erase(fk)
	S.line.erase(fk)
	S._gone(fk)
	t0 = Time.get_ticks_msec()
	while (St.state != "post" or not St._path.is_empty()) and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
	# lunch: there's a way to a chair in the break room, she sits, and comes back after
	if not St._lunch_start():
		bad.append("Dana couldn't get to a chair in the break room for lunch")
	else:
		t0 = Time.get_ticks_msec()
		while St.state != "lunch" and Time.get_ticks_msec() - t0 < 90000:
			await get_tree().process_frame
		var sat: bool = St.state == "lunch" and St.dana.pose == "sit"
		St._t = 0.0
		t0 = Time.get_ticks_msec()
		while (St.state != "post" or not St._path.is_empty()) and Time.get_ticks_msec() - t0 < 90000:
			await get_tree().process_frame
		if not sat or St.state != "post" or St._lunch_chair != null:
			bad.append("Dana didn't have her lunch and come back (sat %s, she's %s)" % [sat, St.state])
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
			var back0: int = Sn.backstock[bar.n]  # (the staff may have been into the cupboard for it already today)
			Sn.aim = { "cupboard": "drinks" if bar.k != "" else "food" }
			Sn.on_e()
			var carried: int = Sn.carry.size()
			Sn.aim = { "spot": bar }
			Sn.on_e()
			if carried < 1 or Sn.carry.size() != carried - 1 or Sn.units.filter(func(u: Dictionary) -> bool: return u.out).size() != empty0 - 1 or Sn.backstock[bar.n] != back0 - 1:
				bad.append("the empty spot didn't get restocked from the cupboard (carried %d, %d of %d still empty, %d of %d in the cupboard)" % [carried, Sn.units.filter(func(u: Dictionary) -> bool: return u.out).size(), empty0, Sn.backstock[bar.n], back0])
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
		bad.append("a parent and kid didn't see their visit through together (parent %s, kid %s, tagged along %s; clerk %s, sale %s)" % [mum.state, kid.state, tagged, $Staff.state, [$Checkout.co.by, $Checkout.co.i, $Checkout.step(), $Checkout.co.get("away", false), $Checkout.co.cust == mum] if $Checkout.co != null else "none"])
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
	# an overdue call: six days late, they're on the register's list; looked up, on a post-it; rung from it, on their record
	var owes: Dictionary = S.members.all[7]
	var late_r := [loot, Clock.day - 8, Clock.day - 6, owes.num]
	S.rented.append(late_r)
	var note = Ph.postit_add(owes, true) if $POS.to_call().has(owes) else null
	if note != null:
		Ph.postit_call(note)
	if Ph.out == null:
		bad.append("somebody six days late didn't get a post-it and a call (%d to call)" % $POS.to_call().size())
	else:
		Ph.out.t = 99.0
		Ph._out_tick(0.0)
		if owes.calls != 1 or note.result == "" or owes.last_call != Clock.day:
			bad.append("the overdue call wasn't put on their record")
		Ph.out = null
		Ph._out_hud()
		Ph.aim_note = note
		Ph.postit_toss(note)
		if not Ph.postits.is_empty():
			bad.append("the post-it didn't go in the bin")
	S.rented.erase(late_r)
	owes.calls = 0
	owes.last_call = -1
	owes.last_result = ""
	owes.promise = -9
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
		Po.deliver()  # a box by the door; into your arms, and unpacked at a cupboard
		if Sn.boxes.size() != 1 or Sn.backstock[ordered[0]] != stock0[ordered[0]] or not Tp.return_bin.has(loot):
			bad.append("the morning's delivery didn't come (%d boxes)" % Sn.boxes.size())
		else:
			Sn.aim = { "box": Sn.boxes[0] }
			Sn.on_e()
			Sn.aim = { "cupboard": "food" }
			Sn.on_e()
			if not Sn.boxes.is_empty() or not Sn.box_carry.is_empty() or Sn.backstock[ordered[0]] != stock0[ordered[0]] + 24:
				bad.append("the delivery's box didn't unpack into the cupboard")
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
	# every copy's really in the shelves to be put out (the locked sections' come with world/extras.glb), and its section's sign turns over
	var bare: int = Tp.tapes.filter(func(t: Dictionary) -> bool: return Tp._corners(t).is_empty()).size()
	var soon: int = $Shift._sign_pairs.filter(func(p: Array) -> bool: return not p[0].visible or (p[1] != null and p[1].visible)).size()
	if bare > 0 or $Shift._sign_pairs.size() < 20 or soon > 0:
		bad.append("the library's tapes or signs aren't all there (%d copies with nothing on the shelf, %d signs, %d still COMING SOON)" % [bare, $Shift._sign_pairs.size(), soon])
	# the rewinders: one plain box; a second once it's bought; high-speed, both of them sports cars
	var looks := func() -> String: return " ".join(Tp._rw_looks.keys().filter(func(k: String) -> bool: return Tp._rw_looks[k].visible))
	var had_rw := [$Shift.upg.get("rewinder2", false), $Shift.upg.get("rewinders", false)]
	var seen := []
	for own: Array in [[false, false], [true, false], [true, true]]:
		$Shift.upg.rewinder2 = own[0]
		$Shift.upg.rewinders = own[1]
		Tp._rewinder_looks()
		seen.append(looks.call())
	$Shift.upg.rewinder2 = had_rw[0]
	$Shift.upg.rewinders = had_rw[1]
	if seen != ["box1", "box1 box2", "car1 car2"]:
		bad.append("the rewinders didn't change with their upgrades (%s)" % [seen])
	# the counter's things: lifted, a ghost where it would go; put back; and set down somewhere else, what goes by where it sits goes with it
	var Co := $Counter
	var prn: Array = Co.items.filter(func(it: Dictionary) -> bool: return it.id == "printer")
	if Co.items.size() < 4 or prn.is_empty() or Co._fixed.size() < 2:
		bad.append("the counter's things weren't all found to move (%d, %d that stay put)" % [Co.items.size(), Co._fixed.size()])
	else:
		var pg: Node3D = prn[0].nodes[0]
		var home: Vector3 = pg.global_position
		var slot0: Vector3 = $Checkout._at.printer
		Co.aim = prn[0]
		Co.start()
		var lifted: bool = Co.moving() and not pg.visible
		Co.cancel()
		var back: bool = not Co.moving() and pg.visible and pg.global_position == home
		var fits := [Co.fits(prn[0], -3.6, 3.93, 0.0), Co.fits(prn[0], -4.95, 3.92, 0.0), Co.fits(prn[0], -3.6, 4.6, 0.0)]  # a free spot; on top of the desensitizer; off the worktop
		Co._put_at(prn[0], -3.6, 3.93, PI / 6.0)
		var went: bool = $Checkout._at.printer.distance_to(slot0) > 0.5 and $Checkout._strip.position.distance_to(Vector3(-3.6, 1.178, 3.93)) < 0.06
		Co._put_at(prn[0], home.x, home.z, 0.0)
		prn[0].moved = false
		if not lifted or not back or fits != [true, false, false] or not went or $Checkout._at.printer.distance_to(slot0) > 0.01:
			bad.append("the receipt printer didn't move about the counter as it should (lifted %s, put back %s, fits %s, its slot went with it %s)" % [lifted, back, fits, went])
	# the cooler's thermometer reads its air
	$Snacks.air = 51.6
	$Snacks._process(0.0)
	if $Snacks._thermo == null or $Snacks._thermo.text != "52°F":
		bad.append("the cooler's thermometer isn't reading its air (%s)" % ($Snacks._thermo.text if $Snacks._thermo != null else "not found"))
	$Snacks.air = 36.0
	# the theater: bought, its door's unchained and somebody finds a seat; a feature set on the terminal sells a ticket
	var chained: Array = $Interact.doors.filter(func(d: Dictionary) -> bool: return d.push and d.locked)
	var sign_at := func(n: Node3D) -> bool: return not chained.is_empty() and n.is_visible_in_tree() and absf(n.global_position.y - 1.5) < 0.05 and Vector2(n.global_position.x - chained[0].at, n.global_position.z - chained[0].c).length() < 0.12
	var signs0: int = $World.find_children("*", "MeshInstance3D", true, false).filter(sign_at).size()
	$Shift.upg.theater = true
	$Shift.open_theater()
	var signs1: int = $World.find_children("*", "MeshInstance3D", true, false).filter(sign_at).size()
	if signs0 != 2 or signs1 != 0:
		bad.append("the theater's COMING SOON signs didn't come down with it (%d before, %d after)" % [signs0, signs1])
	# your own body: in the uniform, under you, headless; and a theater seat folds down under whoever's in it, and springs back up
	var folds: Array = $Interact._folds
	if $Player.body == null or $Player._body_look != "You" or $Player.body._head.visible:
		bad.append("you've no body to look down at (%s)" % $Player._body_look)
	if folds.size() < 40 or folds[0].a != 1.0:
		bad.append("the theater's seats haven't their folding cushions (%d)" % folds.size())
	else:
		var was_at: Vector3 = $Player.global_position
		$Player.sit(folds[0].seat)
		await get_tree().create_timer(1.5).timeout
		var down: float = folds[0].a
		var sat_pose: String = $Player.body.pose if $Player.body != null else ""
		$Player.stand(was_at, 0.0)
		await get_tree().create_timer(1.5).timeout
		if down > 0.05 or folds[0].a < 0.95 or sat_pose != "sit":
			bad.append("a theater seat didn't fold down under you and spring back (%.2f sat, %.2f after; your body %s)" % [down, folds[0].a, sat_pose])
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
	Cu._day_check()
	var pickd: Dictionary = Tp.tapes.filter(func(t: Dictionary) -> bool: return not t.off and t.e.size() == 1 and not Tp._corners(t).is_empty())[0]
	Cu.rec = {}
	Cu.recommend(St)
	Cu.day.goals = [{ "id": "pick", "done": false, "miss": false }, { "id": "money", "done": false, "miss": false }]
	if Cu.rec.is_empty():
		bad.append("nobody on staff had a pick")
	Cu.rec = { "title": pickd.t, "cat": pickd.c, "by": St.first, "day": Clock.day, "done": false }  # (one the check can get off the shelf)
	var rec_tape: Dictionary = pickd
	Cu.banned = 0
	Tp.pickup(rec_tape)
	Cu.pay()
	Cu._day_check()
	Tp.aim_returns = true
	Tp.drop_in_returns()
	if Cu.rec.is_empty() or not Cu.rec.done or not Cu.day.goals[0].done or Cu.day.goals[1].done or not "☐" in Cu.list_line():
		bad.append("the staff's pick, rented, didn't come off the day's list (%s)" % [Cu.rec])
	# the crew as people: known a few days, a favor; done, something for it. And a yes to an application puts you on staff
	Cu.wary.clear()
	Cu._knows(St).k = 3
	Cu._knows(St).day = 0
	Cu._knows(St).named = true
	Cu.rec = { "day": Clock.day, "title": "x", "cat": "y", "done": true }
	Cu.fav = {}
	Cu._fav_day = 0
	Cu.talk(St)
	var asked: Dictionary = Cu.fav.duplicate()
	Cu.fav.done = true
	var trust0: float = Cu.trust
	Cu.talk(St)
	if asked.is_empty() or not Cu.fav.get("paid", false) or Cu.trust <= trust0 or Cu._hint() == "" or Cu.staff_tip(St) == "":
		bad.append("a favor for one of the staff didn't get asked and thanked (%s)" % [asked])
	for stray: Dictionary in Ch.strays.duplicate():
		Ch.stray_take(stray)
		Tp.set_on_shelf(stray.copy, true)
	Cu.app = { "day": Clock.day - 1, "strikes": Cu.strikes, "ans": "yes", "told": true }
	Cu.talk(St)
	if $Shift.mode != "sandbox" or not Cu.rented.is_empty():
		bad.append("taking the job didn't put you on staff")
	$Shift.mode = "customer"
	Cu.fav = {}
	Cu.banned = Clock.day
	if not "YOUR DAY" in "\n".join(Cu.slip()) or not "YOUR RECORD" in "\n".join(Cu.slip()):
		bad.append("a customer's day didn't make a slip")
	# the trail: the note, the time card, the locker's padlock, the badge; the PIN, the register as Ray, the printout, the hatch
	var Tr := $Trail
	Tr.setup()
	var hidden: Array = Tr._spots.keys().filter(func(k: String) -> bool: return Tr._spots[k][4].get("item", "") == "comboNote")
	Tr.aim = { "spot": hidden[0] }
	Tr.on_e()
	Tr._typing = "locker"
	for ch in Tr._codes.locker:
		Tr._digit(ch)
	Tr.aim = { "locker": true }
	Tr.on_e()
	if not Tr.has("badge") or Tr.has("comboNote") or not Tr.found.has("combo:locker"):
		bad.append("Ray's locker didn't give up his badge (pockets: %s)" % [Tr.items])
	$Player.global_position = Vector3(-5.4, 0.1, 2.6)
	Tr.aim = { "register": true }
	Tr.on_e()
	for ch in Tr._codes.pin:
		Tr._term_key(KEY_0 + int(ch))
	Tr._term_key(KEY_1)
	Tr._term_key(KEY_P)
	Tr._term_key(KEY_B)
	Tr._term_key(KEY_4)
	Tr._term_key(KEY_K)
	var screen: String = Tr._term_text()
	Tr._term_key(KEY_E)
	Tr._typing = "hatch"
	for ch in Tr._codes.hatch:
		Tr._digit(ch)
	if not Tr.logged_in or not Tr.has("closetKey") or not Tr.hatch or Tr.has("printout") or Tr.term != null or not "NO SALE" in screen:
		bad.append("the register as Ray didn't lead to the janitor's key and the roof hatch (in %s, pockets %s, hatch %s)" % [Tr.logged_in, Tr.items, Tr.hatch])
	var keyed: Dictionary = Tr._keyed()
	if keyed.size() != 2 or Tr.door(keyed.closetKey) or (not Tr.has("breakKey") and not keyed.breakKey.open and not Tr.door(keyed.breakKey)):
		bad.append("the back rooms' doors don't answer to their keys (%d keyed)" % keyed.size())
	Tr.items.clear()
	Tr.found.clear()
	Tr.hatch = false
	Tr.logged_in = false
	Tr._typing = ""
	Cu.heat = 0.0
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
	# a snack of your own: taken, eaten, the empty in a bin. And the staff fill an empty spot from the cupboard
	var mine: Dictionary = Sn.units.filter(func(u: Dictionary) -> bool: return not u.out)[0]
	Sn.aim = { "take": mine }
	Sn.on_e()
	Sn.held.left = 0  # (eaten)
	var empty: String = Sn.holding()
	Ch.aim = { "bin": Ch.bins[0] }
	Ch.on_e()
	if not mine.out or Sn.held != null or not "take it to the trash" in empty:
		bad.append("a snack didn't get eaten and thrown away (%s)" % empty)
	St._ring_t = 0.0
	t0 = Time.get_ticks_msec()
	while mine.out and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	if mine.out:
		bad.append("nobody on staff restocked an empty rack spot (%s is %s)" % [St.first, St.state])
	# the calendar: Halloween's a busy night, and the weeks before it pull people to the horror shelves
	var day_was := Clock.day
	Clock.day = 32  # (day 1 is September 30: this is October 31)
	var hw: Dictionary = $Shift.season()
	Clock.day = 20
	var lead: Dictionary = $Shift.season()
	Clock.day = day_was
	if hw.today.size() != 1 or hw.today[0][1] != "HALLOWEEN" or absf(hw.rush - 1.25) > 0.01 or not lead.lean.has("Horror") or not lead.today.is_empty() or not $Shift.season().lean.is_empty():
		bad.append("the calendar's wrong about Halloween (%s / %s)" % [hw, lead])
	# a ceiling light burns out; with the step ladder from the closet it's a new tube
	Ch.light_die(3)
	var tube: Dictionary = Ch.dead[-1]  # (this one: another may have gone by itself somewhere, in a run this long)
	Ch.aim = { "light": tube }
	Ch.on_e()
	var no_ladder: bool = Ch._fix == null
	if Ch.tools.ladder.nodes.is_empty():
		bad.append("the step ladder isn't in the janitor's closet")
	else:
		Ch.tool_take("ladder")
		Ch.aim = { "light": tube }
		Ch.on_e()
		var started: bool = Ch._fix != null
		t0 = Time.get_ticks_msec()
		while Ch.dead.has(tube) and Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
		if not no_ladder or Ch.dead.has(tube):
			bad.append("a burnt-out light didn't get its tube swapped (%d dead, started %s, holding %s, fix %s)" % [Ch.dead.size(), started, Ch.tool_held, Ch._fix])
		Ch.tool_return()
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
	# out front: the weather on people, the pizza place, the cars, the glass and the drifts; and what's in a hand
	var Pe := $People
	var W := $Weather
	var Ca := $Cars
	if Ca.parked.size() < 2 or $World.find_children("*", "Node3D", true, false).any(func(n: Node) -> bool: return n.get_child_count() >= 20 and absf(n.position.y + 0.12) < 0.005 and n.position.z < -8.0 and n.position.z > -20.0 and not Ca.is_ancestor_of(n)):
		bad.append("the lot: %d cars parked for the day, or the level's own are still stood there" % Ca.parked.size())
	var lot_day: Array = Ca.parked.map(func(g: Node3D) -> Vector3: return g.position)
	Ca.park_lot(Clock.day, false)
	if Ca.parked.map(func(g: Node3D) -> Vector3: return g.position) != lot_day:
		bad.append("the lot isn't the same lot twice in a day")
	W.set_now("snow")
	var wa: Dictionary = Pe.walker([Vector2(-6.0, -1.0), Vector2(30.0, -1.0)])
	await get_tree().create_timer(3.0).timeout
	if wa.get("snow", 0.0) <= 0.05 or not wa.c._snow_on[0].visible or wa.get("hunch", 0.0) < 0.3 or wa.c.hunch < 0.3:
		bad.append("snow didn't settle on somebody walking by, or they're not hunched against it (snow %s, hunch %s)" % [wa.get("snow"), wa.get("hunch")])
	if W._lumps.size() < 100 or not W._drifts.visible:
		bad.append("no snow drifting against the kerbs (%d lumps)" % W._lumps.size())
	W.set_now("rain")
	wa.umb_own = true
	var wb: Dictionary = Pe.walker([Vector2(-6.0, -1.3), Vector2(30.0, -1.3)])
	wb.umb_own = false
	var wb_x: float = wb.c.position.x
	await get_tree().create_timer(1.0).timeout
	if wa.c.prop != "umbrella" or wa.c._props.umbrella.global_basis.y.normalized().y < 0.8 or wa.c.shield:
		bad.append("an umbrella didn't go up in the rain, straight up (%s)" % [wa.c.prop])
	if wb.c.prop != null or not wb.c.shield or wb.c.position.x - wb_x < 2.0:
		bad.append("caught in the rain with no umbrella: no hand over the head, or no run for it (%.1f m in a second)" % (wb.c.position.x - wb_x))
	if W._glass.size() != 3 or W._glass[0].albedo_color.a < 0.5 or W._glass[1].albedo_color.a < 0.5:
		bad.append("no rain on the storefront glass")
	W.set_now("clear")
	wa.c._blink = false
	wa.c._blink_next = 0.0
	wa.c.set_mood("neutral")
	wa.c.tick(0.01, 0.0)
	if not wa.c._blink or wa.c._face.uv1_offset.y < 0.6:
		bad.append("they don't blink")
	wa.c.slip()
	if not wa.c.busy():
		bad.append("a slip doesn't hold them up")
	Pe._box(wa, true)
	if wa.c._item.get_child_count() != 1 or wa.c.pose != "hold":
		bad.append("a pizza box isn't in their hand")
	var wc: Dictionary = Pe.walker([Vector2(Pe.PIZZA_DOOR.x, -1.0), Pe.PIZZA_DOOR])
	wc.then = Pe._in_tonys.bind(0.5, [Vector2(30.0, -1.0)], null)
	var n_lot: int = Ca.lot.size() + Pe.walkers.size()
	Pe.pizza_run()
	if Ca.lot.size() + Pe.walkers.size() != n_lot + 1:
		bad.append("nobody set out for a pizza")
	# a customer by car: along the road, in at the driveway, into a stall, out of it and in to the store; and off again
	var driver: Dictionary = S.members.all[20]
	driver.car = Ca.new_look()
	S.drives = true
	var dc: Dictionary = S.spawn(driver)
	S.drives = false
	if dc.state != "drivingIn" or dc.c.visible or dc.car == null:
		bad.append("somebody with a car walked up instead (%s)" % dc.state)
	else:
		var car: Dictionary = dc.car
		var t1 := Time.get_ticks_msec()
		while car.phase != "parked" and Time.get_ticks_msec() - t1 < 60000:
			await get_tree().process_frame
		await get_tree().process_frame
		if car.phase != "parked" or absf(car.g.position.x - car.sx) > 0.05 or absf(car.g.position.z - Ca.PARK_Z) > 0.05 or absf(angle_difference(car.g.rotation.y, PI / 2.0)) > 0.1:
			bad.append("a car didn't make it into its stall, nose to the road (%s at %s, turned %.2f)" % [car.phase, car.g.position, car.g.rotation.y])
		if dc.state != "arrive" or not dc.c.visible or Vector2(dc.c.position.x - car.door.x, dc.c.position.z - car.door.y).length() > 1.0 or absf(dc.c.position.y + 0.12) > 0.01:
			bad.append("its driver didn't get out beside it, down on the lot (%s at %s)" % [dc.state, dc.c.position])
		S._gone(dc)
		await get_tree().create_timer(1.0).timeout
		var braking: bool = car.g.get_children().any(func(n: Node) -> bool: return String(n.name).contains("_lamp_tail_") and n.material_override != null)
		if car.phase != "startUp" or not braking or not car.g.get_node("pool_rear").visible:
			bad.append("with everyone back in it the car didn't start up, on the brake, its light on the pavement (%s)" % car.phase)
		t1 = Time.get_ticks_msec()
		while car.phase != "gone" and Time.get_ticks_msec() - t1 < 60000:
			await get_tree().process_frame
		if car.phase != "gone" or Ca.lot.has(car):
			bad.append("the car didn't drive off (%s)" % car.phase)
	var t2 := Time.get_ticks_msec()
	while not wc.box and Pe.walkers.has(wc) and Time.get_ticks_msec() - t2 < 30000:
		await get_tree().process_frame
	if not wc.box:  # (by now they may be home with it)
		bad.append("nobody came away from Tony's counter with a pizza")
	# in hand: a drink off the rack, in yours; the mop, in both of them
	var bottle: Dictionary = Sn.units.filter(func(u: Dictionary) -> bool: return u.node != null and u.k != "" and not u.out)[0]
	Sn.set_out(bottle, true)
	Sn.held = { "u": bottle, "left": 4, "total": 4, "paid": true }
	await get_tree().create_timer(0.2).timeout
	if Sn._hand.get_child_count() != 1 or not Sn._hand.visible or Sn.proxy(bottle) == null:
		bad.append("a drink in your hand doesn't show")
	Sn.held = null
	Sn.set_out(bottle, false)
	P.fly = false
	P.global_position = Vector3(0, 0.05, 8.0)
	Ch.tool_take("mop")
	await get_tree().create_timer(0.5).timeout
	if Ch._rig == null or Ch._rig.global_position.distance_to(P.global_position) > 1.6 or absf(Ch._rig.global_position.y - P.global_position.y) > 0.05 or (P.body != null and not P.body._reach2.on):
		bad.append("the mop isn't out in front of you on the floor, a hand on it")
	Ch.tool_return()
	if Ch._rig != null or not Ch._rig_src.visible:
		bad.append("the mop didn't go back")
	# the switches' rockers; no fog indoors

	if Li._rockers.size() != Li.switches.size():
		bad.append("light switches: %d of %d rockers found" % [Li._rockers.size(), Li.switches.size()])
	else:
		var was_on: bool = Li.zone_on.breakroom
		var rocker: Node3D = Li._rockers.filter(func(r: Array) -> bool: return r[1] == "breakroom")[0][0]
		var tilt := rocker.rotation.x
		Li.flip_switch("breakroom")
		await get_tree().create_timer(0.4).timeout
		if absf(rocker.rotation.x + tilt) > 0.05 or absf(tilt) < 0.2:
			bad.append("a light switch's rocker didn't flip with it (%.2f -> %.2f)" % [tilt, rocker.rotation.x])
		Li.set_zone("breakroom", was_on)
	W.set_now("clear", 0.9, 0.8)
	P.global_position = Vector3(0, 0.05, 8.0)
	await get_tree().create_timer(1.5).timeout
	var fog_in: float = $WorldEnvironment.environment.fog_density
	P.global_position = Vector3(0, 0.05, -6.0)
	await get_tree().create_timer(1.5).timeout
	if fog_in > 0.002 or $WorldEnvironment.environment.fog_density < 0.02:
		bad.append("the fog's indoors too (%.3f in the store, %.3f out on the lot)" % [fog_in, $WorldEnvironment.environment.fog_density])
	W.set_now("clear")
	P.global_position = Vector3(0, 0.05, 8.0)
	# the register: a sale on its own screen, its beeps, a member's whole record

	for k: Dictionary in S.custs.duplicate():
		S._gone(k)
	var rk: Dictionary = S.spawn()
	rk.returning = []
	rk.thief = false
	rk.path = []
	rk.c.position = Vector3(S._counter.x, 0, S._counter.z)
	for t: Dictionary in T.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not T._corners(t).is_empty()).slice(0, 2):
		T.set_on_shelf(t, false)
		rk.tapes.append(t)
	rk.holding = 2
	St._ring_t = -999.0
	S.members.incident(rk.member, "returned a tape full of jam")
	$Checkout.start("player", rk)
	var sale = $Checkout.ring()
	if sale == null or sale.carded != false or sale.items.size() < 2 or sale.cash_in != null:
		bad.append("the register hasn't got the sale (%s)" % [sale])
	while $Checkout.co != null and $Checkout.step()[0] != "ring":
		$Checkout._printing = 0.0
		$Checkout.act($Checkout.step()[1])
	sale = $Checkout.ring()
	$POS._frame()
	screen = "".join($POS._ch)
	if sale == null or sale.carded != true or sale.cash_in == null or not screen.contains("REGISTER · SALE") or not screen.contains("CASH TENDERED") or not screen.contains("INCIDENT") or not screen.contains("SINCE"):
		bad.append("the sale isn't on the register's screen, the account and the cash with it")
	if $POS._mon_glass == null:
		bad.append("the register's monitor isn't found in the level")
	if $Ambience._live and not $Ambience._baked.has("beep1900"):
		bad.append("the register didn't beep at the card")
	while $Checkout.co != null:
		$Checkout._printing = 0.0
		$Checkout.act($Checkout.step()[1])
	if $Ambience._live and not $Ambience._baked.has("buzz9"):
		bad.append("the printer didn't buzz")
	S._gone(rk)
	var rec: Dictionary = rk.member
	$POS.log_in()
	$POS._member_detail(rec)
	var acct := "\n".join($POS._screen.lines.call())
	if not acct.contains("ADDRESS..: %s" % rec.addr) or rec.addr.length() < 6 or not acct.contains("MEMBER SINCE: %d" % rec.since) or not acct.contains("RETURNED A TAPE FULL OF JAM") or not acct.contains("NOTES"):
		bad.append("a member's record hasn't its address, its year, its notes or what's gone on it")
	$POS.log_off()
	# the staff: the rewinder before the shelf; the stool when it's quiet; the chute's door; Tony in his own clothes
	var unwound: Array = T.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not T._corners(t).is_empty()).slice(4, 7)
	for t: Dictionary in unwound:
		T.set_on_shelf(t, false)
		T.set_wind_frac(t, 0.4)
		T.return_bin.append(t)
	var used := false
	var t3 := Time.get_ticks_msec()
	while (unwound.any(func(t: Dictionary) -> bool: return t.off) or not St.carry.is_empty()) and Time.get_ticks_msec() - t3 < 150000:
		used = used or T.rewinders.any(func(rw: Dictionary) -> bool: return rw.tape != null and unwound.has(rw.tape))
		await get_tree().process_frame
	if unwound.any(func(t: Dictionary) -> bool: return t.off or not T.is_rewound(t)) or not used:
		bad.append("returns that came back unrewound didn't go through the rewinder and onto the shelf (through it: %s, still out: %d, %s)" % [used, unwound.filter(func(t: Dictionary) -> bool: return t.off).size(), St.state])
	St.sits = true
	t3 = Time.get_ticks_msec()
	while St.state != "stoolSit" and Time.get_ticks_msec() - t3 < 60000:
		await get_tree().process_frame
	var stool_at: Vector3 = $Things._stool_at()
	if St.state != "stoolSit" or $Things.stool_by != St or Vector2(stool_at.x - St.STOOL_AT.x, stool_at.z - St.STOOL_AT.y).length() > 0.05 or St.dana.pose != "sit" or Vector2(St.dana.position.x - stool_at.x, St.dana.position.z - stool_at.z).length() > 0.05:
		bad.append("with nothing to do, nobody fetched the stool and sat on it by the register (%s, the stool at %s)" % [St.state, stool_at])
	var late_in: Dictionary = S.spawn()
	await get_tree().create_timer(3.0).timeout
	if St.state in ["stoolSit", "stoolSitDown"] or $Things.stool_by != null or St.dana.pose == "sit":
		bad.append("somebody came in and they stayed on the stool (%s)" % St.state)
	St.sits = false
	S._gone(late_in)
	Ch.chute_use()
	await get_tree().create_timer(0.5).timeout
	if Ch._chute_door == null or Ch._chute_door.rotation.x < 0.6:
		bad.append("the trash chute's door doesn't open")
	if Pe.tony == null or Pe.cast.who[-1].get("staff", "") != "Tony" or not Pe.tony.name.begins_with("p%d" % (Pe.cast.who.size() - 1)):
		bad.append("Tony's not in his own clothes")
	# the schedule and the job board on the register: the grid's keys, and AUTO
	var keep_sched: Array = St.roster.map(func(w: Dictionary) -> Array: return w.sched.duplicate())
	var keep_jobs: Array = St.roster.map(func(w: Dictionary) -> Dictionary: return w.jobs.duplicate())
	$POS.log_in()
	$POS.type("W")
	var grid: Dictionary = $POS._screen
	St.roster[0].sched = [0, 0, 0, 0, 0, 0, 0]
	$POS._frame()
	for key in [KEY_1, KEY_D, KEY_S, KEY_ENTER]:  # (the first of them; a day on, an hour down, and set)
		grid.keys.call(key, false)
	var one: Array = St.roster[0].sched.duplicate()
	grid.keys.call(KEY_S, true)  # (shift: painted on down)
	grid.keys.call(KEY_ENTER, false)  # (and that one cleared again)
	if St.hours({ "sched": one }) != 1 or St.hours(St.roster[0]) != 1 or St.roster[0].sched == one:
		bad.append("the schedule's grid: WASD and ENTER didn't set an hour, paint the next, and clear it (%s then %s)" % [one, St.roster[0].sched])
	grid.keys.call(KEY_G, false)
	var day_ok := func(m: int) -> bool:  # one unbroken shift, eight hours at most
		var bits: Array = range(15).filter(func(b: int) -> bool: return (m >> b) & 1 == 1)
		return bits.is_empty() or (bits[-1] - bits[0] + 1 == bits.size() and bits.size() <= 8)
	var fri_eve: bool = range(8, 13).all(func(n: int) -> bool: return St.roster.any(func(w: Dictionary) -> bool: return (int(w.sched[5]) >> n) & 1 == 1))
	if not St.auto_sched or St.roster.any(func(w: Dictionary) -> bool: return St.hours(w) != St.SCHED_MAX or not w.sched.all(day_ok)) or not fri_eve:
		bad.append("AUTO didn't give everyone their %d hours in whole shifts, Friday evening covered (%s)" % [St.SCHED_MAX, St.roster.map(func(w: Dictionary) -> Array: return w.sched)])
	grid.keys.call(KEY_ENTER, false)
	if St.auto_sched:
		bad.append("touching the schedule didn't take it off AUTO")
	$POS._back()
	$POS.type("J")
	grid = $POS._screen
	$POS._frame()
	St.roster[0].jobs.register = 1
	grid.keys.call(KEY_ENTER, false)
	grid.keys.call(KEY_D, false)
	grid.keys.call(KEY_X, false)
	if St.roster[0].jobs.register != 2 or St.roster[0].jobs.phone != 0:
		bad.append("the job board: ENTER didn't step a priority on, or X didn't set the next job to never (%s)" % [St.roster[0].jobs])
	grid.keys.call(KEY_G, false)
	var best_job: String = St.JOBS.keys().filter(func(j: String) -> bool: return j != "register").reduce(func(a: String, b: String) -> String: return b if St.roster[-1].skills[St.JOB_SKILL[b]][0] > St.roster[-1].skills[St.JOB_SKILL[a]][0] else a)
	if not St.auto_jobs or St.roster.all(func(w: Dictionary) -> bool: return w.jobs.register != 1) or St.roster[-1].jobs[best_job] > 2 or St.roster.any(func(w: Dictionary) -> bool: return w.jobs.values().any(func(v: int) -> bool: return v < 1 or v > 4)):
		bad.append("AUTO didn't put each of them on what they're best at, somebody first on the register (%s)" % [St.roster.map(func(w: Dictionary) -> Dictionary: return w.jobs)])
	$POS.log_off()
	St.auto_sched = false
	St.auto_jobs = false
	for i in St.roster.size():
		St.roster[i].sched = keep_sched[i]
		St.roster[i].jobs = keep_jobs[i]
	print("check: %s" % ("ok" if bad.is_empty() else "; ".join(bad)))
	get_tree().quit(0 if bad.is_empty() else 1)
