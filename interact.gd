extends Node
## E on things: the doors and the seats, worked the way the web game works them. What there is to use, and its numbers
## (each door's hinge and swing, the floor it sweeps; every seat), comes from the web game itself, in
## data/interact.json (its tests/export-glb.mjs --data writes it).
## From the web game: store/main.js (hinged doors easing open), store/player.js (toggleDoor, pushDoorTick, playerIn),
## store/shoppers.js (frontDoorTick), store/tv.js (onE: sitting down, standing up), store/checkout.js (how near you
## have to be: 2.4 m for a door, 3.2 for a seat; the words of the tips).
## Different here: the front door opens for you (in the web game, only for customers), and a seat is whichever's
## nearest where the crosshair lands (the web game marks the meshes you sit on; the level here doesn't carry that).

const DOOR_W := 1.1
const PLAYER_R := 0.32

var doors: Array[Dictionary] = []
var seats: Array = []
var front := {}
var no_collide: Array[Node] = []  # what you walk through: push doors, the storefront's doors (see main.gd)
var aim_door = null
var aim_seat = null
var stood_at := {}
var _hold := -1.0  # how long E's been held on something that lifts (-1: it isn't)

@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var hud: CanvasLayer = $"../HUD"
@onready var tapes: Node = $"../Tapes"
@onready var fixtures: Node = $"../Fixtures"
@onready var things: Node = $"../Things"
@onready var shoppers: Node = $"../Shoppers"
@onready var checkout: Node = $"../Checkout"


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	seats = data.seats
	var pivots := {}  # every group in the level, by where it stands: a door's pivot is the one at its hinge
	for n: Node3D in $"../World".find_children("*", "Node3D", true, false):
		if n.get_child_count() and not n is MeshInstance3D:
			pivots[_key(n.global_position.x, n.global_position.z)] = n
	for d: Dictionary in data.doors:
		var pivot: Node3D = pivots.get(_key(d.x, d.z))
		if pivot == null:
			push_warning("no door at %s, %s in the level (moved, or deleted?)" % [d.x, d.z])
			continue
		d.merge({ "pivot": pivot, "a": 0.0, "v": 0.0, "side": 0, "open": false, "rattle": 0.0 })
		doors.append(d)
		if d.push and not d.locked:  # a push door never blocks: it gets out of your way (chained shut, it does)
			no_collide.append(pivot)
	for n: Node3D in $"../World".find_children("door_front*", "Node3D", true, false):
		no_collide.append(n)
		if absf(n.global_position.x - data.frontDoor.x) < 0.05:  # the right leaf: the one that opens
			front = data.frontDoor
			front.merge({ "leaf": n, "k": 0.0, "open": false, "hold": 0.0 })


func _key(x: float, z: float) -> String:
	return "%.2f,%.2f" % [x, z]


func _process(dt: float) -> void:
	for d in doors:
		if d.push:
			_push_door(d, dt)
			continue
		d.a += ((d.openA if d.open else 0.0) - d.a) * minf(1.0, dt * 5.0)  # doors ease open and closed; a locked one rattles briefly when tried
		d.rattle = maxf(0.0, d.rattle - dt)
		if d.get("closing", false) and absf(d.a) < 0.04:  # (the thump comes when it meets the frame)
			d.closing = false
			$"../Ambience".door("wood", "close", _door_at(d))
		d.pivot.rotation.y = d.base + d.a + (0.012 * sin(d.rattle * 70.0) if d.rattle > 0.0 else 0.0)
	_front_door(dt)
	if _hold >= 0.0:
		_hold += dt
		if _hold >= things.HOLD:
			_hold = -1.0
			if fixtures.holdable():
				fixtures.hold_done()
			else:
				things.pick_up()


func _physics_process(_dt: float) -> void:
	_aim()


