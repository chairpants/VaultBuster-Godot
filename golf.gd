extends Node3D
## Golf on the roof. A square of fake turf out on the deck with a tee in it and a club lying beside it: E on either,
## and you're at address (the camera behind the ball, looking down the line). A/D walk you round the ball to aim, W/S
## pick where the club meets the ball: W lower on it (under it: it climbs, with more backspin, and lands shorter),
## S higher on it (thin: low, and running; right at the top, topped). The swing's three clicks: hold to wind the power up and let go at the
## power you want; a line runs back down the meter from there, and the last click wants to land on the mark just
## above the bottom. On it: pure, and straight. A touch early it's pulled left; a touch late, pushed right; let the
## line run out and it's a mishit, low and sliced. Off the middle of the ball costs a little distance.
## (Not the web game's: there W/S slide the strike along the face, toe up and heel down. This is how a ball flies.)
## The ball flies (gravity, drag, backspin's lift, sidespin), bounces off the parapets and the deck, comes down out in
## the world and rolls out, and you get the yardage; then there's another on the tee. E or right-click: done.
## Out there it can dent a car or crack its glass (and off goes the alarm), make one going by swerve or run it off
## the road, or bean somebody on the walk; and one up on Tony's roof stays there.
## From the web game's store/roof.js (GOLF, golfStart, golfEnd, golfStrike, golfTick, golfFly, golfCarHit,
## golfScares, golfSnd, golfHud).
## ponytail: a car's a box here (the web game follows each style's outline, hood to trunk); no dent or crack left on
## it; no scuppers down the downspouts; the trees are a ring round the tee, as the web game's are

const GOLF := { "x": 5.5, "z": 12.0, "R": 0.0214, "SWEET": 0.08, "PURE": 0.015, "CLUB": 1.0, "MAX": 48.0 }  # the tee; the ball; the meter's mark and how close is pure; the club; how far out it can get
const ROOF_Y := 4.0
const ROOF_WALL := 0.91
const ROOFS := [[-7.84, 11.1, -0.1, 29.6], [2.1, 11.1, 29.6, 35.1]]  # the store's roof, at ROOF_Y (the theater's taller block stands up off it, 6.4 m: weather.gd's ROOFS)
const TONY := { "x0": 13.0, "x1": 21.0, "z0": 0.0, "z1": 14.0, "y": 4.385, "wall": 4.65 }

var on := false
var aim := 0.0  # which way down the line (radians, as your yaw)
var face := 0.0  # where the club meets the ball: 1 low on it (it climbs) .. -1 high on it (thin, low)
var st := "idle"  # idle | power | back | down | flight | done
var pow := 0.0
var peak := 0.0
var line := 0.0
var theta := 0.0
var _th0 := 0.0
var _t := 0.0
var _hit := {}
var _v := Vector3.ZERO
var _spin := 0.0
var _lift := 0.0
var _carry = null
var _rolled := false
var _seen := []
var _n := 0
var _aimed := false

var _ball := MeshInstance3D.new()
var _club := Node3D.new()
var _lie: Node3D  # the level's club, lying on the deck by the mat
var _trail := MeshInstance3D.new()
var _pts := PackedVector3Array()
var _cam := Camera3D.new()
var _hud := CanvasLayer.new()
var _meter := Control.new()
var _info := Label.new()
var _lost: Array[Node3D] = []

@onready var player: CharacterBody3D = $"../Player"
@onready var hud: CanvasLayer = $"../HUD"
@onready var amb: Node = $"../Ambience"


func _tee() -> Vector3:
	return Vector3(GOLF.x, ROOF_Y + 0.055 + GOLF.R, GOLF.z)


func _ready() -> void:
	_ball.mesh = SphereMesh.new()
	_ball.mesh.radius = GOLF.R
	_ball.mesh.height = GOLF.R * 2.0
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	white.emission_enabled = true
	white.emission = Color(0.2, 0.2, 0.2)
	_ball.mesh.material = white
	_ball.position = _tee()
	_ball.visible = false
	add_child(_ball)
	_club_build(_club)
	_club.visible = false
	add_child(_club)
	_trail.mesh = ImmediateMesh.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1, 1, 1, 0.55)
	_trail.material_override = tm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_cam.fov = 70.0
	add_child(_cam)
	_hud.layer = 3
	_hud.visible = false
	add_child(_hud)
	_meter.draw.connect(_meter_draw)
	_meter.size = Vector2(44, 260)
	_hud.add_child(_meter)
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_info)
	_lie_find.call_deferred()


