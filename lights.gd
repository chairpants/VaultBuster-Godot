extends Node
## The store's lights: nine zones, each on its own switch, fluorescents that stutter before they strike; and the two
## side lamps by the couch.
## From the web game: store/lounge.js (zoneOn, zoneLvl, setZone, lightingTick, buildFlickerSchedule, flickerLit),
## store/clock.js (flipSwitch), store/tv.js (setLamp), and the room shader in store/core.js (ROOM_FRAG) for which
## zone lights where: the sales floor is three zones along z (front to 10 m, aisles to 19, lounge behind), the back of
## house is the hall, the break room and the restroom, then the theater's lobby and its auditorium (both start off).
## The switches, the zones' rooms and the lamps are the web game's, from data/interact.json.
##
## What a zone's level does to the room is room.gd's business. The real lights are here: the lamps, daylight coming
## in through the storefront (so the back of a dark store is dark, and darker where something's in the way), and the
## screens, which light the room with the colour of the frame on them (SpaceLife's wall TV did the same).

var zone_on := {}  # zone -> bool
var zone_lvl := {}  # zone -> 0..1, flickering while the tubes warm up (what the lights get)
var names := {}
var switches: Array = []
var lamps: Array = []

var _warm := {}  # zone -> { t, duration, schedules } while its tubes restrike
var _windows: Array[SpotLight3D] = []  # daylight (or the night) in through the storefront glass
var _glows: Array[Light3D] = []  # the screens: lit with the colour of what's on them
var _glow := Color.BLACK
var _panels := {}  # zone -> [the material of each ceiling panel in it]
var _boxes := {}

@onready var sky: Node3D = $"../Sky"
@onready var video: Node = $"../Video"
const WINDOWS := 5  # lights along the storefront
const DAYLIGHT := 1.5  # how strong each is at noon
const SCREEN_GAIN := 7.0  # the TV's light, for a full-white frame
const PANEL_ON := Color(0.973, 0.984, 1.0)  # 0xf8fbff
const PANEL_COLD := Color(0.188, 0.204, 0.239)  # 0x30343d: between stutters
const PANEL_OFF := Color(0.051, 0.063, 0.086)  # 0x0d1016


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).lights
	names = d.names
	switches = d.switches
	for zone: String in d.zones:
		zone_on[zone] = d.zones[zone]
		zone_lvl[zone] = 1.0 if zone_on[zone] else 0.0
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	_boxes = d.boxes
	# the ceiling's light panels: flat, white and unlit, up under a ceiling, a few meshes to a zone. Each gets a material
	# of its own, to go dark with its zone's switch and stutter back on with it (the web game's panelMats)
	for zone: String in zone_on:
		_panels[zone] = []
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		var m := mi.mesh.surface_get_material(0)
		var box := mi.global_transform * mi.get_aabb()
		if not m is StandardMaterial3D or m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or m.albedo_color.v < 0.85 or m.albedo_color.s > 0.12:
			continue
		if box.size.y > 0.06 or box.position.y < 2.3:  # (a zone's panels are one mesh, or a few: flat, and up at the ceiling)
			continue
		var zone := zone_at(box.get_center())
		if zone == "":
			continue
		var own: StandardMaterial3D = m.duplicate()
		mi.set_surface_override_material(0, own)
		own.albedo_color = PANEL_ON if zone_on[zone] else PANEL_OFF
		_panels[zone].append(own)
	var f: Array = d.boxes.floor  # the sales floor: x0, x1, back wall z, ceiling
	for i in WINDOWS:  # along the glass, just inside it, shining back into the store: what's in the way throws a shadow
		var w := SpotLight3D.new()
		w.position = Vector3(lerpf(f[0], f[1], (i + 0.5) / WINDOWS), 2.0, 0.45)
		w.basis = Basis.looking_at(Vector3(0, -0.1, 1).normalized())
		w.spot_range = 36.0
		w.spot_angle = 80.0
		w.spot_attenuation = 1.4  # (fading toward the back, as the web game's does)
		w.light_specular = 0.0
		w.shadow_enabled = true
		add_child(w)
		_windows.append(w)
	for sc: Dictionary in all.screens:  # the TV and the theater's screen: out into the room they face, with shadows
		var g := SpotLight3D.new()
		var dir := Vector3(sin(sc.ry), 0, cos(sc.ry))
		g.position = Vector3(sc.x, sc.y, sc.z) + dir * 0.1
		g.basis = Basis.looking_at(dir)
		g.spot_range = 24.0 if sc.kind == "tv" else 15.0
		g.spot_angle = 82.0
		g.spot_attenuation = 1.2
		g.light_specular = 0.0
		g.shadow_enabled = true
		g.set_meta("gain", SCREEN_GAIN * (sc.w * sc.h) / 2.16)  # (a bigger screen's more light: the TV's is 1.8 x 1.2)
		add_child(g)
		_glows.append(g)
	for m: Dictionary in all.minis:  # the monitors over the aisles: a little pool under each
		var g := OmniLight3D.new()
		g.position = Vector3(m.p[0], m.p[1], m.p[2]) + Basis(Quaternion(m.q[0], m.q[1], m.q[2], m.q[3])).z * 0.25
		g.omni_range = 4.5
		g.light_specular = 0.0
		g.set_meta("gain", SCREEN_GAIN * 0.12)
		add_child(g)
		_glows.append(g)
	for lp: Dictionary in d.lamps:  # the side lamps: mood lighting only, barely past their own pool
		var l := OmniLight3D.new()
		l.position = Vector3(lp.p[0], lp.p[1], lp.p[2])
		l.omni_range = lp.range
		l.light_color = Color.hex((int(lp.color) << 8) | 0xff)
		l.light_specular = 0.0
		add_child(l)
		var shades := []  # its shade and bulb: what glows on it, to go out with it
		for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
			var c := mi.global_transform * mi.get_aabb().get_center()
			if mi.mesh != null and Vector2(c.x - l.position.x, c.z - l.position.z).length() < 0.3 and absf(c.y - l.position.y) < 0.45:
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					if m is ShaderMaterial and m.get_shader_parameter("emission") != null and m.get_shader_parameter("emission") != Vector3.ZERO:
						shades.append([m, m.get_shader_parameter("emission")])
		lamps.append({ "light": l, "on": lp.on, "at": l.position, "energy": lp.energy * 1.6, "shades": shades })
		l.light_energy = lp.energy * 1.6 if lp.on else 0.0


