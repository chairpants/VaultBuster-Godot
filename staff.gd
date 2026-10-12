extends Node
## The staff: Dana. At her post she rings up whoever's waiting when you don't, a step at a time: a hand out, then the
## step happens, a beat, the next. With nobody to ring up and tapes in the Returns bin, she takes up to five, lifts
## the counter's pass-through, walks each to its own slot and puts it back, then comes home; called away by somebody
## at the counter, she goes back to her post first and finishes the round after.
## From the web game's store/staff.js (EMP_POST; the "post" state: her turn after a second and a half, the reach before
## each step, 0.9 s to the customer and 0.7 otherwise, quicker with her DEX of 3; chatting while she works; "toShelf"
## and "shelve": a hand to the slot, 0.9 s less a little for her INT of 3, the tag re-armed).
## Not over yet: the job board and the rest of her jobs (snacks, cleaning, the phone), lunch, the stool, going home,
## skills, hiring, the others. She's in all day. She puts a tape away rewound without a trip to the rewinder.

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
var _flap_mid := Vector2.ZERO
var _by_flap := false
var _target = null

@onready var tapes: Node = $"../Tapes"
@onready var people: Node3D = $"../People"
@onready var shoppers: Node = $"../Shoppers"
@onready var checkout: Node = $"../Checkout"
@onready var fixtures: Node = $"../Fixtures"


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	_post = d.things.register.post
	var fb: Dictionary = d.flap.box
	_flap_mid = Vector2((fb.x0 + fb.x1) / 2.0, (fb.z0 + fb.z1) / 2.0)
	var mine: Dictionary = d.nav.duplicate()
	mine.colliders = d.nav.colliders.filter(func(c: Array) -> bool: return not (absf(c[0] - fb.x0) < 0.01 and absf(c[1] - fb.x1) < 0.01 and absf(c[2] - fb.z0) < 0.01 and absf(c[3] - fb.z1) < 0.01))
	_nav = Nav.new(mine)
	_bin_spot = Vector2(d.things.returns.bin[0] - 0.55, d.things.returns.bin[2])  # behind the counter, by the tote
	call_deferred("_hire")


func _hire() -> void:
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
	if dana == null:
		return
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
			_ry = atan2(to.x, to.y)
		# called away: somebody's at the counter and she's out on the floor. Home first
		if waiting != null and checkout.co == null and state in ["toBin", "toShelf"]:
			_go(Vector2(_post.x, _post.z), "toPost")
	else:
		_t -= dt
		match state:
			"post":
				_ry = _post.ry
				_at_post(dt, waiting)
			"toPost":
				state = "post"
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
	if waiting != null:
		return
	dana.set_mood("neutral")
	if not carry.is_empty():  # (called away mid-round: on with it)
		_next()
	elif not tapes.return_bin.is_empty():  # returns to put away
		_go(_bin_spot, "toBin")