func _lie_find() -> void:  # the club the level has lying beside the mat (hidden while it's in your hands)
	var at := Vector3(GOLF.x + 0.75, ROOF_Y + 0.012, GOLF.z - 0.45)
	for n: Node in $"../World".find_children("*", "Node3D", true, false):
		if not n is MeshInstance3D and n.get_child_count() == 3 and n.global_position.distance_to(at) < 0.05:
			_lie = n


func _club_build(g: Node3D) -> void:  # the grip at the origin, the shaft down -y, the head at its foot toeing out along +x
	var L: float = GOLF.CLUB
	for p: Array in [[CylinderMesh, Vector3(0.012, 0.26, 0.01), Vector3(0, -0.13, 0), "#1c1c1e"], [CylinderMesh, Vector3(0.006, L - 0.24, 0.0045), Vector3(0, -0.26 - (L - 0.26) / 2.0, 0), "#c9cdd2"], [BoxMesh, Vector3(0.105, 0.035, 0.03), Vector3(0.04, -L, 0), "#3a3d42"]]:
		var mi := MeshInstance3D.new()
		if p[0] == CylinderMesh:
			mi.mesh = CylinderMesh.new()
			mi.mesh.top_radius = p[1].x
			mi.mesh.bottom_radius = p[1].z
			mi.mesh.height = p[1].y
		else:
			mi.mesh = BoxMesh.new()
			mi.mesh.size = p[1]
		mi.mesh.material = StandardMaterial3D.new()
		mi.mesh.material.albedo_color = Color(p[3])
		mi.mesh.material.metallic = 0.6 if p[3] != "#1c1c1e" else 0.0
		mi.position = p[2]
		g.add_child(mi)


func _f() -> Vector3:  # down the line
	return Vector3(-sin(aim), 0, -cos(aim))


func _rt() -> Vector3:  # to its right
	return Vector3(cos(aim), 0, -sin(aim))


func _stance() -> Vector3:  # a right-hander: on the left of the line, facing the ball
	var p := _tee() + _rt() * -0.72
	p.y = ROOF_Y
	return p


func on_deck(x: float, z: float) -> bool:
	return ROOFS.any(func(r: Array) -> bool: return x > r[0] and x < r[1] and z > r[2] and z < r[3])


func on_tony(x: float, z: float) -> bool:
	return x > TONY.x0 and x < TONY.x1 and z > TONY.z0 and z < TONY.z1


func _floor(x: float, z: float) -> float:
	return ROOF_Y if on_deck(x, z) else TONY.y if on_tony(x, z) else $"../People".floor_y(Vector2(x, z))


# ---- getting into it, and out

func take_aim(hit: Dictionary, hit_d: float) -> String:  # (interact.gd) on the roof: the mat, the tee, the club
	_aimed = false
	if on or not hit or hit_d > 2.6 or player.global_position.y < ROOF_Y - 0.6:
		return ""
	var at: Vector3 = hit.position
	if Vector2(at.x - GOLF.x, at.z - GOLF.z).length() < 0.7 or Vector2(at.x - GOLF.x - 0.75, at.z - GOLF.z + 0.45).length() < 0.6:
		_aimed = true
		return "E — tee one up\nthe practice mat (somebody's been hitting balls off the roof)"
	return ""


func on_e() -> bool:  # (interact.gd) -> it was ours
	if on:
		if st == "idle":
			stop()
		return true
	if _aimed:
		start()
		return true
	return false


func start() -> void:  # golfStart
	var tp: Node = $"../Tapes"
	if $"../Chores".tool_held != "" or not $"../Chores".bag_carry.is_empty() or $"../Things".carrying != "":
		hud.toast("Your hands are full")
		return
	tp.inv_stash()
	on = true
	face = 0.0
	st = "idle"
	pow = 0.0
	theta = 0.0
	aim = player.rotation.y
	_retee()
	player.set_physics_process(false)
	_cam.global_position = player.get_node("Camera").global_position
	_cam.make_current()
	_club.visible = true
	if _lie:
		_lie.visible = false
	_hud.visible = true
	_head(true)
	if shift().mode == "customer":
		$"../Customer".tee_off()


func stop() -> void:  # golfEnd: left where you stood, looking at the ball
	on = false
	var body = player.body
	if body != null:
		body.reach_to(null)
		body.reach_also(null)
	_head(false)
	_club.visible = false
	if _lie:
		_lie.visible = true
	_hud.visible = false
	var p := _stance()
	player.global_position = p
	player.rotation.y = aim - PI / 2.0
	player.get_node("Camera").rotation.x = -0.45
	player.get_node("Camera").make_current()
	player.set_physics_process(true)


