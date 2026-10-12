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
##   drops it in the Returns slot, and it's in the bin till it's put away (tapes.gd).
## - Shoplifters and the gates are the web game's (custSneak, custCatch, custWatched, wisTick, empCatch, tagFix,
##   custHearAlarm, custGone's stolen tapes; title.js's startGateAlarm), the 1-5 call on one you've caught among them;
##   a stolen tape's just gone (no ordering a replacement). The gates' lights don't flash.
## - Everybody's a member (members.gd): the same person every visit, coming in on their own rhythm, what they rent
##   on their account, three out at most, late fees when it's back late. Nobody signs up; nobody's phoned.
## - They pick up snacks (snacks.gd), ask for help at the counter, come in for holds (phone.gd), bring a kid or a
##   friend along, and shove a tape back in the wrong place now and then (chores.gd), the web game's way; but
##   nobody stops to chat, and nobody's talked into a snack at the register.
## - No cars (everyone walks up the sidewalk), nobody going to the theater, nobody signing up.

const Nav := preload("res://nav.gd")
const Staff := preload("res://staff.gd")
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
var rented: Array = []  # what's out: [tape, the day it went out, the day it's due, whose account it's on]
var members := preload("res://members.gd").new()
var asks: Array = []  # who's waiting at the counter for help, in order
var _titles := {}  # title -> its copies
var catch_call = null  # the shoplifter you've stopped, waiting on what happens to them
var _last_member = null
var _slot := {}  # in the lane, facing the drop slot
var alarm_on := false  # the gates going off
var gates_armed := true  # (switched off at the register, tagged tapes walk through)
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
	_beeper.bus = "Store"
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
	var sh: Node = $"../Shift"
	if sh.sim():  # a small member base is a quiet store; and a gentle first week, 40% busy on day 1 up to full on day 5
		r *= (0.45 + 0.55 * minf(1.0, members.all.filter(func(m: Dictionary) -> bool: return m.active).size() / 150.0)) * minf(1.0, 0.25 + 0.15 * Clock.day)
	return r * sh.rep_mult()  # (a better name brings more people in)


func spawn(member = null, kid_of = null) -> Dictionary:  # custSpawn. kid_of: a parent's kid tagging along (not a member: on their parent's number)
	if member == null:
		member = _pick_member(true)
	var who := customer_for(_imul(member.num, 2654435761), member.female) if kid_of == null else _kid_for(kid_of)  # member # -> the same person every time
	var female: bool = who.female
	if kid_of == null:
		_last_member = member
		$"../Shift".stats.visitors += 1
		member.last_visit = Clock.day + Clock.h / 24.0
	who.patience *= 1.0 + member.loyalty / 200.0  # regulars will wait a bit longer; the fed-up, less
	if Clock.h >= 23.0 and randf() < 0.5:  # the 11:30 walk-in, in no hurry at all
		who.stops = 7 + randi() % 4
		who.dwell *= 1.5
	var chores: Node = $"../Chores"
	if chores.grot() >= 3:  # litter, overflowing bins, bags left lying about: people notice
		members.loyal(member, -2)
		if chores._t - chores._mess_note > 120.0:
			chores._mess_note = chores._t
			hud.toast("Customers are noticing the mess (%d spots to clean%s)" % [chores.messes.size(), ", the trash overflowing" if chores.bins.any(func(b: Dictionary) -> bool: return b.n >= b.cap) else ""])
	if member.loyalty >= 40.0 and kid_of == null:
		hud.toast("%s, one of the regulars, came in" % members.name_of(member))
	var out := rentals_of(member)
	var back: Array = out.filter(func(r: Array) -> bool: return r[2] <= Clock.day or (r[2] == Clock.day + 1 and randf() < 0.5)).map(func(r: Array) -> Dictionary: return r[0])  # what's due (or late) comes back; the rest stays out
	who.max_tapes = mini(who.max_tapes, maxi(0, members.RENT_MAX - (out.size() - back.size())))  # 3 out at a time, counting what they're keeping
	if kid_of != null:
		back = []
	var cast: Array = range(people.cast.who.size()).filter(func(i: int) -> bool: return people.cast.who[i].female == female and not people.cast.who[i].has("staff"))
	var c: Node3D = people.spawn(cast[who.seed % cast.size()])
	c.gait = who.gait
	var from := Vector2((-1.0 if randf() < 0.5 else 1.0) * (14.0 + randf() * 6.0), -0.9)  # up the sidewalk
	c.position = Vector3(from.x, 0.0, from.y)
	c.set_mood("on")
	var cust := { "who": who, "member": member, "name": members.name_of(member) if kid_of == null else "%s's kid" % members.name_of(member), "kid": kid_of != null, "party": [], "tag_t": 0.0, "said": {}, "prospect": false, "th_seat": null, "watched": false, "mood_t": 0.0, "snacks": [], "snack_done": false, "snack_unit": null, "opened_cooler": false, "want": {}, "tries": 0, "acked": false, "ask_at": 0.0, "pickup": null, "returning": back, "c": c, "ry": 0.0, "face": 0.0, "hi": 0.0, "holding": 0, "tapes": [], "seen": [], "stops_left": who.stops,
		"path": [_outside, _inside, _door], "from": from, "spot": null, "state": "arrive", "t": 0.6, "paid": false, "reach": "", "reach_copy": null,
		"thief": kid_of == null and randf() < 0.06 * (0.6 if $"../Shift".owned("cameras") else 1.0) * (0.7 if $"../Shift".owned("sign") else 1.0), "sneaking": false, "tagged": false, "alarmed": false, "known": false, "greeted": false, "watch_t": 0.0, "fess": false, "last_z": 0.0,  # (thief: now and then somebody means to walk out with it)
		"heard": false, "look_t": 0.0, "fed_up": false,
		"squeeze": 0.0, "stuck": 0.0, "detour": false, "bump_t": 0.0, "bump_detour": false, "wait_for": null }
	if not back.is_empty():
		c.set_pose("hold")
		c.hold_tape(mini(3, back.size()))
	if kid_of != null:  # small
		c.scale = Vector3.ONE * (0.6 + randf() * 0.08)
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
				var m = _pick_member()
				if m != null:  # (nobody due in: a quiet spell)
					_bring_along(spawn(m))
				_arrive = (6.0 + randf() * 20.0) / rush_level()
	var you: Vector3 = player.global_position
	if you.y < 2.0 and absf(you.z - _you_z) < 1.0 and absf(you.x) < 2.0 and (_you_z - GATE_Z) * (you.z - GATE_Z) < 0.0 and tapes.inv.any(func(t: Dictionary) -> bool: return not t.get("desens", false)):
		start_alarm()  # carried a tape through the gates
	_you_z = you.z
	if alarm_on:
		alarm_t += dt
	var gr: Dictionary = $"../Shift".growth
	if gr.prospects > 0 and not things.locked and open and custs.size() < cap + 1:  # somebody new, here to sign up
		gr.t -= dt
		if gr.t <= 0.0:
			gr.t = (40.0 + randf() * 80.0) / rush_level()
			var pool: Array = members.all.filter(func(m: Dictionary) -> bool: return not m.active and m.status == "" and not custs.any(func(k: Dictionary) -> bool: return k.member == m))
			if pool.is_empty():
				gr.prospects = 0
			else:
				var k := spawn(pool.pick_random())
				k.prospect = true
				k.thief = false
				k.returning = []
				k.tickets = 0
				k.c.hold_tape(0)
				k.c.set_pose("idle")
				gr.prospects -= 1
	for k: Dictionary in custs.duplicate():
		_hear_alarm(k, dt)
		if k.sneaking and not k.alarmed:
			_watched(k, dt)
			for e: Node in Staff.crew:  # staff: a chance each second, better with WIS, to stop them on the way past
				if k.sneaking and e.dana != null and e.dana.position.distance_to(k.c.position) < 3.5 and randf() < dt * 0.03 * Staff.lv(e, "wis"):
					Staff.speaker = e.first
					catch(k, "dana")
					$"../Staff".xp(e, "wis", 20.0)
		_step(k, dt)