func _push_door(d: Dictionary, dt: float) -> void:  # whoever's in the doorway swings it away from the side they came in on; then it springs shut, swinging past center a few times
	if d.locked:
		return
	dt = minf(dt, 0.05)
	var p := player.global_position
	var along: float = (p.x if d.alongX else p.z) - d.c
	var across: float = (p.z if d.alongX else p.x) - d.at
	if absf(along) < DOOR_W / 2.0 + 0.2 and absf(across) < 0.8 and absf(p.y) < 2.2:
		if d.side == 0:
			d.side = -1 if across > 0.0 else 1  # opens away from you; holds that way until the doorway's clear
			if absf(d.a) < 0.15:
				$"../Ambience".door("push", "open", _door_at(d))
	else:
		d.side = 0
	var target: float = PI / 2.0 * 0.95 * d.hinge * (d.side if d.alongX else -d.side) if d.side else 0.0
	d.v += ((90.0 if d.side else 30.0) * (target - d.a) - (16.0 if d.side else 2.2) * d.v) * dt  # pushed: quick and firm; let go: a loose spring
	d.a += d.v * dt
	if absf(d.v) > 0.4:
		d.moving = true
	if d.side == 0 and absf(d.a) < 0.002 and absf(d.v) < 0.01:
		d.a = 0.0
		d.v = 0.0
		if d.get("moving", false):
			d.moving = false
			$"../Ambience".door("push", "settle", _door_at(d))
	d.pivot.rotation.y = d.base + d.a


func _front_door(dt: float) -> void:  # anyone right at the door: it swings open; then the closer pulls it shut
	if front.is_empty():
		return
	var p := player.global_position
	var near: bool = Vector2(p.x - front.near.x, p.z - front.near.z).length() < front.near.r and p.y < 2.5 and not things.locked or shoppers.at_the_door()
	if near:
		if not front.open:  # (the chime rings)
			$"../Ambience".door("push", "open", Vector3(0.9, 1.1, 0.1))
			$"../Ambience".chime(Vector3(shoppers._door.x, 2.3, 0.2))
		front.open = true
		front.hold = 0.7
	elif front.open:
		front.hold -= dt
		if front.hold <= 0.0:
			front.open = false
	var was: float = front.k
	front.k = clampf(front.k + (2.2 if front.open else -1.3) * dt, 0.0, 1.0)
	if was > 0.0 and front.k == 0.0:
		$"../Ambience".door("push", "settle", Vector3(0.9, 1.1, 0.1))
	front.leaf.rotation.y = front.openA * (1.0 - pow(1.0 - front.k, 2.0))