func shift() -> Node:
	return $"../Shift"


func _head(show: bool) -> void:  # (you can see yourself from back here)
	var body = player.body
	if body != null and body._head != null:
		body._head.visible = show
		for n in body.find_children("*_neck", "", true, false):
			n.visible = show


func _retee() -> void:
	_ball.position = _tee()
	_v = Vector3.ZERO
	st = "idle"
	_carry = null
	_pts.clear()
	(_trail.mesh as ImmediateMesh).clear_surfaces()


func _unhandled_input(e: InputEvent) -> void:  # golfMouse
	if not on or not e is InputEventMouseButton:
		return
	get_viewport().set_input_as_handled()
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if e.pressed and st == "idle":
			stop()
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed and st == "idle":
		st = "power"
		pow = 0.0
	elif not e.pressed and st == "power":
		if pow < 0.04:
			st = "idle"
		else:
			peak = pow
			line = pow
			st = "back"
	elif e.pressed and st == "back":
		_strike(line)


func _strike(at) -> void:  # the last click (at: where the line was), or null: it ran out. Full power, pure: ~38 m, ~6 m over the deck
	var e0 = null if at == null else at - GOLF.SWEET
	var e = 0.0 if e0 != null and absf(e0) <= GOLF.PURE else e0
	var c := face
	var ang := 0.0
	var spin := 0.0
	var speed := 18.0 * peak * (1.0 - 0.15 * absf(c))  # (off the middle of the ball: a bit less of it goes into the ball)
	var elev := 0.6 + c * (0.4 if c > 0.0 else 0.25)  # under it, it climbs; over the top, it's thin and low
	var what: Array[String] = []
	if e == null:
		speed *= 0.6
		elev = 0.3 + c * 0.1
		ang = 0.06
		spin = 7.0
		what.append_array(["mishit", "sliced it"])
	elif e > 0.0:
		speed *= 1.0 - minf(0.3, e * 0.8)
		ang = -minf(0.12, e * 0.25)
		spin += -minf(3.0, e * 6.0)
		what.append("way early: hooked it" if e > 0.12 else "a touch early: pulled left")
	elif e < 0.0:
		speed *= 1.0 - minf(0.3, -e * 0.8)
		ang = minf(0.12, -e * 0.4)
		spin += minf(3.0, -e * 20.0)
		what.append("a touch late: pushed right")
	elif absf(c) < 0.15:
		what.append("pure")
	if c >= 0.15:
		what.append("got under it: up it went" if c < 0.7 else "ballooned it")
	elif c <= -0.15:
		what.append("thinned it" if c > -0.7 else "topped it")
	var dir := _f() * cos(ang) + _rt() * sin(ang)
	var v := dir * speed * cos(elev)
	v.y = speed * sin(elev)
	_hit = { "v": v, "spin": spin, "what": what }
	_seen = []
	st = "down"
	_t = 0.0
	_th0 = theta