func start_alarm() -> void:
	if alarm_on or not gates_armed:
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
	$"../Staff".xp("you", "wis", 4.0)
	if randf() >= (0.85 if Staff.has("you", "wis", 10) else 0.5):  # (Stern Look: they mostly don't)
		return  # ...or they keep going
	cust.sneaking = false
	cust.tagged = false
	cust.thief = false
	cust.c.hold_tape(cust.tapes.size())
	cust.c.set_pose("hold")
	cust.c.set_mood("meh")
	cust.hi = 2.0
	hud.toast("%s saw you watching and brought %s to the counter" % [cust.name, cust.tapes[0].t if cust.tapes.size() == 1 else "the tapes"])
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
	if by != "dana":
		$"../Staff".xp("you", "wis", 20.0)
	$"../Shift".stats.caught += 1
	if by == "dana":  # a warning, and out
		hud.toast("Dana caught %s sneaking out with %s (back in the returns bin, a warning) (+150)" % [cust.name, what])
		go(cust, "leave", { "x": _door.x, "z": _door.y })
		return
	hud.toast("Caught %s sneaking out with %s (back in the returns bin) (+150)" % [cust.name, what])
	if catch_call != null:
		catch_decide(5)  # one at a time: the last one gets a warning
	cust.path = []
	cust.state = "caught"
	cust.t = 20.0
	catch_call = cust
	hud.call_box("CAUGHT · %s #%d · %s\n%s" % [cust.name, cust.member.num, what, "   ".join(range(5).map(func(i: int) -> String: return "%d %s" % [i + 1, CATCH_CALLS[i][0]]))])


# what happens to them: you decide (1-5), or after 20 s they get a warning
const CATCH_CALLS := [["Ban 1 week", "banned for a week", "banned", 7], ["Ban 1 month", "banned for a month", "banned", 30], ["Cancel membership", "membership cancelled", "cancelled", 0],
	["Call the police", "arrested", "arrested", 0], ["Let them go with a warning", "let off with a warning", "", 0]]


func catch_decide(key: int) -> void:
	var cust = catch_call
	if cust == null:
		return
	catch_call = null
	hud.call_box("")
	var k: Array = CATCH_CALLS[key - 1]
	if k[2] != "":
		cust.member.status = k[2]
		cust.member.until = Clock.day + k[3]
	hud.toast("%s: %s" % [cust.name, k[1]])
	if custs.has(cust):  # ...and out
		cust.c.set_mood("alarm" if key == 4 else "meh")
		cust.hi = 0.0
		go(cust, "leave", { "x": _door.x, "z": _door.y })


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_Q and aim != null and aim.state == "asking":  # "sorry, all our copies are out"
		all_out(aim)
	if catch_call != null and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode >= KEY_1 and e.physical_keycode <= KEY_5:
		catch_decide(e.physical_keycode - KEY_0)
		get_viewport().set_input_as_handled()  # (not the tape in slot 1-5 as well)


# ---- members: what's on whose account, who comes in when

func rentals_of(m: Dictionary) -> Array:
	return rented.filter(func(r: Array) -> bool: return r.size() > 3 and r[3] == m.num)