func set_zone(zone: String, on: bool) -> void:
	zone_on[zone] = on
	if on:
		var duration := 1.1 + randf() * 0.6
		var schedules := []
		for i in maxi(1, _panels[zone].size()):
			schedules.append(_flicker_schedule(duration))
		_warm[zone] = { "t": 0.0, "duration": duration, "schedules": schedules }
	else:
		_warm.erase(zone)
		zone_lvl[zone] = 0.0
		for p: StandardMaterial3D in _panels[zone]:
			p.albedo_color = PANEL_OFF


func flip_switch(zone: String) -> void:
	set_zone(zone, not zone_on[zone])


func zone_at(p: Vector3) -> String:  # which switch lights this spot ("" outdoors): the room shader's boxes
	var f: Array = _boxes.floor
	var b: Array = _boxes.boh
	var lo: Array = _boxes.lobby
	var th: Array = _boxes.theater
	if p.x > f[0] and p.x < f[1] and p.z > -0.05 and p.z < f[2]:
		return "front" if p.z < 10.0 else "aisles" if p.z < 19.0 else "lounge"
	if p.x > b[0] and p.x < b[1] and p.z >= f[2] and p.z < b[3] and (p.z < b[2] or p.x < f[1]):
		if p.x > f[1]:
			return "closet"
		return "hall" if p.z < b[2] else "breakroom" if p.x < _boxes.bohSplit[0] else "restroom"
	if p.x > lo[0] and p.x < lo[1] and p.z >= lo[2] and p.z < lo[3]:
		return "lobby"
	if p.x > th[0] and p.x < th[1] and p.z >= th[2] and p.z < th[3]:
		return "theater"
	return ""


func set_lamp(lamp: Dictionary, on: bool) -> void:
	lamp.on = on
	lamp.light.light_energy = lamp.energy if on else 0.0
	for s: Array in lamp.shades:
		s[0].set_shader_parameter("emission", s[1] if on else Vector3.ZERO)


func _flicker_schedule(duration: float) -> Array:  # when one tube's lit while it's warming up: [[on, off], ...]
	if randf() > 0.4:
		return [[randf() * 0.5, duration]]  # comes on cleanly, just staggered
	var pulses := []
	var t := randf() * 0.15
	for i in 2 + randi() % 3:  # 2-4 stutters before it strikes
		var on := t + 0.03 + randf() * 0.12
		pulses.append([t, on])
		t = on + 0.05 + randf() * 0.22
	pulses.append([t, duration])
	return pulses


func _process(dt: float) -> void:  # fluorescents restriking, tube by tube (lightingTick)
	var day: Vector3 = sky.day_c * sky.level + Vector3(0.035, 0.045, 0.08) * (1.0 - sky.level)  # what comes in through the glass: daylight, or moonlight and the lot's lamps
	for w in _windows:
		w.light_color = Color(day.x, day.y, day.z).linear_to_srgb()
		w.light_energy = DAYLIGHT
	_glow = _glow.lerp(video.tint, minf(1.0, dt * 6.0))  # the light chases the picture
	for g in _glows:
		g.light_color = _glow
		g.light_energy = g.get_meta("gain")
		g.visible = _glow.v > 0.004
	for zone: String in _warm.keys():
		var w: Dictionary = _warm[zone]
		w.t += dt
		var done: bool = w.t >= w.duration
		var lit := 0
		for k in w.schedules.size():
			var s: Array = w.schedules[k]
			var on: bool = done or s.any(func(p: Array) -> bool: return w.t >= p[0] and w.t < p[1])
			lit += int(on)
			if k < _panels[zone].size():
				_panels[zone][k].albedo_color = PANEL_ON if on else PANEL_COLD
		zone_lvl[zone] = float(lit) / w.schedules.size()
		if done:
			_warm.erase(zone)
