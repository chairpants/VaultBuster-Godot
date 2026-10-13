extends Node3D
## Moving things around the counter. The rewinders, the desensitizer and the receipt printer can be rearranged: hold E
## on one to pick it up, and a see-through copy follows your aim over the worktop (it only shows where it could
## actually sit: on the counter, behind the ledge; red if it won't fit: off the edge, or into the register, the
## post-its or another of them). The wheel turns it, a click sets it down, right-click puts it back where it was, and
## walking off puts it back too. Whatever goes by where one sits (E on it, where the staff reach, where the receipt
## comes out) follows it.
## From the web game's store/chores.js (cmove, footprint, counterItemsList, obb, obbHit, onTop, fits, ghostOf,
## moveStart, moveTick, movePlace, moveCancel, counterMoved) and store/lobby.js (COUNTER: the worktop's two runs).

const TOP := 1.08  # the worktop's height
const TOPS := [[-5.97, -1.93, 3.67, 4.19], [-2.58, -2.06, 0.13, 3.67]]  # its two runs, clear of the ledge: x0, x1, z0, z1 (the north one, the east one)
const HOLD_REACH := 2.4
const TURN := PI / 12.0  # a notch of the wheel

var items: Array = []  # { id, name, nodes (its models: a rewinder's box and its car), fp: { cx, cz, hx, hz } }
var aim = null  # the one the crosshair's on
var move = null  # the one in the air: { it, ghost, ry, spot, ok, from, shown }

var _fixed: Array = []  # the register and its keyboard, the post-its: they stay put
var _ok := StandardMaterial3D.new()
var _bad := StandardMaterial3D.new()
var _rw_off: Array = []
var _pad_off := Vector3.ZERO
var _pending := {}

@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var tapes: Node = $"../Tapes"
@onready var checkout: Node = $"../Checkout"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	for m: Array in [[_ok, Color(0.75, 0.9, 1.0, 0.42)], [_bad, Color(1.0, 0.35, 0.35, 0.38)]]:
		m[0].albedo_color = m[1]
		m[0].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m[0].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_find.call_deferred()


func _group_at(at: Vector3) -> Node3D:  # the level's group that stands just there
	var extras: Node = get_node_or_null("../World/Extras")
	for n: Node3D in $"../World".find_children("*", "Node3D", true, false):
		if not n is MeshInstance3D and not n is CollisionObject3D and n.get_child_count() > 1 and (extras == null or not extras.is_ancestor_of(n)) and n.global_position.distance_to(at) < 0.03:
			return n
	return null


func _find() -> void:  # (once tapes.gd has found the rewinders' models)
	tapes._rewinder_looks()
	var L: Dictionary = tapes._rw_looks
	for i in tapes.rewinders.size():
		var nodes: Array = ["box%d" % (i + 1), "car%d" % (i + 1)].filter(func(k: String) -> bool: return L.has(k)).map(func(k: String) -> Node3D: return L[k])
		if not nodes.is_empty():
			items.append({ "id": "rewinder%d" % i, "name": "rewinder", "nodes": nodes })
			_rw_off.append(nodes[0].global_transform.affine_inverse() * tapes.rewinders[i].at)
	for spec: Array in [["desens", "desensitizer", Vector3(-4.95, TOP, 3.92)], ["printer", "receipt printer", Vector3(-4.62, TOP, 3.958)]]:
		var g := _group_at(spec[2])
		if g != null:
			items.append({ "id": spec[0], "name": spec[1], "nodes": [g] })
			if spec[0] == "desens":
				_pad_off = g.global_transform.affine_inverse() * checkout._at.pad
	for it: Dictionary in items:
		it.fp = _footprint(it.nodes[0])
	for at: Vector3 in [Vector3(-5.45, TOP, 4.0), Vector3(-5.145, TOP, 3.77)]:
		var g := _group_at(at)
		if g != null:
			_fixed.append({ "nodes": [g], "fp": _footprint(g) })
	print("counter: %d things to rearrange (%s), %d that stay put" % [items.size(), ", ".join(items.map(func(it: Dictionary) -> String: return it.id)), _fixed.size()])
	for it: Dictionary in items:  # (a saved store's arrangement)
		if _pending.has(it.id):
			var p: Array = _pending[it.id]
			_put_at(it, p[0], p[1], p[2])