func member_of(t: Dictionary):  # whose account a tape's out on (or null)
	for r: Array in rented:
		if r[0] == t and r.size() > 3:
			return members.by_num.get(r[3])
	return null


func check_in(t: Dictionary) -> void:  # dropped back off: the rental's closed out. Back late: the fee goes on their account, settled at their next checkout
	for r: Array in rented:
		if r[0] == t:
			var late := maxi(0, Clock.day - int(r[2]))
			if late > 0 and r.size() > 3 and members.by_num.has(r[3]):
				members.by_num[r[3]].owed = snappedf(members.by_num[r[3]].owed + late * (2.0 if t.n else 1.0), 0.01)  # $2 a day a new release, $1 the rest
			rented.erase(r)
			$"../Shift".stats.returns += 1
			return


func _weighted(items: Array, w: Array):
	var r: float = randf() * w.reduce(func(a: float, b: float) -> float: return a + b, 0.0)
	var i := 0
	while i < items.size() - 1:
		r -= w[i]
		if r <= 0.0:
			break
		i += 1
	return items[i]


func _pick_member(anyone := false):  # who comes in (custPickMember). About half the time it's someone with tapes out, bringing them back: most likely whoever's due today or late
	var now := Clock.day + Clock.h / 24.0
	var ms: Array = members.all.filter(func(m: Dictionary) -> bool: return m != _last_member and not custs.any(func(k: Dictionary) -> bool: return k.member == m) and members.can_visit(m) and m.loyalty > -60.0)  # not someone who's already in here, banned, or fed up with the place
	if ms.is_empty():
		return null
	var soon := {}  # member # -> days till their soonest rental's due
	for r: Array in rented:
		if r.size() > 3:
			soon[r[3]] = mini(soon.get(r[3], 99), int(r[2]) - Clock.day)
	var due := ms.filter(func(m: Dictionary) -> bool: return soon.get(m.num, 99) <= 1 and now - m.last_visit > 0.25)  # bringing tapes back (just not twice in a few hours)
	if not due.is_empty() and randf() < 0.5:
		return _weighted(due, due.map(func(m: Dictionary) -> float: return 3.0 if soon[m.num] <= 0 else 1.0))
	# everyone else has their own rhythm: most come in every couple of days or so, regulars more, the fed-up less.
	# Whoever's picked might not be due yet; then nobody comes this time
	var ok := ms if anyone else ms.filter(func(m: Dictionary) -> bool: return now - m.last_visit >= 0.4)
	if ok.is_empty():
		return null
	var m: Dictionary = _weighted(ok, ok.map(func(q: Dictionary) -> float: return maxf(0.2, 1.0 + q.loyalty / 40.0)))  # regulars come in more often
	var cadence: float = 2.5 / maxf(0.4, 1.0 + m.loyalty / 50.0)
	return m if anyone or randf() < pow(minf(1.0, (now - m.last_visit) / cadence), 2.0) else null  # (seen yesterday: unlikely today)


const REG_LINES := {
	"hi": ["Hey! How's it going?", "Back again, I know.", "Look who's working today.", "Hey, you're here! Good.", "Busy one today?"],
	"hiTaste": ["Get anything new in %s?", "What's good in %s lately?", "I'm out of %s I haven't seen. Help me out."],
	"counter": ["The usual, I think.", "Anything good come in this week?", "What would you watch tonight?", "Long day?", "I'll have these back on time. Probably.", "Every Friday, right?"],
	"ofYou": ["Tell %s I said hi.", "%s told me to rent this one."],
	"unhappy": ["Just these.", "Can we hurry this up?"],
}
const TASTE_WORDS := { "horror fan": "horror", "parent": "the kids' section", "couch potato": "TV shows", "action junkie": "action", "date night": "romance", "anime kid": "anime" }


func regular_says(cust: Dictionary, when: String, by := "you") -> void:  # a regular has a word for you (once a visit, each); somebody fed up has a short one
	if cust.said.has(when):
		return
	var loy: float = cust.member.loyalty
	var line: String
	if loy <= -30.0 and when == "counter":
		line = REG_LINES.unhappy.pick_random()
	elif loy < 35.0:
		return
	elif when == "hi":
		var t: String = TASTE_WORDS.get(cust.who.taste, "")
		line = REG_LINES.hiTaste.pick_random() % t if t != "" and randf() < 0.5 else REG_LINES.hi.pick_random()
	else:
		line = REG_LINES.ofYou.pick_random() % "Dana" if by != "dana" and randf() < 0.2 else REG_LINES.counter.pick_random()
	cust.said[when] = true
	cust.hi = 2.0
	cust.c.set_mood("meh" if loy <= -30.0 else "happy")
	if by == "you":
		hud.toast("%s: \u201c%s\u201d" % [cust.name, line])


func tag_fix(cust: Dictionary, by: String) -> void:  # their tapes over the desensitizer, and on their way
	for t: Dictionary in cust.tapes:
		t.desens = true
	silence_alarm()
	cust.tagged = false
	cust.c.set_mood("meh")
	cust.hi = 1.5
	hud.toast("%s fixed %s's tag: they're on their way" % ["Dana" if by == "dana" else "You", cust.name])
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
	if cust.kid:  # (kids don't pay: they go find their parent)
		_tag_along(cust)
		return
	if cust.thief and cust.holding > 0 and not (cust.known and randf() < 0.35):  # (you've had an eye on them: maybe not today)
		_sneak(cust)
		return
	if not cust.snack_done:  # a snack on the way, maybe
		cust.snack_done = true
		var racks: Array = $"../Snacks".spots
		if not racks.is_empty() and randf() < (0.4 if cust.holding > 0 else 0.25):
			go(cust, "snack", racks.pick_random())
			return
	if cust.holding == 0 and not cust.watched and randf() < (0.75 if tapes.playing != null else 0.35) and _pick_theater_seat(cust):
		return
	if cust.holding > 0 or not cust.snacks.is_empty():
		cust.c.set_mood("happy")
		line.append(cust)
		to_line(cust)
	elif not _partners(cust).is_empty():  # nothing for them: they wait on whoever they came with
		_tag_along(cust)
	else:
		cust.c.set_mood("meh")
		go(cust, "leave", { "x": _door.x, "z": _door.y })


