extends Node
## Snacks and drinks: the candy racks and the cooler. On the way to the register a customer may pick one up (from
## the front of a lane, and the top), and it's rung up with their tapes: 99 cents for candy, $1.25 a drink. Nothing
## on the racks refills itself. Backstock lives in the stock cupboards behind the counter (drinks / snacks): E on
## one hands you what the racks are missing, up to what's in there and what you can carry; E on an empty spot on a
## rack puts one out (lanes fill from the back and the bottom).
## From the web game's store/shoppers.js (snackPrice, snackSpots, the "snack" and "snacking" states), store/main.js
## (snackLane, laneFront, laneBack) and store/checkout.js (emptySpots, stockTake, stockReturn, stockPlace). What's on
## the racks, and where the cupboards are: data/interact.json; each unit's own node in the level is found by where
## it sits.
## E on one takes it for yourself: click to eat or drink, and the empty goes in a bin.
## More's ordered on the register and is by the front doors next morning, in boxes: carry them to a cupboard and unpack.
## And popcorn, once the machine's bought: a box, a scoop, butter, salt or sugar if you like, and a handful a click.
## What's taken shows in the hand that took it: a customer's, the staff's, yours (up to your mouth for a bite).

const CASE_QTY := 12
const CARRY_MAX := 9

var units: Array = []  # { n, k (a drink's kind, or ""), at, lane, lz, ly, node, out, claim }
var spots: Array = []  # in front of each fixture, where a shopper can reach it: { x, z, ry, units, drinks }
var backstock := {}  # product name -> count in the cupboards
var orders := {}  # ordered on the register, here tomorrow morning: product name -> how many
var carry: Array = []  # rack units you're carrying as stock (the unit is just its look: any empty spot of that product will take it)
var held = null  # the one in your hand: { u, left, total, paid }
var aim := {}  # { cupboard: "drinks" | "food" } | { spot: unit } | { box: box }
var boxes: Array = []  # delivered, waiting by the door (or in your arms): { n, qty, node }
var box_carry: Array = []

var _lanes := {}  # lane -> its units, frontmost (then topmost) first
var _doors: Array = []
var _placed := 0

@onready var hud: CanvasLayer = $"../HUD"
@onready var checkout: Node = $"../Checkout"
@onready var shoppers: Node = $"../Shoppers"


func _ready() -> void:
	var T: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things
	for d: Dictionary in T.cupboards:
		_doors.append({ "kind": d.kind, "at": Vector3(d.at[0], d.at[1], d.at[2]) })
	for s: Dictionary in T.snacks:
		var u := { "n": s.n, "k": s.k, "at": Vector3(s.at[0], s.at[1], s.at[2]), "f": Vector2(s.f[0], s.f[1]), "lane": s.lane, "lz": s.lz, "ly": s.ly, "node": null, "out": false, "claim": null }
		units.append(u)
		_lanes.get_or_add(s.lane, []).append(u)
		backstock[s.n] = CASE_QTY  # a new store: a case of everything in the cupboards
	for lane: Array in _lanes.values():
		lane.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.lz > b.lz if a.lz != b.lz else a.ly > b.ly)  # (fixtures face their local +z)
	call_deferred("_find")
	_hand.rotation_order = EULER_ORDER_XYZ
	$"../Player/Camera".add_child.call_deferred(_hand)
	_thermo_build.call_deferred()


