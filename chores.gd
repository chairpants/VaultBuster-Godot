extends Node3D
## Keeping the place clean. Customers drop things now and then (a wrapper, popcorn, a spilled soda); E picks a mess
## up, but the popcorn wants the carpet sweeper and the soda the mop, both in the janitor's closet (E takes one, E on
## its spot puts it back; one at a time). Four bins fill through the day: the lobby's with the customers, the break
## room's, the restroom's, the counter's. A full one spills onto the floor. E on a bin ties off the bag; carry up to
## two to the chute in the janitor's closet (right-click sets them down). Customers notice a mess.
## From the web game's store/chores.js (MESS, MESS_TOOL, messAdd, messClean, toolTake, toolReturn, scrubStart,
## trashAdd, binBag, bagsSetDown, bagPickUp, chuteDrop, trashTick's rates) and store/shoppers.js (who litters, and
## how a grotty store sits with people). Where the tools, bins and chute are: data/interact.json.
## And tapes put back in the wrong place (misshelve, strayTake): crooked, half out of the row. E pulls one out;
## it wants putting back in its own slot.
## Not over yet: the mop's and sweeper's pose in your hands as you work (it stands in front of you, and sways), the
## heap rising in a bin, the bags' look and sounds, the chute's door, the step ladder and the ceiling tubes that burn out.

const MESS := {  # kind -> [what it's called, the tool it wants]
	"spill": ["spilled soda", "mop"], "wrapper": ["candy wrapper", ""], "popcorn": ["spilled popcorn", "sweeper"],
	"towel": ["paper towel", ""], "cup": ["empty cup", ""], "puddle": ["puddle by the door", "mop"],
}

var messes: Array = []  # { kind, node, x, z }
var tools := {}  # id -> { label, home, size, nodes }
var tool_held := ""
var bins: Array = []  # { id, name, cap, x, z, rimY, r, towels, stand, n, acc, spilled }
var bag_carry: Array = []  # in your hands: { bin, n }
var bags_down: Array = []  # set down somewhere: { bin, n, node, x, z }
var strays: Array = []  # tapes shoved in anywhere: { copy, node, at, ry }
var aim := {}  # what the crosshair's on: { mess } | { tool } | { bin } | { bag } | { chute } | { stray }

var _chute := Vector3.ZERO
var _scrub = null  # { m, t, dur }
var _carried := Node3D.new()  # the tool in your hands
var _hands := Node3D.new()  # the bags in your hands
var _mess_note := -999.0
var _t := 0.0

@onready var player: CharacterBody3D = $"../Player"
@onready var hud: CanvasLayer = $"../HUD"
@onready var checkout: Node = $"../Checkout"
@onready var shoppers: Node = $"../Shoppers"


func _ready() -> void:
	var T: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things
	for id: String in T.tools:
		var t: Dictionary = T.tools[id]
		tools[id] = { "label": t.label, "home": Vector3(t.home[0], t.home[1], t.home[2]), "size": Vector3(t.size[0], t.size[1], t.size[2]), "nodes": [] }
	for b: Dictionary in T.bins:
		b.n = int(b.cap * 0.3 * randf())
		b.acc = 0.0
		b.spilled = false
		bins.append(b)
	_chute = Vector3(T.chute.at[0], T.chute.at[1], T.chute.at[2])
	add_child(_carried)
	$"../Player/Camera".add_child.call_deferred(_hands)
	call_deferred("_find_tools")


func _find_tools() -> void:  # the level's own mop and sweeper: whatever sits in each one's spot
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		var c: Vector3 = mi.global_transform * mi.get_aabb().get_center()
		for t: Dictionary in tools.values():
			if AABB(t.home - t.size / 2.0, t.size).grow(0.03).has_point(c):
				t.nodes.append(mi)


