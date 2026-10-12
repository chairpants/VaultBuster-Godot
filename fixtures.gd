extends Node
## The fixed things E works: the counter's pass-through, the light switches, the side lamps, and the two ladders to
## the roof (the closet's, up through the hatch; the one out back, once it's been kicked down from up there).
## From the web game: store/player.js (toggleFlap) and store/main.js (the leaf lifting, the gate swinging in),
## store/clock.js (flipSwitch), store/tv.js (setLamp), store/roof.js (roofClimb, backLadderE, backLadderDrop, the
## climb in roofTick), store/checkout.js (how near: 2.6 m for the flap and a lamp, 2.2 for a switch and a ladder
## from the ground, 2.4 from the roof; the words of the tips). Where they all are: data/interact.json.
## Different here: a tap on a switch flips its own zone (the web game's hold-E for the whole plate isn't over); the
## hatch's lid only lifts while you're on the ladder (open, you could walk into the hole); the closet's bulb has no
## pull to aim at yet; and a thing's found by where the crosshair lands near it, not by the mesh it hits.

var flap := {}
var ladders := {}
var aim := ""  # "flap" | "switch" | "lamp" | "hatch" | "back" | ""
var aim_what = null  # the switch or the lamp
var flap_open := false
var back_down := false

var _flap_pivot: Node3D
var _flap_gate: Node3D
var _lid: Node3D
var _slide: Node3D  # the back ladder's bottom half
var _slide_v := 0.0

@onready var player: CharacterBody3D = $"../Player"
@onready var lights: Node = $"../Lights"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	flap = d.flap
	ladders = d.ladders
	for n: Node3D in $"../World".find_children("*", "Node3D", true, false):
		if n is MeshInstance3D or n.get_child_count() == 0:
			continue
		var p := n.global_position
		if p.distance_to(_v(flap.pivot)) < 0.02:
			_flap_pivot = n
		elif p.distance_to(_v(flap.gate)) < 0.02:
			_flap_gate = n
		elif p.distance_to(_v(ladders.hatch.lid)) < 0.02:
			_lid = n
		elif p.distance_to(Vector3(0, ladders.back.raise, 0)) < 0.02 and n.get_child_count() >= 8:
			_slide = n
	for what in [["the counter's leaf", _flap_pivot], ["its gate", _flap_gate], ["the hatch's lid", _lid], ["the back ladder", _slide]]:
		if what[1] == null:
			push_warning("%s isn't where the web game has it in the level (moved, or deleted?)" % what[0])


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func on_roof() -> bool:
	return player.global_position.y > ladders.roofY - 0.6


func _process(dt: float) -> void:
	if _flap_pivot:
		_flap_pivot.rotation.z += ((flap.openA if flap_open else 0.0) - _flap_pivot.rotation.z) * minf(1.0, dt * 6.0)  # leaf lifts up against the wall
	if _flap_gate:
		_flap_gate.rotation.y += ((flap.gateA if flap_open else 0.0) - _flap_gate.rotation.y) * minf(1.0, dt * 5.0)  # gate swings in behind the counter
	if _lid:
		_lid.rotation.x += ((-ladders.hatch.lidA if player.climb != null and player.climb.L == ladders.hatch.climb else 0.0) - _lid.rotation.x) * minf(1.0, dt * 2.5)
	if _slide and back_down and _slide.position.y > 0.0:  # the back ladder coming down: it falls
		_slide_v += 14.0 * dt
		_slide.position.y = maxf(0.0, _slide.position.y - _slide_v * dt)


# ---- what the crosshair's on (called from interact.gd, after the doors); returns the tip, "" if it's nothing of ours