func waiting():  # whoever's at the counter, waiting to be rung up (or null)
	return line[0] if not line.is_empty() and line[0].state in ["wait", "impatient", "angry"] else null


func _gone(cust: Dictionary) -> void:
	leave_line(cust)
	asks.erase(cust)
	if cust.snack_unit != null:
		cust.snack_unit.claim = null
	if catch_call == cust:
		catch_call = null
		hud.call_box("")
	var stolen: bool = cust.tagged and not cust.paid and not cust.tapes.is_empty()  # walked out with them unpaid: gone for good. A paid one with a missed tag is still just a rental
	if stolen:
		if $"../Shift".owned("cameras"):
			cust.known = true  # it's all on tape
		$"../Shift".stats.stolen += cust.tapes.size()
		checkout.score -= 75 * cust.tapes.size()
		hud.toast("%s walked out with %s: stolen (%d)" % [cust.name if cust.known else "Someone", _what(cust), -75 * cust.tapes.size()])
	for t: Dictionary in cust.tapes:
		if cust.paid:
			pass  # (on their account since it was rung up: checkout.gd)
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
			cust.step_d = cust.get("step_d", 0.0) + step  # footsteps
			if cust.step_d > 0.7:
				cust.step_d = 0.0
				$"../Ambience".step(c.position)
			cust.ry = atan2(to.x, to.y)
			c.position.y = _floor_y(c.position) if c.position.z > 28.5 else 0.0  # (the theater's ramp)
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
				members.loyal(cust.member, -4)
				hud.toast("%s set off the gates: a tag wasn't desensitized. They're coming back to have it fixed (-25)" % cust.name)
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
					elif cust.pickup != null:  # here for their hold: they ask at the counter
						cust.want = { "kind": "hold", "title": cust.pickup.title, "hold": cust.pickup }
						_ask_go(cust)
					elif cust.prospect:  # straight to the counter, form in hand
						line.append(cust)
						to_line(cust)
					elif cust.get("moviegoer", false):  # ticket in hand: straight in
						if not _pick_theater_seat(cust):
							cust.moviegoer = false
							_next_stop(cust)
					elif not cust.kid and _want(cust):
						_ask_go(cust)
					elif not cust.kid and cust.party.is_empty() and randf() < (0.5 if tapes.playing != null else 0.25) and _pick_theater_seat(cust):
						pass
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
						check_in(t)
						tapes.return_bin.append(t)
					hud.toast("%s returned %s" % [cust.name, cust.returning[0].t if n == 1 else "%d tapes" % n])
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
					if cust.reach != "take":  # put back: into its slot, or (a quarter of the time) just shoved in anywhere
						if randf() < 0.25:
							$"../Chores".misshelve(cust.tapes.pop_back(), cust.spot)
						else:
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
				cust.t = 45.0 * who.patience * (1.3 if Staff.has("you", "cha", 10) else 1.0)  # (Store Favorite)
			"inLine":
				if cust.t <= 0.0 and c.mood != "impatient":
					c.set_mood("impatient")
			"counter":
				c.hold_prop("form" if cust.prospect else "card" if not cust.tapes.is_empty() else "cash")
				c.set_pose("wait")
				c.set_mood("wait")
				cust.state = "wait"
				cust.t = 25.0 * who.patience * (1.3 if Staff.has("you", "cha", 10) else 1.0)
			"wait":
				if cust.t <= 0.0:
					c.set_mood("impatient")
					cust.state = "impatient"
					cust.t = 15.0 * who.patience * (1.3 if Staff.has("you", "cha", 10) else 1.0)
			"impatient":
				if cust.t <= 0.0:
					c.set_mood("angry")
					cust.state = "angry"
					cust.t = 6.0
			"angry":
				if cust.t <= 0.0:
					hud.toast("%s got tired of waiting and walked out (-100)" % cust.name)
					members.loyal(cust.member, -15)
					$"../Shift".stats.walkouts += 1
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
			"signedUp":  # card in hand: now to look around
				if cust.t <= 0.0:
					c.hold_prop(null)
					c.set_pose("idle")
					if cust.stops_left > 0:
						_next_stop(cust)
					else:
						go(cust, "leave", { "x": _door.x, "z": _door.y })
			"tagAlong":
				_tag_tick(cust)
			"thAisle":
				cust.state = "thRow"
			"thRow", "thRowOut":  # sidestep from the center ramp into their stadium row; and back out of it
				var s: Dictionary = cust.th_seat
				var out: bool = cust.state == "thRowOut"
				var to := Vector3(-2.87 if out else s.x, s.y, s.z + 0.42) - c.position
				to.y = 0.0
				if to.length() < 0.05:
					if out:
						if randf() < 0.4:
							$"../Chores".mess_add("cup", s.x, s.z, s.y)  # left their cup under the seat
						cust.th_seat = null
						cust.watched = true
						if cust.holding == 0 and cust.snacks.is_empty() and cust.stops_left > 0 and randf() < 0.5:
							_next_stop(cust)
						elif cust.holding > 0 or not cust.snacks.is_empty():
							line.append(cust)
							to_line(cust)
						else:
							go(cust, "leave", { "x": _door.x, "z": _door.y })
					else:
						c.set_pose("sit", { "hipY": s.hipY })
						cust.from3 = c.position
						cust.state = "thSitDown"
						cust.t = 0.6
						cust.ry = 0.0
				else:
					speed = who.speed * 0.85
					c.position += to.normalized() * minf(to.length(), speed * dt)
					c.position.y = s.y
					cust.ry = atan2(to.x, to.z)
			"thSitDown":
				var s: Dictionary = cust.th_seat
				c.position = cust.from3.lerp(Vector3(s.x, s.y, s.z), 1.0 - maxf(0.0, cust.t) / 0.6)
				cust.ry = 0.0
				if cust.t <= 0.0:
					cust.state = "thWatch"
					cust.t = INF if cust.get("moviegoer", false) and $"../Shift".show.status in ["arriving", "late", "on"] else 40.0 + who.rnd.call() * 80.0  # here for the show: till it lets out
					cust.mood_t = 4.0
					c.set_mood("watch" if tapes.playing != null else "neutral")
			"thWatch":
				if cust.t <= 0.0 or player.seat == cust.th_seat:  # done; or you've sat right in their seat
					c.set_pose("idle")
					c.set_mood("happy" if tapes.playing != null else "neutral")
					c.position = Vector3(cust.th_seat.x, cust.th_seat.y, cust.th_seat.z + 0.42)
					cust.state = "thRowOut"
				else:
					cust.mood_t -= dt
					if cust.mood_t <= 0.0:
						cust.mood_t = 5.0 + who.rnd.call() * 8.0
						c.set_mood(["watch", "watch", "happy", "love"].pick_random() if tapes.playing != null else ["neutral", "meh"].pick_random())
			"snack":  # at the rack: a hand to the one they want
				cust.snack_unit = $"../Snacks".pick(cust.spot)
				if cust.snack_unit != null:
					cust.snack_unit.claim = cust
					c.reach_to(cust.snack_unit.at)
				else:
					c.set_pose("reach")
				c.set_mood("happy")
				cust.state = "snacking"
				cust.t = 1.4
				if cust.spot.drinks and not things.cooler_open:
					things.cooler_open = true
					cust.opened_cooler = true
			"snacking":
				if cust.t <= 0.0:
					var u = cust.snack_unit
					cust.snack_unit = null
					if u != null:
						u.claim = null
						if not u.out:  # in hand, for real
							$"../Snacks".set_out(u, true)
							cust.snacks.append(u)
					c.reach_to(null)
					if cust.opened_cooler:
						things.cooler_open = false
						cust.opened_cooler = false
					c.set_pose("hold" if cust.holding > 0 else "idle")
					_done(cust)
			"toAsk":  # at the counter: "excuse me..."
				cust.state = "asking"
				cust.t = 75.0 * who.patience
				cust.ask_at = Time.get_ticks_msec() / 1000.0
				c.set_mood("ask")
				c.set_pose("idle")
				var w: Dictionary = cust.want
				hud.toast("%s is at the counter to pick up %s: it's on hold for them" % [cust.name, w.title] if w.kind == "hold" else "%s is at the counter looking for %s" % [cust.name, w.title] if w.kind == "title" else "%s is at the counter wanting %s" % [cust.name, TASTE_ASK.get(who.taste, "something good")])
			"asking":
				if cust.hi <= 0.0 and c.mood != "ask":
					c.set_mood("ask")
				if cust.t <= 0.0:  # gave up waiting for help
					if cust.want.kind == "hold":
						hold_out(cust)  # (standing at the counter that long for a hold: same scene)
					else:
						checkout.score -= 20
						members.loyal(cust.member, -8)
						c.set_mood("meh")
						hud.toast("%s gave up waiting for help at the counter (-20)" % cust.name)
						ask_done(cust)
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
					members.loyal(cust.member, -8)
					hud.toast("%s gave up waiting to have their tag fixed and left (-50)" % cust.name)
					go(cust, "leave", { "x": _door.x, "z": _door.y })
			"caught":
				if cust.t <= 0.0:  # (no call made: a warning)
					catch_call = cust
					catch_decide(5)
			"leave":  # out the door, back the way they came
				cust.path = [_inside, _outside, cust.from]
				cust.state = "outside"
	if cust.hi > 0.0:
		cust.hi -= dt
		if cust.hi <= 0.0:
			c.set_mood({ "browse": "browse", "wait": "wait", "inLine": "wait", "impatient": "impatient", "angry": "angry", "asking": "ask" }.get(cust.state, "happy" if cust.holding > 0 else "neutral"))
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
	if $"../Shift".mode == "customer":  # (another customer, to you)
		return "%s\n%s" % [aim.name, aim.who.taste]
	if aim.state == "tagWait":
		return "Their tape set off the gates\nE — desensitize it"
	if aim.state == "asking":
		var w: Dictionary = aim.want
		var give: String = "\nE — hand them %s" % tapes.held.t if tapes.held != null else ""
		if w.kind == "hold":
			return "%s\nHere to pick up %s (on hold)%s\nQ — tell them it's not here" % [aim.name, w.title, give if give != "" else "\nGet it from the holds shelf"]
		if w.kind == "title":
			return "%s\nLooking for %s (%s)%s\nQ — tell them it's all out" % [aim.name, w.title, w.cat, give]
		return "%s\nWants %s%s" % [aim.name, TASTE_ASK.get(aim.who.taste, "something good"), give if give != "" else "\nBring them a tape"]
	if aim.state in ["wait", "impatient", "angry"] and checkout.co == null:
		return "%s\nE — they'd like to sign up" % aim.name if aim.prospect else "E — ring them up"
	if checkout.co != null and checkout.co.cust == aim and checkout.co.by == "player":
		return "E — %s" % checkout.tip() if checkout.step()[1] == "customer" or checkout.step()[0] == "desens" else "Next: %s" % checkout.tip()
	return "%s\n%s" % [aim.name, "Caught · 1-5 to decide" if catch_call == aim else aim.who.taste]