func _footprint(g: Node3D) -> Dictionary:  # its outline on the worktop, in its own frame
	var inv := g.global_transform.affine_inverse()
	var box := AABB()
	var any := false
	for m: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (inv * m.global_transform) * m.get_aabb()
		box = b if not any else box.merge(b)
		any = true
	return { "cx": box.get_center().x, "cz": box.get_center().z, "hx": box.size.x / 2.0 + 0.005, "hz": box.size.z / 2.0 + 0.005 }


func _obb(fp: Dictionary, x: float, z: float, ry: float) -> Dictionary:  # that outline placed in the world: centre, axes, half-sizes
	var c := cos(ry)
	var s := sin(ry)
	return { "x": x + fp.cx * c + fp.cz * s, "z": z - fp.cx * s + fp.cz * c, "ux": Vector2(c, -s), "uz": Vector2(s, c), "hx": fp.hx, "hz": fp.hz }


func _obb_of(it: Dictionary) -> Dictionary:
	var g: Node3D = it.nodes[0]
	return _obb(it.fp, g.global_position.x, g.global_position.z, g.global_rotation.y)


func _hit(a: Dictionary, b: Dictionary) -> bool:  # separating axis test, in plan
	var d := Vector2(b.x - a.x, b.z - a.z)
	for ax: Vector2 in [a.ux, a.uz, b.ux, b.uz]:
		var ra: float = a.hx * absf(a.ux.dot(ax)) + a.hz * absf(a.uz.dot(ax))
		var rb: float = b.hx * absf(b.ux.dot(ax)) + b.hz * absf(b.uz.dot(ax))
		if absf(d.dot(ax)) > ra + rb:
			return false
	return true


func on_top(x: float, z: float) -> bool:
	return TOPS.any(func(t: Array) -> bool: return x >= t[0] and x <= t[1] and z >= t[2] and z <= t[3])


func _there(it: Dictionary) -> bool:  # (the second rewinder, before it's bought, isn't)
	return it.nodes.any(func(n: Node3D) -> bool: return n.visible)


func fits(it: Dictionary, x: float, z: float, ry: float) -> bool:  # all of it on the worktop, and not into anything else
	var o := _obb(it.fp, x, z, ry)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner: Vector2 = Vector2(o.x, o.z) + o.ux * o.hx * sx + o.uz * o.hz * sz
			if not on_top(corner.x, corner.y):
				return false
	return not (items.filter(func(k: Dictionary) -> bool: return k != it and _there(k)) + _fixed).any(func(k: Dictionary) -> bool: return _hit(o, _obb_of(k)))


func holdable() -> bool:  # E held on it would lift it (interact.gd asks)
	return aim != null and move == null


func moving() -> bool:
	return move != null


func tip() -> String:
	return "Aim at the counter · click sets the %s down · the wheel turns it · right-click puts it back" % move.it.name if move.spot == null else "Click — set the %s down · the wheel turns it · right-click puts it back" % move.it.name if move.ok else "It won't fit there · the wheel turns it · right-click puts it back"


func _spot():  # where the crosshair meets the worktop (or null)
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if dir.y > -0.02:
		return null
	var t := (TOP - from.y) / dir.y
	var at := from + dir * t
	return Vector2(at.x, at.z) if t > 0.0 and t < 2.6 and on_top(at.x, at.z) else null


