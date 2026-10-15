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
## They restock the racks from the cupboards too (danaRestockStart ... stockPut).
## Floor help: whoever's been asking at the counter twenty seconds gets what they asked for fetched from the shelf
## (or a pick from their kind of thing). Lunch: half an hour in the break room around midday, on a five-hour shift.
## With nothing on they lean on the counter, look about, and two of them near each other get talking.
## With nothing at all to do for a bit they fetch the stool, park it by the register and sit (and spin, once bored),
## or take a turn round the floor: a few shelves faced up, a look out the window.
## What came back unrewound goes through a rewinder before it's shelved; lunch is a sandwich.
## Your INT and WIS milestones light things up: the slot for the tape in hand, misshelved tapes, a shoplifter.

const Nav := preload("res://nav.gd")
const Traffic := preload("res://traffic.gd")
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
const JOBS := { "register": ["REGISTER", 1], "phone": ["PHONES", 2], "floor": ["FLOOR HELP", 2], "returns": ["RETURNS", 3], "restock": ["RESTOCK", 3], "cleanup": ["CLEANUP", 4] }  # [name, default priority: 1 first, 0 never]
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
var _restock = null  # filling the racks: { kind, units, got, n }
var _fetch = null  # off to a shelf for somebody: { cust | hold, copy, got }
var _lunch_day := -1
var _lunch_chair = null
var _from := Vector2.ZERO
var _bite_t := 0.0
var _bin_t := 0.0  # ($Staff's) how long the returns bin's had something in it: they wait for an armful (three), or forty seconds, before a round
var _fid_t := 0.0  # fidgeting at the counter: how much longer
var _fid_next := 5.0
var _chat_with = null  # the one they're talking to
var _chat_left := 0.0
var _chat_at := -999.0
var _mood_t := 0.0
var _opened_cooler := false
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
	sk[1] += amt * SKILLS[k][3] * (1.5 if not mine and $"../Shift".owned("dana") else 1.0)  # (staff training)
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
	if idx == 0 and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_K and not $"../POS".open:  # the character sheet
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


# ---- the week's hours and the job board, set from the register (pos.gd): by hand, or left on AUTO
# (staff.js: setSched, SCHED_MAX. AUTO isn't the web game's: there it's all by hand)

const SCHED_MAX := 25  # part time: hours a week, each
const JOB_SKILL := { "register": "dex", "phone": "cha", "floor": "int", "returns": "int", "restock": "str", "cleanup": "con" }  # what each job leans on

var auto_sched := false  # ($Staff's) the schedule's kept for you: redone when somebody's hired
var auto_jobs := false  # ...and the job board


func set_sched(i: int, d: int, n: int, on: bool) -> String:  # one hour of one day, for one of them -> what's wrong with that, or ""
	var w: Dictionary = roster[i]
	if ((int(w.sched[d]) >> n) & 1 == 1) == on:
		return ""
	if on and hours(w) >= SCHED_MAX:
		return "%s IS AT %d HOURS (PART TIME)." % [w.first.to_upper(), SCHED_MAX]
	w.sched[d] = int(w.sched[d]) ^ (1 << n)
	return ""


func slot_weight(d: int, n: int) -> float:  # how much an hour wants somebody on: the evening rush most, lunch, the weekend; before opening least
	var h := 9 + n
	var by_hour := 0.3 if h < 10 else 3.0 if h >= 17 and h < 22 else 2.0 if h >= 11 and h < 14 else 1.5 if h >= 14 and h < 17 else 1.2 if h >= 22 else 1.0
	return by_hour * (1.3 if d in [5, 6] else 1.1 if d == 0 else 1.0)


func auto_schedule() -> void:  # everyone's 25 hours, on the hours that want them most: whole shifts, nobody over eight hours a day, as much of the week covered as there are people for
	for w: Dictionary in roster:
		w.sched = [0, 0, 0, 0, 0, 0, 0]
	var slots: Array = []
	for d in 7:
		for n in 15:
			slots.append([d, n])
	slots.sort_custom(func(a: Array, b: Array) -> bool: return slot_weight(a[0], a[1]) > slot_weight(b[0], b[1]) or (slot_weight(a[0], a[1]) == slot_weight(b[0], b[1]) and a[0] * 15 + a[1] < b[0] * 15 + b[1]))
	for pass_n in 2:  # the hours nobody's on first; then, with hours to spare, a second pair of hands on the busiest
		for s: Array in slots:
			var d: int = s[0]
			var n: int = s[1]
			if pass_n == 1 and slot_weight(d, n) < 2.0:
				continue
			if pass_n == 0 and roster.any(func(w: Dictionary) -> bool: return (int(w.sched[d]) >> n) & 1 == 1):
				continue
			var best := -1
			var best_k := -1.0
			for i in roster.size():
				var w: Dictionary = roster[i]
				var day: int = w.sched[d]
				if (day >> n) & 1 == 1 or hours(w) >= SCHED_MAX or hours(w, d) >= 8:
					continue
				var beside := (n > 0 and (day >> (n - 1)) & 1 == 1) or (n < 14 and (day >> (n + 1)) & 1 == 1)
				if day != 0 and not beside:
					continue  # (one shift a day: no coming back in for an hour)
				var k := (2.0 if beside else 0.0) + float(SCHED_MAX - hours(w)) / SCHED_MAX
				if k > best_k:
					best_k = k
					best = i
			if best >= 0:
				roster[best].sched[d] = int(roster[best].sched[d]) | (1 << n)
	for w: Dictionary in roster:  # nobody comes in for an hour or two: those go, and the hours go on the ends of their real shifts (where nobody's on, first; then the busiest)
		for d in 7:
			if hours(w, d) < 3:
				w.sched[d] = 0
		while hours(w) < SCHED_MAX:
			var pick := []
			var pick_k := -1.0
			for d in 7:
				var day: int = w.sched[d]
				if day == 0 or hours(w, d) >= 8:
					continue
				for n in 15:
					if (day >> n) & 1 == 0 and ((n > 0 and (day >> (n - 1)) & 1 == 1) or (n < 14 and (day >> (n + 1)) & 1 == 1)):
						var k := slot_weight(d, n) + (10.0 if not roster.any(func(o: Dictionary) -> bool: return (int(o.sched[d]) >> n) & 1 == 1) else 0.0)
						if k > pick_k:
							pick_k = k
							pick = [d, n]
			if pick.is_empty():
				break
			w.sched[pick[0]] = int(w.sched[pick[0]]) | (1 << pick[1])