func on_e() -> bool:
	if aim == null:
		return false
	if $"../Shift".mode == "customer":  # a hello
		aim.hi = 1.4
		aim.c.set_mood("happy")
		return true
	if aim.sneaking:
		catch(aim, "you")
	elif aim.state == "tagWait":
		tag_fix(aim, "you")
	elif aim.state == "asking":  # hand over what's in your hand, or just "be right with you"
		if tapes.held != null:
			hand_tape(aim, tapes.held)
		else:
			if not aim.acked:
				aim.acked = true
				aim.t += 30.0  # "I'll go look": they'll wait a bit longer
			aim.hi = 1.2
			aim.c.set_mood("happy")
	elif aim.state in ["wait", "impatient", "angry"] and checkout.co == null:  # start ringing them up
		checkout.start("player", aim)
		checkout.act("customer")
	elif checkout.co != null and checkout.co.cust == aim and checkout.co.by == "player":
		checkout.act("customer")
	elif aim.state != "caught":  # just saying hi
		aim.hi = 1.4
		aim.c.set_mood("happy")
		if not aim.greeted:
			regular_says(aim, "hi")
		if not aim.greeted:
			$"../Staff".xp("you", "wis", 2.0)  # (sizing people up)
		if aim.thief and not aim.greeted and randf() < 0.7:
			aim.thief = false  # a friendly hello: suddenly they'd rather just rent it
		aim.greeted = true
	return true