func take_aim(from: Vector3, dir: Vector3, hit: Dictionary, hit_d: float) -> String:
	aim = ""
	aim_what = null
	var roof := on_roof()
	# the ladders: the crosshair near the rungs' line (or, from up top, near where they come over the edge)
	var h: Dictionary = ladders.hatch
	var b: Dictionary = ladders.back
	if roof:
		if _near_ray(from, dir, _v(h.lid) + Vector3(0, -0.2, 0.3), 0.55, 2.4, hit_d):
			aim = "hatch"
			return "E — climb back down"
		if _near_ray(from, dir, Vector3(b.x - 0.2, ladders.roofY + 1.4, b.z), 0.5, 2.4, INF):
			aim = "back"
			return "E — climb down the back ladder" if back_down else "E — kick the ladder down\nit's latched up, out of reach from the ground"
	else:
		if _near_line(from, dir, h.x, h.z, 0.3, ladders.roofY - 0.1, 0.3, 2.2, hit_d):
			aim = "hatch"
			return "E — climb up to the roof"
		if _near_line(from, dir, b.x, b.z, 0.2, 2.8, 0.3, 2.6, hit_d):
			aim = "back"
			return "E — climb up to the roof" if back_down else "A ladder to the roof\npulled up, out of reach"
	if not hit:
		return ""
	var at: Vector3 = hit.position
	if hit_d < 2.2:  # a light switch: the rocker nearest where the crosshair lands
		var best := 0.05
		for s: Dictionary in lights.switches:
			if at.distance_to(_v(s.p)) < best:
				best = at.distance_to(_v(s.p))
				aim = "switch"
				aim_what = s
		if aim == "switch":
			return "E — turn the %s lights %s" % [lights.names[aim_what.zone], "off" if lights.zone_on[aim_what.zone] else "on"]
	if hit_d < 2.6:
		for l: Dictionary in lights.lamps:  # a lamp: its shade, or the stand under it
			if Vector2(at.x - l.at.x, at.z - l.at.z).length() < 0.4 and at.y < l.at.y + 0.4:
				aim = "lamp"
				aim_what = l
				return "E — turn lamp %s" % ("off" if l.on else "on")
		var c: Dictionary = flap.box  # the counter's pass-through: the leaf, or the gate under it
		if at.x > c.x0 - 0.05 and at.x < c.x1 + 0.05 and at.z > c.z0 - 0.12 and at.z < c.z1 + 0.12 and at.y < 2.8:
			aim = "flap"
			return "E — %s the counter pass-through" % ("close" if flap_open else "open")
	return ""


func _near_ray(from: Vector3, dir: Vector3, p: Vector3, off: float, reach: float, hit_d: float) -> bool:
	var t := (p - from).dot(dir)
	return t > 0.2 and t < reach and t < hit_d + 0.5 and (p - from - dir * t).length() < off


func _near_line(from: Vector3, dir: Vector3, x: float, z: float, y0: float, y1: float, off: float, reach: float, hit_d: float) -> bool:
	var flat := Vector2(dir.x, dir.z)  # where the ray passes the rungs' line, seen from above
	if flat.length() < 0.05:
		return false
	var t := (Vector2(x - from.x, z - from.z).dot(flat)) / flat.length_squared()
	var p := from + dir * t
	return t > 0.2 and t < reach and t < hit_d + 0.5 and Vector2(p.x - x, p.z - z).length() < off and p.y > y0 and p.y < y1


func on_e() -> bool:  # true if E was ours
	match aim:
		"flap":
			var c: Dictionary = flap.box
			var p := player.global_position
			if flap_open and p.x > c.x0 - 0.32 and p.x < c.x1 + 0.32 and p.z > c.z0 - 0.32 and p.z < c.z1 + 0.32:
				return true  # trying to close it: not while you're standing in the gap
			flap_open = not flap_open
		"switch":
			lights.flip_switch(aim_what.zone)
		"lamp":
			lights.set_lamp(aim_what, not aim_what.on)
		"hatch":
			player.start_climb(-1 if on_roof() else 1, ladders.hatch.climb, ladders)
		"back":
			if on_roof():
				if back_down:
					player.start_climb(-1, ladders.back.climb, ladders)
				else:  # kicked loose
					back_down = true
					_slide_v = 0.0
					hud.toast("You kick the latch loose. The ladder rattles down: a way back up from outside")
			elif back_down and (_slide == null or _slide.position.y == 0.0):
				player.start_climb(1, ladders.back.climb, ladders)
		_:
			return false
	return true