func _find() -> void:  # each unit's node in the level: the first thing (so a bottle's group, not its cap) that sits just there
	var by := {}
	for n: Node in $"../World".find_children("*", "Node3D", true, false):
		var key := Vector3i((n.global_position * 50.0).round())
		if not by.has(key):
			by[key] = n
	var found := 0
	for u: Dictionary in units:
		var key := Vector3i((u.at * 50.0).round())
		for dx in [0, -1, 1]:
			for dy in [0, -1, 1]:
				for dz in [0, -1, 1]:
					var n = by.get(key + Vector3i(dx, dy, dz))
					if u.node == null and n != null and n.global_position.distance_to(u.at) < 0.015:
						u.node = n
		found += int(u.node != null)
	print("snacks: %d of %d on the racks found in the level" % [found, units.size()])
	var groups := {}
	for u: Dictionary in units:
		var x: float = u.at.x + u.f.x * 0.75
		var z: float = u.at.z + u.f.y * 0.75
		if x < -2.25 and z < 4.5:
			continue  # behind the counter is staff only
		var key := "%d,%d" % [roundi(x / 1.5), roundi(z / 1.5)]
		if not groups.has(key):
			groups[key] = { "x": 0.0, "z": 0.0, "ry": atan2(-u.f.x, -u.f.y), "units": [], "drinks": false }
		var g: Dictionary = groups[key]
		g.x += x
		g.z += z
		g.units.append(u)
		g.drinks = g.drinks or u.k != ""
	var reach: PackedByteArray = shoppers._nav.reachable_from(shoppers._door.x, shoppers._door.y)
	for g: Dictionary in groups.values():
		g.x /= g.units.size()
		g.z /= g.units.size()
		var at: int = shoppers._nav.at(g.x, g.z)
		if at >= 0 and reach[at] == 1:
			spots.append(g)


func price(u: Dictionary) -> float:  # drinks carry a kind (Soda, Water...), candy doesn't
	return 1.25 if u.k != "" else 0.99


func set_out(u: Dictionary, out: bool) -> void:  # off the rack / back on it
	u.out = out
	if u.node != null:
		u.node.visible = not out


func pick(spot: Dictionary):  # what a shopper would grab here: a product, then a lane of it, then the front one (or null)
	var left: Array = spot.units.filter(func(u: Dictionary) -> bool: return not u.out and u.claim == null)
	var cold: Array = left.filter(func(u: Dictionary) -> bool: return u.k == "" or u.get("temp", 36.0) <= DRINK_WARM)
	if not cold.is_empty():
		left = cold  # anyone would reach past a warm can for a cold one
	if left.is_empty():
		return null
	var want: String = left.pick_random().n
	var lanes := {}
	for u: Dictionary in left:
		if u.n == want:
			lanes[u.lane] = true
	for u: Dictionary in _lanes[lanes.keys().pick_random()]:
		if left.has(u):
			return u
	return null


func holding() -> String:  # what's in your hand, for the HUD
	if popcorn != null and held == null:
		if popcorn.kind == "kernel":
			return "A piece of popcorn · click to eat"
		var how := " and ".join(PackedStringArray(popcorn.toppings.map(func(t: String) -> String: return TOPPINGS[t])))
		return "%s popcorn · %d handful%s left · click to eat" % [how.capitalize() if how != "" else "Plain", popcorn.fill, "" if popcorn.fill == 1 else "s"] if popcorn.fill > 0 else "Empty popcorn box · refill it or take it to the trash" if popcorn.used else "Empty popcorn box"
	if held == null:
		return ""
	var drink: bool = held.u.k != ""
	return "%s · %d %s%s left · click to %s" % [held.u.n.capitalize(), held.left, "sip" if drink else "bite", "" if held.left == 1 else "s", "drink" if drink else "eat"] if held.left > 0 else "Empty %s %s · take it to the trash" % [held.u.n.capitalize(), "can" if drink else "wrapper"]


# ---- in a hand: the very unit off the rack (its look, part for part), in a customer's or the staff's (person.gd's
# hold_item), or in yours: the same slot a tape sits in, up to the mouth and back for a bite or a sip (checkout.js:
# snackProxy, showSnack; main.js: the bite). And the popcorn box

const HAND_AT := Vector3(0.3, -0.28, -0.55)
const HAND_ROT := Vector3(0.05, -0.4, 0.06)

var _hand := Node3D.new()
var _hand_for = null  # what's showing in it: the unit, or "box" / "kernel"
var _bite := 0.0
var _bite_drink := false