func auto_assign_jobs() -> void:  # each to what they're best at: their strongest job first, on down; whoever's quickest at the register always has it first
	var top := -1
	for i in roster.size():
		if top < 0 or roster[i].skills.dex[0] > roster[top].skills.dex[0]:
			top = i
	for i in roster.size():
		var w: Dictionary = roster[i]
		var order: Array = JOBS.keys()
		order.sort_custom(func(a: String, b: String) -> bool: return w.skills[JOB_SKILL[a]][0] > w.skills[JOB_SKILL[b]][0] or (w.skills[JOB_SKILL[a]][0] == w.skills[JOB_SKILL[b]][0] and JOBS[a][1] < JOBS[b][1]))
		for k in order.size():
			w.jobs[order[k]] = mini(4, 1 + k if k < 2 else 2 + k / 2)  # 1, 2, 3, 3, 4, 4
		if i == top or roster.size() == 1:
			w.jobs.register = 1
		elif w.jobs.register > 2:
			w.jobs.register = 2  # (and nobody's too busy to ring somebody up)


func hire(w: Dictionary) -> void:  # onto the roster: five 5-hour shifts, staggered (evenings, the rush; every other hire afternoons), the job board's usual order
	var i := roster.size()
	if not w.has("sched"):
		w.sched = [0, 0, 0, 0, 0, 0, 0]
		for k in 5:
			w.sched[(3 + i * 2 + k) % 7] |= 31 << (3 if i % 2 == 1 else 8)  # 12-5 PM / 5-10 PM
	if not w.has("jobs"):
		w.jobs = {}
	for id: String in JOBS:  # (a job that's new since they were hired: its usual place)
		if not w.jobs.has(id):
			w.jobs[id] = JOBS[id][1]
	roster.append(w)
	if auto_sched:
		auto_schedule()
	if auto_jobs:
		auto_assign_jobs()
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
	_lunch_chair = null
	_fetch_drop()
	_restock_end(true)


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
	if looks.is_empty():  # a hire: one of the crew's uniformed bodies (the people export's "Crew": his khakis and polo, or hers)
		looks = range(people._templates.size()).filter(func(i: int) -> bool: return people.cast.who[i].female == who.female and people.cast.who[i].get("staff", "") == "Crew")
	if looks.is_empty():  # (a cast from before there were any: whatever customer's clothes fit)
		looks = range(people._templates.size()).filter(func(i: int) -> bool: return people.cast.who[i].female == who.female and not people.cast.who[i].has("staff"))
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


# ---- the stool: when nothing's going on at the register for a bit, they fetch it (wherever you left it, if they can
# walk there), park it beside the register and sit; looking about, a lazy half turn now and then, and once they're
# bored stiff, a real spin. Anything to do gets them off it (staff.js: empFetchStool, empStoolSit, the stool states)

const STOOL_AT := Vector2(-4.75, 2.7)  # where it's parked: beside the register, clear of the shuffle to the pad
const STOOL_WAIT := 8.0  # seconds of nothing going on before they go for it
const BORED_AT := 25.0  # seconds up there before they're bored enough to really spin

static var sits := true  # (off for the self-check's own scenes: nobody wanders off for the stool in the middle of one)

var _idle := 0.0
var _stool_plan := ""
var _stool_home := 0.0
var _bored := 0.0
var _spins := 0
var _spin_t := 0.0
var _side := Vector2.ZERO
var _sat := 0.0


func _quiet() -> bool:  # nothing for them to do: nobody in, no sale, no alarm, nothing in the returns
	return sits and on_duty() and shoppers.custs.is_empty() and checkout.co == null and not shoppers.alarm_on and tapes.return_bin.is_empty() and not _lunch_due()


func _stool_side(toward: Vector2):  # somewhere to stand beside it, on the side nearest there, that they can walk to (or null)
	var things: Node = $"../Things"
	var at := Vector2(things._stool_at().x, things._stool_at().z)
	var a0 := atan2(toward.x - at.x, toward.y - at.y)
	for da: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8, 2.4, -2.4, PI]:
		var p := at + Vector2(sin(a0 + da), cos(a0 + da)) * 0.6
		if p.distance_to(Vector2(dana.position.x, dana.position.z)) < 0.1 or not _nav.path(dana.position.x, dana.position.z, p.x, p.y).is_empty():
			return p
	return null


func _stool_fetch() -> void:
	var things: Node = $"../Things"
	if things._stool == null or things.stool_by != null or things.on_stool or things.carrying == "stool":
		return
	var at := Vector2(things._stool_at().x, things._stool_at().z)
	var side = _stool_side(Vector2(dana.position.x, dana.position.z))
	if side == null:
		return  # can't get to it (a closed door, boxed in)
	things.stool_by = self
	_stool_plan = "sit" if at.distance_to(STOOL_AT) < 0.3 else "carry"
	dana.set_mood("happy")
	_go(side, "toStool")
	if state != "toStool":
		things.stool_by = null


func _stool_sit() -> void:  # back onto the seat from wherever they're standing
	dana.reach_to(null)
	dana.set_pose("sit", { "hipY": 0.77, "tuck": 0.5 })  # up on the seat, feet pulled back onto the footring
	state = "stoolSitDown"
	_t = 0.7
	_from = Vector2(dana.position.x, dana.position.z)


func _stool_leave() -> void:  # dropped mid-whatever: let go of it right now
	var things: Node = $"../Things"
	if things.stool_by != self:
		return
	things._solid(things._stool, true)
	if state in ["stoolSitDown", "stoolSit", "stoolStandUp"]:
		var side = _stool_side(Vector2(_post.x, _post.z))
		if side != null:
			dana.position.x = side.x
			dana.position.z = side.y
	dana.set_pose("idle")
	dana.reach_to(null)
	dana.look_at_yaw(null)
	things.stool_by = null


