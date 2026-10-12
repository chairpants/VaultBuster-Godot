extends Node
## The staff: everyone hired, each with their own skills, week and job priorities. This script is one employee; the
## node $Staff is the first of them and keeps the roster (who's been hired), making a node like itself for each of
## the others. At their spot behind the counter they ring up whoever's waiting when you don't, a step at a time: a
## hand out, then the step happens, a beat, the next. With nobody to ring up and tapes in the Returns bin, they take
## an armful, lift the counter's pass-through, walk each to its own slot and put it back, then come home; called
## away by somebody at the counter, back to the post first. With nothing else to do they clean up: the nearest
## mess, a bin that's filling (or a bag left on the floor) to the chute. They work their shifts: in through the
## front door, out again when it's over.
## And skills: six stats, you and every one of them, levelled by doing the work (K shows them). Each level makes
## that kind of work go better, and some levels unlock something.
## From the web game's store/staff.js (EMP_POST, empAt, the "post" state, toShelf / shelve, defaultSched, onDuty,
## danaStartJob's cleanup, JOBS and their priorities; SKILLS, MILESTONES, xpToNext, lv, has, gainXp, empWage;
## rollApplicant, DANA_APP, makeEmployee, hireCost, STAFF_MAX) and store/customer-mode.js (cmRoster).
## Not over yet: the jobs with nothing here to do yet (floor help, restocking the racks), lunch, the stool, chatting,
## an applicant's own look (a hire wears one of the cast's clothes), what the INT and WIS unlocks light up. They put
## a tape away rewound without a trip to the rewinder, and carry a bag of trash without it showing.

const Nav := preload("res://nav.gd")
const PACE := 1.3  # m/s
const STAFF_MAX := 4
const SKILLS := {  # [short, long, what it's for, XP rate: so the rarer kinds of work level about as fast as the constant ones]
	"dex": ["DEX", "Dexterity", "the register, desensitizing, the rewinders", 0.6], "int": ["INT", "Intelligence", "shelving, misshelves, finding requests, holds", 1.2],
	"cha": ["CHA", "Charisma", "upsells, recommendations, sign-ups, the phone", 1.0], "str": ["STR", "Strength", "restocking the racks, unpacking deliveries", 1.4],
	"con": ["CON", "Constitution", "cleaning up, being on your feet all day", 1.5], "wis": ["WIS", "Wisdom", "reading customers, spotting shoplifters, the gate alarm", 2.5],
}
const SKILL_MAX := 20
const MILESTONES := {  # level -> [name, what it does, staff get it too]
	"dex": { 5: ["Quick Thread", "rewinders you load run 30% faster", true], 10: ["Lucky Spool", "1 in 5 rewinds is done in a blink", true] },
	"int": { 5: ["Shelf Sense", "the slot for the tape in your hand glows", false], 10: ["Keen Eye", "misshelved tapes glow", false] },
	"cha": { 5: ["Smooth Talker", "charging late fees costs half the goodwill", true], 10: ["Store Favorite", "customers wait 30% longer in line", false] },
	"str": { 5: ["Strong Grip", "carry a third trash bag", false], 10: ["Pack Mule", "carry two more boxes", false] },
	"con": { 5: ["Second Wind", "sprint 15% faster", false], 10: ["Neat Freak", "cleaning a mess sweeps up others within 3m", false] },
	"wis": { 5: ["Sixth Sense", "shoplifters glow red", false], 10: ["Stern Look", "a shoplifter you stare down gives up 85% of the time", false] },
}
const JOBS := { "register": ["REGISTER", 1], "phone": ["PHONES", 2], "returns": ["RETURNS", 3], "cleanup": ["CLEANUP", 4] }  # [name, default priority: 1 first, 0 never]
const FIRST_F := ["Dana", "Tina", "Kim", "Stacy", "Jen", "Lisa", "Amy", "Becky", "Tanya", "Rhonda", "Gina", "Missy", "Carla", "Wendy", "Trish", "Nikki", "Shawna", "Heather"]
const FIRST_M := ["Kevin", "Troy", "Duane", "Chad", "Marcus", "Todd", "Ray", "Eddie", "Jason", "Luis", "Derek", "Kyle", "Brian", "Andre", "Shane", "Gary", "Manny", "Rob"]
const LASTS := ["Reyes", "Kowalski", "Nguyen", "Brennan", "Okafor", "Delgado", "Murphy", "Patel", "Hendricks", "Lund", "Castillo", "Baker", "Ortiz", "Sato", "Fitzgerald", "Novak", "Harlan", "Pruitt"]