func proxy(u: Dictionary) -> Node3D:  # a copy of one off the rack, at the size it is in the world, its middle at the origin
	if u.node == null:
		return null
	var p: Node3D = u.node.duplicate()
	p.visible = true
	p.transform = Transform3D(Basis.from_scale(u.node.global_basis.get_scale()))
	for body in p.find_children("*", "CollisionObject3D", true, false):
		body.free()
	return p


func _box_of(n: Node3D, xf: Transform3D, box: Array) -> void:  # the room its meshes take up, in its own frame
	if n is MeshInstance3D and n.mesh != null:
		var b: AABB = xf * n.get_aabb()
		box[0] = b if box[0].size == Vector3.ZERO else box[0].merge(b)
	for c in n.get_children():
		if c is Node3D:
			_box_of(c, xf * c.transform, box)


func _popcorn_box(fill: int) -> Node3D:  # the striped carton, and the popcorn heaped in it as full as it is (chores.js: popcornGroup)
	var g := Node3D.new()
	var part := func(size: Vector3, at: Vector3, color: String, round := false) -> void:
		var mi := MeshInstance3D.new()
		if round:
			mi.mesh = SphereMesh.new()
			mi.mesh.radius = size.x
			mi.mesh.height = size.y
		else:
			mi.mesh = BoxMesh.new()
			mi.mesh.size = size
		mi.mesh.material = StandardMaterial3D.new()
		mi.mesh.material.albedo_color = Color(color)
		mi.position = at
		g.add_child(mi)
	part.call(Vector3(0.09, 0.13, 0.06), Vector3.ZERO, "#f4efe6")
	for x: float in [-0.03, 0.0, 0.03]:  # red stripes, front and back
		part.call(Vector3(0.012, 0.13, 0.062), Vector3(x, 0, 0), "#c8312a")
	part.call(Vector3(0.092, 0.13, 0.012), Vector3.ZERO, "#c8312a")  # ...and down each side
	if fill > 0:  # the popcorn, heaped up past the rim when it's full
		part.call(Vector3(0.042, 0.05, 0), Vector3(0, 0.07 - (1.0 - fill / 8.0) * 0.11, 0), "#f3e2a0", true)
	return g


func _kernel() -> Node3D:  # a single piece
	var mi := MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	mi.mesh.radius = 0.012
	mi.mesh.height = 0.02
	mi.mesh.material = StandardMaterial3D.new()
	mi.mesh.material.albedo_color = Color("#f3e2a0")
	return mi


func _hand_tick(dt: float) -> void:
	var want = held.u if held != null else ("box%d" % popcorn.fill if popcorn.kind == "box" else "kernel") if popcorn != null else null  # (the box's look changes as it's eaten)
	if not is_same(want, _hand_for):
		_hand_for = want
		for c in _hand.get_children():
			c.queue_free()
		var n: Node3D = null
		if want is Dictionary:
			n = proxy(want)
			if n != null:  # (held by its middle, whatever shape it is)
				var box := [AABB()]
				_box_of(n, Transform3D(), box)
				n.position = -(n.transform.basis * box[0].get_center())
		elif want is String and want.begins_with("box"):
			n = _popcorn_box(popcorn.fill)
		elif want == "kernel":
			n = _kernel()
		if n != null:
			_hand.add_child(n)
			$"../Room".light(_hand)
	_hand.visible = _hand_for != null and $"../Tapes".held == null and not $"../Checkout"._hand.visible
	_bite = maxf(0.0, _bite - dt)
	var k := sin((1.0 - _bite / 0.4) * PI) if _bite > 0.0 else 0.0  # bite / sip: up to the mouth and back
	_hand.position = HAND_AT + Vector3(-0.22, 0.2, 0.12) * k
	_hand.rotation = HAND_ROT + Vector3((1.0 if _bite_drink else 0.35) * k, 0, 0)


