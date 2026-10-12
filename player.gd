extends CharacterBody3D
## First person. WASD to walk, the mouse to look, Shift to run, Space to jump.
## E: whatever the crosshair's on (see interact.gd). Click: tapes (see tapes.gd). L: skip an hour (see clock.gd).
## F: fly (through walls too; Space up, Ctrl down). The ladders don't climb yet, so it's the way onto the roof.
## Esc frees the mouse; click to take it back.

const SPEED := 3.2
const RUN := 6.5
const JUMP := 4.2
const SENS := 0.0025
const EYE := 1.6  # the camera, above your feet
const SEAT_EYE := 0.72  # ...and above your hips, sat down (the web game's camera rides the body's head)

var fly := false
var seat = null  # the seat you're in (one of interact.gd's), or null

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
		elif e.physical_keycode == KEY_F and seat == null:
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


func _physics_process(dt: float) -> void:
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
