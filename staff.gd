extends Node
## The staff: Dana, on the register. When somebody's waiting at the counter and nobody's ringing them up, she does, a
## step at a time: a hand out, then the step happens, a beat, the next.
## From the web game's store/staff.js (EMP_POST; the "post" state: her turn after a second and a half, the reach before
## each step, 0.9 s to the customer and 0.7 otherwise, quicker with her DEX of 3; chatting while she works).
## Not over yet: everything else she does (the job board, cleaning, lunch, the stool, going home; restocking, but for
## a stand-in: returns find their own way back to the shelf while she's idle),
## skills, hiring, the others. She's at her post all day.

const DEX := 3

var dana: Node3D
var _ring_t := 0.0
var _co_t := 0.0
var _reached := false
var _chat_t := 0.0
var _post := {}
var _restock_t := 0.0

@onready var tapes: Node = $"../Tapes"
@onready var people: Node3D = $"../People"
@onready var shoppers: Node = $"../Shoppers"
@onready var checkout: Node = $"../Checkout"


func _ready() -> void:
	_post = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.register.post
	call_deferred("_hire")


func _hire() -> void:
	for i in people.cast.who.size():
		if people.cast.who[i].get("staff", "") == "Dana":
			dana = people.spawn(i)
	if dana == null:
		return
	dana.position = Vector3(_post.x, 0.0, _post.z)  # behind the register, facing the customer side
	dana.rotation.y = _post.ry
	dana.walk_lean = false


func _process(dt: float) -> void:
	if dana == null:
		return
	var co = checkout.co
	var waiting = shoppers.waiting()
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
				dana.set_pose("idle")
				_co_t = 0.35
			else:
				_reached = true
				dana.set_pose("reach")
				_co_t = (0.9 if s[1] == "customer" else 0.7) * maxf(0.45, 1.0 - 0.04 * (DEX - 1))  # (DEX: quick hands at the register)
	else:
		dana.talking = false
		dana.look_at_yaw(null)
		dana.set_pose("idle")
		if waiting == null:
			dana.set_mood("neutral")
			# restocking: with nobody to ring up, a return goes back on its shelf every so often. (The web game walks her
			# to the bin and round the shelves with them; that's not over, so here they just get there)
			_restock_t = _restock_t + dt if not tapes.return_bin.is_empty() else 0.0  # (25 s from when there's something to put away)
			if _restock_t > 25.0:
				_restock_t = 0.0
				tapes.set_on_shelf(tapes.return_bin.pop_front(), true)
	dana.tick(dt, 0.0)
