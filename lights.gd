extends Node
## The store's lights: nine zones, each on its own switch, fluorescents that stutter before they strike; and the two
## side lamps by the couch.
## From the web game: store/lounge.js (zoneOn, zoneLvl, setZone, lightingTick, buildFlickerSchedule, flickerLit),
## store/clock.js (flipSwitch), store/tv.js (setLamp), and the room shader in store/core.js (ROOM_FRAG) for which
## zone lights where: the sales floor is three zones along z (front to 10 m, aisles to 19, lounge behind), the back of
## house is the hall, the break room and the restroom, then the theater's lobby and its auditorium (both start off).
## The switches, the zones' rooms and the lamps are the web game's, from data/interact.json.
##
## What a zone's level does to the room is room.gd's business. The lamps are real lights.

var zone_on := {}  # zone -> bool
var zone_lvl := {}  # zone -> 0..1, flickering while the tubes warm up (what the lights get)
var names := {}
var switches: Array = []
var lamps: Array = []

var _warm := {}  # zone -> { t, duration, schedules } while its tubes restrike
const TUBES := 8  # how many fixtures stutter on, a zone (the web game counts its ceiling panels)


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).lights
	names = d.names
	switches = d.switches
	for zone: String in d.zones:
		zone_on[zone] = d.zones[zone]
		zone_lvl[zone] = 1.0 if zone_on[zone] else 0.0
	for lp: Dictionary in d.lamps:  # the side lamps: mood lighting only, barely past their own pool
		var l := OmniLight3D.new()
		l.position = Vector3(lp.p[0], lp.p[1], lp.p[2])
		l.omni_range = lp.range
		l.light_color = Color.hex((int(lp.color) << 8) | 0xff)
		l.light_specular = 0.0
		add_child(l)
		lamps.append({ "light": l, "on": lp.on, "at": l.position, "energy": lp.energy * 1.6 })
		l.light_energy = lp.energy * 1.6 if lp.on else 0.0


func set_zone(zone: String, on: bool) -> void:
	zone_on[zone] = on
	if on:
		var duration := 1.1 + randf() * 0.6
		var schedules := []
		for i in TUBES:
			schedules.append(_flicker_schedule(duration))
		_warm[zone] = { "t": 0.0, "duration": duration, "schedules": schedules }
	else:
		_warm.erase(zone)
		zone_lvl[zone] = 0.0


func flip_switch(zone: String) -> void:
	set_zone(zone, not zone_on[zone])


func set_lamp(lamp: Dictionary, on: bool) -> void:
	lamp.on = on
	lamp.light.light_energy = lamp.energy if on else 0.0


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
	for zone: String in _warm.keys():
		var w: Dictionary = _warm[zone]
		w.t += dt
		var done: bool = w.t >= w.duration
		var lit := 0
		for s: Array in w.schedules:
			if done or s.any(func(p: Array) -> bool: return w.t >= p[0] and w.t < p[1]):
				lit += 1
		zone_lvl[zone] = float(lit) / w.schedules.size()
		if done:
			_warm.erase(zone)