# ---- a turn round the floor: with nothing going on, as likely as the stool. A few shelves faced up (a hand along the
# row, a look at it), a look out the front windows, and back. (Not the web game's: there it's the stool or the counter)

var _rounds := 0  # stops left on this turn round the floor


func _spare() -> bool:  # somebody else has the register: no call to stand there with them
	return sits and on_duty() and not shoppers.alarm_on and crew.any(func(e: Node) -> bool: return e != self and e.idx < idx and e.dana != null and e.state == "post")


func _wander_start() -> bool:
	if shoppers._spots.is_empty():
		return false
	_rounds = 2 + randi() % 3
	return _wander_next()


func _wander_next() -> bool:  # -> on the way to the next stop (or home: that was the last)
	dana.reach_to(null)
	dana.look_at_yaw(null)
	dana.set_pose("idle")
	_rounds -= 1
	if _rounds < 0 or not (_quiet() or _spare()):
		_go(Vector2(_post.x, _post.z), "toPost")
		return false
	if randf() < 0.25:  # the front windows: what's it doing out there
		_target = { "x": -3.0 + randf() * 9.0, "z": 1.3, "ry": PI, "window": true }
	else:
		_target = shoppers._spots.pick_random()
	_go(Vector2(_target.x, _target.z), "toTidy")
	return state == "toTidy"


func _wander_tick() -> bool:  # -> it was one of its states
	match state:
		"toTidy":  # there: straighten the row (or just look out)
			_ry = _target.ry
			state = "tidy"
			_t = 2.5 + randf() * 2.5
			dana.set_mood("watch" if _target.has("window") else "browse")
			if not _target.has("window"):
				dana.reach_to(dana.position + Vector3(sin(_ry), 0.0, cos(_ry)) * 0.7 + Vector3(0, 1.0 + randf() * 0.5, 0))
		"tidy":
			if _t <= 0.0 or not (_quiet() or _spare()):
				dana.set_mood("neutral")
				_wander_next()
		_:
			return false
	return true


func _stool_tick(dt: float) -> bool:  # -> it was one of the stool's states
	var things: Node = $"../Things"
	var at := Vector2(things._stool_at().x, things._stool_at().z)
	match state:
		"toStool":
			if not _quiet():
				_stool_leave()
				_go(Vector2(_post.x, _post.z), "toPost")
			elif _stool_plan == "sit":
				_stool_sit()
			else:  # a hand on the seat
				dana.reach_to(Vector3(at.x, 0.72, at.y), 1, true)
				state = "stoolGrab"
				_t = 0.7
		"stoolGrab":
			if _t <= 0.0:
				things._solid(things._stool, false)
				things._vel = 0.0
				dana.reach_to(null)
				dana.set_pose("hold")
				_go(Vector2(STOOL_AT.x, STOOL_AT.y - 0.5), "stoolCarry")  # behind its spot, facing the counter
				if state != "stoolCarry":
					_stool_leave()
		"stoolCarry":  # there: down it goes, and they're straight onto it
			things._stool.global_position = Vector3(STOOL_AT.x, 0.0, STOOL_AT.y)
			things._solid(things._stool, true)
			_ry = 0.0
			_stool_sit()
		"stoolSitDown":
			var k := 1.0 - maxf(0.0, _t) / 0.7
			dana.position.x = lerpf(_from.x, at.x, k)
			dana.position.z = lerpf(_from.y, at.y, k)
			if _t <= 0.0:
				things._angle = _face - PI
				_stool_home = _face
				state = "stoolSit"
				_t = 3.0 + randf() * 5.0
				_bored = 0.0
				_spins = 0
				_sat = 0.0
				dana.set_mood("neutral")
		"stoolSit":
			_sat += dt
			if not _quiet() or things.on_stool or _sat > 75.0:  # something's up (or it's been a while: a look round for something to do): off they get
				var side = _stool_side(Vector2(_post.x, _post.z))
				_side = side if side != null else Vector2(dana.position.x, dana.position.z - 0.6)
				_from = Vector2(dana.position.x, dana.position.z)
				state = "stoolStandUp"
				_t = 0.5
				dana.set_pose("idle")
				dana.look_at_yaw(null)
				dana.set_mood("neutral")
				return true
			_bored += dt
			if _spins > 0:  # bored stiff: shove after shove, same as you tapping E
				_spin_t -= dt
				if _spin_t <= 0.0:
					_spins -= 1
					_spin_t = 0.22 + randf() * 0.12
					things._vel = minf(things.T.stool.MAX, things._vel + things.T.stool.PUSH)
					if _spins == 0:
						dana.set_mood("love")  # wheeeee
			if things._vel == 0.0:  # stopped facing who-knows-where: scoot back round to the counter
				var d := angle_difference(things._angle, _stool_home - PI)
				things._angle += signf(d) * minf(absf(d), 0.9 * dt)
			_ry = things._angle + PI
			_face = _ry
			if _t <= 0.0 and things._vel == 0.0 and _chat_with == null:  # a whim: the longer nothing happens, the more bored they get
				var r := randf()
				if _bored > BORED_AT:  # that's it: a real spin
					_bored = 0.0
					_spins = 4 + randi() % 4
					_spin_t = 0.0
					dana.look_at_yaw(null)
					dana.set_mood("happy")
				elif r < 0.2:  # a lazy half turn
					things._vel = minf(things.T.stool.MAX, 1.5 + randf() * 1.5)
					dana.set_mood("happy")
					dana.look_at_yaw(null)
				elif r < 0.5:  # what's going on over there
					dana.look_at_yaw((randf() * 2.0 - 1.0) * 1.1)
					dana.set_mood("browse")
				else:  # sigh
					dana.look_at_yaw(null)
					dana.set_mood("meh" if _bored > BORED_AT / 2.0 else "neutral")
				_t = 4.0 + randf() * 8.0
		"stoolStandUp":
			var k := 1.0 - maxf(0.0, _t) / 0.5
			dana.position.x = lerpf(_from.x, _side.x, k)
			dana.position.z = lerpf(_from.y, _side.y, k)
			if _t <= 0.0:
				things.stool_by = null
				_idle = 0.0
				_go(Vector2(_post.x, _post.z), "toPost")
		_:
			return false
	return true