static var crew: Array = []  # every employee's node, $Staff first
static var speaker := "Dana"  # whoever on staff is doing the talking (hud.gd puts their name on what's said)
static var you := {}  # your own skills: stat -> [level, xp]

var idx := 0  # which hire this is
var who := {}  # this one: { first, last, female, skills: { stat: [level, xp] }, sched: [7 masks: bit n = 9+n o'clock], jobs: { id: priority } }
var first := "Dana"
var roster: Array = []  # ($Staff's) everyone hired
var hires := 0  # (each hire costs more than the last)
var dana: Node3D  # their body, while they're in
var state := "post"  # post | toBin | binTake | toShelf | shelve | toPost | ...
var carry: Array = []  # the returns in their arms

var _ring_t := 0.0
var _co_t := 0.0
var _reached := false
var _chat_t := 0.0
var _post := {}
var _path: Array = []
var _t := 0.0
var _face := 0.0
var _ry := 0.0
var _nav: RefCounted  # their own map: the pass-through's no wall to them
var _bin_spot := Vector2.ZERO
var _chute_spot := Vector2.ZERO
var _flap_mid := Vector2.ZERO
var _by_flap := false
var _alarm_t := 0.0
var _step_d := 0.0
var _mess = null
var _stray = null
var _trash = null  # the bin, or the bag on the floor, they're after
var _bag = null  # the bag in their hands
var _on_always := not OS.get_cmdline_user_args().is_empty()  # (the tests: the first of them is always in)
var _clock_t := 0.0
var _target = null
var _rostered := false
var _sheet := Label.new()
var _sheet_layer := CanvasLayer.new()

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
	_post = d.things.register.post.duplicate()
	_post.x += 0.72 * idx  # each one's spot behind the counter when there's nothing on
	var fb: Dictionary = d.flap.box
	_flap_mid = Vector2((fb.x0 + fb.x1) / 2.0, (fb.z0 + fb.z1) / 2.0)
	var mine: Dictionary = d.nav.duplicate()
	mine.colliders = d.nav.colliders.filter(func(c: Array) -> bool: return not (absf(c[0] - fb.x0) < 0.01 and absf(c[1] - fb.x1) < 0.01 and absf(c[2] - fb.z0) < 0.01 and absf(c[3] - fb.z1) < 0.01))
	_nav = Nav.new(mine)
	_chute_spot = Vector2(d.things.chute.stand.x, d.things.chute.stand.z)
	_bin_spot = Vector2(d.things.returns.bin[0] - 0.55, d.things.returns.bin[2])  # behind the counter, by the tote
	if idx > 0:
		return
	crew = [self]
	speaker = "Dana"
	you = _skills({})
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_sheet.add_theme_font_override("font", font)
	_sheet.add_theme_font_size_override("font_size", 15)
	_sheet.add_theme_color_override("font_outline_color", Color.BLACK)
	_sheet.add_theme_constant_override("outline_size", 6)
	_sheet.position = Vector2(40, 130)
	_sheet_layer.add_child(_sheet)
	_sheet_layer.visible = false
	add_child(_sheet_layer)


# ---- skills

static func _skills(levels: Dictionary) -> Dictionary:
	var out := {}
	for k: String in SKILLS:
		out[k] = [int(levels.get(k, 1)), 0.0]
	return out


static func xp_to_next(l: int) -> int:  # XP from level l to l+1: 60, 90, 135, 203... x1.5 each
	return roundi(60.0 * pow(1.5, l - 1))


static func lv(w, k: String) -> int:  # w: "you", or an employee's node
	var sk: Dictionary = you if w is String else w.who.get("skills", {})
	return sk[k][0] if sk.has(k) else 1


static func has(w, k: String, l: int) -> bool:
	return lv(w, k) >= l


func xp(w, k: String, amt: float) -> void:  # doing a task earns XP in its stat (gainXp). w: "you", or an employee's node
	var mine := w is String
	var sk: Array = (you if mine else w.who.skills)[k]
	if sk[0] >= SKILL_MAX or amt <= 0.0:
		return
	sk[1] += amt * SKILLS[k][3]
	while sk[0] < SKILL_MAX and sk[1] >= xp_to_next(sk[0]):
		sk[1] -= xp_to_next(sk[0])
		sk[0] += 1
		var m: Array = MILESTONES[k].get(sk[0], [])
		if mine:
			hud.toast("%s %d! Unlocked %s: %s" % [SKILLS[k][0], sk[0], m[0], m[1]] if not m.is_empty() else "%s up! Level %d" % [SKILLS[k][0], sk[0]])
		else:
			hud.toast("%s's %s is up to %d%s" % [w.first, SKILLS[k][1], sk[0], " (%s: %s)" % [m[0], m[1]] if not m.is_empty() and m[2] else ""])