func _unhandled_input(e: InputEvent) -> void:  # a click: a bite, a sip (consumeSnack); a handful (eatPopcorn)
	if _bite > 0.0:
		return
	if popcorn != null and held == null and $"../Tapes".held == null and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if popcorn.kind == "kernel":
			popcorn = null
		elif popcorn.fill > 0:
			popcorn.fill -= 1
			_bite = 0.4
			_bite_drink = false
			if popcorn.fill == 0:
				popcorn.toppings = []  # last handful: an empty box, ready for a refill
		get_viewport().set_input_as_handled()
		return
	if held == null or held.left <= 0 or $"../Tapes".held != null or not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not held.paid:  # (a customer: eaten before it's paid for goes on your tab)
		held.paid = true
		$"../Customer".tab += price(held.u)
	if held.left == held.total and held.u.k != "" and held.u.get("temp", 36.0) > DRINK_WARM:
		hud.toast("Ugh. It's warm (%d°F)" % roundi(held.u.temp))
	held.left -= 1
	_bite = 0.4
	_bite_drink = held.u.k != ""
	get_viewport().set_input_as_handled()


func empty_spots() -> Array:  # rack spots with nothing on them, that nobody's holding
	return units.filter(func(u: Dictionary) -> bool: return u.out and not carry.has(u) and not (held != null and held.u == u and held.left == held.total) and not preload("res://staff.gd").crew.any(func(e: Node) -> bool: return e._restock != null and e._restock.got.has(u)) and not shoppers.custs.any(func(k: Dictionary) -> bool: return k.snacks.has(u)))


# ---- the crosshair on a cupboard or an empty spot (called from interact.gd)

func unit_on_ray(from: Vector3, dir: Vector3, hit_d: float):  # the one on the shelf the crosshair's on (or null): by the line of sight, not where it lands (cans and bottles are too small to stop it: it lands on the shelf or the back of the case behind them)
	var best = null
	var best_t := INF
	for u: Dictionary in units:
		if u.out or u.claim != null:
			continue
		var c: Vector3 = u.at + Vector3(0, 0.07, 0)
		var t := (c - from).dot(dir)
		if t < 0.0 or t > hit_d + 0.15 or t > 2.4 or t >= best_t:
			continue
		if (c - from - dir * t).length() < 0.05:
			best = u
			best_t = t
	return best


func take_aim(hit: Dictionary, hit_d: float, from := Vector3.ZERO, dir := Vector3.ZERO) -> String:
	aim = {}
	if not hit or hit_d > 2.4:
		return ""
	var at: Vector3 = hit.position
	var part := ""
	for k: String in POP_AT:
		if at.distance_to(POP_AT[k][0]) < POP_AT[k][1] and (part == "" or k != "corn"):  # (the little things on the shelf before the big glass case)
			part = k
	if part != "" and box_carry.is_empty():
		aim = { "pop": part }
		return popcorn_step(part, false)
	for b: Dictionary in boxes:
		if not box_carry.has(b) and at.distance_to(b.node.position) < 0.3:
			aim = { "box": b }
			return "E — pick up %s ×%d%s\nunpack at a stock cupboard behind the counter" % [b.n.capitalize(), b.qty, " too" if not box_carry.is_empty() else ""]
	if not box_carry.is_empty():  # arms full of boxes: a stock cupboard, or another box
		for d: Dictionary in _doors:
			if at.distance_to(d.at) < 0.3:
				aim = { "cupboard": d.kind }
				return "E — unpack %s" % ("the box" if box_carry.size() == 1 else "all %d boxes" % box_carry.size())
		return "Carrying %d box%s · unpack at a stock cupboard behind the counter" % [box_carry.size(), "" if box_carry.size() == 1 else "es"]
	for d: Dictionary in _doors:
		if at.distance_to(d.at) < 0.3:
			aim = { "cupboard": d.kind }
			var drinks: bool = d.kind == "drinks"
			var n := empty_spots().filter(func(u: Dictionary) -> bool: return (u.k != "") == drinks).size()
			var mine := carry.filter(func(u: Dictionary) -> bool: return (u.k != "") == drinks).size()
			return "E — grab what the %s racks are missing (%d)" % ["drink" if drinks else "snack", n] if n > 0 else "E — put the stock back" if mine > 0 else "The %s cupboard\nthe racks are full" % ("drinks" if drinks else "snacks")
	if held != null and held.left == held.total and at.distance_to(held.u.at) < 0.16:  # its own empty spot: back it goes
		aim = { "putback": true }
		return "E — put the %s back" % held.u.n.capitalize()
	if carry.is_empty():  # one for yourself (another, with one in hand: that one goes in its slot)
		var near = unit_on_ray(from, dir, hit_d) if dir != Vector3.ZERO else null
		for u: Dictionary in ([] if near != null else units):
			if not u.out and u.claim == null and at.distance_to(u.at) < (0.1 if near == null else at.distance_to(near.at)):
				near = u
		if near != null:
			aim = { "take": near }
			return "E — take the %s ($%.2f)%s" % [near.n.capitalize(), price(near), " · %d°F" % roundi(near.get("temp", 36.0)) if near.k != "" else ""]  # (each drink's its own temperature: a fresh one's warm for a while)
		return ""
	var best = null
	for u: Dictionary in units:
		if u.out and at.distance_to(u.at) < (0.15 if best == null else at.distance_to(best.at)) and carry.any(func(c: Dictionary) -> bool: return c.n == u.n):
			best = u
	if best == null:
		return "Carrying stock: %s" % ", ".join(_count(carry))
	aim = { "spot": best }
	return "E — put out the %s" % best.n.capitalize()