# ---- the rewinders: what came back unrewound goes through one before it's shelved, both machines at once if there
# are the tapes for it (staff.js: the "rewind" state; chores.js: rewinderSpot)

var _rewinding: Array = []  # theirs, in the machines


func _rewinders() -> Array:  # the ones that are there to use
	return tapes.rewinders.slice(0, 2 if $"../Shift".owned("rewinder2") else 1)


func _rewinder_spot() -> Vector2:  # on the staff's side of the counter, at the free one nearest (or the first)
	var rws: Array = _rewinders()
	var free: Array = rws.filter(func(rw: Dictionary) -> bool: return rw.tape == null)
	var pick: Dictionary = (free if not free.is_empty() else rws)[0]
	for rw: Dictionary in (free if not free.is_empty() else rws):
		if rw.at.distance_to(dana.position) < pick.at.distance_to(dana.position):
			pick = rw
	return Vector2(clampf(pick.at.x, -5.67, -3.1), 3.2) if pick.at.z > 3.6 else Vector2(-3.05, pick.at.z)  # (the north run of the counter, or the east one)


func _rewind_tick() -> void:
	for t: Dictionary in _rewinding.duplicate():  # someone else took it out: it's theirs now
		if not tapes.rewinders.any(func(rw: Dictionary) -> bool: return is_same(rw.tape, t)):
			carry.erase(t)
			_rewinding.erase(t)
	if _t > 0.0:
		return  # one hand, one tape at a time
	var mine := func(t) -> bool: return _rewinding.any(func(x: Dictionary) -> bool: return is_same(x, t))
	for rw: Dictionary in tapes.rewinders:
		if rw.done and rw.tape != null and mine.call(rw.tape):  # out it comes, rewound
			_rewinding.erase(rw.tape)
			_ry = atan2(rw.at.x - dana.position.x, rw.at.z - dana.position.z)
			dana.reach_to(rw.at + Vector3(0, 0.08, 0))
			rw.tape = null
			_t = 0.5
			dana.set_mood("neutral")
			dana.hold_tape(mini(3, carry.size() - _rewinding.size()))
			return
	var next = null
	for t: Dictionary in carry:
		if not tapes.is_rewound(t) and not mine.call(t):
			next = t
			break
	var free: Array = _rewinders().filter(func(rw: Dictionary) -> bool: return rw.tape == null)
	if next != null and not free.is_empty():  # in it goes
		var rw: Dictionary = free[0]
		rw.tape = next
		rw.f0 = tapes.wind_frac(next)
		rw.t = 0.0
		rw.dur = maxf(1.0, rw.f0 * 10.0) * (0.5 if $"../Shift".owned("rewinders") else 1.0)
		rw.done = rw.f0 <= 0.0
		_rewinding.append(next)
		_ry = atan2(rw.at.x - dana.position.x, rw.at.z - dana.position.z)
		dana.reach_to(rw.at + Vector3(0, 0.08, 0))
		_t = 0.8
		dana.set_mood("wait")
		dana.hold_tape(mini(3, carry.size() - _rewinding.size()))
		return
	if _rewinding.is_empty():  # nothing of theirs running: done, or both machines taken by someone else
		if next != null:
			dana.set_mood("impatient")
		else:
			dana.reach_to(null)
			_next()
		return
	dana.reach_to(null)  # waiting on the machines
	dana.set_pose("hold")


func _sandwich() -> Node3D:  # in its wax paper (staff.js: sandwichMesh)
	var g := Node3D.new()
	for l: Array in [[0.11, 0.015, 0.09, "#e0b878", 0.0], [0.115, 0.008, 0.095, "#5aa83a", 0.011], [0.11, 0.008, 0.09, "#d65a4a", 0.018], [0.11, 0.015, 0.09, "#e0b878", 0.03]]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.mesh.size = Vector3(l[0], l[1], l[2])
		mi.mesh.material = StandardMaterial3D.new()
		mi.mesh.material.albedo_color = Color(l[3])
		mi.position.y = l[4]
		g.add_child(mi)
	$"../Room".light(g)
	return g


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
	dana.hold_tape(mini(3, carry.size()))
	dana.set_pose("hold")
	if carry.any(func(t: Dictionary) -> bool: return not tapes.is_rewound(t)):  # be kind: the rewinder first
		var spot := _rewinder_spot()
		if Vector2(dana.position.x, dana.position.z).distance_to(spot) < 0.1:
			state = "rewind"
			_path = []
		else:
			_go(spot, "toRewinder")
		if state != "toPost":
			return
	_target = carry[0]
	var fx := cos(_target.ry)  # (shelves face their local +x)
	var fz := -sin(_target.ry)
	_go(Vector2(_target.p[0] + fx * 0.8, _target.p[2] + fz * 0.8), "toShelf")


# ---- your own skills' milestones that show something: Shelf Sense (INT 5) lights the slot for the tape in your hand,
# Keen Eye (INT 10) the misshelved tapes, Watchful (WIS 5) a red light over anyone sneaking something out (staff.js:
# milestoneTick, beaconAt)

var _beacons: Array[MeshInstance3D] = []


func _beacon(i: int, at: Vector3, ry: float, color: Color, size: Vector3) -> void:
	while _beacons.size() <= i:
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = false
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_beacons.append(m)
	var b := _beacons[i]
	b.visible = true
	b.transform = Transform3D(Basis(Vector3.UP, ry).scaled(size), at)
	var c := color
	c.a = 0.35 + 0.25 * sin(Time.get_ticks_msec() / 180.0)  # a slow pulse
	(b.material_override as StandardMaterial3D).albedo_color = c


