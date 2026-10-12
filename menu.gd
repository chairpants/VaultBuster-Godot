extends CanvasLayer
## The main menu: three store files, like a cartridge's save files. Pick one and you can PLAY it (an empty one: a
## new store), COPY it to another file, or DELETE it. Escape in the store brings it back up as the pause screen
## (the store stops while it's up, and saves). And the settings: store sounds, TV volume, mouse sensitivity, look
## inversion, smooth edges, how long a shift is.
## From the web game's store/title.js (slotInfo, titleMenu and its settings). The game holds one store at a time,
## so playing another file reloads into it.
## A new store's a sandbox or a simulation (shift.gd). Not over yet: the customer mode. Not up at all when the game's run
## with arguments (--check, --shot).

const SLOTS := 3
const SET_PATH := "user://settings.json"

static var slot := 1  # the store file in play (kept across the reload into another)
static var pending_mode := "sandbox"  # what kind of store a new one is (shift.gd picks it up)
static var go := false  # (reloading into a file somebody pressed PLAY on: straight in)
static var settings := { "sound": 100.0, "tv": 100.0, "sens": 100.0, "invert": false, "aa": true, "shift": 21.0 }
static var _read := false

var up := false

var _live := OS.get_cmdline_user_args().is_empty()
var _started := false
var _sel := 0
var _step := ""  # "" | "copy" (pick where) | "del"
var _page := "main"
var _box := VBoxContainer.new()

@onready var main: Node = get_parent()


static func path(n: int) -> String:
	return "user://store_%d.json" % n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	if not _read:
		_read = true
		if FileAccess.file_exists(SET_PATH):
			var d = JSON.parse_string(FileAccess.get_file_as_string(SET_PATH))
			if d is Dictionary:
				settings.merge(d, true)
		if FileAccess.file_exists("user://store.json") and not FileAccess.file_exists(path(1)):
			DirAccess.rename_absolute(ProjectSettings.globalize_path("user://store.json"), ProjectSettings.globalize_path(path(1)))  # (the store from before there were files: it's file 1)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(mid)
	_box.custom_minimum_size.x = 460.0
	_box.add_theme_constant_override("separation", 8)
	mid.add_child(_box)
	visible = false
	apply.call_deferred()
	if "--menu" in OS.get_cmdline_user_args():  # (godot --path . -- --shot --menu: a picture of it)
		open.call_deferred()
	if _live:
		if go:
			go = false
			_started = true
		else:
			open.call_deferred()


func apply() -> void:  # the settings, as they are
	var bus := AudioServer.get_bus_index("Store")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(settings.sound / 100.0, 0.0001)))
	main.get_node("Video").audio.volume_db = linear_to_db(maxf(settings.tv / 100.0, 0.0001))
	var p: Node = main.get_node("Player")
	p.sens_k = settings.sens / 100.0
	p.invert_y = settings.invert
	get_viewport().msaa_3d = Viewport.MSAA_4X if settings.aa else Viewport.MSAA_DISABLED
	Clock.HOUR = settings.shift * 60.0 / 14.0


func open() -> void:  # up over the store: everything stops
	up = true
	visible = true
	_sel = slot if _started or FileAccess.file_exists(path(slot)) else 0
	_step = ""
	_page = "main"
	if _started and _live:
		main.get_node("Save").save_store()
	get_tree().paused = true
	if _live:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_render()


func resume() -> void:
	up = false
	visible = false
	_started = true
	get_tree().paused = false
	if _live:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func info(n: int) -> String:  # what's in a store file, for the menu ("" for an empty one)
	if not FileAccess.file_exists(path(n)):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(path(n)))
	if not d is Dictionary or d.get("v") != 1:
		return ""
	var rep: float = d.get("shift", {}).get("rep", 50.0)
	var stars := clampi(roundi(1.0 + rep / 25.0), 1, 5)
	return ("Simulation" if d.get("shift", {}).get("mode", "") == "simulation" else "Sandbox") + " · day %d · $%d · %s" % [int(d.clock.day), roundi(d.get("shift", {}).get("budget", 10000.0)), "★".repeat(stars) + "☆".repeat(5 - stars)]


func _reload_into(n: int, play: bool) -> void:  # the game into file n (and on into the store, if play)
	slot = n
	go = play
	get_tree().paused = false
	main.get_node("Save")._live = false  # (nothing saves over what's next)
	Clock.h = Clock.START
	Clock.day = 1
	Clock.warp = 0.0
	get_tree().reload_current_scene()


func _new(n: int, m: String) -> void:  # a new store in file n (the one on screen, if it's that file and nothing's been played in it; else a reload into it)
	pending_mode = m
	if n == slot and not _started and m == "sandbox":
		resume()
	else:
		if _started and _live:
			main.get_node("Save").save_store()
		_reload_into(n, true)


func _play(n: int) -> void:
	if n == slot:
		resume()  # (the store that's already loaded)
		return
	if _started and _live:
		main.get_node("Save").save_store()
	_reload_into(n, true)