func misshelve(copy: Dictionary, spot = null, near = null) -> void:  # put back in the wrong place: crooked, half out of the row, by some other tape on that shelf (misshelve)
	if near == null:
		near = copy
		if spot != null and spot.has("copies"):
			for t: Dictionary in spot.copies:
				if not t.off and t != copy:
					near = t
					break
	var T: Node = $"../Tapes"
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(T.size.x, T.size.y, T.size.z)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08)
	box.material = m
	mi.mesh = box
	mi.position = Vector3(near.p[0] + cos(near.ry) * 0.07, near.p[1] + 0.02, near.p[2] - sin(near.ry) * 0.07)
	mi.rotation = Vector3(0.0, near.ry, 0.4)
	add_child(mi)
	$"../Room".light(mi)
	strays.append({ "copy": copy, "node": mi, "at": Vector3(near.p[0], near.p[1], near.p[2]), "ry": near.ry, "near": near.k })


func stray_take(s: Dictionary) -> void:  # off the shelf and into a hand
	s.node.queue_free()
	strays.erase(s)


func grot() -> int:  # litter, overflowing bins, bags left lying about
	return messes.size() + bins.filter(func(b: Dictionary) -> bool: return b.n >= b.cap).size() + bags_down.size()


# ---- messes

func _blob(mesh: Mesh, color: Color, at: Vector3, alpha := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, m)
	mi.mesh = mesh
	mi.position = at
	return mi


func mess_add(kind: String, x: float, z: float, y := 0.0) -> void:  # messAdd
	if messes.size() >= 20:
		return
	var g := Node3D.new()
	match kind:
		"spill":
			for i in 4:
				var d := CylinderMesh.new()
				d.top_radius = 0.07 + randf() * 0.1
				d.bottom_radius = d.top_radius
				d.height = 0.001
				g.add_child(_blob(d, Color.hex(0x4a2410ff), Vector3((randf() - 0.5) * 0.25, 0.002 + i * 0.0005, (randf() - 0.5) * 0.25), 0.85))
		"puddle":
			for i in 5:
				var d := CylinderMesh.new()
				d.top_radius = 0.08 + randf() * 0.14
				d.bottom_radius = d.top_radius
				d.height = 0.001
				g.add_child(_blob(d, Color.hex(0x9fb0c2ff), Vector3((randf() - 0.5) * 0.4, 0.002 + i * 0.0005, (randf() - 0.5) * 0.4), 0.5))
		"wrapper":
			var w := BoxMesh.new()
			w.size = Vector3(0.1, 0.006, 0.05)
			g.add_child(_blob(w, Color.hex([0xd23b3bff, 0x3b7bd2ff, 0xe0b020ff].pick_random()), Vector3.ZERO))
		"popcorn":
			for i in 14:
				var k := SphereMesh.new()
				k.radius = 0.018
				k.height = 0.036
				k.radial_segments = 6
				k.rings = 3
				g.add_child(_blob(k, Color.hex(0xf6e7a8ff), Vector3((randf() - 0.5) * 0.35, 0.012, (randf() - 0.5) * 0.35)))
		"towel":
			var t := SphereMesh.new()
			t.radius = 0.035
			t.height = 0.06
			t.radial_segments = 5
			t.rings = 2
			g.add_child(_blob(t, Color.hex(0xf6f3eaff), Vector3(0, 0.03, 0)))
		"cup":
			var c := CylinderMesh.new()
			c.top_radius = 0.045
			c.bottom_radius = 0.035
			c.height = 0.14
			var mi := _blob(c, Color.hex(0xd9d9d9ff), Vector3(0, 0.045, 0))
			mi.rotation.z = PI / 2.0
			g.add_child(mi)
	g.position = Vector3(x, y + 0.005, z)
	g.rotation.y = randf() * TAU
	add_child(g)
	$"../Room".light(g)
	messes.append({ "kind": kind, "node": g, "x": x, "z": z })


func mess_clean(m: Dictionary, by := "you") -> void:  # messClean
	if by == "you":
		$"../Staff".xp("you", "con", 6.0)
	m.node.queue_free()
	messes.erase(m)
	checkout.score += 15
	hud.toast("%s up the %s (+15)" % ["Dana cleaned" if by == "dana" else "Cleaned", MESS[m.kind][0]])
	trash_add(_bin("lobby" if m.z < 28.0 else "breakroom" if m.x < 8.3 else "restroom"), 1, false)  # (it goes in the nearest bin)


