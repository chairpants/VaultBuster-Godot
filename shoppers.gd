extends Node
## Customers. Each walks through a visit: up the sidewalk and in the door, a few shelves looked over, a tape taken (or
## put back, or none), then the line at the register, getting steadily less patient, and out again.
## From the web game's store/shoppers.js: customerFor (who they are, from a seed: their taste, patience, pace, how
## many shelves they'll look at, how many tapes they'll take), rushLevel and custTick (how busy it is through the
## day; who comes in when), browseSpots (every stretch of shelf, found from the tapes), custGo, custNextStop,
## custDwell, custDecide, custPickCopy, custDone, the line (custToLine, custLeaveLine), and the visit itself (custStep).
##
## Not over yet, and so different here:
## - What they rent comes back when it's due (two nights a new release, five the rest): somebody walks in with it and
##   drops it in the Returns slot, and it's in the bin till it's put away (tapes.gd). Nobody's late, so no fees.
## - Shoplifters and the gates are the web game's (custSneak, custCatch, custWatched, wisTick, empCatch, tagFix,
##   custHearAlarm, custGone's stolen tapes; title.js's startGateAlarm), but for what needs members: nobody's got a
##   name or a record, so one you catch is let off with a warning (no 1-5 call), and a stolen tape's just gone (no
##   ordering a replacement). The gates' lights don't flash; they're never switched off.
## - Nobody's a member: each is a new face (the web game's are its 150 members, the same person every visit).
## - No snacks, no questions at the counter, no kids or company, no cars, nobody going to the theater.

const Nav := preload("res://nav.gd")
const TASTES := [
	["horror fan", ["Horror", "Horror & Anthology", "MonsterVision"]],
	["parent", ["Family & Kids", "Kids & Educational", "Animation", "Holiday"]],
	["couch potato", ["Sitcoms", "Classic Sitcoms", "Drama & Adventure", "Sketch Comedy & Late Night", "Reality TV"]],
	["action junkie", ["Action & Adventure", "Sci-Fi & Fantasy"]],
	["date night", ["Comedy", "Drama"]],
	["anime kid", ["Anime", "Animation", "Sci-Fi & Fantasy"]],
	["wanderer", []],  # no favorites: grabs whatever catches their eye
]
const GAIT_ODDS := [["plain", 30.0], ["brisk", 14.0], ["stroll", 10.0], ["bouncy", 10.0], ["shuffle", 10.0], ["swagger", 10.0], ["sway", 8.0], ["stomp", 8.0]]

var custs: Array[Dictionary] = []
var line: Array[Dictionary] = []  # the checkout line: line[0] is the one at the counter
var aim = null  # the customer the crosshair's on
var rented: Array = []  # what's out: [tape, the day it went out, the day it's due]
var _slot := {}  # in the lane, facing the drop slot
var alarm_on := false  # the gates going off
var alarm_t := 0.0

const GATE_Z := 4.0  # the security gates' line across the entry lane (|x| < 2)
var _beeper := AudioStreamPlayer3D.new()
var _you_z := 0.0

var _nav: RefCounted
var _spots: Array = []  # where they browse: { x, z, ry, n, cats, copies }
var _door := Vector2.ZERO
var _outside := Vector2.ZERO
var _inside := Vector2.ZERO
var _counter := {}
var _arrive := 3.0

@onready var people: Node3D = $"../People"
@onready var tapes: Node = $"../Tapes"
@onready var things: Node = $"../Things"
@onready var weather: Node3D = $"../Weather"
@onready var hud: CanvasLayer = $"../HUD"
@onready var player: CharacterBody3D = $"../Player"
@onready var interact: Node = $"../Interact"
@onready var checkout: Node = $"../Checkout"


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).nav
	_nav = Nav.new(d)
	_door = Vector2(d.door.x, d.door.z)
	_outside = Vector2(d.outside[0], d.outside[1])
	_inside = Vector2(d.inside[0], d.inside[1])
	_counter = d.counter
	var sl: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.returns.slot
	_slot = { "x": sl[0] + 0.6, "z": sl[2], "ry": -PI / 2.0 }
	var wav := AudioStreamWAV.new()  # the two-tone shop alarm: a square wave, 2600 then 2050 Hz, 0.2 s on in every 0.28
	var data := PackedByteArray()
	for f: float in [2600.0, 2050.0]:
		for i in int(22050 * 0.28):
			data.append((40 if fmod(i * f / 22050.0, 1.0) < 0.5 else 216) if i < 22050 * 0.2 else 0)
	wav.data = data
	wav.mix_rate = 22050
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = data.size()
	_beeper.stream = wav
	_beeper.volume_db = -16.0
	_beeper.unit_size = 6.0
	_beeper.position = Vector3(0.0, 1.5, GATE_Z)
	add_child(_beeper)
	call_deferred("_browse_spots")  # (once the tapes have found themselves)


