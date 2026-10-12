extends Node
## The staff: Dana. At her post she rings up whoever's waiting when you don't, a step at a time: a hand out, then the
## step happens, a beat, the next. With nobody to ring up and tapes in the Returns bin, she takes up to five, lifts
## the counter's pass-through, walks each to its own slot and puts it back, then comes home; called away by somebody
## at the counter, she goes back to her post first and finishes the round after.
## From the web game's store/staff.js (EMP_POST; the "post" state: her turn after a second and a half, the reach before
## each step, 0.9 s to the customer and 0.7 otherwise, quicker with her DEX of 3; chatting while she works; "toShelf"
## and "shelve": a hand to the slot, 0.9 s less a little for her INT of 3, the tag re-armed).
## She works her shifts: Wednesday to Sunday, 5 to 10 PM (defaultSched, onDuty); in through the front door, out again
## when it's over. The rest of the time the register's yours. With nothing else to do she cleans up: the nearest
## mess, or a bin that's filling (or a bag left on the floor) to the chute (danaStartJob's cleanup; toMess, toBin,
## toBag, toChute).
## Not over yet: the job board (her jobs are in its default order), snacks, the phone, questions at the counter,
## lunch (her shift's never over midday), the stool, skills, hiring, the others. She puts a tape away rewound
## without a trip to the rewinder, and carries a bag of trash without it showing.

const Nav := preload("res://nav.gd")
const DEX := 3
const INT := 3
const PACE := 1.3  # m/s
const ARMFUL := 5

var dana: Node3D
var state := "post"  # post | toBin | binTake | toShelf | shelve | toPost
var carry: Array = []  # the returns in her arms

var _ring_t := 0.0
var _co_t := 0.0
var _reached := false
var _chat_t := 0.0
var _post := {}
var _path: Array = []
var _t := 0.0
var _face := 0.0
var _ry := 0.0
var _nav: RefCounted  # her own map: the pass-through's no wall to her
var _bin_spot := Vector2.ZERO
var _chute_spot := Vector2.ZERO
var _flap_mid := Vector2.ZERO
var _by_flap := false
var _alarm_t := 0.0
var _step_d := 0.0
var _mess = null
var _stray = null
var _trash = null  # the bin, or the bag on the floor, she's after
var _bag = null  # the bag in her hands
var _on_always := not OS.get_cmdline_user_args().is_empty()  # (the tests: she's always in)
var _clock_t := 0.0
var _target = null

@onready var tapes: Node = $"../Tapes"
@onready var people: Node3D = $"../People"
@onready var shoppers: Node = $"../Shoppers"
@onready var checkout: Node = $"../Checkout"
@onready var fixtures: Node = $"../Fixtures"
@onready var hud: CanvasLayer = $"../HUD"
@onready var chores: Node = $"../Chores"
@onready var interact: Node = $"../Interact"


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	_post = d.things.register.post
	var fb: Dictionary = d.flap.box
	_flap_mid = Vector2((fb.x0 + fb.x1) / 2.0, (fb.z0 + fb.z1) / 2.0)
	var mine: Dictionary = d.nav.duplicate()
	mine.colliders = d.nav.colliders.filter(func(c: Array) -> bool: return not (absf(c[0] - fb.x0) < 0.01 and absf(c[1] - fb.x1) < 0.01 and absf(c[2] - fb.z0) < 0.01 and absf(c[3] - fb.z1) < 0.01))
	_nav = Nav.new(mine)
	_chute_spot = Vector2(d.things.chute.stand.x, d.things.chute.stand.z)
	_bin_spot = Vector2(d.things.returns.bin[0] - 0.55, d.things.returns.bin[2])  # behind the counter, by the tote


func on_duty() -> bool:  # should she be in the store right now? Five 5-hour shifts: Wednesday to Sunday, 5 to 10 PM
	if _on_always:
		return true
	var n := int(Clock.h) - 9
	return $"../Shift".owned("hire") and n >= 8 and n <= 12 and Clock.date().weekday in [3, 4, 5, 6, 0]