func rate(w: Dictionary) -> float:  # by the hour: $7 for an average hand, a little more for the better ones (empWage / 5)
	var avg := 0.0
	for k: String in SKILLS:
		avg += w.skills[k][0] / 6.0
	return snappedf((35.0 + 3.0 * roundf(avg - 2.5)) / 5.0, 0.01)


func hours(w: Dictionary, weekday := -1) -> int:  # scheduled, that day (or the whole week)
	var n := 0
	for d in 7:
		if weekday < 0 or d == weekday:
			for b in 15:
				n += (int(w.sched[d]) >> b) & 1
	return n


func _unhandled_input(e: InputEvent) -> void:
	if idx == 0 and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_K:  # the character sheet
		_sheet_layer.visible = not _sheet_layer.visible


func _sheet_text() -> String:
	var rows := PackedStringArray(["SKILLS · K to close", "", "            " + "  ".join(SKILLS.keys().map(func(k: String) -> String: return SKILLS[k][0].rpad(8)))])
	var line := func(name: String, sk: Dictionary) -> String:
		return name.rpad(12).left(12) + "  ".join(SKILLS.keys().map(func(k: String) -> String: return ("%2d %s" % [sk[k][0], "#".repeat(int(5.0 * sk[k][1] / xp_to_next(sk[k][0]))).rpad(5, "-")]).rpad(8)))
	rows.append(line.call("You", you))
	for w: Dictionary in roster:
		rows.append(line.call(w.first, w.skills))
	rows.append("")
	for k: String in SKILLS:
		rows.append("%s  %s" % [SKILLS[k][0], SKILLS[k][2]])
		for l: int in MILESTONES[k]:
			rows.append("     %s %2d %s: %s" % ["★" if has("you", k, l) else "☆", l, MILESTONES[k][l][0], MILESTONES[k][l][1]])
	return "\n".join(rows)


# ---- the roster ($Staff's)

func applicant() -> Dictionary:  # a name, and stats that always add up to the same total: each one's as good as the others, just good at different things (rollApplicant)
	var female := randf() < 0.5
	var levels := {}
	for k: String in SKILLS:
		levels[k] = 1
	var left := 15 - 6
	while left > 0:
		var k: String = SKILLS.keys().pick_random()
		if levels[k] < 6:
			levels[k] += 1
			left -= 1
	return { "first": (FIRST_F if female else FIRST_M).pick_random(), "last": LASTS.pick_random(), "female": female, "skills": _skills(levels) }


func _dana() -> Dictionary:  # DANA_APP
	return { "first": "Dana", "last": "Reyes", "female": true, "skills": _skills({ "dex": 3, "int": 3, "cha": 3, "str": 2, "con": 2, "wis": 2 }) }


func hire(w: Dictionary) -> void:  # onto the roster: five 5-hour shifts, staggered (evenings, the rush; every other hire afternoons), the job board's usual order
	var i := roster.size()
	if not w.has("sched"):
		w.sched = [0, 0, 0, 0, 0, 0, 0]
		for k in 5:
			w.sched[(3 + i * 2 + k) % 7] |= 31 << (3 if i % 2 == 1 else 8)  # 12-5 PM / 5-10 PM
	if not w.has("jobs"):
		w.jobs = {}
		for id: String in JOBS:
			w.jobs[id] = JOBS[id][1]
	roster.append(w)
	if i == 0:
		who = w
		first = w.first
		return
	var e := Node.new()
	e.set_script(load("res://staff.gd"))
	e.idx = i
	e.who = w
	e.first = w.first
	e.name = "Staff%d" % i
	get_parent().add_child(e)
	crew.append(e)


func hire_cost() -> int:
	return roundi(250.0 * pow(1.55, hires) / 5.0) * 5


func _muster() -> void:  # once the save's been read (or there isn't one): who's on staff
	var shift: Node = $"../Shift"
	if roster.is_empty() and (not shift.sim() or shift.owned("hire")):
		hire(_dana())  # (a sandbox; or a simulation from when Dana was the only hire)
	if shift.mode == "customer":
		customer_crew()