func _beacons_tick() -> void:
	var n := 0
	var T: Vector3 = tapes.size
	var held = tapes.held
	if held != null and held.get("off", false) and has("you", "int", 5):
		_beacon(n, Vector3(held.p[0], held.p[1], held.p[2]), held.ry, Color("#66ffcc"), Vector3(T.x * 1.4, T.y * 1.1, T.z * 1.1))
		n += 1
	if has("you", "int", 10):
		for st: Dictionary in chores.strays:
			if st.node != null and is_instance_valid(st.node):
				_beacon(n, st.node.global_position, st.node.global_rotation.y, Color("#ffcc33"), Vector3(T.x * 1.3, T.y * 1.2, T.z * 1.3))
				n += 1
	if has("you", "wis", 5):
		for k: Dictionary in shoppers.custs:
			if k.get("sneaking", false) and not k.get("alarmed", false):
				_beacon(n, k.c.position + Vector3(0, 2.05, 0), 0.0, Color("#ff3030"), Vector3.ONE * 0.18)
				n += 1
	for i in range(n, _beacons.size()):
		_beacons[i].visible = false


func _process(dt: float) -> void:
	_clock_t += dt
	if idx == 0:
		_beacons_tick()
		if not _rostered and _clock_t > 0.4:
			_rostered = true
			_muster()
		if _sheet_layer.visible:
			_sheet.text = _sheet_text()
		_bin_t = _bin_t + dt if not tapes.return_bin.is_empty() else 0.0
		_chats(dt)
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
	if _fid_t > 0.0 and (state != "post" or waiting != null):
		_fidget_stop()
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
			var vel := Traffic.walk(dana.get_instance_id(), Vector2(dana.position.x, dana.position.z), to / d, speed, "staff", dt, Callable(_nav, "open_at") if dana.position.z > 0.25 else Callable())  # (out of the customers' way: they're who it's for)
			speed = vel.length()
			if speed > 0.001:
				dana.position += Vector3(vel.x, 0.0, vel.y) / speed * minf(d, speed * dt)
			_step_d += minf(d, speed * dt)
			for door: Dictionary in interact.doors:  # they get the doors
				if not door.open and not door.locked and not door.push and Vector2((door.shut.x0 + door.shut.x1) / 2.0, (door.shut.z0 + door.shut.z1) / 2.0).distance_to(Vector2(dana.position.x, dana.position.z)) < 1.2:
					interact.toggle_door(door)
			if _step_d > 0.7:
				_step_d = 0.0
				$"../Ambience".step(dana.position)
			if speed > 0.001:
				_ry = atan2(vel.x, vel.y)
			if state == "stoolCarry":  # (the stool, out in front of them)
				$"../Things"._stool.global_position = dana.position + Vector3(sin(_ry), 0.0, cos(_ry)) * 0.45
		# called away: somebody's at the counter, nobody's at the register, and they're out on the floor. Home first
		if waiting != null and checkout.co == null and crew[0].clerk() == null and _pri("register") < 9 and state in ["toBin", "toShelf", "toMess", "toTrash", "toBag", "toStray", "stockGo", "stockTo", "toTidy"]:
			_restock_end(true)
			_trash = null
			_mess = null
			_go(Vector2(_post.x, _post.z), "toPost")
	elif _stool_tick(dt) or _wander_tick():
		_t -= dt
	else:
		_t -= dt
		match state:
			"post":
				_ry = _post.ry
				_at_post(dt, waiting)
			"toRewinder":
				state = "rewind"
			"rewind":
				if waiting != null and checkout.co == null and crew[0].clerk() == null and _pri("register") < 9:  # somebody's at the counter: back to the register (what's in the machines keeps)
					dana.reach_to(null)
					_go(Vector2(_post.x, _post.z), "toPost")
				else:
					_rewind_tick()
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
			"stockGo":  # at the cupboard: in for what the racks need
				dana.reach_to(_cupboard(_restock.kind))
				state = "stockGrab"
				_t = 1.0
			"stockGrab":
				if _t <= 0.0:
					dana.reach_to(null)
					var sn: Node = $"../Snacks"
					var free: Array = sn.empty_spots()
					for u: Dictionary in _restock.units:
						if free.has(u) and sn.backstock[u.n] > 0:
							sn.backstock[u.n] -= 1
							_restock.got.append(u)
					_restock.units = []
					_restock_next()
			"stockTo":
				var u: Dictionary = _restock.got[0]
				var things: Node = $"../Things"
				if u.k != "" and not things.cooler_open:
					things.cooler_open = true
					_opened_cooler = true
				dana.reach_to(u.at)
				state = "stockPut"
				_t = 0.8
			"stockPut":
				if _t <= 0.0:
					var u: Dictionary = _restock.got.pop_front()
					dana.reach_to(null)
					if u.out:
						$"../Snacks".set_out(u, false)
						if u.k != "":
							u.temp = $"../Snacks".ROOM_F
						checkout.score += 3
						_restock.n += 1
						crew[0].xp(self, "str", 2.0)
					else:
						$"../Snacks".backstock[u.n] += 1  # somebody beat them to it
					_restock_next()
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
						dana.hold_item(chores._bag_mesh(_bag.bin))  # (tied off, in hand)
						$"../Ambience".bag(Vector3(_trash.x, _trash.rimY, _trash.z))
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
						dana.hold_item(chores._bag_mesh(_bag.bin))
						_go(_chute_spot, "toChute")
					else:
						_go(Vector2(_post.x, _post.z), "toPost")
					_trash = null
			"toChute":
				dana.reach_to(chores._chute)
				chores.chute_use()
				state = "chuting"
				_t = 1.3
			"chuting":
				if _bag != null and _t < 0.9:  # in it goes
					_bag = null
					dana.hold_item(null)
					checkout.score += 10
					crew[0].xp(self, "str", 3.0)
					crew[0].xp(self, "con", 2.0)
					hud.toast("%s took a bag of trash down the chute (+10)" % first)
				if _t <= 0.0:
					dana.reach_to(null)
					_go(Vector2(_post.x, _post.z), "toPost")
			"fetchGo":  # at the shelf: a hand to it
				dana.reach_to(Vector3(_fetch.copy.p[0], _fetch.copy.p[1], _fetch.copy.p[2]))
				state = "fetchTake"
				_t = 0.8
			"fetchTake":
				if _t <= 0.0:
					dana.reach_to(null)
					if _fetch.copy.off or (_fetch.has("cust") and _fetch.cust.state != "asking"):  # somebody beat them to it / they've gone
						_fetch_drop()
						_go(Vector2(_post.x, _post.z), "toPost")
					else:
						tapes.set_on_shelf(_fetch.copy, false)
						_fetch.got = true
						dana.hold_tape(1)
						dana.set_pose("hold")
						var tray: Vector3 = $"../Phone"._tray
						_go(Vector2(tray.x, tray.z + 0.6) if _fetch.has("hold") else Vector2(_fetch.cust.c.position.x, _post.z), "fetchBack")  # to the holds shelf; or back behind the counter, across from them
						if state != "fetchBack":  # (no way there: it's on the tray all the same)
							state = "fetchGive"
							_path = []
							_t = 0.0
			"fetchBack":
				if _fetch == null:
					state = "post"
				elif _fetch.has("hold"):
					dana.reach_to($"../Phone"._tray + Vector3(0, 0.1, 0))
					state = "fetchGive"
					_t = 0.9
				elif _fetch.cust.state != "asking" or not shoppers.custs.has(_fetch.cust):
					_fetch_drop()
					_go(Vector2(_post.x, _post.z), "toPost")
				else:
					dana.reach_to(_fetch.cust.c.position + Vector3(0, 1.2, 0))
					state = "fetchGive"
					_t = 0.9
			"fetchGive":
				if _t <= 0.0:
					dana.reach_to(null)
					dana.hold_tape(0)
					dana.set_pose("idle")
					speaker = first
					if _fetch.has("hold"):
						_fetch.hold.copy = _fetch.copy
						_fetch.got = false
						$"../Phone"._render()
						checkout.score += 15
						crew[0].xp(self, "int", 5.0)
						crew[0].xp(self, "cha", 3.0)
						hud.toast("%s put %s on the holds shelf for %s (+15)" % [first, _fetch.copy.t, shoppers.members.name_of(_fetch.hold.member)])
					elif _fetch.cust.state == "asking" and shoppers.hand_tape(_fetch.cust, _fetch.copy, "dana"):
						_fetch.got = false  # they took it
						crew[0].xp(self, "cha", 5.0)
					_fetch_drop()
					_go(Vector2(_post.x, _post.z), "toPost")
			"toLunch":
				state = "lunchSit"
				_t = 0.7
				_from = Vector2(dana.position.x, dana.position.z)
				dana.set_pose("sit", { "hipY": 0.47 })
			"lunchSit":  # into the chair
				var k := 1.0 - maxf(0.0, _t) / 0.7
				dana.position.x = lerpf(_from.x, _lunch_chair[0], k)
				dana.position.z = lerpf(_from.y, _lunch_chair[1], k)
				_ry = _lunch_chair[2]
				if _t <= 0.0:
					state = "lunch"
					_t = Clock.HOUR * 0.5
					_bite_t = 0.0
					dana.hold_item(_sandwich())
					dana.set_mood("happy")
			"lunch":  # eating, looking about, the odd glance at the clock
				_bite_t -= dt
				if _bite_t <= 0.0:
					_bite_t = 3.0 + randf() * 5.0
					var r := randf()
					dana.set_mood("happy" if r < 0.4 else "neutral" if r < 0.7 else "love" if r < 0.85 else "sleep")
					dana.look_at_yaw((randf() * 2.0 - 1.0) * 0.8 if r > 0.6 else null)
				if _t <= 0.0 or not on_duty():
					dana.hold_item(null)
					dana.set_pose("idle")
					dana.look_at_yaw(null)
					dana.set_mood("neutral")
					state = "lunchUp"
					_t = 0.5
			"lunchUp":
				if _t <= 0.0:
					dana.position.x = _lunch_chair[0] - sin(_lunch_chair[2]) * 0.5
					dana.position.z = _lunch_chair[1] - cos(_lunch_chair[2]) * 0.5
					_lunch_chair = null
					hud.toast("%s's back from lunch" % first)
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
					tapes.set_on_shelf(_target, true)
					checkout.score += 5
					crew[0].xp(self, "int", 4.0)
					dana.reach_to(null)
					_next()
	_face += angle_difference(_face, _ry) * minf(1.0, dt * 8.0)
	dana.rotation.y = _face
	if speed == 0.0:  # (stood still: still somebody to walk round)
		Traffic.person(dana.get_instance_id(), Vector2(dana.position.x, dana.position.z), Vector2.ZERO, "staff")
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
	var easy: bool = _fid_t > 0.0 or _chat_with != null  # (fidgeting or chatting: their head and face are their own)
	if not easy:
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
	if not easy:
		dana.set_mood("neutral")
	if not carry.is_empty():  # (called away mid-round: on with it)
		_next()
		return
	if _t <= 0.0 and _lunch_due() and _lunch_start():
		return
	var jobs: Array = ["floor", "returns", "restock", "cleanup"].filter(func(j: String) -> bool: return _pri(j) < 9)  # the job board's order
	jobs.sort_custom(func(a: String, b: String) -> bool: return _pri(a) < _pri(b))
	for job: String in jobs:
		if job == "floor" and _t <= 0.0:
			var now := Time.get_ticks_msec() / 1000.0
			var asking: Array = shoppers.asks.filter(func(k: Dictionary) -> bool: return k.state == "asking" and not k.get("dana_on", false) and now - k.ask_at > 20.0)
			if not asking.is_empty() and _fetch_start(asking[0]):
				return
		if job == "returns" and (tapes.return_bin.size() >= 3 or crew[0]._bin_t > 40.0) and not crew.any(func(e: Node) -> bool: return e != self and e.state in ["toBin", "binTake"]):
			_go(_bin_spot, "toBin")
			return
		if job == "returns" and not chores.strays.is_empty():  # the bin's done: straighten up what customers shoved in anywhere
			var free: Array = chores.strays.filter(func(s: Dictionary) -> bool: return not crew.any(func(e: Node) -> bool: return e != self and e._stray == s))
			if not free.is_empty():
				_stray = free[0]
				_go(Vector2(_stray.at.x + cos(_stray.ry) * 0.8, _stray.at.z - sin(_stray.ry) * 0.8), "toStray")
				return
		if job == "restock" and _restock_start():
			return
		if job == "cleanup" and _cleanup():
			return
	_idle = _idle + dt if (_quiet() or _spare()) and _t <= 0.0 and _chat_with == null else 0.0  # nothing going on (or somebody else has the register): the stool, or a turn round the floor
	if _idle > STOOL_WAIT:
		_idle = 0.0
		var stool_free: bool = _quiet() and _pri("register") < 9 and $"../Things".stool_by == null
		if (not stool_free or randf() < 0.5) and _wander_start():
			return
		if stool_free:
			_stool_fetch()
		if state != "post":
			return
	_idle_tick(dt)