func _count(us: Array) -> Array:
	var by := {}
	for u: Dictionary in us:
		by[u.n] = by.get(u.n, 0) + 1
	return by.keys().map(func(k: String) -> String: return "%d %s" % [by[k], k.capitalize()])


func on_e() -> bool:
	if aim.has("pop"):
		popcorn_step(aim.pop, true)
		return true
	if aim.has("box") or not box_carry.is_empty():
		_box_e()
		return true
	if aim.has("cupboard"):  # stockTake
		var drinks: bool = aim.cupboard == "drinks"
		var need := empty_spots().filter(func(u: Dictionary) -> bool: return (u.k != "") == drinks)
		if need.is_empty():  # nothing to grab for: whatever you're carrying goes back
			var back := carry.filter(func(u: Dictionary) -> bool: return (u.k != "") == drinks)
			for u: Dictionary in back:
				carry.erase(u)
				backstock[u.n] += 1
			hud.toast("Put back %d in the %s cupboard" % [back.size(), "drink" if drinks else "snack"] if not back.is_empty() else "The %s racks are full" % ("drink" if drinks else "snack"))
			return true
		var got := 0
		var out := {}
		for u: Dictionary in need:
			if backstock[u.n] <= 0:
				out[u.n] = true
			elif carry.size() < CARRY_MAX:
				backstock[u.n] -= 1
				carry.append(u)
				got += 1
		hud.toast("Grabbed %d to restock%s%s" % [got, " (hands full: come back for the rest)" if got < need.size() - out.size() else "", " · out of %s" % ", ".join(out.keys().slice(0, 2)) if not out.is_empty() else ""] if got > 0 else "Out of stock")
		return true
	if aim.has("take"):
		var u: Dictionary = aim.take
		if not $"../Tapes".inv_make_room():
			hud.toast("Your hands are full: 9 is all you can carry")
			return true
		set_out(u, true)
		var n := 8 if u.k != "" else 4
		held = { "u": u, "left": n, "total": n, "paid": $"../Shift".mode != "customer" }
		return true
	if aim.has("putback"):
		set_out(held.u, false)
		held = null
		return true
	if aim.has("spot"):  # stockPlace: out it goes, at the back of its lane
		var want: Dictionary = aim.spot
		var mine: Array = carry.filter(func(c: Dictionary) -> bool: return c.n == want.n)
		var lane: Array = _lanes[want.lane].filter(func(u: Dictionary) -> bool: return u.out)
		if mine.is_empty() or lane.is_empty():
			return true
		carry.erase(mine[0])
		set_out(lane[-1], false)
		if want.k != "":
			lane[-1].temp = ROOM_F  # straight from the cupboard: it'll need a while in the cooler
		_placed += 1
		checkout.score += 3
		if carry.is_empty():
			hud.toast("Restocked %d item%s on the racks (+%d)" % [_placed, "" if _placed == 1 else "s", 3 * _placed])
			_placed = 0
		return true
	return false