func _aim() -> void:  # what the crosshair's on, and what E would do about it
	aim_door = null
	aim_seat = null
	fixtures.aim = ""
	$"../Chores".aim = {}
	if player.climb != null:
		tapes.clear_aim()
		hud.tip("")
		return
	things.lifting = _hold >= 0.0
	if things.on_stool:
		tapes.clear_aim()
		hud.tip("Press E to spin · tap it fast to spin harder · WASD to get up")
		return
	if player.seat != null:
		tapes.clear_aim()
		hud.tip("Press E to stand up (and pull your pants up)" if player.seat.kind == "toilet" else "Press E to stand up")
		return
	if player.fly:
		tapes.clear_aim()
		hud.tip("")
		return
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.2)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var hit_d: float = from.distance_to(hit.position) if hit else INF
	if hit and hit_d < 2.4:
		var n: Node = hit.collider
		while n and aim_door == null:
			for d in doors:
				if d.pivot == n and not d.push:
					aim_door = d
			n = n.get_parent()
	if aim_door != null:
		tapes.clear_aim()
		hud.tip("Locked" if aim_door.locked else "E — %s the door" % ("close" if aim_door.open else "open"))
		return
	var cust_tip: String = shoppers.take_aim(from, dir, hit_d)  # a customer (see shoppers.gd)
	if cust_tip != "" and not things.carrying:
		tapes.clear_aim()
		hud.tip(cust_tip)
		return
	shoppers.aim = null
	var till_tip: String = checkout.take_aim(hit, hit_d)  # the register, the pad, the printer (see checkout.gd)
	if till_tip != "" and not things.carrying:
		tapes.clear_aim()
		hud.tip(till_tip)
		return
	checkout.aim = ""
	var thing_tip: String = things.take_aim(from, dir, hit, hit_d)  # the stool, the standee, the cooler, the deadbolt... (see things.gd)
	if thing_tip != "":
		tapes.clear_aim()
		hud.tip(thing_tip)
		return
	var fix_tip: String = fixtures.take_aim(from, dir, hit, hit_d)  # the flap, switches, lamps, ladders (see fixtures.gd)
	if fix_tip != "":
		tapes.clear_aim()
		hud.tip(fix_tip)
		return
	var home_tip: String = $"../Shift".take_aim(hit, hit_d)  # the front doors, near close: the way home (see shift.gd)
	if home_tip != "" and not things.carrying:
		tapes.clear_aim()
		hud.tip(home_tip)
		return
	$"../Shift".aim = false
	var chore_tip: String = $"../Chores".take_aim(hit, hit_d)  # a mess, the mop, a bin, the chute (see chores.gd)
	if chore_tip != "" and not things.carrying:
		tapes.clear_aim()
		hud.tip(chore_tip)
		return
	$"../Chores".aim = {}
	var tape_tip: String = tapes.aim(from, dir, hit, hit_d)  # tapes, your tape's slot, a screen (see tapes.gd)
	if tape_tip != "":
		hud.tip(tape_tip)
		return
	if hit:  # a seat: the nearest one to where the crosshair lands, if that's on it or right by it
		var best := 0.8
		for s: Dictionary in seats:
			var off: float = hit.position.distance_to(Vector3(s.x, s.y + s.hipY, s.z))
			if off < best:
				best = off
				aim_seat = s
	if aim_seat != null:
		hud.tip("Press E to sit on the toilet" if aim_seat.kind == "toilet" else "Press E to sit on the couch" if aim_seat.kind == "couch" else "Press E to take a seat")
	else:
		hud.tip("Holding %s%s" % [tapes.held.t, "" if tapes.is_rewound(tapes.held) else " · not rewound"] if tapes.held != null else "")


func _unhandled_input(e: InputEvent) -> void:
	if not e is InputEventKey or e.echo or e.physical_keycode != KEY_E:
		return
	if e.pressed:
		if things.holdable() or fixtures.holdable():
			_hold = 0.0  # a tap does one thing, a hold lifts it: wait and see which
		else:
			on_e()
	elif _hold >= 0.0:
		_hold = -1.0
		on_e()


func on_e() -> void:
	if things.on_e_first():
		return
	if player.seat != null:  # E always stands you up
		player.stand(stood_at.at, stood_at.yaw)
	elif aim_door != null:
		toggle_door(aim_door)
	elif shoppers.on_e():
		pass
	elif checkout.on_e():
		pass
	elif things.on_e():
		pass
	elif fixtures.on_e():
		pass
	elif $"../Chores".on_e():
		pass
	elif $"../Shift".on_e():
		pass
	elif tapes.aim_rewinder:
		tapes.rewinder_use()
	elif tapes.aim_returns and tapes.held != null:
		tapes.drop_in_returns()
	elif tapes.aim_tv != null:
		tapes.vcr_use()
	elif aim_seat != null:
		stood_at = { "at": player.global_position, "yaw": player.rotation.y }
		player.sit(aim_seat)


func toggle_door(d: Dictionary) -> void:
	if d.push:
		return  # push doors aren't opened, they're walked through
	if d.locked:
		d.rattle = 0.35  # just jiggles in its frame
		$"../Ambience".door("wood", "rattle", _door_at(d))
		return
	if _player_in(d.shut if d.open else d.openBox):
		return  # you're standing where it would swing to
	d.open = not d.open
	if d.open:
		$"../Ambience".door("wood", "open", _door_at(d))
	else:
		d.closing = true


func _door_at(d: Dictionary) -> Vector3:
	return Vector3((d.shut.x0 + d.shut.x1) / 2.0, 1.05, (d.shut.z0 + d.shut.z1) / 2.0)


func _player_in(c: Dictionary) -> bool:
	var p := player.global_position
	return p.x > c.x0 - PLAYER_R and p.x < c.x1 + PLAYER_R and p.z > c.z0 - PLAYER_R and p.z < c.z1 + PLAYER_R