func _browse_spots() -> void:  # every shelf face in the store, found from the tapes: ~1.5 m stretches, each a spot 0.8 m out in the aisle
	var groups := {}
	for t: Dictionary in tapes.tapes:
		var fx := cos(t.ry)  # shelves face their local +x
		var fz := -sin(t.ry)
		var sx: float = t.p[0] + fx * 0.8
		var sz: float = t.p[2] + fz * 0.8
		if sx < -2.25 and sz < 4.5:
			continue  # behind the counter is staff only
		var key := "%d,%d,%d" % [roundi(sx / 1.5), roundi(sz / 1.5), roundi(t.ry / (PI / 2.0))]
		if not groups.has(key):
			groups[key] = { "x": 0.0, "z": 0.0, "fx": fx, "fz": fz, "n": 0, "cats": {}, "copies": [] }
		var gr: Dictionary = groups[key]
		gr.x += sx
		gr.z += sz
		gr.n += 1
		gr.copies.append(t)
		gr.cats[t.c] = gr.cats.get(t.c, 0) + 1
	var reach: PackedByteArray = _nav.reachable_from(_door.x, _door.y)
	for gr: Dictionary in groups.values():
		if gr.n < 4:
			continue
		var s := { "x": gr.x / gr.n, "z": gr.z / gr.n, "ry": atan2(-gr.fx, -gr.fz), "n": gr.n, "cats": gr.cats, "copies": gr.copies }  # facing the shelf
		var at: int = _nav.at(s.x, s.z)
		if at >= 0 and reach[at] == 1:
			_spots.append(s)
	print("shoppers: %d stretches of shelf to browse" % _spots.size())


# ---- who's walking in