# ---- the trash

func _bag_max() -> int:  # one in each hand (Strong Grip: a third hugged in front)
	return 3 if preload("res://staff.gd").has("you", "str", 5) else 2


func _bin(id: String) -> Dictionary:
	for b: Dictionary in bins:
		if b.id == id:
			return b
	return {}


func trash_add(b: Dictionary, k := 1, spill := true) -> void:  # something into a bin; a full one spills onto the floor in front of it
	if b.is_empty():
		return
	for i in k:
		if b.n < b.cap:
			b.n += 1
			if b.n == b.cap and spill:
				hud.toast("The %s is full: bag it and take it to the chute in the janitor's closet" % b.name)
		elif spill:
			mess_add("towel" if b.towels else "wrapper" if randf() < 0.6 else "cup", b.stand.x + (randf() - 0.5) * 0.7, b.stand.z + (randf() - 0.5) * 0.3)
			if not b.spilled:
				b.spilled = true
				hud.toast("The %s is overflowing onto the floor" % b.name)


func _bag_mesh(bin_id: String) -> MeshInstance3D:  # a tied-off liner: black from the lobby, white from the others
	var s := SphereMesh.new()
	s.radius = 0.17
	s.height = 0.4
	s.radial_segments = 10
	s.rings = 6
	var mi := _blob(s, Color.hex(0x1c1c1eff if bin_id == "lobby" else 0xe6e8eaff), Vector3.ZERO)
	$"../Room".light(mi)
	return mi


func _show_hands() -> void:  # hanging at your sides, one each
	for c in _hands.get_children():
		c.queue_free()
	for i in bag_carry.size():
		var mi := _bag_mesh(bag_carry[i].bin)
		mi.position = Vector3(0.36 if i == 0 else -0.36, -0.62, -0.45)
		_hands.add_child(mi)


func _bag_place(bin_id: String, n: int, x: float, z: float) -> void:  # a bag on the floor
	var mi := _bag_mesh(bin_id)
	mi.position = Vector3(x, player.global_position.y + 0.2 if absf(player.global_position.x - x) < 1.0 and absf(player.global_position.z - z) < 1.0 else 0.2, z)
	add_child(mi)
	bags_down.append({ "bin": bin_id, "n": n, "node": mi, "x": x, "z": z })


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and not bag_carry.is_empty():  # right-click: at your feet, either side
		for i in bag_carry.size():
			var side := 0.22 if i == 0 else -0.22
			_bag_place(bag_carry[i].bin, bag_carry[i].n, player.global_position.x + cos(player.rotation.y) * side, player.global_position.z - sin(player.rotation.y) * side)
		bag_carry.clear()
		_show_hands()
		get_viewport().set_input_as_handled()


# ---- the day's trash, the tool in hand

func _process(dt: float) -> void:
	_t += dt
	if Clock.h < Clock.CLOSE:  # the customers' through the lobby bin, the staff's lunches, paper towels
		var in_store: int = shoppers.custs.size()
		var rate := { "lobby": 0.9 * in_store, "breakroom": 0.4, "restroom": 0.08 * in_store, "counter": 0.1 }
		for b: Dictionary in bins:
			b.acc += dt / Clock.HOUR * rate.get(b.id, 0.0)
			if b.acc >= 1.0:
				b.acc -= 1.0
				trash_add(b)
	for k: Dictionary in shoppers.custs:  # now and then somebody drops something
		k.litter_t = k.get("litter_t", (15.0 + randf() * 60.0) if randf() < 0.15 else INF) - dt
		if k.litter_t <= 0.0 and not k.path.is_empty() and not k.state in ["leave", "outside", "arrive"]:
			k.litter_t = INF
			var r := randf()
			mess_add("wrapper" if r < 0.5 else "popcorn" if r < 0.8 else "spill", k.c.position.x, k.c.position.z)
	if tool_held != "":  # out in front of you, a bit to the right; working a mess over, side to side
		var fwd := -player.global_basis.z
		var right := player.global_basis.x
		var sway := sin(_scrub.t * TAU / 0.8) * 0.26 if _scrub != null else 0.0
		_carried.global_position = player.global_position + fwd * 0.6 + right * (0.14 + sway)
		_carried.rotation.y = player.rotation.y
		_carried.visible = player.seat == null
	if _scrub != null:
		_scrub.t += dt
		if not messes.has(_scrub.m) or tool_held == "":
			_scrub = null  # (somebody beat you to it)
		elif _scrub.t >= _scrub.dur:
			mess_clean(_scrub.m)
			_scrub = null