func _hire(arrive: bool) -> void:  # already at her post if the store's just loaded; else in through the door
	for i in people.cast.who.size():
		if people.cast.who[i].get("staff", "") == "Dana":
			dana = people.spawn(i)
	if dana == null:
		return
	dana.position = Vector3(_post.x, 0.0, _post.z)  # behind the register, facing the customer side
	dana.rotation.y = _post.ry
	_face = _post.ry
	_ry = _post.ry
	dana.walk_lean = false
	state = "post"
	if arrive:
		dana.position = Vector3(shoppers._door.x, 0.0, shoppers._door.y)
		_go(Vector2(_post.x, _post.z), "toPost")
		hud.toast("Dana clocked in")


func _go(to: Vector2, then: String) -> void:
	_path = _nav.path(dana.position.x, dana.position.z, to.x, to.y)
	state = then
	if _path.is_empty() and then != "toPost":  # (no way there: home)
		state = "toPost"
		_path = _nav.path(dana.position.x, dana.position.z, _post.x, _post.z)


func _next() -> void:  # the next return to put away, or home
	if carry.is_empty():
		dana.hold_tape(0)
		dana.set_pose("idle")
		_go(Vector2(_post.x, _post.z), "toPost")
		return
	_target = carry[0]
	dana.hold_tape(mini(3, carry.size()))
	dana.set_pose("hold")
	var fx := cos(_target.ry)  # (shelves face their local +x)
	var fz := -sin(_target.ry)
	_go(Vector2(_target.p[0] + fx * 0.8, _target.p[2] + fz * 0.8), "toShelf")