# ---- help at the counter: a title they're after, something good, a hold they've come in for (custWant ... custAllOut)

const TASTE_ASK := { "horror fan": "something scary", "parent": "something for the kids", "couch potato": "a show to binge",
	"action junkie": "something with some action", "date night": "something for date night", "anime kid": "some anime" }


func _copies(title: String) -> Array:
	if _titles.is_empty():
		for t: Dictionary in tapes.tapes:
			_titles.get_or_add(t.t, []).append(t)
	return _titles.get(title, [])


func on_shelf_copy(title: String):  # a copy of it that's in (or null)
	for t: Dictionary in _copies(title):
		if not t.off and not t.get("lost", false):
			return t
	return null


func a_title(cats: Array, in_odds: float):  # a title somebody might have in mind: usually one that's in, now and then one that's all out. -> one of its copies (or null)
	_copies("")
	var pool: Array = _titles.keys().filter(func(k: String) -> bool: return not _titles[k][0].get("lib", false) and (cats.is_empty() or cats.has(_titles[k][0].c)))  # (what the store carries)
	var in_now := pool.filter(func(k: String) -> bool: return on_shelf_copy(k) != null)
	var out := pool.filter(func(k: String) -> bool: return on_shelf_copy(k) == null)
	var from := in_now if randf() < in_odds or out.is_empty() else out
	return _titles[from.pick_random()][0] if not from.is_empty() else null


func _want(cust: Dictionary) -> bool:
	if asks.size() >= 3 or cust.who.max_tapes <= cust.holding:
		return false  # (at their limit: nothing to ask for)
	var r := randf()
	if r < 0.16:
		var t = a_title(cust.who.cats, 0.75)
		if t == null:
			return false
		cust.want = { "kind": "title", "title": t.t, "cat": t.c }
	elif r < 0.28 and not cust.who.cats.is_empty():
		cust.want = { "kind": "rec" }
	else:
		return false
	cust.tries = 0
	return true


func _ask_go(cust: Dictionary) -> void:
	asks.append(cust)
	go(cust, "toAsk", { "x": _counter.x + 1.2 + 0.7 * (asks.size() - 1), "z": _counter.z + 0.1, "ry": PI })


func ask_done(cust: Dictionary, then := "") -> void:  # helped (or gave up): off the counter, and on with it
	asks.erase(cust)
	if then == "pay":
		line.append(cust)
		to_line(cust)
	elif then == "leave":
		go(cust, "leave", { "x": _door.x, "z": _door.y })
	elif cust.stops_left > 0:
		_next_stop(cust)
	else:
		_done(cust)


func _takes(cust: Dictionary, tape: Dictionary) -> void:
	if tape == tapes.held:
		tapes.release()
	cust.tapes.append(tape)
	cust.holding = cust.tapes.size()
	cust.c.hold_tape(mini(3, cust.holding))
	cust.c.set_pose("hold")