func tool_take(id: String) -> void:  # toolTake
	var t: Dictionary = tools[id]
	tool_held = id
	for c in _carried.get_children():
		c.queue_free()
	for mi: MeshInstance3D in t.nodes:
		var c: MeshInstance3D = mi.duplicate()
		for body in c.find_children("*", "CollisionObject3D", true, false):
			body.free()  # (in your hands it doesn't bump into things)
		_carried.add_child(c)
		c.global_transform = Transform3D(mi.global_basis, mi.global_position - Vector3(t.home.x, 0.0, t.home.z))  # upright, as it stood
		mi.visible = false


func tool_return() -> void:  # toolReturn
	for mi: MeshInstance3D in tools[tool_held].nodes:
		mi.visible = true
	for c in _carried.get_children():
		c.queue_free()
	tool_held = ""
	_scrub = null


# ---- the crosshair on any of it (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = {}
	if not hit or hit_d > 2.4:
		return ""
	var at: Vector3 = hit.position
	for s: Dictionary in strays:  # a misshelved tape sticks out in front of the row
		if at.distance_to(s.node.position) < 0.16:
			aim = { "stray": s }
			return "E — pull out %s\nmisshelved: it goes back in its own slot" % s.copy.t
	for m: Dictionary in messes:
		if Vector2(at.x - m.x, at.z - m.z).length() < 0.3 and absf(at.y - m.node.position.y) < 0.3:
			aim = { "mess": m }
			var need: String = MESS[m.kind][1]
			if need != "" and tool_held != need:
				return "The %s\nneeds the %s · janitor's closet" % [MESS[m.kind][0], tools[need].label]
			return "E — clean up the %s%s" % [MESS[m.kind][0], " with the %s" % tools[need].label if need != "" else ""]
	for id: String in tools:
		if AABB(tools[id].home - tools[id].size / 2.0, tools[id].size).grow(0.08).has_point(at) and (tool_held == "" or tool_held == id):
			aim = { "tool": id }
			return "E — put the %s back" % tools[id].label if tool_held == id else "E — take the %s" % tools[id].label
	for g: Dictionary in bags_down:
		if at.distance_to(g.node.global_position) < 0.4:
			aim = { "bag": g }
			return "E — pick up the bag"
	if at.distance_to(_chute) < 0.5:
		aim = { "chute": true }
		return "E — %s down the chute" % ("a bag" if bag_carry.size() == 1 else "%d bags" % bag_carry.size()) if not bag_carry.is_empty() else "The trash chute"
	for b: Dictionary in bins:
		if Vector2(at.x - b.x, at.z - b.z).length() < b.r + 0.2 and at.y < b.rimY + 0.35:
			aim = { "bin": b }
			return "E — dig through the %s" % b.name if $"../Shift".mode == "customer" else "E — tie off the bag · the %s (%d of %d)" % [b.name, b.n, b.cap]
	return ""


