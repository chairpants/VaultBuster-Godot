extends CanvasLayer
## What's on the screen: the day and the time top left (the first line of the web game's HUD, and whether the store's
## open), a crosshair, the line for whatever you're aiming at, and toasts (the clock's, for now).

var _clock := _label(26)
var _status := _label(14, Color(1, 0.83, 0))
var _cross := _label(18)
var _tip := _label(18)
var _toast := _label(20)
var _toast_t := 0.0
var _fade := ColorRect.new()
var _fade_text := _label(40)


func _label(size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _ready() -> void:
	_cross.text = "+"
	_fade.color = Color.BLACK
	_fade.visible = false
	add_child(_fade)
	move_child(_fade_text, -1)
	Clock.toast.connect(toast)


func tip(text: String) -> void:
	_tip.text = text


func fade(text: String) -> void:  # the screen gone black with a word on it ("" brings it back)
	_fade.visible = text != ""
	_fade_text.text = text


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 4.0


func _process(dt: float) -> void:
	var s := get_viewport().get_visible_rect().size
	_clock.text = "%s %s" % [Clock.weekday(), Clock.fmt_clock(Clock.h)]
	_status.text = Clock.status()
	_clock.position = Vector2(16, 8)
	_status.position = Vector2(16, 44)
	_toast_t -= dt
	_toast.visible = _toast_t > 0.0
	for l: Label in [_cross, _tip, _toast, _fade_text]:
		l.reset_size()
	_fade.size = s
	_fade_text.visible = _fade.visible
	_fade_text.position = (s - _fade_text.size) / 2.0
	_cross.position = (s - _cross.size) / 2.0
	_tip.position = Vector2((s.x - _tip.size.x) / 2.0, s.y * 0.78)
	_toast.position = Vector2((s.x - _toast.size.x) / 2.0, s.y * 0.12)
