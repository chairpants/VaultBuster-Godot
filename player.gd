extends CharacterBody3D
## First person. WASD to walk, the mouse to look, Shift to run, Space to jump.
## E: whatever the crosshair's on (see interact.gd). Click: tapes (see tapes.gd). L: skip an hour (see clock.gd).
## F: fly (through walls too; Space up, Ctrl down).
## Esc frees the mouse; click to take it back.

const SPEED := 3.2
const RUN := 6.5
const JUMP := 4.2
const SENS := 0.0025
const EYE := 1.6  # the camera, above your feet
const SEAT_EYE := 0.72  # ...and above your hips, sat down (the web game's camera rides the body's head)

var fly := false
var seat = null  # the seat you're in (one of interact.gd's), or null
var climb = null  # on a ladder: { dir (1 up, -1 down), L (the ladder's climb), t, ... } (see fixtures.gd)

@onready var cam: Camera3D = $Camera


func _ready() -> void:
	if OS.get_cmdline_user_args().is_empty():  # (not for --check and --shot: they'd take the mouse off whoever's at the machine)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * SENS)
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * SENS, -1.5, 1.5)
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()  # (the click that takes the mouse back doesn't also pick something up)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif e.physical_keycode == KEY_F and seat == null and climb == null:
			fly = not fly
			$Shape.disabled = fly


func sit(s: Dictionary) -> void:  # looking the way the seat faces
	seat = s
	$Shape.disabled = true
	velocity = Vector3.ZERO
	global_position = Vector3(s.x, s.y + s.hipY + SEAT_EYE - EYE, s.z)
	rotation.y = s.ry + PI
	cam.rotation.x = 0.0


func stand(at: Vector3, yaw: float) -> void:  # back where you were stood
	seat = null
	$Shape.disabled = fly
	global_position = at
	rotation.y = yaw


func start_climb(dir: int, L: Dictionary, ladders: Dictionary) -> void:  # up (1) or down (-1) a ladder (the web game's roofClimb)
	climb = { "dir": dir, "L": L, "t": 0.0, "from": cam.global_position, "roof_y": ladders.roofY, "dur": ladders.dur }
	$Shape.disabled = true
	velocity = Vector3.ZERO
	rotation.y = L.yaw  # facing the rungs, up or down
	cam.rotation.x = 0.0


func _climb(dt: float) -> void:  # walk the step to the foot, then up and out (or over the edge and down): the climb in the web game's roofTick
	var c: Dictionary = climb
	c.t = minf(c.dur, c.t + dt)
	var k: float = c.t / c.dur
	var e := k * k * (3.0 - 2.0 * k)
	var step := 0.04 * sin(k * PI * 12.0)  # a rung at a time
	var y_hi: float = c.roof_y + EYE
	var a := minf(1.0, k * 5.0)
	var at := Vector3(lerpf(c.from.x, c.L.x, a), 0.0, lerpf(c.from.z, c.L.z, a))
	var end: Dictionary = c.L.up if c.dir > 0 else c.L.down
	at.y = (EYE + (y_hi + 0.15 - EYE) * e if c.dir > 0 else y_hi + 0.15 + (EYE - y_hi - 0.15) * e) + step
	if k > 0.92:
		at = at.lerp(Vector3(end.x, y_hi if c.dir > 0 else EYE, end.z), (k - 0.92) / 0.08)
	global_position = at - Vector3(0, EYE, 0)
	if c.t >= c.dur:
		climb = null
		$Shape.disabled = fly
		global_position = Vector3(end.x, (c.roof_y if c.dir > 0 else 0.0) + 0.05, end.z)


func _physics_process(dt: float) -> void:
	if climb != null:
		_climb(dt)
		return
	if seat != null:
		return
	var dir := Vector3(_key(KEY_D) - _key(KEY_A), 0, _key(KEY_S) - _key(KEY_W)).normalized()
	var speed := RUN if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	if fly:
		var up := _key(KEY_SPACE) - _key(KEY_CTRL)
		global_position += (cam.global_basis * dir + Vector3.UP * up) * speed * 2.0 * dt
		velocity = Vector3.ZERO
		return
	var v := global_basis * dir * speed
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		velocity.y = JUMP if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
	else:
		velocity.y -= 9.8 * dt
	move_and_slide()


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0