func _btn(text: String, on: Callable, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18 if big else 15)
	b.pressed.connect(on)
	return b


func _label(text: String, size := 15, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _render() -> void:
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(_label("VAULTBUSTER VIDEO", 34, Color(1, 0.83, 0)))
	if _page == "settings":
		_box.add_child(_label("SETTINGS", 18))
		_slider("Store sounds", "sound", 0, 100, 5, "%d%%")
		_slider("TV volume", "tv", 0, 100, 5, "%d%%")
		_slider("Mouse sensitivity", "sens", 25, 300, 5, "%d%%")
		_toggle("Invert look", "invert")
		_toggle("Smooth edges", "aa")
		_slider("Shift length", "shift", 10, 60, 1, "%d min")
		_box.add_child(_btn("BACK", func() -> void:
			_page = "main"
			_render()))
		return
	_box.add_child(_label("COPY STORE %d TO…" % _sel if _step == "copy" else "PAUSED" if _started else "SELECT A STORE", 18))
	for n in range(1, SLOTS + 1):
		var what := info(n)
		var here: bool = n == slot and _started
		_box.add_child(_btn("%d   %s%s\n     %s" % [n, "STORE %d" % n if what != "" or here else "NEW STORE", " · PLAYING" if here else "", ("replace it" if what != "" else "copy here") if _step == "copy" and n != _sel else what if what != "" else "in play, not saved yet" if here else "empty"], _pick.bind(n), true))
		if n != _sel or _step == "copy":
			continue
		var row := HBoxContainer.new()
		_box.add_child(row)
		if _step == "del":
			row.add_child(_label("Delete store %d for good?  " % n, 15, Color(1, 0.5, 0.45)))
			row.add_child(_btn("DELETE", _delete.bind(n)))
			row.add_child(_btn("KEEP IT", func() -> void:
				_step = ""
				_render()))
		elif what != "" or here:
			row.add_child(_btn("RESUME" if here else "PLAY", _play.bind(n)))
			row.add_child(_btn("COPY", func() -> void:
				_step = "copy"
				_render()))
			row.add_child(_btn("DELETE", func() -> void:
				_step = "del"
				_render()))
		else:
			row.add_child(_btn("SANDBOX\nDana on staff, $10,000 in the budget:\nbuy whatever you like and just play store", _new.bind(n, "sandbox")))
			row.add_child(_btn("SIMULATION\nA bare-bones store: no staff, the theater\nlocked up, part of the library. Build it up", _new.bind(n, "simulation")))
	_box.add_child(_btn("SETTINGS", func() -> void:
		_page = "settings"
		_render()))
	_box.add_child(_btn("QUIT", func() -> void:
		if _started:
			main.get_node("Save").save_store()
		get_tree().quit()))
	_box.add_child(_label("WASD walk · Shift run · Space jump · C crouch · E use · Q the other thing · 1-9 / wheel what's in hand\nL skip an hour · J the log · M store sounds · F9 a fresh store · Esc this menu", 12, Color(0.7, 0.74, 0.8)))


func _pick(n: int) -> void:
	if _step == "copy":
		if n != _sel:  # copyStore
			if _sel == slot and _started:
				main.get_node("Save").save_store()
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path(_sel)), ProjectSettings.globalize_path(path(n)))
			if n == slot:
				_reload_into(n, false)  # copied over the one on screen: load the copy
				return
			_sel = n
		_step = ""
	else:
		_sel = n
		_step = ""
	_render()


func _delete(n: int) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path(n)))
	if n == slot:
		_reload_into(n, false)  # (the store on screen goes with it)
		return
	_sel = 0
	_step = ""
	_render()


func _changed() -> void:
	apply()
	var f := FileAccess.open(SET_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


func _slider(text: String, key: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var row := HBoxContainer.new()
	var name_l := _label(text)
	name_l.custom_minimum_size.x = 170.0
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = settings[key]
	s.custom_minimum_size.x = 210.0
	var out := _label(fmt % int(settings[key]))
	s.value_changed.connect(func(v: float) -> void:
		settings[key] = v
		out.text = fmt % int(v)
		_changed())
	row.add_child(name_l)
	row.add_child(s)
	row.add_child(out)
	_box.add_child(row)


func _toggle(text: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = settings[key]
	c.toggled.connect(func(on: bool) -> void:
		settings[key] = on
		_changed())
	_box.add_child(c)


func _unhandled_input(e: InputEvent) -> void:
	if not _live or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.physical_keycode == KEY_ESCAPE:
		if not up:
			open()
		elif _page != "main" or _step != "":
			_page = "main"
			_step = ""
			_render()
		elif _started:
			resume()
		get_viewport().set_input_as_handled()
	elif up and e.physical_keycode == KEY_ENTER and _page == "main" and _step == "" and _sel > 0 and (info(_sel) != "" or (_sel == slot and _started)):
		_play(_sel)
