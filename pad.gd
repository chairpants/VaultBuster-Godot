extends Node
## A gamepad, played as the keyboard and mouse: everything already listens for those, so the pad just presses them.
## Left stick walks (WASD), right stick looks (the mouse), and the buttons:
##   A jump (Space)  ·  X use (E, held as long as it's held: lifting the stool, peeling a post-it)  ·  Y the other thing (Q)
##   B crouch (C)  ·  left stick in: run (Shift)  ·  RB click  ·  LB right-click  ·  D-pad left/right: what's in hand
##   D-pad up: skip an hour (L)  ·  D-pad down: the log (J)  ·  Start: the menu (Esc)  ·  Back: the skills (K)
## Not the web game's: it has no gamepad.
## ponytail: the sticks are read as keys (on past a third of the way), so walking's all or nothing; true analogue
## steps would want player.gd reading the axis itself

const LOOK := 900.0  # pixels a second of mouse, at full tilt (the settings' sensitivity scales it from there, as it does the mouse)
const DEAD := 0.35
const BUTTONS := { JOY_BUTTON_A: KEY_SPACE, JOY_BUTTON_X: KEY_E, JOY_BUTTON_Y: KEY_Q, JOY_BUTTON_B: KEY_C, JOY_BUTTON_LEFT_STICK: KEY_SHIFT,
	JOY_BUTTON_DPAD_UP: KEY_L, JOY_BUTTON_DPAD_DOWN: KEY_J, JOY_BUTTON_START: KEY_ESCAPE, JOY_BUTTON_BACK: KEY_K }
const CLICKS := { JOY_BUTTON_RIGHT_SHOULDER: MOUSE_BUTTON_LEFT, JOY_BUTTON_LEFT_SHOULDER: MOUSE_BUTTON_RIGHT, JOY_BUTTON_DPAD_LEFT: MOUSE_BUTTON_WHEEL_UP, JOY_BUTTON_DPAD_RIGHT: MOUSE_BUTTON_WHEEL_DOWN }

var _held := {}  # key -> pressed by the stick
var _on := false  # (asleep till a button on the pad's pressed: a virtual pad, Steam's say, with a stick off-centre, mustn't drive you)
var _rest := {}  # each stick's reading when it woke: what "centred" is for this pad


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton and e.pressed and not _on:
		_on = true
		var pad: int = e.device
		for ax in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			_rest[ax] = Input.get_joy_axis(pad, ax) if absf(Input.get_joy_axis(pad, ax)) < 0.5 else 0.0
	if e is InputEventJoypadButton and _on:
		if BUTTONS.has(e.button_index):
			_key(BUTTONS[e.button_index], e.pressed)
		elif CLICKS.has(e.button_index):
			var m := InputEventMouseButton.new()
			m.button_index = CLICKS[e.button_index]
			m.pressed = e.pressed
			m.position = get_viewport().get_visible_rect().size / 2.0
			m.global_position = m.position
			Input.parse_input_event(m)


func _key(k: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = on
	Input.parse_input_event(ev)


func _process(dt: float) -> void:
	if not _on or Input.get_connected_joypads().is_empty():
		return
	var pad: int = Input.get_connected_joypads()[0]
	var axis := func(ax: int) -> float: return Input.get_joy_axis(pad, ax) - _rest.get(ax, 0.0)
	var move := Vector2(axis.call(JOY_AXIS_LEFT_X), axis.call(JOY_AXIS_LEFT_Y))
	for k: Array in [[KEY_W, move.y < -DEAD], [KEY_S, move.y > DEAD], [KEY_A, move.x < -DEAD], [KEY_D, move.x > DEAD]]:
		if k[1] != _held.get(k[0], false):
			_held[k[0]] = k[1]
			_key(k[0], k[1])
	var look := Vector2(axis.call(JOY_AXIS_RIGHT_X), axis.call(JOY_AXIS_RIGHT_Y))
	if look.length() > 0.15:
		var m := InputEventMouseMotion.new()
		m.relative = look * look.length() * LOOK * dt  # (eased: fine aim near the middle)
		Input.parse_input_event(m)