func on_e() -> bool:
	if aim.is_empty():
		return false
	if aim.has("stray"):
		if $"../Tapes".inv_make_room():
			stray_take(aim.stray)
			aim.stray.copy.stray_fix = true
			$"../Tapes"._take(aim.stray.copy)
			checkout.score += 5
		else:
			hud.toast("Hands full")
		return true
	if aim.has("mess"):
		var m: Dictionary = aim.mess
		var need: String = MESS[m.kind][1]
		if need != "" and tool_held != need:
			hud.toast("That needs the %s: it's in the janitor's closet" % tools[need].label)
		elif need != "":  # the mop / sweeper: worked over, cleaned at the end
			if _scrub == null:
				_scrub = { "m": m, "t": 0.0, "dur": 2.4 if tool_held == "mop" else 2.1 }
		else:
			mess_clean(m)
			if preload("res://staff.gd").has("you", "con", 10):  # Neat Freak: sweep up around it too
				for o: Dictionary in messes.filter(func(o: Dictionary) -> bool: return MESS[o.kind][1] in ["", tool_held] and Vector2(o.x - m.x, o.z - m.z).length() < 3.0):
					mess_clean(o)
	elif aim.has("tool"):
		if tool_held == aim.tool:
			tool_return()
		elif not bag_carry.is_empty():
			hud.toast("Your hands are full")
		else:
			tool_take(aim.tool)
	elif aim.has("bin"):  # binBag
		var b: Dictionary = aim.bin
		var sn: Node = $"../Snacks"
		if sn.held != null and sn.held.left <= 0:  # an empty: in it goes
			sn.held = null
			trash_add(b)
			return true
		if $"../Shift".mode == "customer":  # (a customer digs through it)
			$"../Trail".search_bin(b)
			return true
		if b.n == 0:
			hud.toast("The %s is empty" % b.name)
		elif bag_carry.size() >= _bag_max() or tool_held != "":
			hud.toast("Hands full: take these to the chute first" if tool_held == "" else "Put the %s back first" % tools[tool_held].label)
		else:
			bag_carry.append({ "bin": b.id, "n": b.n })  # the bag out, and a fresh liner in
			b.n = 0
			b.acc = 0.0
			b.spilled = false
			checkout.score += 5
			$"../Staff".xp("you", "con", 3.0)
			_show_hands()
	elif aim.has("bag"):  # bagPickUp
		if bag_carry.size() >= _bag_max():
			hud.toast("Hands full")
		else:
			aim.bag.node.queue_free()
			bags_down.erase(aim.bag)
			bag_carry.append({ "bin": aim.bag.bin, "n": aim.bag.n })
			_show_hands()
	elif aim.has("chute") and not bag_carry.is_empty():  # chuteDrop
		var n := bag_carry.size()
		bag_carry.clear()
		_show_hands()
		checkout.score += 10 * n
		$"../Staff".xp("you", "str", 3.0 * n)
		$"../Staff".xp("you", "con", 2.0 * n)
		hud.toast("Took %s of trash down the chute (+%d)" % ["a bag" if n == 1 else "%d bags" % n, 10 * n])
	return true


# ---- for the save

func snapshot() -> Dictionary:
	var fill := {}
	for b: Dictionary in bins:
		fill[b.id] = b.n
	return { "strays": strays.map(func(s: Dictionary) -> Array: return [s.copy.k, s.near]), "messes": messes.map(func(m: Dictionary) -> Array: return [m.kind, m.x, m.z]), "bins": fill,
		"bags": (bags_down + bag_carry.map(func(g: Dictionary) -> Dictionary: return { "bin": g.bin, "n": g.n, "x": player.global_position.x, "z": player.global_position.z })).map(func(g: Dictionary) -> Array: return [g.bin, g.n, g.x, g.z]) }


func restore(d: Dictionary) -> void:
	var by := {}
	for t: Dictionary in $"../Tapes".tapes:
		by[t.k] = t
	for s: Array in d.get("strays", []):
		if by.has(s[0]) and by.has(s[1]):
			$"../Tapes".set_on_shelf(by[s[0]], false)
			misshelve(by[s[0]], null, by[s[1]])
	for m: Array in d.get("messes", []):
		mess_add(m[0], m[1], m[2])
	for b: Dictionary in bins:
		b.n = int(d.get("bins", {}).get(b.id, b.n))
	for g: Array in d.get("bags", []):
		_bag_place(g[0], int(g[1]), g[2], g[3])
