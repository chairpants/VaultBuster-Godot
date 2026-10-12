extends Node
## The store's lights: nine zones, each on its own switch, fluorescents that stutter before they strike; and the two
## side lamps by the couch.
## From the web game: store/lounge.js (zoneOn, zoneLvl, setZone, lightingTick, buildFlickerSchedule, flickerLit),
## store/clock.js (flipSwitch), store/tv.js (setLamp), and the room shader in store/core.js (ROOM_FRAG) for which
## zone lights where: the sales floor is three zones along z (front to 10 m, aisles to 19, lounge behind), the back of
## house is the hall, the break room and the restroom, then the theater's lobby and its auditorium (both start off).
## The switches, the zones' rooms and the lamps are the web game's, from data/interact.json.
##
## Godot's own: the web game lights by where a pixel is, in its materials' shader, with no light objects. Here each
## zone is a grid of plain lights under its ceiling, so light crosses a wall where a room's dark next to a lit one.

var zone_on := {}  # zone -> bool
var zone_lvl := {}  # zone -> 0..1, flickering while the tubes warm up (what the lights get)
var names := {}
var switches: Array = []
var lamps: Array = []

var _warm := {}  # zone -> { t, duration, schedules } while its tubes restrike
var _tubes := {}  # zone -> [OmniLight3D]

@onready var sky: Node3D = $"../Sky"


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).lights
	names = d.names
	switches = d.switches
	var f: Array = d.boxes.floor  # x0, x1, back wall z, ceiling
	var b: Array = d.boxes.boh  # x0, x1, hall | rooms z, z1
	var rooms := {  # zone -> [x0, x1, z0, z1, the lights' height]
		"front": [f[0], f[1], 0.0, 10.0, 3.0], "aisles": [f[0], f[1], 10.0, 19.0, 3.0], "lounge": [f[0], f[1], 19.0, f[2], 3.0],
		"hall": [b[0], f[1], f[2], b[2], 2.4], "closet": [f[1], b[1], f[2], b[2], 2.2],
		"breakroom": [b[0], d.boxes.bohSplit[0], b[2], b[3], 2.4], "restroom": [d.boxes.bohSplit[0], f[1], b[2], b[3], 2.4],
		"lobby": [d.boxes.lobby[0], d.boxes.lobby[1], d.boxes.lobby[2], d.boxes.lobby[3], 2.6],
		"theater": [d.boxes.theater[0], d.boxes.theater[1], d.boxes.theater[2], d.boxes.theater[3], 3.4],
	}
	for zone: String in d.zones:
		zone_on[zone] = d.zones[zone]
		zone_lvl[zone] = 1.0 if zone_on[zone] else 0.0
		_tubes[zone] = []
		var r: Array = rooms[zone]
		var nx := maxi(1, roundi((r[1] - r[0]) / 4.5))
		var nz := maxi(1, roundi((r[3] - r[2]) / 4.5))
		for ix in nx:
			for iz in nz:
				var l := OmniLight3D.new()
				l.position = Vector3(r[0] + (ix + 0.5) * (r[1] - r[0]) / nx, r[4], r[2] + (iz + 0.5) * (r[3] - r[2]) / nz)
				l.omni_range = minf(8.0, maxf(3.5, maxf(r[1] - r[0], r[3] - r[2])))
				l.light_color = Color(1.0, 0.82, 0.6) if zone == "closet" or zone == "theater" else Color(1, 0.98, 0.94)  # (one bare bulb; the house lights: warm)
				l.light_specular = 0.0
				add_child(l)
				_tubes[zone].append(l)
	for lp: Dictionary in d.lamps:  # the side lamps: mood lighting only, barely past their own pool
		var l := OmniLight3D.new()
		l.position = Vector3(lp.p[0], lp.p[1], lp.p[2])
		l.omni_range = lp.range
		l.light_color = Color.hex((int(lp.color) << 8) | 0xff)
		l.light_specular = 0.0
		add_child(l)
		lamps.append({ "light": l, "on": lp.on, "at": l.position, "energy": lp.energy * 4.0 })
		l.light_energy = lp.energy * 4.0 if lp.on else 0.0


func set_zone(zone: String, on: bool) -> void:
	zone_on[zone] = on
	if on:
		var duration := 1.1 + randf() * 0.6
		var schedules := []
		for i in _tubes[zone].size():
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


func _process(dt: float) -> void:
	var base := lerpf(0.7, 0.25, sky.level)  # (by day the daylight's in there with them already)
	for zone: String in _tubes:
		var lit: Array = []
		if _warm.has(zone):  # fluorescents restriking, tube by tube
			var w: Dictionary = _warm[zone]
			w.t += dt
			var done: bool = w.t >= w.duration
			var n := 0
			for s: Array in w.schedules:
				var on: bool = done or s.any(func(p: Array) -> bool: return w.t >= p[0] and w.t < p[1])
				lit.append(on)
				n += int(on)
			zone_lvl[zone] = float(n) / maxi(1, w.schedules.size())
			if done:
				_warm.erase(zone)
		for i in _tubes[zone].size():
			_tubes[zone][i].light_energy = base * ((1.0 if lit[i] else 0.0) if lit.size() else zone_lvl[zone])