func _cupboard(kind: String) -> Vector3:  # one of that kind's cupboard doors
	var doors: Array = $"../Snacks"._doors.filter(func(d: Dictionary) -> bool: return d.kind == kind)
	return doors[doors.size() / 2].at


func _restock_start() -> bool:  # from the cupboard to the racks, an armful at a time (danaRestockStart). -> off to do it
	var sn: Node = $"../Snacks"
	if crew.any(func(e: Node) -> bool: return e != self and e._restock != null):
		return false
	var need: Array = sn.empty_spots().filter(func(u: Dictionary) -> bool: return sn.backstock[u.n] > 0)
	if need.is_empty():
		return false
	var drinks := need.filter(func(u: Dictionary) -> bool: return u.k != "")
	var food := need.filter(func(u: Dictionary) -> bool: return u.k == "")
	var kind := "drinks" if drinks.size() >= food.size() else "food"
	_restock = { "kind": kind, "units": (drinks if kind == "drinks" else food).slice(0, mini(10, 4 + lv(self, "str"))), "got": [], "n": 0 }  # (STR: a bigger armful)
	dana.set_mood("neutral")
	var door := _cupboard(kind)
	_go(Vector2(door.x - 0.6, door.z), "stockGo")
	if state == "toPost":
		_restock = null
		return false
	return true