# ---- drink temperature: the cooler's air climbs toward room temperature while its door's open and comes back down
# (slowly) once it's shut; each drink on the rack follows the air, a few minutes behind. Fresh stock goes in warm. A
# customer who gets a warm one when there wasn't a cold one to be had isn't happy (lobby.js: coolerThermo; checkout.js:
# drinkTempTick, custWarmDrink)

const DRINK_WARM := 45.0
const ROOM_F := 70.0

var air := 36.0  # °F in the cooler
var _temp_t := 0.0
var _warned := false


var _thermo: Label3D  # the cooler's own little LCD, top corner behind the glass: the case's air, as it reads now
var _thermo_shown := -999


func _thermo_build() -> void:  # over the level's (which only ever says what it said when it was exported)
	var hit: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.cooler.hit
	for m: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		var size := m.get_aabb().size
		if absf(size.x - 0.066) < 0.004 and absf(size.y - 0.03) < 0.004 and size.z < 0.004 and m.global_position.distance_to(Vector3(hit[0], 1.9, hit[2])) < 1.6 and m.global_position.y > 1.5:
			var lcd := MeshInstance3D.new()
			lcd.mesh = QuadMesh.new()
			lcd.mesh.size = Vector2(0.066, 0.03)
			lcd.mesh.material = StandardMaterial3D.new()
			lcd.mesh.material.albedo_color = Color("#9fb89a")
			lcd.mesh.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lcd.position = Vector3(0, 0, 0.0006)
			m.add_child(lcd)
			_thermo = Label3D.new()
			var font := SystemFont.new()
			font.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
			font.font_weight = 700
			_thermo.font = font
			_thermo.font_size = 56
			_thermo.pixel_size = 0.00038
			_thermo.outline_size = 0
			_thermo.modulate = Color("#1d2a1c")
			_thermo.position = Vector3(0, 0, 0.001)
			lcd.add_child(_thermo)
	if _thermo == null:
		push_warning("the cooler's thermometer isn't where the web game has it: the temperature's only in the door's tip")


func _process(dt: float) -> void:
	_hand_tick(dt)
	if _thermo != null and roundi(air) != _thermo_shown:
		_thermo_shown = roundi(air)
		_thermo.text = "%d°F" % _thermo_shown
	var open: bool = $"../Things".cooler_open
	var quick: bool = $"../Shift".upg.get("compressor", false)  # (a better compressor: slower to warm, quicker back down)
	air += ((66.0 if open else 36.0) - air) * minf(1.0, dt * ((0.012 if quick else 0.02) if open else (0.03 if quick else 0.012)))
	_temp_t += dt
	if _temp_t < 0.5:
		return
	var k := minf(1.0, _temp_t / 150.0)  # a can takes a few minutes to follow the air
	_temp_t = 0.0
	for u: Dictionary in units:
		if u.k != "" and not u.out:
			u.temp = u.get("temp", 36.0) + (air - u.get("temp", 36.0)) * k
	if air > 42.0 and not _warned:
		_warned = true
		hud.toast("The cooler's warming up: %d°F%s" % [roundi(air), ", and the door's open" if open else ""])
	elif air < 38.0:
		_warned = false


func any_warm() -> bool:
	return units.any(func(u: Dictionary) -> bool: return u.k != "" and not u.out and u.get("temp", 36.0) > DRINK_WARM)


func warm_check(cust: Dictionary, u: Dictionary) -> void:  # what they took off the rack: warm only counts against you if there wasn't a cold one
	if u.k == "" or u.get("temp", 36.0) <= DRINK_WARM or units.any(func(o: Dictionary) -> bool: return o.k != "" and not o.out and o.get("temp", 36.0) <= DRINK_WARM):
		return
	checkout.score -= 10
	shoppers.members.loyal(cust.member, -3)
	cust.c.set_mood("meh")
	cust.hi = 1.8
	hud.toast("%s grabbed a warm %s (%d°F) (-10)" % [cust.name, u.n.capitalize(), roundi(u.temp)])