func hand_tape(cust: Dictionary, tape: Dictionary, by := "you") -> bool:  # -> true if they took it
	var c: Node3D = cust.c
	var w: Dictionary = cust.want
	var Who := "Dana" if by == "dana" else "You"
	if w.kind == "hold":  # their hold: only that title will do
		var h: Dictionary = w.hold
		if tape.t != w.title:
			c.set_mood("meh")
			cust.hi = 1.4
			hud.toast("%s: “That's not what I had on hold. It's %s”" % [cust.name, w.title])
			return false
		var set_aside: bool = tape == h.pulled or tape == h.copy
		if tape == h.copy:
			h.copy = null
		$"../Phone".hold_end(h)
		_takes(cust, tape)
		if set_aside:
			c.set_mood("love")
			cust.hi = 1.8
			checkout.score += 40
			members.loyal(cust.member, 8)
			hud.toast("%s handed %s their hold: %s (+40)" % [Who, cust.name, tape.t])
		else:  # it wasn't set aside: you scrambled and found one on the floor
			c.set_mood("meh")
			cust.hi = 1.6
			checkout.score += 5
			members.loyal(cust.member, -2)
			hud.toast("%s's hold wasn't set aside. %s found a copy of %s on the shelf: awkward, but they got it (+5)" % [cust.name, Who, tape.t])
		ask_done(cust, "pay")
		return true
	var likes: bool = cust.who.cats.has(tape.c)
	var exact: bool = w.kind == "title" and tape.t == w.title
	var odds: float = (0.6 if tape.c == w.cat else 0.4 if likes else 0.12) if w.kind == "title" else 0.85 if likes else 0.2
	if not exact and randf() >= odds:
		cust.tries += 1
		c.set_mood("meh")
		cust.hi = 1.6
		hud.toast("%s offered %s %s: “Nah, not really my thing”" % [Who, cust.name, tape.t])
		if cust.tries >= 2:  # they'll find something themselves
			members.loyal(cust.member, -3)
			ask_done(cust)
		return false
	_takes(cust, tape)
	c.set_mood("love")
	cust.hi = 1.8
	var fast := maxi(0, roundi(60.0 - (Time.get_ticks_msec() / 1000.0 - cust.ask_at)))
	var pts: int = 80 + fast if exact else 40 if w.kind == "title" else 80 + fast if likes else 30
	checkout.score += pts
	$"../Staff".xp("you", "int" if exact else "cha", 10.0 if exact or likes else 5.0)
	members.loyal(cust.member, 10 if exact else 4 if w.kind == "title" else 8 if likes else 2)
	hud.toast(("%s found %s %s" % [Who, cust.name, tape.t] if exact else "%s took %s instead of %s" % [cust.name, tape.t, w.title] if w.kind == "title" else "%s recommended %s to %s%s" % [Who, tape.t, cust.name, ": right up their alley" if likes else ""]) + " (+%d)" % pts)
	ask_done(cust, "pay")
	return true


func hold_out(cust: Dictionary) -> void:  # "you said you'd hold it!"
	var w: Dictionary = cust.want
	var had: bool = w.hold.copy != null or w.hold.pulled != null or on_shelf_copy(w.title) != null
	checkout.score -= 50 if had else 30
	members.loyal(cust.member, -12 if had else -8)
	cust.c.set_mood("angry")
	cust.hi = 3.0
	hud.toast("Told %s their hold for %s wasn't there. There was a copy right there. They were not happy (-50)" % [cust.name, w.title] if had else "%s came in for %s on hold, and there wasn't one. “You SAID you'd hold it!” (-30)" % [cust.name, w.title])
	$"../Phone".hold_end(w.hold)
	ask_done(cust, "leave" if randf() < 0.6 else "")


func all_out(cust: Dictionary) -> void:  # Q: "sorry, all our copies are out"
	if cust.want.kind == "hold":
		hold_out(cust)
		return
	if cust.want.kind != "title":
		return
	cust.c.set_mood("meh")
	cust.hi = 1.5
	if on_shelf_copy(cust.want.title) != null:  # ...it was right there
		checkout.score -= 30
		members.loyal(cust.member, -5)
		hud.toast("Told %s %s was out, but there's one on the shelf (-30)" % [cust.name, cust.want.title])
		ask_done(cust)  # they'll have a look themselves
		return
	checkout.score += 10
	members.loyal(cust.member, 2)
	hud.toast("Told %s %s is all out (+10)" % [cust.name, cust.want.title])
	ask_done(cust, "leave" if randf() < 0.5 else "")


# ---- not alone: a parent's kid, a friend (kidFor, custBringAlong, custRideWith, custTagAlong, custTagAlongTick)

const LEAVING := ["leave", "outside"]


func _kid_for(parent: Dictionary) -> Dictionary:  # a kid: small, their own taste; a fresh face each visit
	var who := customer_for(randi(), randf() < 0.5)
	who.taste = "kid"
	who.cats = ["Family & Kids", "Kids & Educational", "Animation"]
	who.stops = 1 + randi() % 3
	who.speed = parent.who.speed
	who.picky = 0.8
	who.max_tapes = 1
	who.dwell = 0.8
	who.gait = "bouncy"
	return who


func _beside(cust: Dictionary, lead: Dictionary) -> void:  # walking up beside them (a step further out along the sidewalk)
	var lp: Vector3 = lead.c.position
	cust.c.position = lp + Vector3((1.0 if lp.x > 0.0 else -1.0) * 0.8, 0.0, -0.35)
	cust.from = Vector2(cust.c.position.x, cust.c.position.z)
	cust.path = [_outside, _inside, _door]
	cust.state = "arrive"
	lead.party = [lead, cust]
	cust.party = lead.party


func _bring_along(lead: Dictionary) -> void:  # a regular arrival might not be alone
	if lead.pickup != null or custs.size() >= mini(6, roundi(2.0 + 2.0 * rush_level())):
		return
	var parent: bool = lead.who.taste == "parent"
	var r := randf()
	if r < (0.5 if parent else 0.05):
		_beside(spawn(lead.member, lead), lead)
		if lead.member.loyalty >= 40.0:
			hud.toast("%s brought their kid" % lead.name)
	elif r < (0.62 if parent else 0.24):
		var ms: Array = members.all.filter(func(m: Dictionary) -> bool: return m != lead.member and not custs.any(func(k: Dictionary) -> bool: return k.member == m) and members.can_visit(m) and m.loyalty > -60.0)
		if ms.is_empty():
			return
		var k := spawn(ms.pick_random())
		_beside(k, lead)
		k.thief = false  # (nobody shoplifts with a friend watching)
		lead.thief = false
		k.who.speed = lead.who.speed