func _process(dt: float) -> void:  # golfTick
	_ball.visible = player.global_position.y > ROOF_Y - 0.6 or on
	if not on:
		return
	var F := _f()
	var Rt := _rt()
	var stance := _stance()
	if st == "idle":  # aim (A/D: round the ball), where on the ball (W/S: W lower on it, S higher)
		var turn := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		aim -= turn * dt * 0.9
		var slide := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		face = clampf(face + slide * dt * 1.2, -1.0, 1.0)
	if st == "power":
		pow = minf(1.0, pow + dt / 1.1)
	if st == "back":
		line -= dt * 0.85
		if line <= 0.0:
			line = 0.0
			_strike(null)
	# the club: arms and shaft one lever from between the shoulders, swung in the plane of the line and the ball
	var pivot := stance
	pivot.y = ROOF_Y + 1.38
	var d0 := (_tee() - pivot).normalized()
	var n := d0.cross(F).normalized()
	var want = -2.6 * (pow if st == "power" else peak) if st in ["power", "back"] else 0.0 if st == "idle" else 2.3 if st in ["flight", "done"] else null
	if want != null:
		theta += (want - theta) * minf(1.0, dt * 10.0)
	if st == "down":  # the downswing: through the ball and up to the finish
		_t += dt
		var k := minf(1.0, _t / 0.32)
		var was := theta
		theta = _th0 + (2.3 - _th0) * k * k
		if was < 0.0 and theta >= 0.0:
			_v = _hit.v
			_spin = _hit.spin
			_lift = maxf(0.02, 0.09 + 0.05 * face)  # (low on the ball: more backspin, holding it up; thin: hardly any)
			_n = 0
			_rolled = false
			st = "flight"
			_t = 0.0
			amb.golf("clank", _tee(), 0.5)  # (the club on the ball)
	var d := d0.rotated(n, theta)
	var L := _tee().distance_to(pivot)
	var grip := pivot + d * (L - GOLF.CLUB)
	var y_a := -d
	var x_a := (Rt - y_a * Rt.dot(y_a)).normalized()
	_club.global_transform = Transform3D(Basis(x_a, y_a, x_a.cross(y_a)), grip + x_a * -0.04 + y_a * (face * 0.012))  # (the head toes out 4 cm: centred on the ball; set down a touch lower or higher for where you'll catch it)
	var body = player.body
	player.global_position = stance
	player.rotation.y = atan2(-Rt.x, -Rt.z)  # (facing the ball)
	if body != null:
		body.reach_to(grip, 0, false)
		body.reach_also(grip, 1)
	if st == "flight":
		_fly(dt)
	elif st == "done":
		_t += dt
		if _t > 2.4:
			_retee()
	# the camera: behind the ball at address; in flight it chases the ball, a few metres back along the way it's gone
	var home := _tee() + F * -2.4 + Rt * 0.55
	home.y = ROOF_Y + 1.55
	if st in ["flight", "done"]:
		var b := _ball.position
		var out := Vector3(b.x - _tee().x, 0, b.z - _tee().z)
		var far := out.length()
		var back := out / far if far > 0.5 else F
		var chase := b - back * minf(4.0, 2.4 + far * 0.05)
		chase.y = maxf(b.y + 1.3, (ROOF_Y if on_deck(chase.x, chase.z) else 0.0) + 0.6)
		if st == "flight":
			_cam.position += _v * dt
		_cam.position = _cam.position.lerp(chase, minf(1.0, dt * 3.0))
		var over := ROOF_Y + 0.6 if on_deck(_cam.position.x, _cam.position.z) else TONY.wall + 0.3 if on_tony(_cam.position.x, _cam.position.z) else 0.0
		_cam.position.y = maxf(_cam.position.y, over)
		var to := b - _cam.position
		var yaw := atan2(-to.x, -to.z)
		var pitch := maxf(-0.6, atan2(to.y, Vector2(to.x, to.z).length()))
		_cam.rotation.y += angle_difference(_cam.rotation.y, yaw) * minf(1.0, dt * 6.0)
		_cam.rotation.x += (pitch - _cam.rotation.x) * minf(1.0, dt * 6.0)
	else:
		_cam.position = home
		_cam.rotation = Vector3(_cam.rotation.x + (-0.3 - _cam.rotation.x) * minf(1.0, dt * 6.0), aim, 0.0)
	_hud_tick()