# ---- popcorn: box -> scoop -> toppings (optional) -> eat. The machine's against the wall by the lounge once it's
# bought (chores.js: popcornStep, eatPopcorn, TOPPINGS; where its parts are: lobby.js, worked out from its place())

const POP_AT := { "corn": [Vector3(-7.40, 1.16, 6.75), 0.42], "boxes": [Vector3(-7.50, 0.92, 7.15), 0.1], "salt": [Vector3(-7.30, 0.85, 7.27), 0.06],
	"sugar": [Vector3(-7.29, 0.87, 7.18), 0.06], "butter": [Vector3(-7.47, 0.9, 7.28), 0.08] }  # part -> [where, how near the crosshair has to be]
const TOPPINGS := { "butter": "buttered", "salt": "salted", "sugar": "sugared" }

var popcorn = null  # in your hand: { kind: "box", fill: 0-8 handfuls, toppings: [], used } or { kind: "kernel" } (a single piece, grabbed bare-handed)


func popcorn_step(what: String, apply: bool):  # the one place the sequence's rules live: -> the tip for a part of the station; or, with apply, does the step (-> whether it did)
	var hp = popcorn
	var tip := ""
	var act := Callable()
	if not $"../Shift".owned("popcorn"):
		tip = "The popcorn machine\nnot plugged in: an upgrade on the register"
	elif hp == null and $"../Tapes".inv.size() >= $"../Tapes".INV_MAX and what in ["boxes", "corn"]:
		tip = "Hands full: 9 is all you can carry"
	elif what == "boxes":
		if hp == null:
			tip = "E — take a popcorn box"
			act = func() -> void:
				$"../Tapes".inv_make_room()
				popcorn = { "kind": "box", "fill": 0, "toppings": [], "used": false }
		else:
			tip = "Eat that piece first (click)" if hp.kind == "kernel" else "You've already got a box"
	elif what == "corn":
		if hp == null:
			tip = "E — grab a piece of popcorn"
			act = func() -> void:
				$"../Tapes".inv_make_room()
				popcorn = { "kind": "kernel" }
		elif hp.kind == "kernel":
			tip = "Eat that piece first (click)"
		elif hp.fill == 8:
			tip = "Your box is full"
		else:
			tip = "E — top it off" if hp.fill > 0 else "E — scoop popcorn"
			act = func() -> void:
				hp.fill = 8
				hp.used = true
	elif hp == null or hp.kind == "kernel":  # salt / sugar / butter
		tip = "Grab a popcorn box first"
	elif hp.fill == 0:
		tip = "Scoop some popcorn first"
	elif hp.toppings.has(what):
		tip = "Already %s" % TOPPINGS[what]
	else:
		tip = "E — add %s" % what
		act = func() -> void: hp.toppings.append(what)
	if apply and act.is_valid():
		act.call()
	return act.is_valid() if apply else tip


# ---- deliveries: yesterday's orders, as boxes just inside the doors (checkout.js: boxes, BOX_AT, boxMake, boxesLayout,
# boxDeliver, boxPick, boxUnpack). E on one and it's in your arms (three, more with STR); E on a stock cupboard unpacks them

func deliver() -> int:  # -> how many boxes came
	var n := orders.size()
	for k: String in orders:
		_box(k, orders[k])
	orders.clear()
	_boxes_layout()
	return n


func _box(product: String, qty: int) -> void:  # a brown carton, taped, with a label
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.44, 0.34, 0.34)
	body.add_child(shape)
	for part: Array in [[Vector3(0.44, 0.34, 0.34), Color.hex(0xa87a4aff), 0.0], [Vector3(0.445, 0.005, 0.06), Color.hex(0xc9a86aff), 0.171]]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.mesh.size = part[0]
		mi.mesh.material = StandardMaterial3D.new()
		mi.mesh.material.albedo_color = part[1]
		mi.position.y = part[2]
		body.add_child(mi)
	var l := Label3D.new()
	l.text = "%s ×%d" % [product.to_upper(), qty]
	l.pixel_size = 0.0012
	l.font_size = 40
	l.outline_size = 0
	l.modulate = Color.hex(0x222222ff)
	l.position = Vector3(0.0, 0.02, 0.172)
	body.add_child(l)
	add_child(body)
	boxes.append({ "n": product, "qty": qty, "node": body })