func _seeded(seed: int) -> Callable:  # the web game's seeded(): the same seed, the same numbers
	var s := [seed & 0xffffffff]
	return func() -> float:
		s[0] = (s[0] + 0x6D2B79F5) & 0xffffffff
		var t: int = _imul(s[0] ^ (s[0] >> 15), 1 | s[0])
		t = ((t + _imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t
		return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0


func _imul(a: int, b: int) -> int:
	return ((a & 0xffffffff) * (b & 0xffffffff)) & 0xffffffff


func customer_for(seed: int, female: bool) -> Dictionary:
	var rnd := _seeded(seed)
	var taste: Array = TASTES[int(rnd.call() * TASTES.size())]
	var who := { "seed": seed, "rnd": rnd, "female": female, "taste": taste[0], "cats": taste[1],
		"patience": 0.6 + rnd.call() * 1.2,  # scales how long they'll wait at the counter
		"speed": 1.0 + rnd.call() * 0.55,  # m/s
		"picky": 0.25 + rnd.call() * 0.5 }  # chance a shelf they like has something for them
	var r: float = rnd.call()  # shelves they'll look at: 1-3 mostly, a proper browse now and then, rarely 7-10
	who.stops = 7 + int(rnd.call() * 4) if r < 0.05 else 4 + int(rnd.call() * 3) if r < 0.2 else 1 + int(rnd.call() * 3)
	who.max_tapes = 1 + int(rnd.call() < 0.35) + int(rnd.call() < 0.12)  # most rent one; some make a night of it
	who.dwell = 0.6 + rnd.call() * 0.9  # how long they tend to stand at a shelf
	who.stops = mini(10, who.stops + who.max_tapes - 1)  # a bigger haul means more shelves to look at
	var style := _seeded(seed ^ 0x5bd1e995)  # how they move: its own stream
	var total := 0.0
	var odds := []
	for o: Array in GAIT_ODDS:
		var n: float = o[1] * ((0.4 if female else 1.6) if o[0] == "swagger" else (1.8 if female else 0.3) if o[0] == "sway" else 1.0)
		odds.append([o[0], n])
		total += n
	var x: float = style.call() * total
	who.gait = "plain"
	for o: Array in odds:
		x -= o[1]
		if x < 0.0:
			who.gait = o[0]
			break
	return who


func rush_level() -> float:  # slow mornings, a lunch bump, the after-school wave, the evening rush (bigger Friday and Saturday nights), a trickle before close
	var h := Clock.h
	var d: int = Clock.date().weekday
	var r := 0.5 if h < 12.0 else 0.9 if h < 14.0 else 0.7 if h < 15.0 else 1.2 if h < 17.5 else 0.9 if h < 18.5 else 1.5 if h < 21.5 else 0.9 if h < 23.0 else 0.5
	if (d == 5 or d == 6) and h >= 18.0:
		r *= 1.35
	if d == 2:
		r *= 1.15  # new release Tuesday
	var k: float = weather.k  # the weather: a wet afternoon is slow, a wet evening's a movie night
	if k > 0.0:
		r *= (1.0 - 0.4 * k if h < 17.0 else 1.0) if weather.kind == "snow" else (1.0 - 0.3 * k if h < 17.0 else 1.0 + 0.25 * k)
	return r


func spawn() -> Dictionary:
	var female := randf() < 0.5
	var who := customer_for(randi(), female)
	var cast: Array = range(people.cast.who.size()).filter(func(i: int) -> bool: return people.cast.who[i].female == female and not people.cast.who[i].has("staff"))
	var c: Node3D = people.spawn(cast[who.seed % cast.size()])
	c.gait = who.gait
	var from := Vector2((-1.0 if randf() < 0.5 else 1.0) * (14.0 + randf() * 6.0), -0.9)  # up the sidewalk
	c.position = Vector3(from.x, 0.0, from.y)
	c.set_mood("on")
	var cust := { "who": who, "c": c, "ry": 0.0, "face": 0.0, "hi": 0.0, "holding": 0, "tapes": [], "seen": [], "stops_left": who.stops,
		"path": [_outside, _inside, _door], "from": from, "spot": null, "state": "arrive", "t": 0.6, "paid": false, "reach": "", "reach_copy": null,
		"thief": randf() < 0.06, "sneaking": false, "tagged": false, "alarmed": false, "known": false, "greeted": false, "watch_t": 0.0, "fess": false, "last_z": 0.0,  # (thief: now and then somebody means to walk out with it)
		"heard": false, "look_t": 0.0, "fed_up": false,
		"squeeze": 0.0, "stuck": 0.0, "detour": false, "bump_t": 0.0, "bump_detour": false, "wait_for": null }
	# about half the time it's someone with tapes out, bringing them back: what's due (or late), and half the time what's due tomorrow
	var due := rented.filter(func(r: Array) -> bool: return r[2] <= Clock.day or (r[2] == Clock.day + 1 and randf() < 0.5))
	cust.returning = []
	if not due.is_empty() and randf() < 0.5:
		due.shuffle()
		for r: Array in due.slice(0, 1 + randi() % 3):
			rented.erase(r)
			cust.returning.append(r[0])
		c.set_pose("hold")
		c.hold_tape(mini(3, cust.returning.size()))
	custs.append(cust)
	return cust


# ---- the visit

func _process(dt: float) -> void:
	var cap := mini(6, roundi(2.0 + 2.0 * rush_level()))
	var open := Clock.h >= Clock.OPEN and Clock.h < Clock.LAST_IN
	if custs.size() < cap and not things.locked and open and not people._templates.is_empty():  # locked: whoever's inside finishes up; nobody new
		_arrive -= dt
		if _arrive <= 0.0:
			if custs.any(func(k: Dictionary) -> bool: return Vector2(k.c.position.x - _door.x, k.c.position.z - _door.y).length() < 1.2):
				_arrive = 1.0  # someone's in the doorway: give them a sec
			else:
				spawn()
				_arrive = (6.0 + randf() * 20.0) / rush_level()
	var you: Vector3 = player.global_position
	if you.y < 2.0 and absf(you.z - _you_z) < 1.0 and absf(you.x) < 2.0 and (_you_z - GATE_Z) * (you.z - GATE_Z) < 0.0 and tapes.inv.any(func(t: Dictionary) -> bool: return not t.get("desens", false)):
		start_alarm()  # carried a tape through the gates
	_you_z = you.z
	if alarm_on:
		alarm_t += dt
	var dana: Node3D = $"../Staff".dana
	for k: Dictionary in custs.duplicate():
		_hear_alarm(k, dt)
		if k.sneaking and not k.alarmed:
			_watched(k, dt)
			if k.sneaking and dana != null and dana.position.distance_to(k.c.position) < 3.5 and randf() < dt * 0.03 * 2.0:  # (her WIS of 2: a chance each second to stop them on the way past)
				catch(k, "dana")
		_step(k, dt)


func start_alarm() -> void:
	if alarm_on:
		return
	alarm_on = true
	alarm_t = 0.0
	_beeper.play()


func silence_alarm() -> void:
	alarm_on = false
	_beeper.stop()


func _hear_alarm(cust: Dictionary, dt: float) -> void:  # everyone's head snaps round to the gates for a moment; let it ring and they get fed up, and anyone waiting to pay loses patience faster
	var c: Node3D = cust.c
	if not alarm_on:
		if cust.heard:
			cust.heard = false
			cust.fed_up = false
			if cust.look_t > 0.0:
				cust.look_t = 0.0
				c.look_at_yaw(null)
		return
	if not cust.heard:
		cust.heard = true
		cust.look_t = 1.4 + randf() * 0.6
		if not cust.alarmed:  # (whoever set it off has their own face on)
			c.set_mood("shock")
			cust.hi = 1.2
	if cust.look_t > 0.0:
		c.look_at_yaw(clampf(angle_difference(cust.face, atan2(-c.position.x, GATE_Z - c.position.z)), -1.3, 1.3))  # over the shoulder, as far as a neck goes
		cust.look_t -= dt
		if cust.look_t <= 0.0:
			c.look_at_yaw(null)
	if alarm_t > 4.0 and not cust.fed_up and not cust.alarmed:
		cust.fed_up = true
		c.set_mood("meh")
		cust.hi = 2.5
	if cust.state in ["wait", "impatient", "inLine"]:
		cust.t -= dt * 0.5  # standing there listening to that


func _what(cust: Dictionary) -> String:
	return cust.tapes[0].t if cust.tapes.size() == 1 else "%d tapes" % cust.tapes.size()


func _sneak(cust: Dictionary) -> void:  # a shoplifter: tapes under the jacket, eyes everywhere, straight for the door
	cust.sneaking = true
	cust.tagged = cust.tapes.any(func(t: Dictionary) -> bool: return not t.get("desens", false))
	cust.alarmed = false
	cust.c.hold_tape(0)
	cust.c.set_pose("idle")
	cust.c.set_mood("shifty")
	go(cust, "leave", { "x": _door.x, "z": _door.y })


func _watched(cust: Dictionary, dt: float) -> void:  # sneaking out, they notice you watching (the crosshair on them a moment): half the time they lose their nerve and bring it to the counter
	if cust.fess:
		return
	if aim != cust:
		cust.watch_t = 0.0
		return
	cust.watch_t += dt
	if cust.watch_t < 0.8:
		return
	cust.fess = true
	if randf() >= 0.5:
		return  # ...or they keep going
	cust.sneaking = false
	cust.tagged = false
	cust.thief = false
	cust.c.hold_tape(cust.tapes.size())
	cust.c.set_pose("hold")
	cust.c.set_mood("meh")
	cust.hi = 2.0
	hud.toast("A customer saw you watching and brought %s to the counter" % (cust.tapes[0].t if cust.tapes.size() == 1 else "the tapes"))
	line.append(cust)
	to_line(cust)


func catch(cust: Dictionary, by: String) -> void:  # stopped before they're out the door: the tapes come back (custCatch, empCatch)
	var what := _what(cust)
	tapes.return_bin.append_array(cust.tapes)
	cust.tapes = []
	cust.holding = 0
	cust.tagged = false
	cust.sneaking = false
	cust.known = true
	cust.c.hold_tape(0)
	cust.c.set_mood("shock")
	cust.hi = 1.5
	checkout.score += 150
	hud.toast("%s a customer sneaking out with %s (back in the returns bin, a warning) (+150)" % ["Dana caught" if by == "dana" else "Caught", what])
	if by == "dana":
		go(cust, "leave", { "x": _door.x, "z": _door.y })
	else:  # a word with them, then out
		cust.path = []
		cust.state = "caught"
		cust.t = 2.0


func tag_fix(cust: Dictionary, by: String) -> void:  # their tapes over the desensitizer, and on their way
	for t: Dictionary in cust.tapes:
		t.desens = true
	silence_alarm()
	cust.tagged = false
	cust.c.set_mood("meh")
	cust.hi = 1.5
	hud.toast("%s fixed a customer's tag: they're on their way" % ("Dana" if by == "dana" else "You"))
	go(cust, "leave", { "x": _door.x, "z": _door.y })


func at_the_door() -> bool:  # anyone right at the door: it swings open (interact.gd)
	return custs.any(func(k: Dictionary) -> bool: return Vector2(k.c.position.x - 0.9, k.c.position.z + 0.2).length() < 1.3)


func go(cust: Dictionary, state: String, spot: Dictionary, avoid_player := false) -> void:  # head for a spot; state is what to do on arrival
	var p: Vector3 = cust.c.position
	if state == "leave":
		leave_line(cust)
	var you := Vector2(player.global_position.x, player.global_position.z)
	if you.distance_to(Vector2(spot.x, spot.z)) <= 0.6:  # you're standing on it: the next spot along
		var ry: float = spot.get("ry", 0.0)
		for k in [0.75, -0.75, 1.1, -1.1]:
			var q := Vector2(spot.x + cos(ry) * k, spot.z - sin(ry) * k)
			if _nav.open_at(q.x, q.y) and you.distance_to(q) > 0.6:
				spot = spot.duplicate()
				spot.x = q.x
				spot.z = q.y
				break
	var others: Array = custs.filter(func(k: Dictionary) -> bool: return k != cust and k.c.position.z > 0.3).map(func(k: Dictionary) -> Vector2: return Vector2(k.c.position.x, k.c.position.z))
	if avoid_player:
		others.append(you)
	var way: Array = _nav.path(p.x, p.z, spot.x, spot.z, others)
	if way.is_empty():
		way = _nav.path(p.x, p.z, spot.x, spot.z)  # someone's standing in the doorway: plan through them (the walk waits them out)
	if not avoid_player:
		cust.detour = false
	cust.stuck = 0.0
	cust.bump_detour = false
	if way.is_empty():  # no way there right now: try again in a sec (never straight through a wall)
		cust.path = []
		cust.repath = [state, spot]
		cust.state = "repath"
		cust.t = 1.0
		cust.spot = spot
		return
	cust.path = way
	cust.state = state
	cust.spot = spot


func _yield_to_you(cust: Dictionary, to: Vector2, dt: float) -> bool:  # yields while you're right ahead; goes round after a moment; slips past if there's truly no way
	if cust.squeeze > 0.0:
		cust.squeeze -= dt  # excuse me...
		return false
	var off := Vector2(player.global_position.x - cust.c.position.x, player.global_position.z - cust.c.position.z)
	if not (off.length() < (0.5 if cust.detour else 0.75) and off.dot(to) > 0.0 and absf(player.global_position.y - cust.c.position.y) < 1.5):
		return false
	cust.stuck += dt
	if cust.stuck > 0.6 and not cust.detour:
		cust.detour = true
		go(cust, cust.state, cust.spot, true)  # go around
		cust.detour = true
		cust.stuck = 0.01
	elif cust.stuck > 3.5:
		cust.squeeze = 1.4  # no way round: slip past
		cust.stuck = 0.0
	return true


func _bumps(cust: Dictionary, to: Vector2, dt: float) -> bool:  # the same manners with the other shoppers (and Dana): wait a beat, go round, slip past
	if cust.squeeze > 0.0:
		return false
	var here := Vector2(cust.c.position.x, cust.c.position.z)
	var dir := to.normalized()
	var who = null
	for k: Dictionary in custs:
		var off := Vector2(k.c.position.x, k.c.position.z) - here
		if k != cust and k.get("wait_for") != cust and off.length() < 0.7 and off.dot(dir) > off.length() * 0.5:
			who = k
			break
	cust.wait_for = who  # (two meeting head-on don't both wait: whoever's already waiting on the other gets the right of way)
	if who == null:
		cust.bump_t = 0.0
		return false
	cust.bump_t += dt
	if cust.bump_t > 0.7 and not cust.bump_detour:
		go(cust, cust.state, cust.spot)  # go around
		cust.bump_detour = true
		cust.bump_t = 0.01
	elif cust.bump_t > 3.0:
		cust.squeeze = 1.4  # pardon me
		cust.bump_t = 0.0
	return true


func _line_spot(i: int) -> Dictionary:  # the front of the line stands at the counter, the rest queue back into the store behind them
	return { "x": _counter.x, "z": _counter.z + 0.85 * i, "ry": PI } if i else _counter


func to_line(cust: Dictionary) -> void:
	var i := line.find(cust)
	go(cust, "queue" if i else "counter", _line_spot(i))


func leave_line(cust: Dictionary) -> void:  # out of the line: everyone behind shuffles up a spot
	var i := line.find(cust)
	if i < 0:
		return
	line.remove_at(i)
	for k: Dictionary in line.slice(i):
		if k.state in ["queue", "inLine", "counter"]:
			to_line(k)


func _likes(cust: Dictionary, spot) -> float:  # 0..1: how much of this shelf is their kind of thing
	if spot == null or not spot.has("cats"):
		return 0.0
	var cats: Array = cust.who.cats
	if cats.is_empty():
		return 0.3
	var n := 0
	for c: String in cats:
		n += spot.cats.get(c, 0)
	return minf(1.0, float(n) / spot.n)


func _next_stop(cust: Dictionary) -> void:  # a shelf they haven't looked at yet (and nobody else is at), favoring their kind of thing
	var spots := _spots.filter(func(s: Dictionary) -> bool: return not cust.seen.has(s) and not custs.any(func(k: Dictionary) -> bool: return k != cust and k.spot == s))
	if cust.stops_left == 1 and cust.holding == 0 and not cust.who.cats.is_empty():  # last stop, still empty-handed: one more try at their favorite section
		var favs := spots.filter(func(s: Dictionary) -> bool: return _likes(cust, s) > 0.5)
		if not favs.is_empty():
			spots = favs
	if spots.is_empty():
		_done(cust)
		return
	var total := 0.0
	var w := []
	for s: Dictionary in spots:
		w.append(1.0 + 8.0 * _likes(cust, s))
		total += w[-1]
	var r: float = cust.who.rnd.call() * total
	var i := 0
	while i < spots.size() - 1:
		r -= w[i]
		if r <= 0.0:
			break
		i += 1
	cust.seen.append(spots[i])
	go(cust, "stop", spots[i])


func _pick_copy(cust: Dictionary):  # a copy still on this shelf, favoring their kind of thing
	var cs: Array = cust.spot.copies.filter(func(t: Dictionary) -> bool: return not t.off and t != tapes.held and not tapes._corners(t).is_empty())
	if cs.is_empty():
		return null
	var total := 0.0
	var w := []
	for t: Dictionary in cs:
		w.append(6.0 if cust.who.cats.has(t.c) else 1.0)
		total += w[-1]
	var r: float = cust.who.rnd.call() * total
	var i := 0
	while i < cs.size() - 1:
		r -= w[i]
		if r <= 0.0:
			break
		i += 1
	return cs[i]


func _decide(cust: Dictionary) -> void:  # done browsing this shelf: take one, put one back, or move on
	var who: Dictionary = cust.who
	var likes := _likes(cust, cust.spot)
	var last: bool = cust.stops_left <= 1
	cust.stops_left -= 1
	var take: float = ((who.picky * likes * 1.2 if not who.cats.is_empty() else 0.25) + (0.3 if last and cust.holding == 0 else 0.03)) * pow(0.7, cust.holding)  # each extra tape is a harder sell
	if cust.holding < who.max_tapes and who.rnd.call() < take:
		cust.reach = "take"
	elif cust.holding > 0 and who.rnd.call() < 0.2:
		cust.reach = "swap"  # saw something better: put theirs back, take this
	elif cust.holding > 0 and who.rnd.call() < 0.12:
		cust.reach = "return"  # second thoughts
	else:
		cust.reach = ""
	if cust.reach != "":
		cust.reach_copy = null if cust.reach == "return" else _pick_copy(cust)  # decided now, so the hand goes to the copy they'll take
		var to = cust.reach_copy if cust.reach_copy != null else (cust.tapes[-1] if not cust.tapes.is_empty() else null)  # ...or the slot theirs goes back into
		if to != null:
			cust.c.reach_to(Vector3(to.p[0], to.p[1], to.p[2]))
		else:
			cust.c.set_pose("reach")
		cust.c.set_mood("meh" if cust.reach == "return" else "love" if likes > 0.4 else "happy")
		cust.state = "reach"
		cust.t = 1.3
	else:
		cust.c.set_mood("happy" if cust.holding > 0 else "neutral")
		if cust.stops_left > 0:
			_next_stop(cust)
		else:
			_done(cust)


func _done(cust: Dictionary) -> void:  # out of shelves to look at: to the register, or out
	if cust.thief and cust.holding > 0 and not (cust.known and randf() < 0.35):  # (you've had an eye on them: maybe not today)
		_sneak(cust)
		return
	if cust.holding > 0:
		cust.c.set_mood("happy")
		line.append(cust)
		to_line(cust)
	else:
		cust.c.set_mood("meh")
		go(cust, "leave", { "x": _door.x, "z": _door.y })


func waiting():  # whoever's at the counter, waiting to be rung up (or null)
	return line[0] if not line.is_empty() and line[0].state in ["wait", "impatient", "angry"] else null


func _gone(cust: Dictionary) -> void:
	leave_line(cust)
	var stolen: bool = cust.tagged and not cust.paid and not cust.tapes.is_empty()  # walked out with them unpaid: gone for good. A paid one with a missed tag is still just a rental
	if stolen:
		checkout.score -= 75 * cust.tapes.size()
		hud.toast("Someone walked out with %s: stolen (%d)" % [_what(cust), -75 * cust.tapes.size()])
	for t: Dictionary in cust.tapes:
		if cust.paid:
			rented.append([t, Clock.day, Clock.day + (2 if t.n else 5)])  # a new release is out two nights, the rest five
		elif stolen:
			t.lost = true
		else:
			tapes.set_on_shelf(t, true)
		t.desens = false  # (its tag's armed again when it's next on the shelf)
	cust.c.queue_free()
	custs.erase(cust)


func _step(cust: Dictionary, dt: float) -> void:  # custStep
	var c: Node3D = cust.c
	var who: Dictionary = cust.who
	var speed := 0.0
	if not cust.path.is_empty():  # walking: follow the path
		var to: Vector2 = cust.path[0] - Vector2(c.position.x, c.position.z)
		var d := to.length()
		if d < 0.05:
			cust.path.pop_front()
		elif _yield_to_you(cust, to, dt) or _bumps(cust, to, dt):  # you're in the way, or another shopper is
			pass
		else:
			speed = who.speed * (1.4 if cust.state == "outside" and not cust.paid and cust.holding > 0 else 1.0)  # storming out
			var step := minf(d, speed * dt)
			c.position += Vector3(to.x, 0.0, to.y) / d * step
			cust.ry = atan2(to.x, to.y)
			for door: Dictionary in interact.doors:  # open any unlocked closed door right in front of them
				if not door.open and not door.locked and not door.push:
					var mid := Vector2((door.shut.x0 + door.shut.x1) / 2.0, (door.shut.z0 + door.shut.z1) / 2.0)
					if mid.distance_to(Vector2(c.position.x, c.position.z)) < 1.1:
						interact.toggle_door(door)
		if cust.tagged and not cust.alarmed and absf(c.position.x) < 2.0 and cust.last_z >= GATE_Z and c.position.z < GATE_Z:  # out through the gates with a tagged tape
			cust.alarmed = true
			start_alarm()
			c.set_mood("alarm")
			if cust.paid and not cust.sneaking:  # a paying customer: you missed a tag. Back to the counter, not happy about it
				checkout.score -= 25
				cust.hi = 2.5
				hud.toast("A customer set off the gates: a tag wasn't desensitized. They're coming back to have it fixed (-25)")
				go(cust, "tagBack", { "x": _counter.x + 0.9, "z": _counter.z, "ry": PI })  # beside the line
		if cust.path.is_empty() and cust.spot != null and cust.spot.has("ry"):
			cust.ry = cust.spot.ry
	else:  # arrived: do this stop's thing
		cust.t -= dt
		match cust.state:
			"repath":
				if cust.t <= 0.0:
					go(cust, cust.repath[0], cust.repath[1])
			"arrive":  # in the door
				cust.state = "boot"
				cust.t = 0.0
			"outside":  # off up the sidewalk
				c.set_mood("off")
				_gone(cust)
				return
			"boot":
				if cust.t <= 0.0:
					c.set_mood("neutral")
					if not cust.returning.is_empty():
						go(cust, "dropoff", _slot)
					else:
						_next_stop(cust)
			"dropoff":  # at the slot: a hand out to it
				c.reach_to(Vector3(_slot.x - 0.6, 0.9, _slot.z))
				cust.state = "dropping"
				cust.t = 1.2
			"dropping":
				if cust.t <= 0.0:
					var n: int = cust.returning.size()
					for t: Dictionary in cust.returning:
						if randf() < 0.4:  # (not everybody's kind)
							tapes.set_wind_frac(t, 0.15 + randf() * 0.85)
						tapes.return_bin.append(t)
					hud.toast("A customer returned %s" % (cust.returning[0].t if n == 1 else "%d tapes" % n))
					if tapes.return_bin.size() >= 15 and tapes.return_bin.size() - n < 15:
						hud.toast("Returns are piling up: %d in the bin" % tapes.return_bin.size())
					cust.returning = []
					c.reach_to(null)
					c.hold_tape(0)
					c.set_pose("idle")
					c.set_mood("happy")
					if randf() < 0.5:
						_next_stop(cust)
					else:
						go(cust, "leave", { "x": _door.x, "z": _door.y })
			"stop":
				c.set_mood("browse")
				cust.state = "browse"
				cust.t = (2.0 + who.rnd.call() * 5.0) * who.dwell * (2.5 if who.rnd.call() < 0.1 else 1.0)  # a few seconds mostly; now and then something really grabs them
			"browse":
				if cust.t <= 0.0:
					_decide(cust)
			"reach":
				if cust.t <= 0.0:
					if cust.reach != "take":  # put back, into its slot
						tapes.set_on_shelf(cust.tapes.pop_back(), true)
					var got = cust.reach_copy if cust.reach_copy != null and not cust.reach_copy.off else (null if cust.reach == "return" else _pick_copy(cust))
					if cust.reach != "return" and got != null:
						tapes.set_on_shelf(got, false)
						cust.tapes.append(got)
					c.reach_to(null)
					cust.holding = cust.tapes.size()
					c.hold_tape(cust.holding)
					c.set_pose("hold" if cust.holding > 0 else "idle")
					if cust.stops_left > 0:
						_next_stop(cust)
					else:
						_done(cust)
			"queue":
				c.set_pose("wait")
				c.set_mood("wait")
				cust.state = "inLine"
				cust.t = 45.0 * who.patience
			"inLine":
				if cust.t <= 0.0 and c.mood != "impatient":
					c.set_mood("impatient")
			"counter":
				c.hold_prop("card")
				c.set_pose("wait")
				c.set_mood("wait")
				cust.state = "wait"
				cust.t = 25.0 * who.patience
			"wait":
				if cust.t <= 0.0:
					c.set_mood("impatient")
					cust.state = "impatient"
					cust.t = 15.0 * who.patience
			"impatient":
				if cust.t <= 0.0:
					c.set_mood("angry")
					cust.state = "angry"
					cust.t = 6.0
			"angry":
				if cust.t <= 0.0:
					hud.toast("A customer got tired of waiting and walked out (-100)")
					checkout.score -= 100
					cust.tagged = not cust.tapes.is_empty()
					cust.alarmed = false
					c.hold_prop(null)
					c.set_pose("hold")
					go(cust, "leave", { "x": _door.x, "z": _door.y })
			"checkout":  # being rung up (checkout.gd)
				pass
			"paid":
				if cust.t <= 0.0:
					c.set_mood("happy")
					go(cust, "leave", { "x": _door.x, "z": _door.y })
			"tagBack":  # at the end of the counter, tape held out
				c.set_pose("hold")
				c.set_mood("impatient")
				cust.state = "tagWait"
				cust.t = 30.0 * who.patience
			"tagWait":
				if cust.t <= 0.0:  # nobody fixed it: out they go anyway, alarm or no
					checkout.score -= 50
					c.set_mood("angry")
					cust.tagged = false
					hud.toast("A customer gave up waiting to have their tag fixed and left (-50)")
					go(cust, "leave", { "x": _door.x, "z": _door.y })
			"caught":
				if cust.t <= 0.0:
					c.set_mood("meh")
					go(cust, "leave", { "x": _door.x, "z": _door.y })
			"leave":  # out the door, back the way they came
				cust.path = [_inside, _outside, cust.from]
				cust.state = "outside"
	if cust.hi > 0.0:
		cust.hi -= dt
		if cust.hi <= 0.0:
			c.set_mood({ "browse": "browse", "wait": "wait", "inLine": "wait", "impatient": "impatient", "angry": "angry" }.get(cust.state, "happy" if cust.holding > 0 else "neutral"))
	cust.last_z = c.position.z
	cust.face += angle_difference(cust.face, cust.ry) * minf(1.0, dt * 8.0)
	c.rotation.y = cust.face
	c.tick(dt, speed)


# ---- the crosshair on one of them (called from interact.gd)

func take_aim(from: Vector3, dir: Vector3, hit_d: float) -> String:
	aim = null
	var best := 3.0
	for k: Dictionary in custs:
		var to: Vector3 = k.c.position + Vector3(0, 1.1, 0) - from
		var t := to.dot(dir)
		if t > 0.2 and t < best and t < hit_d + 0.4 and (to - dir * t).length() < 0.45:
			best = t
			aim = k
	if aim == null:
		return ""
	aim.known = true  # (walking ones too: a shoplifter doesn't stop. You've had a look at them)
	if aim.state == "tagWait":
		return "Their tape set off the gates\nE — desensitize it"
	if aim.state in ["wait", "impatient", "angry"] and checkout.co == null:
		return "E — ring them up"
	if checkout.co != null and checkout.co.cust == aim and checkout.co.by == "player":
		return "E — %s" % checkout.tip() if checkout.step()[1] == "customer" or checkout.step()[0] == "desens" else "Next: %s" % checkout.tip()
	return "A customer\n%s" % aim.who.taste


func on_e() -> bool:
	if aim == null:
		return false
	if aim.sneaking:
		catch(aim, "you")
	elif aim.state == "tagWait":
		tag_fix(aim, "you")
	elif aim.state in ["wait", "impatient", "angry"] and checkout.co == null:  # start ringing them up
		checkout.start("player", aim)
		checkout.act("customer")
	elif checkout.co != null and checkout.co.cust == aim and checkout.co.by == "player":
		checkout.act("customer")
	elif aim.state != "caught":  # just saying hi
		aim.hi = 1.4
		aim.c.set_mood("happy")
		if aim.thief and not aim.greeted and randf() < 0.7:
			aim.thief = false  # a friendly hello: suddenly they'd rather just rent it
		aim.greeted = true
	return true