func _restock_next() -> void:
	if _restock.got.is_empty():
		_restock_end(false)
		_go(Vector2(_post.x, _post.z), "toPost")
		return
	var u: Dictionary = _restock.got[0]
	dana.hold_item($"../Snacks".proxy(u))  # (the next one to go out, in hand)
	dana.set_pose("hold")
	_go(Vector2(u.at.x + u.f.x * 0.75, u.at.z + u.f.y * 0.75), "stockTo")
	if state == "toPost":  # (no way to that one: back in the cupboard with what's left)
		_restock_end(true)


func _restock_end(called_away: bool) -> void:  # done, or called away: what's still in their arms goes back in the cupboard
	if _restock == null:
		return
	for u: Dictionary in _restock.got:
		$"../Snacks".backstock[u.n] += 1
	if _opened_cooler:
		$"../Things".cooler_open = false
		_opened_cooler = false
	if dana != null:
		dana.hold_item(null)
		dana.set_pose("idle")
		dana.reach_to(null)
	if _restock.n > 0:
		hud.toast("%s restocked %d item%s on the racks%s (+%d)" % [first, _restock.n, "" if _restock.n == 1 else "s", " before being needed elsewhere" if called_away else "", 3 * _restock.n])
	_restock = null


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


# ---- at their post with nothing to do: the small stuff; and two of them idle and near each other, a chat
# (empIdleTick, empFidgetStop, staffChatTick, CHAT_TOPICS)

const CHAT_TOPICS := ["last night's X-Files", "a guy who returned a tape full of sand", "the new Pearl Jam album", "weekend plans", "whether Titanic's ever coming out on tape",
	"car trouble", "the Bulls game", "which of the regulars rewinds", "a weird dream", "the best pizza in town", "Friends", "the district manager's tie"]

static var _chat_tick := 0.0
static var _chat_said := -999.0


func _idle_tick(dt: float) -> void:
	if _fid_t > 0.0:
		_fid_t -= dt
		if _fid_t <= 0.0:
			_fidget_stop()
		return
	if _chat_with != null:
		return
	_fid_next -= dt
	if _fid_next > 0.0:
		return
	_fid_next = 4.0 + randf() * 7.0
	var r := randf()
	if r < 0.4:  # forearms on the counter
		_fid_t = 4.0 + randf() * 6.0
		dana.set_pose("lean")
		dana.set_mood("neutral" if randf() < 0.5 else "meh")
	elif r < 0.6:  # how long till...
		_fid_t = 1.3
		dana.set_pose("watch")
	else:  # keeping an eye on the floor
		_fid_t = 1.5 + randf() * 2.0
		dana.look_at_yaw((randf() * 2.0 - 1.0) * 1.2)
		dana.set_mood("browse")


func _fidget_stop() -> void:
	_fid_t = 0.0
	if dana != null:
		if dana.pose in ["lean", "watch"]:
			dana.set_pose("idle")
		dana.look_at_yaw(null)


func _chat_busy() -> bool:
	return dana == null or state != "post" or not _path.is_empty() or (checkout.co != null and checkout.co.get("emp") == self) or shoppers.waiting() != null