func _process(dt: float) -> void:
	_clock_t += dt
	if dana == null:
		if on_duty() and _clock_t > 0.2:  # off the clock: in when her shift starts
			_hire(_clock_t > 3.0)
		return
	if not on_duty() and state == "post" and checkout.co == null and carry.is_empty():  # her shift's over: out the front door
		_go(Vector2(shoppers._door.x, shoppers._door.y), "toExit")
		dana.set_mood("happy")
		hud.toast("Dana clocked out")
	var waiting = shoppers.waiting()
	var speed := 0.0
	# the pass-through: up as she comes to it, down behind her
	var by_flap := Vector2(dana.position.x, dana.position.z).distance_to(_flap_mid) < 1.3
	if state != "post" and by_flap:
		fixtures.flap_open = true
		_by_flap = true
	elif _by_flap and not by_flap:
		_by_flap = false
		fixtures.flap_open = false
	if not _path.is_empty():  # walking
		var to: Vector2 = _path[0] - Vector2(dana.position.x, dana.position.z)
		var d := to.length()
		if d < 0.05:
			_path.pop_front()
		else:
			speed = PACE
			dana.position += Vector3(to.x, 0.0, to.y) / d * minf(d, speed * dt)
			_step_d += minf(d, speed * dt)
			for door: Dictionary in interact.doors:  # she gets the doors
				if not door.open and not door.locked and not door.push and Vector2((door.shut.x0 + door.shut.x1) / 2.0, (door.shut.z0 + door.shut.z1) / 2.0).distance_to(Vector2(dana.position.x, dana.position.z)) < 1.2:
					interact.toggle_door(door)
			if _step_d > 0.7:
				_step_d = 0.0
				$"../Ambience".step(dana.position)
			_ry = atan2(to.x, to.y)
		# called away: somebody's at the counter and she's out on the floor. Home first
		if waiting != null and checkout.co == null and state in ["toBin", "toShelf", "toMess", "toTrash", "toBag", "toStray"]:
			_trash = null
			_mess = null
			_go(Vector2(_post.x, _post.z), "toPost")
	else:
		_t -= dt
		match state:
			"post":
				_ry = _post.ry
				_at_post(dt, waiting)
			"toPost":
				state = "post"
			"toStray":
				dana.reach_to(_stray.node.position if chores.strays.has(_stray) else _stray.at)
				state = "strayTake"
				_t = 0.8
			"strayTake":
				if _t <= 0.0:
					dana.reach_to(null)
					if chores.strays.has(_stray):
						chores.stray_take(_stray)
						carry.append(_stray.copy)
						checkout.score += 5
					_stray = null
					_next()
			"toExit":  # gone home
				dana.queue_free()
				dana = null
				state = "post"
				return
			"toMess":
				dana.set_pose("crouch")
				dana.reach_to(Vector3(_mess.x, 0.05, _mess.z))
				state = "cleaning"
				_t = 1.4
			"cleaning":
				if _t <= 0.0:
					dana.reach_to(null)
					dana.set_pose("idle")
					if chores.messes.has(_mess):
						chores.mess_clean(_mess, "dana")
					_mess = null
					_go(Vector2(_post.x, _post.z), "toPost")
			"toTrash":  # at the bin: the bag out, a fresh liner in
				dana.reach_to(Vector3(_trash.x, _trash.rimY + 0.05, _trash.z))
				state = "bagging"
				_t = 2.2 * maxf(0.5, 1.0 - 0.03 * (DEX - 1))
			"bagging":
				if _t <= 0.0:
					dana.reach_to(null)
					if _trash.n == 0:  # somebody beat her to it
						_go(Vector2(_post.x, _post.z), "toPost")
					else:
						_bag = { "bin": _trash.id, "n": _trash.n }
						_trash.n = 0
						_trash.acc = 0.0
						_trash.spilled = false
						_go(_chute_spot, "toChute")
					_trash = null
			"toBag":  # one somebody left on the floor
				dana.set_pose("crouch")
				dana.reach_to(Vector3(_trash.x, 0.25, _trash.z))
				state = "bagLift"
				_t = 0.8
			"bagLift":
				if _t <= 0.0:
					dana.set_pose("idle")
					dana.reach_to(null)
					if chores.bags_down.has(_trash):
						chores.bags_down.erase(_trash)
						_trash.node.queue_free()
						_bag = { "bin": _trash.bin, "n": _trash.n }
						_go(_chute_spot, "toChute")
					else:
						_go(Vector2(_post.x, _post.z), "toPost")
					_trash = null
			"toChute":
				dana.reach_to(chores._chute)
				state = "chuting"
				_t = 1.3
			"chuting":
				if _bag != null and _t < 0.9:  # in it goes
					_bag = null
					checkout.score += 10
					hud.toast("Dana took a bag of trash down the chute (+10)")
				if _t <= 0.0:
					dana.reach_to(null)
					_go(Vector2(_post.x, _post.z), "toPost")
			"toBin":  # by the tote: a hand in
				dana.reach_to(Vector3(_bin_spot.x + 0.55, 0.6, _bin_spot.y), 1, true)
				state = "binTake"
				_t = 0.8
			"binTake":
				if _t <= 0.0:
					while carry.size() < ARMFUL and not tapes.return_bin.is_empty():
						carry.append(tapes.return_bin.pop_front())
					dana.reach_to(null)
					_next()
			"toShelf":  # at the shelf: a hand to its own slot
				_ry = atan2(_target.p[0] - dana.position.x, _target.p[2] - dana.position.z)
				dana.reach_to(Vector3(_target.p[0], _target.p[1], _target.p[2]))
				state = "shelve"
				_t = 0.9 * maxf(0.5, 1.0 - 0.03 * (INT - 1))  # (INT: knows right where it goes)
			"shelve":
				if _t <= 0.0:  # back in its slot, rewound, tag re-armed
					carry.erase(_target)
					_target.desens = false
					_target.ep = 0
					_target.at = 0.0
					tapes.set_on_shelf(_target, true)
					checkout.score += 5
					dana.reach_to(null)
					_next()
	_face += angle_difference(_face, _ry) * minf(1.0, dt * 8.0)
	dana.rotation.y = _face
	dana.tick(dt, speed)