func customer_crew() -> void:  # customer mode: the store's never short-handed. Three at least, and every hour it's open covered: one opens (9-5), one closes (4-midnight), one's in for the middle of the day (noon-8)
	while roster.size() < 3:
		hire(_dana() if roster.is_empty() else applicant())
	for i in roster.size():
		var s: Array = [[0, 8], [7, 8], [3, 8]][i % 3]
		for d in 7:
			roster[i].sched[d] = ((1 << s[1]) - 1) << s[0]


func clerk():  # whoever's at their post with nothing on (or null)
	for e: Node in crew:
		if e.dana != null and e.state == "post" and e._path.is_empty() and not (checkout.co != null and checkout.co.get("emp") == e):
			return e
	return null


func anyone():  # whoever's in (their node), the one at the register first
	var c = clerk()
	if c != null:
		return c
	for e: Node in crew:
		if e.dana != null:
			return e
	return null


func send_home() -> void:  # they went home overnight: in when their shifts start
	tapes.return_bin.append_array(carry)
	carry = []
	if dana != null:
		dana.queue_free()
		dana = null
	state = "post"
	_path = []
	_mess = null
	_trash = null
	_bag = null


# ---- one of them

func on_duty() -> bool:  # should they be in the store right now? (onDuty)
	if who.is_empty():
		return false
	if _on_always and idx == 0:
		return true
	var n := int(Clock.h) - 9
	return n >= 0 and n < 15 and (int(who.sched[Clock.date().weekday]) >> n) & 1 == 1


func _pri(job: String) -> int:  # off counts as never
	var p: int = who.jobs.get(job, 0)
	return p if p > 0 else 9