func _fly(dt: float) -> void:  # golfFly
	var b := _ball.position
	var cars: Array = $"../Cars".all_cars().filter(func(c: Dictionary) -> bool: return is_instance_valid(c.g) and Vector2(c.g.position.x - b.x, c.g.position.z - b.z).length() < 9.0)
	_t += dt
	_scares(b)
	for i in 4:
		var h := dt / 4.0
		var sp := _v.length()
		if not _rolled:
			_v += _v * (-0.0025 * sp * h)  # drag
			var hl := maxf(0.001, Vector2(_v.x, _v.z).length())
			var side := _spin * sp / 40.0  # sidespin: off to the right of the way it's going (+: a fade / slice)
			var ax := -_v.z / hl * side
			var az := _v.x / hl * side
			_v.x += ax * h
			_v.z += az * h
			_v.y += (_lift * sp - 9.8) * h  # backspin holds it up
		var nb := b + _v * h
		if nb.y < 2.4 and cars.any(func(c: Dictionary) -> bool: return _car_hit(c, b, nb)):
			continue  # off a car
		if on_tony(b.x, b.z) != on_tony(nb.x, nb.z) and nb.y < TONY.wall:  # next door's walls, its coping
			if on_tony(nb.x, b.z) != on_tony(b.x, b.z):
				_v.x *= -0.4
			if on_tony(b.x, nb.z) != on_tony(b.x, b.z):
				_v.z *= -0.4
			_v.y *= 0.7
			continue
		if on_deck(b.x, b.z) and not on_deck(nb.x, nb.z) and nb.y < ROOF_Y + ROOF_WALL + GOLF.R:  # the parapet: off it and back
			if not on_deck(nb.x, b.z):
				_v.x *= -0.4
			if not on_deck(b.x, nb.z):
				_v.z *= -0.4
			_v.y *= 0.7
			continue
		if Vector2(nb.x - GOLF.x, nb.z - GOLF.z).length() > GOLF.MAX:  # into the trees: it drops out of them
			_v.x *= -0.15
			_v.z *= -0.15
			continue
		var fl := _floor(nb.x, nb.z) + GOLF.R
		b = nb
		if _rolled or b.y < fl:
			b.y = fl
			if _carry == null:
				_carry = Vector2(b.x - GOLF.x, b.z - GOLF.z).length()
			_spin = 0.0
			_lift = 0.0
			if not _rolled and _v.y < -1.5:  # a bounce: it bites
				_v.y *= -0.3
				_v.x *= 0.45
				_v.z *= 0.45
			else:  # rolling out
				_v.y = 0.0
				_rolled = true
				var hs := Vector2(_v.x, _v.z).length()
				var k := maxf(0.0, hs - 5.0 * h) / maxf(hs, 0.0001)
				_v.x *= k
				_v.z *= k
	_ball.position = b
	if _n < 120 and not _rolled:  # the trail, a point every so often
		_pts.append(b)
		_n += 1
		var im := _trail.mesh as ImmediateMesh
		im.clear_surfaces()
		if _pts.size() > 1:
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for p in _pts:
				im.surface_add_vertex(p)
			im.surface_end()
	if (_rolled and Vector2(_v.x, _v.z).length() < 0.05) or _t > 25.0:  # it's stopped: how far
		var yd := Vector2(b.x - GOLF.x, b.z - GOLF.z).length() / 0.9144
		var carry: float = (_carry if _carry != null else 0.0) / 0.9144
		if on_tony(b.x, b.z):  # up on Tony's roof: it stays there (the one on the tee's a new one)
			var lost: MeshInstance3D = _ball.duplicate()
			add_child(lost)
			_lost.append(lost)
			if _lost.size() > 20:
				_lost.pop_front().queue_free()
			hud.toast("%d yards, onto Tony's roof. That one's not coming back" % roundi(yd))
		else:
			hud.toast("%d yards%s · %s" % [roundi(yd), " (%d in the air)" % roundi(carry) if carry > 1.0 else "", ", ".join(PackedStringArray(_hit.what))])
		st = "done"
		_t = 0.0


func _car_hit(c: Dictionary, b: Vector3, nb: Vector3) -> bool:  # golfCarHit: the ball into a car this step -> true (it bounced)
	var g: Node3D = c.g
	var size: Vector2 = $"../Cars".size_of(g)
	var R: float = GOLF.R + 0.04
	var q := g.global_transform.affine_inverse() * nb
	var top := 1.4 if size.x < 4.4 else 1.75  # ponytail: the roof's height, about (a van's taller)
	if absf(q.x) > size.x / 2.0 + 0.14 + R or absf(q.z) > size.y / 2.0 + R or q.y < 0.12 or q.y > top + R:
		return false
	var qp := g.global_transform.affine_inverse() * b
	var n: Vector3
	var glass := false
	if qp.y > top + R - 0.03:  # came down on it
		n = Vector3.UP
		glass = absf(q.x) < size.x * 0.25  # (the roof's middle: the glass either end of it, near enough)
	elif absf(qp.z) > size.y / 2.0 + R - 0.03:  # into its side (above the beltline: a window)
		n = Vector3(0, 0, signf(qp.z))
		glass = q.y > 0.95
	else:  # its nose or its tail
		n = Vector3(signf(qp.x), 0, 0)
	var facing := (g.global_basis * n).normalized()
	var m = c.m
	var cv := Vector3(m.vx if m != null else 0.0, 0, 0)
	var rel := _v - cv
	var vn := rel.dot(facing)
	if vn >= 0.0:
		return false
	rel = (rel - facing * vn) * 0.7 - facing * vn * 0.3  # off it: a dull bounce, some speed scrubbed off
	_v = rel + cv
	var hard := -vn
	if hard < 2.5:
		return true  # just a tap
	var where := "a car on the road" if m != null else "a customer's car" if c.lot != null else "a car in the lot"
	amb.golf("glass" if glass else "clank", b)
	var cars: Node = $"../Cars"
	if m != null:  # one going by: it swerves, or (through the glass, or hard) off the road it goes
		if m.get("hit_by") == _hit:
			return true
		m.hit_by = _hit
		amb.golf("screech", b)
		if glass or hard > 9.0:
			cars.crash(m)
			amb.golf("thud", g.position, 0.9)
			hud.toast("Hit %s! It's run off the road (-10)" % where)
			$"../Checkout".score -= 10
		else:
			cars.swerve(m, signf(g.position.z - b.z) if g.position.z != b.z else 1.0)
			amb.golf("horn", g.position)
			hud.toast("Bounced it off %s. It swerved, and leaned on the horn" % where)
		return true
	if g.get_meta("alarm_t", 99.0) > 10.0:
		cars.alarm(g)
		amb.golf("alarm", g.position)
	if not _seen.has(g):
		_seen.append(g)
		hud.toast(("Cracked the glass on %s. There goes the alarm" if glass else "Dented %s. There goes the alarm") % where + (" (-5)" if c.lot != null else ""))
		if c.lot != null:
			$"../Checkout".score -= 5
	return true