func _process(_dt: float) -> void:
	aim = null
	if $"../Shift".mode == "customer" or player.seat != null:
		return
	if move == null:  # which of them the crosshair's on: the one whose outline it lands in
		var from := cam.global_position
		var dir := -cam.global_basis.z
		if dir.y < -0.02:
			for it: Dictionary in items.filter(_there):
				var o := _obb_of(it)
				for h: float in [0.0, 0.05, 0.1]:  # (its base, and a little up its sides)
					var t: float = (TOP + h - from.y) / dir.y
					var d: Vector2 = Vector2(from.x + dir.x * t, from.z + dir.z * t) - Vector2(o.x, o.z)
					if t > 0.0 and t < HOLD_REACH and absf(d.dot(o.ux)) <= o.hx and absf(d.dot(o.uz)) <= o.hz:
						aim = it
		return
	if Vector2(player.global_position.x - move.from.px, player.global_position.z - move.from.pz).length() > 3.0:  # moveTick
		cancel("You walked off: the %s's back where it was" % move.it.name)
		return
	move.spot = _spot()
	move.ghost.visible = move.spot != null
	if move.spot == null:
		return
	var ok := fits(move.it, move.spot.x, move.spot.y, move.ry)
	if ok != move.ok or not move.shown:
		move.ok = ok
		move.shown = true
		for m: MeshInstance3D in move.ghost.find_children("*", "MeshInstance3D", true, false):
			m.material_override = _ok if ok else _bad
	move.ghost.global_position = Vector3(move.spot.x, TOP + 0.002, move.spot.y)
	move.ghost.global_rotation = Vector3(0, move.ry, 0)


func start() -> void:  # hold E on one: up it comes (moveStart)
	var it: Dictionary = aim
	if checkout.co != null and it.id in ["desens", "printer"]:
		hud.toast("Not in the middle of a checkout")
		return
	if it.id.begins_with("rewinder") and tapes.rewinders[it.id.to_int()].tape != null:
		hud.toast("Take the tape out of it first")
		return
	var g: Node3D = it.nodes.filter(func(n: Node3D) -> bool: return n.visible)[0]
	var ghost: Node3D = g.duplicate()  # a see-through copy
	for body in ghost.find_children("*", "CollisionObject3D", true, false):
		body.free()
	add_child(ghost)
	ghost.visible = false
	move = { "it": it, "ghost": ghost, "ry": g.global_rotation.y, "spot": null, "ok": false, "shown": false, "was": g,
		"from": { "px": player.global_position.x, "pz": player.global_position.z } }
	g.visible = false


func _end() -> void:
	move.was.visible = true
	move.ghost.queue_free()
	move = null


func place() -> void:  # click: set it down, if it fits (movePlace)
	if move.spot == null:
		hud.toast("Aim at a free spot on the counter")
	elif not move.ok:
		hud.toast("It won't fit there")
	else:
		var it: Dictionary = move.it
		var at: Vector2 = move.spot
		var ry: float = move.ry
		_end()
		_put_at(it, at.x, at.y, ry)


func cancel(why := "") -> void:  # right-click / walked off: it never left (moveCancel)
	if move == null:
		return
	_end()
	if why != "":
		hud.toast(why)


func _put_at(it: Dictionary, x: float, z: float, ry: float) -> void:  # there it sits, and everything that goes by where it sits follows it (counterMoved)
	for n: Node3D in it.nodes:
		n.global_position = Vector3(x, n.global_position.y, z)
		n.global_rotation = Vector3(0, ry, 0)
	it.moved = true
	var xf: Transform3D = it.nodes[0].global_transform
	if it.id.begins_with("rewinder"):
		tapes.rewinders[it.id.to_int()].at = xf * _rw_off[it.id.to_int()]
	elif it.id == "desens":
		checkout._at.pad = xf * _pad_off
	elif it.id == "printer":
		checkout.printer_moved(xf)


func _unhandled_input(e: InputEvent) -> void:
	if move == null or not (e is InputEventMouseButton and e.pressed) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	match e.button_index:
		MOUSE_BUTTON_LEFT: place()
		MOUSE_BUTTON_RIGHT: cancel()
		MOUSE_BUTTON_WHEEL_UP: move.ry += TURN
		MOUSE_BUTTON_WHEEL_DOWN: move.ry -= TURN
	get_viewport().set_input_as_handled()  # (not a tape off the shelf, nor the next thing in your pockets)


# ---- for the save

func snapshot() -> Dictionary:
	var out := {}
	for it: Dictionary in items:
		if it.get("moved", false):
			out[it.id] = [it.nodes[0].global_position.x, it.nodes[0].global_position.z, it.nodes[0].global_rotation.y]
	return out


func restore(d: Dictionary) -> void:
	_pending = d
	for it: Dictionary in items:
		if d.has(it.id):
			_put_at(it, d[it.id][0], d[it.id][1], d[it.id][2])