func box_spots() -> Array:  # where the delivery's stacked, for walking round: the bottom row's (x, z)s
	return boxes.filter(func(b: Dictionary) -> bool: return not box_carry.has(b) and b.node.position.y < 0.3).map(func(b: Dictionary) -> Vector2: return Vector2(b.node.position.x, b.node.position.z))


func _boxes_layout() -> void:  # stacked by the door, solid: you and the customers go round them
	var i := 0
	for b: Dictionary in boxes:
		if box_carry.has(b):
			continue
		if b.node.get_parent() != self:
			b.node.reparent(self, false)
		b.node.get_child(0).disabled = false
		b.node.scale = Vector3.ONE
		b.node.position = Vector3(-1.5 + (i % 2) * 0.5, 0.17 + (i / 10) * 0.36, 0.75 + (i / 2) % 5 * 0.5)  # just inside the doors, beside the lane
		b.node.rotation = Vector3(0.0, 0.1 * (i % 3 - 1), 0.0)
		i += 1
	for k in box_carry.size():  # carried low and to the side, stacked
		var node: Node3D = box_carry[k].node
		node.get_child(0).disabled = true
		node.reparent(get_viewport().get_camera_3d(), false)
		node.scale = Vector3.ONE * 0.75
		node.position = Vector3(0.3, -0.52 + k * 0.34 * 0.75, -0.8)
		node.rotation = Vector3.ZERO


func _box_max() -> int:  # (STR: more boxes at once; Pack Mule)
	var Staff := preload("res://staff.gd")
	return mini(6, 3 + (Staff.lv("you", "str") - 1) / 3) + (2 if Staff.has("you", "str", 10) else 0)


func _box_e() -> void:
	if aim.has("box"):  # boxPick
		if box_carry.size() >= _box_max():
			hud.toast("That's all you can carry")
		else:
			box_carry.append(aim.box)
			_boxes_layout()
	elif aim.has("cupboard"):  # boxUnpack
		for b: Dictionary in box_carry:
			backstock[b.n] = backstock.get(b.n, 0) + b.qty
			boxes.erase(b)
			b.node.queue_free()
		hud.toast("Unpacked %s into the stock cupboards (+%d)" % [", ".join(box_carry.map(func(b: Dictionary) -> String: return "%s ×%d" % [b.n.capitalize(), b.qty])), 5 * box_carry.size()])
		checkout.score += 5 * box_carry.size()
		$"../Staff".xp("you", "str", 6.0 * box_carry.size())
		box_carry.clear()


# ---- for the save

func snapshot() -> Dictionary:
	var back := backstock.duplicate()
	for u: Dictionary in carry:  # (what's in your arms: back in the cupboard)
		back[u.n] += 1
	return { "air": air, "warm": range(units.size()).filter(func(i: int) -> bool: return units[i].get("temp", 36.0) > 37.0).map(func(i: int) -> Array: return [i, units[i].temp]), "boxes": boxes.map(func(b: Dictionary) -> Array: return [b.n, b.qty]), "back": back, "out": range(units.size()).filter(func(i: int) -> bool: return units[i].out) }


func restore(d: Dictionary) -> void:
	air = d.get("air", 36.0)
	for w: Array in d.get("warm", []):
		if int(w[0]) < units.size():
			units[int(w[0])].temp = w[1]
	for b: Array in d.get("boxes", []):
		_box(b[0], int(b[1]))
	_boxes_layout()
	for k: String in d.get("back", {}):
		if backstock.has(k):
			backstock[k] = int(d.back[k])
	for i in d.get("out", []):
		if int(i) < units.size():
			set_out.call_deferred(units[int(i)], true)  # (once the level's been looked through for them)