func _chats(dt: float) -> void:  # ($Staff's: the whole crew's)
	for e: Node in crew:
		if e._chat_with == null:
			continue
		var o: Node = e._chat_with
		e._chat_left -= dt
		if e._chat_left <= 0.0 or e._chat_busy() or o._chat_busy():
			e._chat_with = null
			if e.dana != null:
				e.dana.talking = false
				e.dana.look_at_yaw(null)
			continue
		e.dana.look_at_yaw(clampf(angle_difference(e._face, atan2(o.dana.position.x - e.dana.position.x, o.dana.position.z - e.dana.position.z)), -1.3, 1.3))
		e.dana.talking = true
		e._mood_t -= dt
		if e._mood_t <= 0.0:
			e._mood_t = 1.5 + randf() * 2.5
			e.dana.set_mood(["happy", "happy", "neutral", "love", "shock"].pick_random())
	_chat_tick -= dt
	if _chat_tick > 0.0:
		return
	_chat_tick = 3.0
	var idle: Array = crew.filter(func(e: Node) -> bool: return e._chat_with == null and not e._chat_busy() and e.on_duty() and _clock_t - e._chat_at > 60.0)
	if idle.size() < 2 or randf() < 0.5 or idle[0].dana.position.distance_to(idle[1].dana.position) > 4.0:
		return
	var t := 6.0 + randf() * 8.0
	for pair: Array in [[idle[0], idle[1]], [idle[1], idle[0]]]:
		pair[0]._chat_with = pair[1]
		pair[0]._chat_left = t
		pair[0]._chat_at = _clock_t
		pair[0]._fidget_stop()
	if _clock_t - _chat_said > 240.0:
		_chat_said = _clock_t
		hud.toast("%s and %s are chatting about %s" % [idle[0].first, idle[1].first, CHAT_TOPICS.pick_random()])


# ---- floor help: off to the shelves for whoever's asking at the counter (empFetch, empFetchDrop)

func _fetch_start(cust: Dictionary) -> bool:  # the title they asked for, or a pick from their kind of thing. -> dealt with, one way or another
	var w: Dictionary = cust.want
	speaker = first
	if w.kind == "hold" and w.hold.copy != null:  # right behind them on the holds shelf
		var t: Dictionary = w.hold.copy
		w.hold.pulled = t
		dana.reach_to($"../Phone"._tray + Vector3(0, 0.1, 0))
		_t = 1.2
		shoppers.hand_tape(cust, t, "dana")
		return true
	var copy = shoppers.on_shelf_copy(w.title) if w.kind != "rec" else null
	if copy == null and w.kind == "hold":
		shoppers.hold_out(cust)
		return true
	if copy == null and w.kind == "title":  # they check the screen: all out
		shoppers.all_out(cust)
		return true
	if copy == null:
		var knows := minf(0.95, 0.45 + 0.05 * lv(self, "int"))  # (INT: knows the stock)
		var pool: Array = tapes.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not t.get("lost", false) and not t.get("lib", false) and (cust.who.cats.has(t.c) or randf() >= knows))
		if pool.is_empty():
			return false
		copy = pool.pick_random()
	_go(Vector2(copy.p[0] + cos(copy.ry) * 0.8, copy.p[2] - sin(copy.ry) * 0.8), "fetchGo")
	if state != "fetchGo":
		return false  # (no way to that shelf)
	cust.dana_on = true
	_fetch = { "cust": cust, "copy": copy, "got": false }
	dana.set_mood("happy")
	hud.toast("%s went to find %s for %s" % [first, w.title if w.kind == "title" else "something", cust.name])
	return true


func _fetch_drop() -> void:  # whatever they were fetching goes back where it came from
	if _fetch == null:
		return
	if _fetch.got:
		tapes.set_on_shelf(_fetch.copy, true)
		if dana != null:
			dana.hold_tape(0)
	if _fetch.has("cust"):
		_fetch.cust.dana_on = false
	elif _fetch.hold.copy == null:
		_fetch.hold.by = "you"  # (a hold they didn't get to is yours to do)
	_fetch = null


func fetch_hold(h: Dictionary, copy: Dictionary) -> bool:  # promised on the phone: off to the shelf for it, and onto the holds shelf. -> on their way
	if dana == null or _fetch != null:
		return false
	_go(Vector2(copy.p[0] + cos(copy.ry) * 0.8, copy.p[2] - sin(copy.ry) * 0.8), "fetchGo")
	if state != "fetchGo":
		return false
	_fetch = { "hold": h, "copy": copy, "got": false }
	return true


# ---- lunch in the break room: half an hour, sometime around midday, on a long enough shift (empLunchDue, empLunchStart)

const LUNCH_CHAIRS := [[3.6, 31.05, 0.0], [4.2, 31.1, 0.15], [3.9, 32.45, PI], [4.82, 31.8, -PI / 2.0 + 0.2]]  # x, z, the way it faces


func _lunch_due() -> bool:  # (only on a 5-hour shift, when it's not busy)
	if _lunch_day == Clock.day or Clock.h < 11.5 or Clock.h > 14.5 or hours(who, Clock.date().weekday) < 5:
		return false
	if checkout.co != null or shoppers.waiting() != null or shoppers.custs.size() > 3:
		return false
	var covered: bool = crew.any(func(e: Node) -> bool: return e != self and e.dana != null and e.state == "post")  # someone else on the register, or it's quiet
	return covered or shoppers.rush_level() < 0.9 or Clock.h > 14.0


func _lunch_start() -> bool:
	var free: Array = LUNCH_CHAIRS.filter(func(c: Array) -> bool: return not crew.any(func(e: Node) -> bool: return e._lunch_chair == c))
	if free.is_empty():
		return false
	var ch: Array = free[0]
	_go(Vector2(ch[0] - sin(ch[2]) * 0.5, ch[1] - cos(ch[2]) * 0.5), "toLunch")  # the way the chair faces (to the table): come at it from behind
	if state != "toLunch":
		return false
	_lunch_day = Clock.day
	_lunch_chair = ch
	dana.talking = false
	hud.toast("%s's on lunch" % first)
	return true


# ---- for the save ($Staff's)

func snapshot() -> Dictionary:
	return { "roster": roster, "hires": hires, "you": you, "auto_sched": auto_sched, "auto_jobs": auto_jobs }


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	hires = int(d.get("hires", 0))
	auto_sched = d.get("auto_sched", false)
	auto_jobs = d.get("auto_jobs", false)
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