func _partners(cust: Dictionary) -> Array:  # whoever they came with that's still busy in the store
	return cust.party.filter(func(k: Dictionary) -> bool: return k != cust and custs.has(k) and not k.state in LEAVING and k.state != "tagAlong")


func _tag_along(cust: Dictionary) -> void:  # done: go wait by whoever they came with
	var kids: Array = cust.party.filter(func(k: Dictionary) -> bool: return k.kid and k != cust and custs.has(k) and k.state != "tagAlong" and not k.state in LEAVING)
	if not cust.kid and not kids.is_empty():  # a parent: "come on, we're going"
		var kid: Dictionary = kids[0]
		cust.c.set_mood("impatient")
		cust.hi = 2.0
		kid.stops_left = 0
		kid.c.set_mood("meh")
		kid.hi = 1.5
		if kid.state in ["stop", "browse", "reach"] or not kid.path.is_empty():
			kid.c.reach_to(null)
			_tag_along(kid)
		if not kid.get("hurried", false):  # (and they hurry)
			kid.hurried = true
			kid.who.speed *= 1.35
	cust.state = "tagAlong"
	cust.t = 0.0
	cust.path = []
	cust.tag_t = 0.0
	cust.c.set_pose("hold" if cust.holding > 0 else "idle")


func _tag_tick(cust: Dictionary) -> void:  # standing by: near whoever's still going; when nobody is, out together
	var c: Node3D = cust.c
	var busy := _partners(cust)
	if cust.kid and not cust.tapes.is_empty():  # a kid with a tape: "can we get this one?"
		var par: Dictionary = cust.party[0]
		if custs.has(par) and par.state in ["stop", "browse", "reach", "tagAlong"] and par.c.position.distance_to(c.position) < 1.6:
			var t: Dictionary = cust.tapes.pop_back()
			cust.holding = 0
			c.hold_tape(0)
			c.set_mood("ask")
			cust.hi = 2.0
			par.tapes.append(t)  # (they cave)
			par.holding += 1
			par.c.hold_tape(mini(3, par.holding))
			par.c.set_pose("hold")
			par.c.set_mood("meh")
			par.hi = 1.5
			if par.state == "tagAlong":  # that's one more to pay for
				par.state = "browse"
				par.t = 0.5
				par.stops_left = 0
		elif not custs.has(par) or par.state in LEAVING or par.state in ["queue", "inLine", "counter", "wait", "impatient", "angry", "checkout", "paid"]:  # too late (they're paying, or going): it gets stuck on the nearest shelf
			if cust.spot != null and cust.spot.has("copies"):
				$"../Chores".misshelve(cust.tapes.pop_back(), cust.spot)
			else:
				tapes.set_on_shelf(cust.tapes.pop_back(), true)
			cust.holding = 0
			c.hold_tape(0)
	var others: Array = cust.party.filter(func(k: Dictionary) -> bool: return k != cust and custs.has(k) and not k.state in LEAVING)
	if busy.is_empty() and (others.is_empty() or others[0].state == "tagAlong" or cust.kid):  # everyone's done: out the door together
		c.set_mood("happy" if cust.holding > 0 or cust.paid else "neutral")
		c.talking = false
		go(cust, "leave", { "x": _door.x, "z": _door.y })
		return
	if cust.t > 0.0:
		return
	var k: Dictionary = busy[0] if not busy.is_empty() else others[0]
	var q: Vector3 = k.c.position
	cust.tag_t += 2.0
	if cust.tag_t > 90.0 and not busy.is_empty() and not k.kid:  # "come on..."
		k.stops_left = mini(k.stops_left, 0)
		k.c.set_mood("meh")
		k.hi = 1.0
	if q.distance_to(c.position) > 1.8:  # go stand beside them (by the line, not in it)
		var a := randf() * TAU
		var spot := { "x": q.x + cos(a) * 0.9, "z": q.z + sin(a) * 0.9 + (0.6 if k.state in ["inLine", "queue", "counter", "wait", "checkout"] else 0.0) }
		spot.ry = atan2(q.x - spot.x, q.z - spot.z)
		go(cust, "tagAlong", spot)
		cust.t = 2.5
		return
	cust.ry = atan2(q.x - c.position.x, q.z - c.position.z)
	c.talking = randf() < 0.5
	c.set_mood("browse" if randf() < 0.3 else "neutral")
	cust.state = "tagAlong"
	cust.t = 2.0 + randf() * 2.0


# ---- the theater (custPickTheaterSeat; the thAisle ... thRowOut states)

func open_way(box: Dictionary) -> void:  # a door that was chained shut isn't any more: the way through it's on the map
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).nav
	d.colliders = d.colliders.filter(func(c: Array) -> bool: return not (absf(c[0] - box.x0) < 0.01 and absf(c[1] - box.x1) < 0.01 and absf(c[2] - box.z0) < 0.01 and absf(c[3] - box.z1) < 0.01))
	_nav = Nav.new(d)


func _floor_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 1.0, at.z), Vector3(at.x, at.y - 2.0, at.z))
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else at.y


func _pick_theater_seat(cust: Dictionary) -> bool:  # an open stadium seat; they walk to its row on the center ramp
	if not $"../Shift".owned("theater"):
		return false
	var open: Array = interact.seats.filter(func(s: Dictionary) -> bool: return s.kind == "theater" and s != player.seat and not custs.any(func(k: Dictionary) -> bool: return k != cust and k.th_seat == s))
	if open.is_empty():
		return false
	cust.th_seat = open[int(cust.who.rnd.call() * open.size())]
	go(cust, "thAisle", { "x": -2.87, "z": cust.th_seat.z + 0.42, "ry": 0.0 })
	return true