func _scares(b: Vector3) -> void:  # close calls: a car coming up on it in the road swerves; people on the walk jump (and if it hits one...)
	for c: Dictionary in $"../Cars".all_cars():
		var m = c.m
		if m == null or _seen.has(m) or b.y > 2.0:
			continue
		var g: Node3D = c.g
		var ahead: float = (b.x - g.position.x) * signf(m.v0)
		if ahead > -1.0 and ahead < 8.0 and absf(b.z - g.position.z) < 2.2:
			_seen.append(m)
			$"../Cars".swerve(m, signf(g.position.z - b.z) if g.position.z != b.z else 1.0)
			amb.golf("screech", g.position, 0.6)
			amb.golf("horn", g.position)
			hud.toast("A car swerved round it, leaning on the horn")
	var folks: Array = $"../People".walkers.map(func(w: Dictionary) -> Node3D: return w.c) + $"../Shoppers".custs.map(func(k: Dictionary) -> Node3D: return k.c)
	for p: Node3D in folks:
		if not is_instance_valid(p) or not p.visible or _seen.has(p) or b.y > 2.4:
			continue
		var dist := Vector2(b.x - p.position.x, b.z - p.position.z).length()
		if dist > 1.4:
			continue
		_seen.append(p)
		p.set_mood("shock")
		p.stagger(signf(b.x - p.position.x) if b.x != p.position.x else 1.0)
		if dist < 0.35 and b.y < 1.9:
			_v.x *= -0.3
			_v.z *= -0.3
			amb.golf("thud", b, 0.4)
			hud.toast("Beaned somebody with it. “OW! Hey!” (-10)")
			$"../Checkout".score -= 10
		else:
			hud.toast("“Hey! Watch it!”")


# ---- the meter: the power filling up the bar, the line running back down it, the mark just above the bottom

func _hud_tick() -> void:
	var s := get_viewport().get_visible_rect().size
	_meter.position = Vector2(s.x - 90.0, s.y / 2.0 - 130.0)
	_meter.queue_redraw()
	var where := "the middle" if absf(face) < 0.15 else "%s on the ball %d%%, %s" % ["low" if face > 0.0 else "high", roundi(absf(face) * 100.0), "higher" if face > 0.0 else "lower"]
	_info.text = "A / D — aim · W / S — contact: %s\nHold click — power · let go · click on the mark\nE / right-click — done" % where if st == "idle" else "Let go at the power you want" if st == "power" else "Click on the mark!" if st == "back" else ""
	_info.reset_size()
	_info.position = Vector2((s.x - _info.size.x) / 2.0, s.y - 120.0)


func _meter_draw() -> void:
	var w := _meter.size.x
	var h := _meter.size.y
	_meter.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.55))
	_meter.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.5), false, 2.0)
	var fill := pow if st == "power" else peak if st == "back" else 0.0
	_meter.draw_rect(Rect2(4, h - 4 - (h - 8) * fill, w - 8, (h - 8) * fill), Color("#f2c200"))
	var mark := h - 4 - (h - 8) * GOLF.SWEET
	_meter.draw_rect(Rect2(0, mark - (h - 8) * GOLF.PURE, w, (h - 8) * GOLF.PURE * 2.0), Color(0.2, 1.0, 0.4, 0.8))  # the mark: pure, either side of it
	if st == "back":
		var y := h - 4 - (h - 8) * line
		_meter.draw_rect(Rect2(-6, y - 2, w + 12, 4), Color.WHITE)