func _hire(arrive: bool) -> void:  # already at their post if the store's just loaded; else in through the door
	var looks: Array = range(people.cast.who.size()).filter(func(i: int) -> bool: return people.cast.who[i].get("staff", "") == "Dana") if first == "Dana" else []
	if looks.is_empty():  # ponytail: a hire wears one of the cast's clothes; their own outfit wants adding to the people export
		looks = range(people.cast.who.size()).filter(func(i: int) -> bool: return people.cast.who[i].female == who.female and not people.cast.who[i].has("staff"))
	if looks.is_empty():
		return
	dana = people.spawn(looks[(first + who.last).hash() % looks.size()])
	dana.position = Vector3(_post.x, 0.0, _post.z)  # behind the register, facing the customer side
	dana.rotation.y = _post.ry
	_face = _post.ry
	_ry = _post.ry
	dana.walk_lean = false
	state = "post"
	if arrive:
		dana.position = Vector3(shoppers._door.x, 0.0, shoppers._door.y)
		_go(Vector2(_post.x, _post.z), "toPost")
		hud.toast("%s clocked in" % first)


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
	if idx == 0:
		if not _rostered and _clock_t > 0.4:
			_rostered = true
			_muster()
		if _sheet_layer.visible:
			_sheet.text = _sheet_text()
	if dana == null:
		if on_duty() and _clock_t > 0.5:  # off the clock: in when their shift starts
			_hire(_clock_t > 3.0)
		return
	if not on_duty() and state == "post" and not (checkout.co != null and checkout.co.get("emp") == self) and carry.is_empty():  # their shift's over: out the front door
		_go(Vector2(shoppers._door.x, shoppers._door.y), "toExit")
		dana.set_mood("happy")
		hud.toast("%s clocked out" % first)
	var waiting = shoppers.waiting()
	var speed := 0.0
	# the pass-through: up as they come to it, down behind them
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
			speed = PACE * (1.0 + 0.03 * (lv(self, "con") - 1))  # (CON: quicker on their feet)
			dana.position += Vector3(to.x, 0.0, to.y) / d * minf(d, speed * dt)
			_step_d += minf(d, speed * dt)
			for door: Dictionary in interact.doors:  # they get the doors
				if not door.open and not door.locked and not door.push and Vector2((door.shut.x0 + door.shut.x1) / 2.0, (door.shut.z0 + door.shut.z1) / 2.0).distance_to(Vector2(dana.position.x, dana.position.z)) < 1.2:
					interact.toggle_door(door)
			if _step_d > 0.7:
				_step_d = 0.0
				$"../Ambience".step(dana.position)
			_ry = atan2(to.x, to.y)
		# called away: somebody's at the counter, nobody's at the register, and they're out on the floor. Home first
		if waiting != null and checkout.co == null and crew[0].clerk() == null and _pri("register") < 9 and state in ["toBin", "toShelf", "toMess", "toTrash", "toBag", "toStray"]:
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
						speaker = first
						chores.mess_clean(_mess, "dana")
						crew[0].xp(self, "con", 6.0)
					_mess = null
					_go(Vector2(_post.x, _post.z), "toPost")
			"toTrash":  # at the bin: the bag out, a fresh liner in
				dana.reach_to(Vector3(_trash.x, _trash.rimY + 0.05, _trash.z))
				state = "bagging"
				_t = 2.2 * maxf(0.5, 1.0 - 0.03 * (lv(self, "dex") - 1))
			"bagging":
				if _t <= 0.0:
					dana.reach_to(null)
					if _trash.n == 0:  # somebody beat them to it
						_go(Vector2(_post.x, _post.z), "toPost")
					else:
						_bag = { "bin": _trash.id, "n": _trash.n }
						_trash.n = 0
						_trash.acc = 0.0
						_trash.spilled = false
						crew[0].xp(self, "con", 3.0)
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
					crew[0].xp(self, "str", 3.0)
					crew[0].xp(self, "con", 2.0)
					hud.toast("%s took a bag of trash down the chute (+10)" % first)
				if _t <= 0.0:
					dana.reach_to(null)
					_go(Vector2(_post.x, _post.z), "toPost")
			"toBin":  # by the tote: a hand in
				dana.reach_to(Vector3(_bin_spot.x + 0.55, 0.6, _bin_spot.y), 1, true)
				state = "binTake"
				_t = 0.8
			"binTake":
				if _t <= 0.0:
					while carry.size() < mini(20, 6 + 2 * lv(self, "str")) and not tapes.return_bin.is_empty():  # (STR: a bigger armful)
						carry.append(tapes.return_bin.pop_front())
					dana.reach_to(null)
					_next()
			"toShelf":  # at the shelf: a hand to its own slot
				_ry = atan2(_target.p[0] - dana.position.x, _target.p[2] - dana.position.z)
				dana.reach_to(Vector3(_target.p[0], _target.p[1], _target.p[2]))
				state = "shelve"
				_t = 0.9 * maxf(0.5, 1.0 - 0.03 * (lv(self, "int") - 1))  # (INT: knows right where it goes)
			"shelve":
				if _t <= 0.0:  # back in its slot, rewound, tag re-armed
					carry.erase(_target)
					_target.desens = false
					_target.ep = 0
					_target.at = 0.0
					tapes.set_on_shelf(_target, true)
					checkout.score += 5
					crew[0].xp(self, "int", 4.0)
					dana.reach_to(null)
					_next()
	_face += angle_difference(_face, _ry) * minf(1.0, dt * 8.0)
	dana.rotation.y = _face
	dana.tick(dt, speed)