func _at_post(dt: float, waiting) -> void:
	_alarm_t = _alarm_t + dt if shoppers.alarm_on else 0.0  # the gates going off: a few seconds' grace (yours if you want it), then she shuts it off
	if _alarm_t > 4.0:
		shoppers.silence_alarm()
		hud.toast("Dana shut off the gate alarm")
	var co = checkout.co
	if waiting != null and co == null:  # their turn: start ringing them up (yours, if you get to them first)
		dana.set_mood("happy")
		_ring_t += dt
		if _ring_t > 1.5:
			_ring_t = 0.0
			checkout.start("dana", waiting)
			_co_t = 0.0
			_reached = false
	else:
		_ring_t = 0.0
	var mine: bool = checkout.co != null and checkout.co.by == "dana"
	if mine:  # chatting while she works: faces them, nods, smiles
		dana.talking = true
		var s: Array = checkout.step()
		var q: Vector3 = checkout.co.cust.c.position
		dana.look_at_yaw(angle_difference(dana.rotation.y, atan2(q.x - dana.position.x, q.z - dana.position.z)) if s[1] == "customer" else null)
		_chat_t -= dt
		if _chat_t <= 0.0:
			_chat_t = 1.5 + randf() * 2.0
			dana.set_mood(["happy", "happy", "neutral", "love"].pick_random())
		_co_t -= dt
		if _co_t <= 0.0:  # one step at a time: hand out, then the step happens
			if _reached:
				_reached = false
				checkout.act(s[1])
				dana.reach_to(null)
				_co_t = 0.35
			else:
				_reached = true
				dana.reach_to(Vector3(lerpf(dana.position.x, q.x, 0.55), 1.05, lerpf(dana.position.z, q.z, 0.55)) if s[1] == "customer" else checkout._at["pos" if s[1] == "register" else s[1]], 1, false)  # across the counter to them, or to the register, the pad, the printer
				_co_t = (0.9 if s[1] == "customer" else 0.7) * maxf(0.45, 1.0 - 0.04 * (DEX - 1))  # (DEX: quick hands at the register)
		return
	dana.talking = false
	dana.look_at_yaw(null)
	dana.reach_to(null)
	for k: Dictionary in shoppers.custs:  # back with a tag that set the gates off (a few seconds: yours if you want it)
		if k.state == "tagWait" and k.t < 30.0 * k.who.patience - 3.0:
			shoppers.tag_fix(k, "dana")
			break
	if waiting != null:
		return
	dana.set_mood("neutral")
	if not carry.is_empty():  # (called away mid-round: on with it)
		_next()
	elif not tapes.return_bin.is_empty():  # returns to put away
		_go(_bin_spot, "toBin")
	elif not chores.strays.is_empty():  # the bin's done: straighten up what customers shoved in anywhere
		_stray = chores.strays[0]
		_go(Vector2(_stray.at.x + cos(_stray.ry) * 0.8, _stray.at.z - sin(_stray.ry) * 0.8), "toStray")
	else:
		_cleanup()


func _cleanup() -> void:  # litter, spills, taking out the trash: a bag on the floor or a nearly-full bin before litter; otherwise litter first
	var t = chores.bags_down[0] if not chores.bags_down.is_empty() else null
	if t == null:
		var full: Array = chores.bins.filter(func(b: Dictionary) -> bool: return b.n >= b.cap * 0.6)
		full.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.n) / a.cap > float(b.n) / b.cap)
		if not full.is_empty():
			t = full[0]
	if t != null and (chores.messes.is_empty() or t.has("node") or t.n >= t.cap * 0.85):
		_trash = t
		dana.set_mood("neutral")
		if t.has("node"):
			_go(Vector2(t.x + 0.45, t.z), "toBag")
		else:
			_go(Vector2(t.stand.x, t.stand.z), "toTrash")
		if state == "toPost":
			_trash = null  # (no way there)
		return
	if chores.messes.is_empty():
		return
	var here := Vector2(dana.position.x, dana.position.z)
	var m: Dictionary = chores.messes[0]
	for o: Dictionary in chores.messes:
		if here.distance_to(Vector2(o.x, o.z)) < here.distance_to(Vector2(m.x, m.z)):
			m = o
	_mess = m
	dana.set_mood("neutral")
	_go(Vector2(m.x + 0.45, m.z), "toMess")
	if state == "toPost":
		_mess = null
