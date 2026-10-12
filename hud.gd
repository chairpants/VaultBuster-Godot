extends CanvasLayer
## What's on the screen: the day and the time top left (the first line of the web game's HUD, and whether the store's
## open), a crosshair, the line for whatever you're aiming at, and toasts (the clock's, for now).

var _clock := _label(26)
var _status := _label(14, Color(1, 0.83, 0))
var _cross := _label(18)
var _tip := _label(18)
var _toast := _label(20)
var _toast_t := 0.0
var _call := _label(18, Color(1, 0.83, 0))

@onready var till: Node = $"../Checkout"
var _inv := _label(15)
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


func inventory(names: Array, sel: int) -> void:  # what you're carrying, numbered; the one in hand in brackets (nothing shown for one or none)
	var parts := PackedStringArray()
	for i in names.size():
		var n: String = names[i] if names[i].length() <= 22 else names[i].left(21) + "…"
		parts.append(("[%d %s]" if i == sel else "%d %s") % [i + 1, n])
	_inv.text = "   ".join(parts) if names.size() > 1 else ""


func call_box(text: String) -> void:  # a decision waiting on you ("" clears it)
	_call.text = text


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 4.0


func _process(dt: float) -> void:
	var s := get_viewport().get_visible_rect().size
	_clock.text = "%s %s" % [Clock.weekday(), Clock.fmt_clock(Clock.h)]
	_status.text = "%s · $%.2f · SCORE %d" % [Clock.status(), till.take, till.score] if till.served > 0 else Clock.status()
	if till.co != null and till.co.by == "player":  # the sale in hand: what's next
		_status.text += "\nNEXT: %s" % till.tip().to_upper()
	_clock.position = Vector2(16, 8)
	_status.position = Vector2(16, 44)
	_toast_t -= dt
	_toast.visible = _toast_t > 0.0
	for l: Label in [_cross, _tip, _toast, _fade_text, _inv, _call]:
		l.reset_size()
	_call.position = Vector2((s.x - _call.size.x) / 2.0, s.y * 0.2)
	_fade.size = s
	_fade_text.visible = _fade.visible
	_fade_text.position = (s - _fade_text.size) / 2.0
	_cross.position = (s - _cross.size) / 2.0
	_inv.position = Vector2((s.x - _inv.size.x) / 2.0, s.y - 44.0)
	_tip.position = Vector2((s.x - _tip.size.x) / 2.0, s.y * 0.78)
	_toast.position = Vector2((s.x - _toast.size.x) / 2.0, s.y * 0.12)