func _at_post(dt: float, waiting) -> void:
	_alarm_t = _alarm_t + dt if shoppers.alarm_on else 0.0  # the gates going off: a few seconds' grace (yours if you want it), then they shut it off
	if _alarm_t > 4.0:
		shoppers.silence_alarm()
		crew[0].xp(self, "wis", 3.0)
		hud.toast("%s shut off the gate alarm" % first)
	var co = checkout.co
	if waiting != null and co == null and _pri("register") < 9:  # their turn: start ringing them up (yours, if you get to them first)
		dana.set_mood("happy")
		_ring_t += dt
		if _ring_t > 1.5:
			_ring_t = 0.0
			speaker = first
			checkout.start("dana", waiting)
			checkout.co.emp = self
			_co_t = 0.0
			_reached = false
	else:
		_ring_t = 0.0
	var mine: bool = checkout.co != null and checkout.co.by == "dana" and checkout.co.get("emp", self) == self
	if mine:  # chatting while they work: faces them, nods, smiles
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
				speaker = first
				var last: bool = s[0] in ["handback", "newcard"]
				checkout.act(s[1])
				if last and checkout.co == null:
					crew[0].xp(self, "dex", 10.0)
				dana.reach_to(null)
				_co_t = 0.35
			else:
				_reached = true
				dana.reach_to(Vector3(lerpf(dana.position.x, q.x, 0.55), 1.05, lerpf(dana.position.z, q.z, 0.55)) if s[1] == "customer" else checkout._at["pos" if s[1] == "register" else s[1]], 1, false)  # across the counter to them, or to the register, the pad, the printer
				_co_t = (0.9 if s[1] == "customer" else 0.7) * maxf(0.45, 1.0 - 0.04 * (lv(self, "dex") - 1))  # (DEX: quick hands at the register)
		return
	dana.talking = false
	dana.look_at_yaw(null)
	dana.reach_to(null)
	for k: Dictionary in shoppers.custs:  # back with a tag that set the gates off (a few seconds: yours if you want it)
		if k.state == "tagWait" and k.t < 30.0 * k.who.patience - 3.0:
			speaker = first
			shoppers.tag_fix(k, "dana")
			crew[0].xp(self, "dex", 3.0)
			break
	if waiting != null and _pri("register") < 9 and (crew[0].clerk() == self or checkout.co == null):
		return
	dana.set_mood("neutral")
	if not carry.is_empty():  # (called away mid-round: on with it)
		_next()
		return
	var jobs: Array = ["returns", "cleanup"].filter(func(j: String) -> bool: return _pri(j) < 9)  # the job board's order
	jobs.sort_custom(func(a: String, b: String) -> bool: return _pri(a) < _pri(b))
	for job: String in jobs:
		if job == "returns" and not tapes.return_bin.is_empty() and not crew.any(func(e: Node) -> bool: return e != self and e.state in ["toBin", "binTake"]):
			_go(_bin_spot, "toBin")
			return
		if job == "returns" and not chores.strays.is_empty():  # the bin's done: straighten up what customers shoved in anywhere
			var free: Array = chores.strays.filter(func(s: Dictionary) -> bool: return not crew.any(func(e: Node) -> bool: return e != self and e._stray == s))
			if not free.is_empty():
				_stray = free[0]
				_go(Vector2(_stray.at.x + cos(_stray.ry) * 0.8, _stray.at.z - sin(_stray.ry) * 0.8), "toStray")
				return
		if job == "cleanup" and _cleanup():
			return


func _cleanup() -> bool:  # litter, spills, taking out the trash: a bag on the floor or a nearly-full bin before litter; otherwise litter first. -> off to do some
	var taken := func(x) -> bool: return crew.any(func(e: Node) -> bool: return e != self and (e._mess == x or e._trash == x))
	var bags: Array = chores.bags_down.filter(func(g: Dictionary) -> bool: return not taken.call(g))
	var t = bags[0] if not bags.is_empty() else null
	if t == null:
		var full: Array = chores.bins.filter(func(b: Dictionary) -> bool: return b.n >= b.cap * 0.6 and not taken.call(b))
		full.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.n) / a.cap > float(b.n) / b.cap)
		if not full.is_empty():
			t = full[0]
	var messes: Array = chores.messes.filter(func(m: Dictionary) -> bool: return not taken.call(m))
	if t != null and (messes.is_empty() or t.has("node") or t.n >= t.cap * 0.85):
		_trash = t
		dana.set_mood("neutral")
		if t.has("node"):
			_go(Vector2(t.x + 0.45, t.z), "toBag")
		else:
			_go(Vector2(t.stand.x, t.stand.z), "toTrash")
		if state == "toPost":
			_trash = null  # (no way there)
		return true
	if messes.is_empty():
		return false
	var here := Vector2(dana.position.x, dana.position.z)
	var m: Dictionary = messes[0]
	for o: Dictionary in messes:
		if here.distance_to(Vector2(o.x, o.z)) < here.distance_to(Vector2(m.x, m.z)):
			m = o
	_mess = m
	dana.set_mood("neutral")
	_go(Vector2(m.x + 0.45, m.z), "toMess")
	if state == "toPost":
		_mess = null
	return true


# ---- for the save ($Staff's)

func snapshot() -> Dictionary:
	return { "roster": roster, "hires": hires, "you": you }


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	hires = int(d.get("hires", 0))
	for k: String in d.get("you", {}):
		if you.has(k):
			you[k] = [int(d.you[k][0]), d.you[k][1]]
	for e: Node in crew.slice(1):  # (whoever was on it before: the save has the say)
		e.send_home()
		e.queue_free()
	crew = [self]
	roster = []
	who = {}
	_rostered = true
	for w: Dictionary in d.get("roster", []):
		for k: String in w.skills:
			w.skills[k] = [int(w.skills[k][0]), w.skills[k][1]]
		for i in w.sched.size():
			w.sched[i] = int(w.sched[i])
		for j: String in w.jobs:
			w.jobs[j] = int(w.jobs[j])
		hire(w)
