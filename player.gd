extends CharacterBody3D
## First person. WASD to walk, the mouse to look, Shift to run, Space to jump.
## F: fly (through walls too; Space up, Ctrl down). The ladders don't climb yet, so it's the way onto the roof.
## Esc frees the mouse; click to take it back.

const SPEED := 3.2
const RUN := 6.5
const JUMP := 4.2
const SENS := 0.0025

var fly := false

@onready var cam: Camera3D = $Camera


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * SENS)
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * SENS, -1.5, 1.5)
	elif e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif e.physical_keycode == KEY_F:
			fly = not fly
			$Shape.disabled = fly


func _physics_process(dt: float) -> void:
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
