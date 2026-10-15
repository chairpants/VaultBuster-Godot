extends Node3D
## The cars: the day's few in the lot (different every day, the same all day), the ones going by on the road (one
## under every pass the ambience plays, so you see what you hear), and the ones that turn in: along the road, slowing,
## in at the driveway on its side of the lot, up its lane and nosed into a stall; leaving, backed out into the lane
## for the way it's going, down to the far driveway and off. Lamps follow the driving (brakes, reverse; headlights and
## the dim tail lights at night, and the light they throw on the pavement). They keep out of each other's way.
## From the web game's exterior/lot.js (car, STYLES, PAINT, parkLot, roadPass, driveIn, driveOut, carAhead, lotTick,
## lampSet). The models are its own, one of each style (world/cars.glb: tests/export-glb.mjs --cars), painted here.
## A car turning in is heard coming along the road as one going by is; one with somebody waiting in it idles, lit up.
## A golf ball off the roof (golf.gd) sets off an alarm, makes one going by swerve, or runs it off the road.

const LOT_Y := -0.12
const LANE := { 1: -3.3, -1: -6.3 }  # the drive's two lanes, by which way you're going along x
const ROAD := { 1: -15.45, -1: -18.75 }  # ...and the road's (right-hand traffic: eastbound nearer the store)
const CURB := -12.3
const ROAD_NEAR := -13.8
const GATE := { 1: -22.24, -1: 26.56 }  # the driveway you turn in at, coming that way (and leave by, going the other)
const NO_PARK := [0, 1, 2, 19, 20, 21]  # stalls nobody parks in: the driveways, and past them
const PARK_Z := -9.9
const ROAD_END := 35.0
const SIZES := [[4.1, 1.75], [4.1, 1.72], [4.1, 1.82], [3.8, 1.68], [4.5, 1.85], [4.2, 1.75]]  # sedan, wagon, pickup, hatchback, minivan, coupe: long, wide
# mid-90s paint, weighted roughly like the lots of the day: white most of all, then that era's hunter green and teal,
# burgundy, silver, black, navy, champagne, with the odd red, plum or dark gray
const PAINT := [0xeceae2, 0xeceae2, 0xeceae2, 0xf2efe6, 0x1f4a36, 0x1f4a36, 0x16392b, 0x2e7d7a, 0x2a8a86, 0x6a1a26, 0x5a1520, 0xb8bcc2, 0xa4a8ae, 0x1c1c1f, 0x1f2f5a, 0x2a4373, 0xcdb88e, 0xa31d1d, 0x4a2d55, 0x4a4d52]
const MOVING := ["approach", "aisle", "turnIn", "backOut", "shift", "leave"]  # (shift: stopped in the lane after backing out, still in the way)
const HEAD_POOL := Vector2(11.0, 7.0)  # out ahead of the bumper, and how wide the cones get

var parked: Array[Node3D] = []  # the day's
var movers: Array[Dictionary] = []  # going by: { g, id, vx, v0 }
var lot: Array[Dictionary] = []  # turning in, parked a while, leaving: { id, look, stall, sx, dir, phase, t, u, g, on_parked, door, path, len, e }

var _styles: Array[Node3D] = []
var _holder: Node3D
var _paints := {}
var _lit := {}  # the lamps lit: kind -> [materials by how bright]
var _pool := {}  # the light on the pavement: its meshes and materials
var _ids := 0
var _day := -1
var _traffic: Array = []  # this frame's moving cars: { g, id, back }

@onready var lights: Node = $"../Lights"

const Traffic := preload("res://traffic.gd")


func _ready() -> void:
	if not ResourceLoader.exists("res://world/cars.glb"):
		push_warning("world/cars.glb isn't there: no cars (node tests/export-glb.mjs --cars, in the web game's repo)")
		return
	_holder = load("res://world/cars.glb").instantiate()
	for s in SIZES.size():
		var g: Node3D = _holder.get_node_or_null("car%d" % s)
		if g == null:
			break
		for m: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
			if m.mesh.surface_get_material(0) != null and m.mesh.surface_get_material(0).resource_name == "paint":
				m.set_meta("paint", true)
		_styles.append(g)
	$"../Room".light(_holder)  # lit as everything else out there is
	for k: Array in [["head", [0xfff4c8]], ["tail", [0x8c140e, 0xff3a24]], ["rev", [0xffffff]]]:
		_lit[k[0]] = k[1].map(func(hex: int) -> StandardMaterial3D:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color.hex((hex << 8) | 0xff) * (1.0 if hex == 0x8c140e else 1.6)  # (what's lit up bright blooms; the dim tail lights don't)
			return m)
	_pools_build()


