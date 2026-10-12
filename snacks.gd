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
## Not over yet: taking one yourself (eating, drinking, the empties), warm drinks and the cooler's thermostat, the
## snack offer at the register, ordering more (a new store has a case of everything), Dana restocking, what a
## customer's carrying showing in their hand.

const CASE_QTY := 12
const CARRY_MAX := 9

var units: Array = []  # { n, k (a drink's kind, or ""), at, lane, lz, ly, node, out, claim }
var spots: Array = []  # in front of each fixture, where a shopper can reach it: { x, z, ry, units, drinks }
var backstock := {}  # product name -> count in the cupboards
var orders := {}  # ordered on the register, here tomorrow morning: product name -> how many
var carry: Array = []  # rack units you're carrying as stock (the unit is just its look: any empty spot of that product will take it)
var aim := {}  # { cupboard: "drinks" | "food" } | { spot: unit }

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
	if left.is_empty():
		return null
	var want: String = left.pick_random().n
	var lanes := {}
	for u: Dictionary in left:
		if u.n == want:
			lanes[u.lane] = true
	for u: Dictionary in _lanes[lanes.keys().pick_random()]:
		if not u.out and u.claim == null:
			return u
	return null


func empty_spots() -> Array:  # rack spots with nothing on them, that nobody's holding
	return units.filter(func(u: Dictionary) -> bool: return u.out and not carry.has(u) and not shoppers.custs.any(func(k: Dictionary) -> bool: return k.snacks.has(u)))


# ---- the crosshair on a cupboard or an empty spot (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = {}
	if not hit or hit_d > 2.4:
		return ""
	var at: Vector3 = hit.position
	for d: Dictionary in _doors:
		if at.distance_to(d.at) < 0.3:
			aim = { "cupboard": d.kind }
			var drinks: bool = d.kind == "drinks"
			var n := empty_spots().filter(func(u: Dictionary) -> bool: return (u.k != "") == drinks).size()
			var mine := carry.filter(func(u: Dictionary) -> bool: return (u.k != "") == drinks).size()
			return "E — grab what the %s racks are missing (%d)" % ["drink" if drinks else "snack", n] if n > 0 else "E — put the stock back" if mine > 0 else "The %s cupboard\nthe racks are full" % ("drinks" if drinks else "snacks")
	if carry.is_empty():
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
	if aim.has("spot"):  # stockPlace: out it goes, at the back of its lane
		var want: Dictionary = aim.spot
		var mine: Array = carry.filter(func(c: Dictionary) -> bool: return c.n == want.n)
		var lane: Array = _lanes[want.lane].filter(func(u: Dictionary) -> bool: return u.out)
		if mine.is_empty() or lane.is_empty():
			return true
		carry.erase(mine[0])
		set_out(lane[-1], false)
		_placed += 1
		checkout.score += 3
		if carry.is_empty():
			hud.toast("Restocked %d item%s on the racks (+%d)" % [_placed, "" if _placed == 1 else "s", 3 * _placed])
			_placed = 0
		return true
	return false


# ---- for the save

func snapshot() -> Dictionary:
	var back := backstock.duplicate()
	for u: Dictionary in carry:  # (what's in your arms: back in the cupboard)
		back[u.n] += 1
	return { "back": back, "out": range(units.size()).filter(func(i: int) -> bool: return units[i].out) }


func restore(d: Dictionary) -> void:
	for k: String in d.get("back", {}):
		if backstock.has(k):
			backstock[k] = int(d.back[k])
	for i in d.get("out", []):
		if int(i) < units.size():
			set_out.call_deferred(units[int(i)], true)  # (once the level's been looked through for them)