func _exit_tree() -> void:
	if _holder:
		_holder.free()


func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _pools_build() -> void:  # not real lights: light painted onto the pavement, additively, on a plane under the car
	var head := Image.create(256, 128, false, Image.FORMAT_L8)
	for y in 128:
		for x in 256:
			var u := (x + 0.5) / 256.0
			var v := (y + 0.5) / 128.0 * 2.0 - 1.0
			var d := u * HEAD_POOL.x
			var a := 0.0
			for lx: float in [-0.62, 0.62]:  # two cones, one per lamp, spreading and fading with distance
				var spread := 0.35 + d * 0.27
				a += 1.0 - _sstep(spread * 0.55, spread, absf(v * HEAD_POOL.y / 2.0 - lx * (1.0 + d * 0.08)))
			var k := minf(1.0, a) * _sstep(0.0, 0.8, d) * (1.0 / (1.0 + pow(d / 4.5, 2.0)) + 0.35 * exp(-pow((d - 3.0) / 2.0, 2.0))) * (1.0 - _sstep(0.85, 1.0, u))
			head.set_pixel(x, y, Color(k, k, k))
	var rear := Image.create(128, 128, false, Image.FORMAT_L8)
	for y in 128:
		for x in 128:
			var u := (x + 0.5) / 128.0
			var v := (y + 0.5) / 128.0 * 2.0 - 1.0
			var k := (1.0 - _sstep(0.15, 1.0, Vector2(u * 1.15, v * 0.75).length())) * _sstep(0.0, 0.12, u)  # a wash spreading back from the bumper
			rear.set_pixel(x, y, Color(k, k, k))
	var tex := { "head": ImageTexture.create_from_image(head), "rear": ImageTexture.create_from_image(rear) }
	for k: Array in [["head", "head", 0xffefc2, 0.75], ["brake", "rear", 0xff1c0c, 0.85], ["tail", "rear", 0xff1c0c, 0.18], ["rev", "rear", 0xfff6ea, 0.6]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = tex[k[1]]
		m.albedo_color = Color.hex((k[2] << 8) | 0xff) * k[3]
		m.disable_fog = true
		_pool[k[0]] = m


func new_look() -> Dictionary:  # carNew: a style and a colour (a member's own, kept on their record)
	return { "s": randi() % SIZES.size(), "c": PAINT.pick_random() }


func _car(x: float, z: float, yaw: float, look: Dictionary) -> Node3D:  # one of them, there: nose toward the road at yaw 0
	var g: Node3D = _styles[int(look.s) % _styles.size()].duplicate()
	var c := int(look.c)
	for m: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		if m.has_meta("paint"):
			if not _paints.has(c):
				var p: Material = m.mesh.surface_get_material(0).duplicate()
				if p is ShaderMaterial:
					p.set_shader_parameter("albedo", Color.hex((c << 8) | 0xff))
				else:
					p.albedo_color = Color.hex((c << 8) | 0xff)
				_paints[c] = p
			m.set_surface_override_material(0, _paints[c])
	var size: Array = SIZES[int(look.s) % SIZES.size()]
	var body := StaticBody3D.new()  # ponytail: a box you can't walk through, moving or not; the shape of the thing if you ever need to climb on one
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(size[0], 1.3, size[1])
	shape.position.y = 0.65
	body.add_child(shape)
	g.add_child(body)
	for p: Array in [["head", HEAD_POOL.x, HEAD_POOL.y, 1.0], ["rear", 3.4, size[1] + 2.2, -1.0], ["rev", 2.6, size[1] + 1.2, -1.0]]:  # (the nose is local +x)
		var q := MeshInstance3D.new()
		q.mesh = QuadMesh.new()
		q.mesh.size = Vector2(p[1], p[2])
		q.name = "pool_" + p[0]
		q.material_override = _pool[p[0] if p[0] != "rear" else "tail"]
		q.rotation = Vector3(-PI / 2.0, 0.0 if p[3] > 0.0 else PI, 0.0)
		q.position = Vector3(p[3] * (size[0] / 2.0 + 0.1 + p[1] / 2.0), 0.02, 0.0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.visible = false
		g.add_child(q)
	g.position = Vector3(x, LOT_Y, z)
	g.rotation.y = PI / 2.0 + yaw
	g.rotation_order = EULER_ORDER_YXZ
	g.set_meta("size", Vector2(size[0], size[1]))
	add_child(g)
	return g


# ---- what a golf ball off the roof can do to them (golf.gd): set one off, make one swerve, or run one off the road
# (lot.js: carsOut)

var _alarms: Array[Node3D] = []


func all_cars() -> Array:  # every car out there: { g, m (one going by), lot (one turning in or parked by a customer) }
	return parked.map(func(g: Node3D) -> Dictionary: return { "g": g, "m": null, "lot": null }) 		+ lot.map(func(c: Dictionary) -> Dictionary: return { "g": c.g, "m": null, "lot": c }) 		+ movers.map(func(m: Dictionary) -> Dictionary: return { "g": m.g, "m": m, "lot": null })


func size_of(g: Node3D) -> Vector2:  # (long, wide)
	return g.get_meta("size", Vector2(4.1, 1.75))


func alarm(g: Node3D) -> void:  # its lights flashing with it, ten seconds
	g.set_meta("alarm_t", 0.0)
	if not g in _alarms:
		_alarms.append(g)


func swerve(m: Dictionary, away: float) -> void:  # away: +1 toward the store, -1 away from it
	if not m.has("sw") and not m.has("crash"):
		m.sw = { "t": 0.0, "T": 1.3, "A": away * 1.1 }


func crash(m: Dictionary) -> void:  # off to its right: the lot's curb, or the grass over the road
	m.erase("sw")
	m.crash = { "st": "off", "t": 0.0, "z1": ROAD_NEAR + 0.6 if m.v0 > 0.0 else -20.4 - 0.8 }


func _alarms_tick(dt: float) -> void:
	for g in _alarms.duplicate():
		if not is_instance_valid(g):
			_alarms.erase(g)
			continue
		var t: float = g.get_meta("alarm_t", 0.0) + dt
		g.set_meta("alarm_t", t)
		var on := int(t * 2.5) % 2 == 0
		if t < 10.0:
			g.set_meta("lamps", "")  # (whatever else had them: the alarm has the say)
			lamps(g, on, 2 if on else 0)
		else:
			_alarms.erase(g)
			g.set_meta("lamps", "")
			lamps(g)


func night() -> bool:
	return lights._night_t >= 0.0


func lamps(g: Node3D, head := false, tail := 0, rev := false) -> void:  # head (on at night), tail (0 off, 1 the dim running lights, 2 the brakes), rev (in reverse)
	var dark := night()
	var key := "%d%d%d%d" % [int(head), tail, int(rev), int(dark)]
	if g.get_meta("lamps", "") == key:
		return
	g.set_meta("lamps", key)
	for m: Node in g.get_children():
		var n := String(m.name)
		if n == "pool_head":
			m.visible = dark and head
		elif n == "pool_rear":
			m.visible = dark and tail > 0
			m.material_override = _pool.brake if tail == 2 else _pool.tail
		elif n == "pool_rev":
			m.visible = dark and rev
		elif n.contains("_lamp_head_"):
			m.material_override = _lit.head[0] if head else null
		elif n.contains("_lamp_tail_"):
			m.material_override = _lit.tail[tail - 1] if tail > 0 else null
		elif n.contains("_lamp_rev_"):
			m.material_override = _lit.rev[0] if rev else null


func _running(g: Node3D, brake := false) -> void:  # just driving along
	lamps(g, night(), 2 if brake else 1 if night() else 0)


func stall_x(k: int) -> float:
	return -27.74 + 2.6 * (k + 1)


func park_lot(day: int, busy: bool) -> void:  # the lot: a few cars, more on a busy day, mostly nosed in, now and then backed in, never quite straight
	for g in parked:
		g.queue_free()
	parked = []
	_day = day
	if _styles.is_empty():
		return
	var st := [7919 * day + 13]  # (the web game's own little generator: the same lot on the same day)
	var rnd := func() -> float:
		st[0] = (st[0] * 16807) % 2147483647
		return st[0] / 2147483647.0
	var free: Array = range(22).filter(func(k: int) -> bool: return not k in NO_PARK)
	var n := 2 + int(rnd.call() * 4.0) + (2 if busy else 0)
	while n > 0 and not free.is_empty():
		n -= 1
		var k: int = free.pop_at(int(rnd.call() * free.size()))
		var back_in: bool = rnd.call() < 0.25
		var x: float = stall_x(k) + (rnd.call() - 0.5) * 0.3
		var z: float = PARK_Z + (rnd.call() - 0.5) * 0.4
		var yaw: float = (PI if back_in else 0.0) + (rnd.call() - 0.5) * 0.12
		var s := int(rnd.call() * SIZES.size())
		var g := _car(x, z, yaw, { "s": s, "c": PAINT[int(rnd.call() * PAINT.size())] })
		g.set_meta("stall", k)
		parked.append(g)


func _clear_at(x0: float, z: float, gap: float) -> bool:  # nobody already starting out there
	for o: Node3D in movers.map(func(m: Dictionary) -> Node3D: return m.g) + lot.map(func(c: Dictionary) -> Node3D: return c.g):
		if absf(o.position.z - z) < 1.5 and absf(o.position.x - x0) < gap:
			return false
	return true


func pass_by(dir: int, v: float) -> void:  # one going by on the road (roadPass)
	if _styles.is_empty():
		return
	var x0 := -dir * ROAD_END
	while not _clear_at(x0, ROAD[dir], 8.0):
		x0 -= dir * 8.0
	var g := _car(x0, ROAD[dir], -PI / 2.0 if dir > 0 else PI / 2.0, new_look())
	_ids += 1
	movers.append({ "g": g, "id": _ids, "vx": dir * v, "v0": dir * v, "z0": ROAD[dir] })
	_running(g)


func _spline(pts: Array) -> Curve2D:  # through the points, smoothly (x, z); driven along at a speed, by its length
	var c := Curve2D.new()
	c.bake_interval = 0.2
	for i in pts.size():
		var a: Vector2 = pts[maxi(0, i - 1)]
		var b: Vector2 = pts[mini(pts.size() - 1, i + 1)]
		var here: Vector2 = pts[i]
		var t := (b - a).normalized() * minf(here.distance_to(a), here.distance_to(b)) / 3.0 if a != b else Vector2.ZERO
		c.add_point(here, -t if i > 0 else Vector2.ZERO, t if i < pts.size() - 1 else Vector2.ZERO)
	return c


func _in_path(d: int, E: float, back: float) -> Curve2D:  # from the road, through the driveway, into its lane (back: start that much further off)
	var L: float = ROAD[d]
	var A: float = LANE[d]
	return _spline([Vector2(E - d * (34.0 + back), L), Vector2(E - d * 7.0, L), Vector2(E - d * 1.6, L + 0.7), Vector2(E, ROAD_NEAR), Vector2(E, CURB), Vector2(E + d * 0.8, (CURB + A) / 2.0), Vector2(E + d * 3.2, A - 0.2 * signf(A + 4.8)), Vector2(E + d * 7.0, A)])


func _out_path(e: int, X: float, x0: float) -> Curve2D:  # from its lane, out the driveway, onto the road and away
	var L: float = ROAD[e]
	var A: float = LANE[e]
	return _spline([Vector2(x0, A), Vector2(X - e * 3.5, A), Vector2(X - e * 0.8, (CURB + A) / 2.0), Vector2(X, CURB), Vector2(X, ROAD_NEAR), Vector2(X + e * 1.6, L + 0.7), Vector2(X + e * 7.0, L), Vector2(X + e * 36.0, L)])


func drive_in(look: Dictionary, on_parked: Callable, near = null):  # -> the car (where to get out: car.door), or null: no free stall. near: an x to park close to (next door's customers)
	if _styles.is_empty():
		return null
	var taken: Array = parked.map(func(g: Node3D) -> int: return g.get_meta("stall")) + lot.map(func(c: Dictionary) -> int: return c.stall)
	var free: Array = range(22).filter(func(k: int) -> bool: return not k in NO_PARK and not k in taken)
	if free.is_empty():
		return null
	if near != null:
		free.sort_custom(func(a: int, b: int) -> bool: return absf(stall_x(a) - near) < absf(stall_x(b) - near))
		free = free.slice(0, 3)
	var k: int = free.pick_random()
	var sx := stall_x(k)
	var ways: Array = [1, -1].filter(func(d: int) -> bool: return (sx - GATE[d]) * d >= 10.0)  # (a stall right by a driveway: from the other end)
	var dir: int = ways.pick_random()  # which way it's coming along the road (and up the drive)
	var back := 0.0
	while not _clear_at(GATE[dir] - dir * (34.0 + back), ROAD[dir], 9.0):  # (somebody already starting out there: further back)
		back += 9.0
	_ids += 1
	var path := _in_path(dir, GATE[dir], back)
	var p0 := path.sample_baked(0.0)
	var c := { "id": _ids, "look": look, "stall": k, "sx": sx, "dir": dir, "phase": "approach", "t": 0.0, "u": 0.0, "g": _car(p0.x, p0.y, 0.0, look), "on_parked": on_parked,
		"door": Vector2(sx - 1.2, PARK_Z), "path": path, "len": path.get_baked_length(), "e": 1, "riders": [], "k": 1.0, "v": 0.0 }  # (the driver's side: west, nosed in toward the road)
	lot.append(c)
	$"../Ambience".drive(dir, 13.0)
	return c


func drive_out(c: Dictionary) -> void:  # in and gone (or never got parked: just gone)
	if c.phase == "gone":
		return
	if c.phase != "parked":
		Traffic.gone(c.id)
		c.g.queue_free()
		lot.erase(c)
		c.phase = "gone"
		return
	c.phase = "startUp"  # started up, foot on the brake, into reverse; then whichever way they're headed
	c.t = 0.0
	c.e = 1 if randf() < 0.5 else -1


# keeping out of each other: a moving car with another moving car just ahead of it (in its path, close for its speed)
# waits. Two that'd each wait on the other: the one that came first goes. Parked cars don't count (they stay put)
func _sees(a: Dictionary, b: Dictionary, reach: float) -> bool:
	var k := -1.0 if a.back else 1.0
	var f := Vector2(cos(a.g.rotation.y) * k, -sin(a.g.rotation.y) * k)
	var d := Vector2(b.g.position.x - a.g.position.x, b.g.position.z - a.g.position.z)
	var al := d.dot(f)
	return al > 0.5 and al < reach and absf(d.x * f.y - d.y * f.x) < 1.7


func _ahead(g: Node3D, speed: float) -> bool:
	var me = null
	for t: Dictionary in _traffic:
		if t.g == g:
			me = t
	if me == null:
		return false
	var reach := maxf(7.5, 4.0 + absf(speed) * 0.85)
	for o: Dictionary in _traffic:
		if o == me:
			continue
		if _sees(me, o, reach) and not (_sees(o, me, 12.0) and me.id < o.id):
			return true
		if me.id > o.id and g.position.distance_to(o.g.position) < 1.8:  # (right on top of each other, as can happen starting out: the newer one waits)
			return true
	return false


func _steer(c: Dictionary, x: float, z: float, back := false) -> void:  # put it at x/z, pointing the way it's going (backwards: the other way)
	var d := Vector2(x - c.g.position.x, z - c.g.position.z)
	if d.length_squared() > 1e-8:
		c.g.rotation.y = atan2(d.y, -d.x) if back else atan2(-d.y, d.x)  # (the nose is the car's local +x)
	c.g.position.x = x
	c.g.position.z = z


func _along(c: Dictionary, v: float, dt: float) -> bool:  # drive c along its path at v m/s -> true at the end
	if _gas(c, v, _ahead(c.g, v), dt) < 1.0:
		lamps(c.g, night(), 2)  # (easing off for whatever's ahead: on the brake)
	c.u = minf(1.0, c.u + v * c.k * dt / c.len)
	var p: Vector2 = c.path.sample_baked(c.u * c.len)
	_steer(c, p.x, p.y)
	return c.u >= 1.0


func _gas(c: Dictionary, v: float, held: bool, dt: float, back := false) -> float:  # how much of its speed it's doing: off it to a stop for a car ahead or anybody in its road, back on once it's clear
	held = held or Traffic.blocked(c.id, back, v * c.get("k", 1.0))
	c.k = move_toward(c.get("k", 1.0), 0.0 if held else 1.0, dt * ((2.0 if v > 7.0 else 3.5) if held else 1.0))
	c.v = v * c.k * (-1.0 if back else 1.0)
	return c.k


func _bez(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a * (1.0 - t) * (1.0 - t) + b * 2.0 * t * (1.0 - t) + c * t * t


func _process(dt: float) -> void:
	if _styles.is_empty():
		return
	if Clock.day != _day:
		park_lot(Clock.day, Clock.date().weekday in [5, 6])
	_alarms_tick(dt)
	_traffic = movers.map(func(m: Dictionary) -> Dictionary: return { "g": m.g, "id": m.id, "back": false })
	for c in lot:
		if c.phase in MOVING:
			_traffic.append({ "g": c.g, "id": c.id, "back": c.phase == "backOut" })
	for m: Dictionary in movers.duplicate():  # the cars going by: braking for whoever's turning in ahead of them
		var dir := signf(m.v0)
		var p: Vector3 = m.g.position
		var vz := 0.0
		if m.has("crash"):  # off the road: braking hard onto the shoulder, sat there on its hazards, then away again
			var c: Dictionary = m.crash
			c.t += dt
			if c.st == "off":
				m.vx = dir * maxf(0.0, absf(m.vx) - 9.0 * dt)
				vz = (c.z1 - p.z) * 2.2
				if absf(m.vx) < 0.05:
					m.vx = 0.0
					c.st = "sat"
					c.t = 0.0
					m.g.rotation.z = dir * 0.025  # (up on the curb, or nose down in the grass)
			elif c.st == "sat":
				var on := int(c.t * 1.6) % 2 == 0
				lamps(m.g, night(), 2 if on else 0)  # the hazards
				if c.t > 22.0:
					c.st = "back"
					m.g.rotation.z = 0.0
			else:
				m.vx = dir * minf(absf(m.v0), absf(m.vx) + 2.5 * dt)
				vz = (m.z0 - p.z) * 1.2
				if absf(p.z - m.z0) < 0.03 and m.vx == m.v0:
					p.z = m.z0
					m.erase("crash")
		elif m.has("sw"):  # a swerve: out round it and back into the lane
			var s: Dictionary = m.sw
			s.t += dt
			var k: float = s.t / s.T
			if k >= 1.0:
				p.z = m.z0
				m.erase("sw")
			else:
				vz = s.A * PI / s.T * cos(PI * k)
		else:
			var held := _ahead(m.g, m.vx) or Traffic.blocked(m.id, false, absf(m.vx))
			m.vx = move_toward(m.vx, 0.0 if held else m.v0, (14.0 if held else 4.0) * dt)
			_running(m.g, held)
		p.x += m.vx * dt
		p.z += vz * dt
		m.g.position = p
		if m.vx != 0.0 or vz != 0.0:
			m.g.rotation.y = atan2(-vz, m.vx if m.vx != 0.0 else dir * 0.01)  # (pointing the way it's going: the nose is local +x)
		Traffic.car(m.id, Vector2(p.x, p.z), m.g.rotation.y, size_of(m.g), absf(m.vx))
		if (m.g.position.x - dir * ROAD_END) * dir > 0.0:
			Traffic.gone(m.id)
			m.g.queue_free()
			movers.erase(m)
	for c: Dictionary in lot:
		if c.phase == "parked" and c.get("idling", false):  # somebody waiting in it, engine running, lights on
			_running(c.g)
	for g: Node3D in parked:  # (the day's: solid, to walk round)
		Traffic.car(g.get_instance_id(), Vector2(g.position.x, g.position.z), g.rotation.y, size_of(g), 0.0)
	for c: Dictionary in lot:
		Traffic.car(c.id, Vector2(c.g.position.x, c.g.position.z), c.g.rotation.y, size_of(c.g), c.v if c.phase in MOVING else 0.0)
	for c: Dictionary in lot.duplicate():
		var g: Node3D = c.g
		var A: float = LANE[c.dir]
		match c.phase:
			"approach":  # along the road and round in at the driveway: road speed, slowing for the turn
				var v: float = 11.0 if c.u < 0.55 else 11.0 - (c.u - 0.55) / 0.2 * 6.5 if c.u < 0.75 else 4.5
				_running(g, c.u > 0.5 and c.u < 0.78)
				if _along(c, v, dt):
					c.phase = "aisle"
			"aisle":  # up its lane toward the stall; the turn in starts 3 m short of it
				if _gas(c, 5.0, _ahead(g, 5.0), dt) < 1.0:
					lamps(g, night(), 2)
					if c.k == 0.0:
						continue
				var x: float = g.position.x + c.dir * 5.0 * c.k * dt
				var left: float = (c.sx - c.dir * 3.0 - x) * c.dir
				if c.k == 1.0:
					_running(g, left < 2.5)  # slowing for it
				if left <= 0.0:
					c.phase = "turnIn"
					c.t = 0.0
				else:
					_steer(c, x, A)
			"turnIn":
				c.t = minf(1.0, c.t + dt / 2.0 * _gas(c, 3.0, _ahead(g, 3.0), dt))
				var p := _bez(Vector2(c.sx - c.dir * 3.0, A), Vector2(c.sx, A), Vector2(c.sx, PARK_Z), 1.0 - (1.0 - c.t) * (1.0 - c.t))
				_steer(c, p.x, p.y)
				lamps(g, night(), 2)
				if c.t >= 1.0:
					c.phase = "stopped"
					c.t = 0.0
					c.v = 0.0
			"stopped":  # in the stall, foot still on the brake; then into park and off
				c.t += dt
				if c.t >= 0.9:
					c.phase = "parked"
					lamps(g)
					if c.on_parked.is_valid():
						c.on_parked.call(c)
			"startUp":  # started, on the brake; into reverse
				c.t += dt
				lamps(g, night(), 2, c.t > 0.6)
				if c.t >= 1.2:
					c.phase = "backOut"
					c.t = 0.0
			"backOut":  # back out into the lane for the way it's going, tail swinging away from it
				var E: float = LANE[c.e]
				var k := _gas(c, 3.0, _ahead(g, 3.0), dt, true)  # (nothing behind it: nobody walking past, no car in the lane)
				c.wait = c.get("wait", 0.0) + dt if k < 0.5 else c.get("wait", 0.0)
				if c.wait > 1.0 and not c.get("claimed", false):  # been waiting: the space it needs, out of its stall and round into the lane
					c.claimed = true
					var z0: float = PARK_Z - 1.0
					var z1: float = E + 1.4
					Traffic.claim(c.id, Vector2(c.sx - c.e * 1.4, (z0 + z1) / 2.0), Vector2.RIGHT, Vector2(4.2, (z1 - z0) / 2.0))
				if k == 0.0:
					lamps(g, night(), 2, true)
					continue
				c.t = minf(1.0, c.t + dt / 2.4 * k)
				var p := _bez(Vector2(c.sx, PARK_Z), Vector2(c.sx, E), Vector2(c.sx - c.e * 2.8, E), c.t * c.t * (3.0 - 2.0 * c.t))
				_steer(c, p.x, p.y, true)
				lamps(g, night(), 2 if c.t > 0.7 else 1 if night() else 0, true)  # (easing to a stop at the end: on the brake)
				if c.t >= 1.0:
					c.phase = "shift"
					c.t = 0.0
					c.v = 0.0
					Traffic.claim(c.id)
			"shift":  # stopped in the lane, on the brake, out of reverse and into drive
				c.t += dt
				lamps(g, night(), 2, c.t < 0.35)
				if c.t >= 0.6:
					c.phase = "leave"
					c.path = _out_path(c.e, GATE[-c.e], g.position.x)
					c.len = c.path.get_baked_length()
					c.u = 0.0
			"leave":  # down the lane, out the driveway and off along the road
				var X: float = GATE[-c.e]
				var L: float = ROAD[c.e]  # (at the curb: a gap in the traffic coming along its lane first)
				if c.u > 0.3 and c.u < 0.55 and movers.any(func(m: Dictionary) -> bool: return absf(m.g.position.z - L) < 1.5 and (X - m.g.position.x) * c.e > -3.0 and (X - m.g.position.x) * c.e < 22.0):
					lamps(g, night(), 2)
					c.k = 0.0
					c.v = 0.0
					continue
				_running(g, c.u > 0.15 and c.u < 0.3)
				if _along(c, 5.0 if c.u < 0.4 else 11.0, dt):
					Traffic.gone(c.id)
					g.queue_free()
					lot.erase(c)
					c.phase = "gone"
