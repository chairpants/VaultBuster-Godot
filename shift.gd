extends Node
## The shift, start to finish. Two goals a day, something to aim at ($20 and 50 points each, at close). After close,
## with the customers gone, E on the front doors clocks you out: the closing walk-through (what's been left undone),
## the day's goals, the store's reputation moved by how it went, and the slip. Then the next morning: 9:00, the doors
## locked, you just inside them, an hour to get things ready.
## From the web game's store/shift.js (shiftStats, GOALS, dayGoals, goalState, repStars, repMult, repProgress) and
## store/title.js (clockOut, beginShift, nextShift). A better name brings more people in (shoppers.gd's rush).
## Different here: sleeping it off on the cardboard after close ends the day the same way.
## Not over yet: what isn't here to count (snack upsells, show tickets, misshelved tapes, burnt-out lights, empty rack
## spots, wages), whose points were whose.

const W := 34  # the slip's width
const GOALS := {  # two a day. n: how many, by the day (the yes/no ones have none)
	"serve": ["Ring up %d customers", 6, 2.0, 30], "rent": ["Rent out %d tapes", 8, 3.0, 40],
	"noWalk": ["Nobody walks out"], "tidy": ["A clean closing check"],
}

var stats := {}
var goals: Array = []  # today's: [{ id, n }]
var rep := 50.0  # the store's reputation, 0..100 (1-5 stars)
var budget := 300.0
var report := false
var aim := false  # the crosshair's on the way home

var _layer := CanvasLayer.new()
var _slip := Label.new()
var _t := 0.0

@onready var main: Node = get_parent()
@onready var hud: CanvasLayer = $"../HUD"
@onready var player: CharacterBody3D = $"../Player"
@onready var checkout: Node = $"../Checkout"
@onready var shoppers: Node = $"../Shoppers"
@onready var tapes: Node = $"../Tapes"
@onready var chores: Node = $"../Chores"


func _ready() -> void:
	stats = _fresh()
	goals = day_goals()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_slip.add_theme_font_override("font", font)
	_slip.add_theme_font_size_override("font_size", 15)
	_slip.set_anchors_preset(Control.PRESET_CENTER)
	_slip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_slip.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_slip)
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)


func _fresh() -> Dictionary:
	return { "visitors": 0, "returns": 0, "walkouts": 0, "stolen": 0, "caught": 0, "fees_collected": 0.0, "fees_waived": 0.0, "snack_take": 0.0 }


func rep_stars() -> int:
	return clampi(roundi(1.0 + rep / 25.0), 1, 5)


func rep_mult() -> float:
	return 0.7 + rep / 100.0 * 0.6


func _stars(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(5 - n)


func day_goals() -> Array:
	var ids: Array = GOALS.keys()
	ids.shuffle()
	return ids.slice(0, 2).map(func(id: String) -> Dictionary: return { "id": id, "n": mini(GOALS[id][3], GOALS[id][1] + int(GOALS[id][2] * Clock.day)) if GOALS[id].size() > 1 else 0 })


func goal_state(g: Dictionary, chk = null) -> Dictionary:  # -> { text, mark: "✓" | "✗" | "☐", have }
	var counted: bool = GOALS[g.id].size() > 1
	var text: String = GOALS[g.id][0] % g.n if counted else GOALS[g.id][0]
	if counted:
		var got: int = checkout.served if g.id == "serve" else checkout.rentals
		return { "text": text, "mark": "✓" if got >= g.n else "✗" if chk != null else "☐", "have": "%d/%d" % [mini(got, g.n), g.n] }
	var holds: bool = stats.walkouts == 0 if g.id == "noWalk" else chk == null or chk.bin + chk.messes + chk.trash == 0  # (the yes/no ones only count once the day's done, but fail as soon as they fail)
	return { "text": text, "mark": "✗" if not holds else "✓" if chk != null else "☐", "have": "" }


func goal_line() -> String:  # for the HUD
	return "   ".join(goals.map(func(g: Dictionary) -> String:
		var s := goal_state(g)
		return "%s %s%s" % [s.mark, s.text, " " + s.have if s.have != "" else ""]))


func _row(k: String, v) -> String:
	return k + " " + ".".repeat(maxi(1, W - k.length() - str(v).length() - 2)) + " " + str(v)


func clock_out() -> void:  # clockOut: the shift slip (what came in, what walked out, a grade)
	report = true
	_t = 0.0
	player.set_physics_process(false)
	var chk := { "bin": tapes.return_bin.size(), "messes": chores.messes.size(),
		"trash": chores.bins.filter(func(b: Dictionary) -> bool: return b.n >= b.cap * 0.75).size() + chores.bags_down.size() + chores.bag_carry.size() }  # the closing walk-through
	chk.empty = main.get_node("Snacks").empty_spots().size()
	var chk_pts: int = -10 * (chk.bin + chk.messes + chk.trash) - 2 * chk.empty
	checkout.score += chk_pts
	var gs := goals.map(func(g: Dictionary) -> Dictionary: return goal_state(g, chk))
	var met := gs.filter(func(g: Dictionary) -> bool: return g.mark == "✓").size()
	budget += 20.0 * met
	checkout.score += 50 * met
	var s := stats
	var tried: int = checkout.served + s.walkouts
	var sc: float = (100.0 * checkout.served / tried if tried > 0 else 100.0) - 15.0 * s.stolen
	var grade := "A" if sc >= 93.0 else "B" if sc >= 85.0 else "C" if sc >= 75.0 else "D" if sc >= 60.0 else "F"
	var rep_d := 0 if s.visitors == 0 else clampi({ "A": 5, "B": 3, "C": 1, "D": -2, "F": -5 }[grade] - 2 * s.stolen - (chk.messes + chk.trash) / 2, -10, 8)
	rep = clampf(rep + rep_d, 0.0, 100.0)
	var d := Clock.date()
	var line := "-".repeat(W)
	var n := rep_stars()
	var next: Array = ["  TOP RATED: KEEP IT THERE"]
	if n < 5:  # how far to the next star: a star every 25 points, and roughly how many A nights (+5 each) it'll take
		var lo := 0.0 if n <= 1 else 25.0 * (n - 1.5)
		var hi := 25.0 * (n - 0.5)
		var k := roundi(clampf((rep - lo) / (hi - lo), 0.0, 1.0) * 20.0)
		var nights := maxi(1, ceili((hi - rep) / 5.0))
		next = ["  NEXT STAR [%s%s]" % ["#".repeat(k), "-".repeat(20 - k)], "  ~%d MORE A NIGHT%s TO %s" % [nights, "S" if nights > 1 else "", _stars(n + 1)]]
	var rows: Array = [
		"VAULTBUSTER VIDEO #0417".lpad(28), "END OF SHIFT".lpad(23), "",
		_row("%s %02d/%02d/%s" % [Clock.weekday(), d.month, d.day, str(d.year).right(2)], "DAY %d" % Clock.day), _row("CLOCKED OUT", Clock.fmt_clock(Clock.h)), line,
		_row("CUSTOMERS IN", s.visitors), _row("RUNG UP", checkout.served), _row("WALKED OUT", s.walkouts),
		_row("TAPES RENTED", checkout.rentals), _row("RETURNS CHECKED IN", s.returns),
		_row("SHOPLIFTERS CAUGHT", s.caught), _row("TAPES STOLEN", s.stolen), line,
		_row("RENTALS", "$%.2f" % (checkout.take - s.fees_collected - s.snack_take)), _row("SNACKS", "$%.2f" % s.snack_take), _row("LATE FEES", "$%.2f" % s.fees_collected),
		_row("FEES WAIVED", "$%.2f" % s.fees_waived), _row("TOTAL TAKE", "$%.2f" % checkout.take), _row("STORE BUDGET", "$%.2f" % budget), line, "CLOSING CHECK",
		_row("  LEFT IN RETURNS BIN", chk.bin), _row("  MESSES", chk.messes), _row("  TRASH NOT TAKEN OUT", chk.trash), _row("  EMPTY RACK SPOTS", chk.empty), _row("  POINTS", chk_pts), line, "DAY GOALS",
	]
	for g: Dictionary in gs:
		rows.append(_row(("  %s %s" % [g.mark, g.text]).left(W - 8), "+$20" if g.mark == "✓" else "-"))
	rows.append_array([line, "", _row("REPUTATION", "%s %s" % [_stars(n), "%+d" % rep_d if rep_d != 0 else "="])])
	rows.append_array(next)
	rows.append_array([_row("STORE SCORE", checkout.score), "", ("SHIFT GRADE:  %s" % ("-" if s.visitors == 0 else grade)).lpad(22), "", "THANK YOU - BE KIND, REWIND".lpad(30), "", "E — the next morning".lpad(27)])
	_slip.text = "\n".join(rows)
	_layer.visible = true


func begin_shift() -> void:  # first thing in the morning: 9:00, doors locked, you just inside them (beginShift)
	Clock.h = Clock.START
	Clock.warp = 0.0
	stats = _fresh()
	goals = day_goals()
	checkout.co = null
	checkout.served = 0
	checkout.rentals = 0
	checkout.take = 0.0
	checkout.score = 0
	var st: Node = main.get_node("Staff")  # (they went home overnight: in when their shifts start)
	if st.dana != null:
		tapes.return_bin.append_array(st.carry)
		st.carry = []
		st.dana.queue_free()
		st.dana = null
		st.state = "post"
		st._path = []
	for k: Dictionary in shoppers.custs.duplicate():  # anyone still in at close went home too (unpaid tapes back on the shelf)
		if not k.paid:
			for t: Dictionary in k.tapes:
				tapes.set_on_shelf(t, true)
			k.tapes = []
		k.tagged = false
		shoppers._gone(k)
	shoppers.silence_alarm()
	main.get_node("Phone").new_day()
	var th: Node = main.get_node("Things")
	if not th.locked:
		th.aim = "lock"
		th.on_e()
		th.aim = ""
	player.global_position = Vector3(0.0, 0.1, 1.4)
	player.rotation.y = PI
	hud.toast("%s · day %d. Doors open at 10 — unlock them when you're ready" % [Clock.weekday(), Clock.day])


func next_shift() -> void:
	report = false
	_layer.visible = false
	player.set_physics_process(true)
	Clock.day += 1
	begin_shift()
	var sv: Node = main.get_node("Save")
	if sv._live:
		sv.save_store()


func _process(dt: float) -> void:
	_t += dt


func _unhandled_input(e: InputEvent) -> void:
	if not report:
		return
	if _t > 0.6 and ((e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_E, KEY_ENTER, KEY_SPACE]) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)):
		next_shift()
	if e is InputEventKey or e is InputEventMouseButton:
		get_viewport().set_input_as_handled()  # (nothing else happens while the slip's up)


# ---- the crosshair on the way home (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = false
	var f: Dictionary = main.get_node("Interact").front
	if not hit or hit_d > 2.4 or f.is_empty() or Clock.h < 23.0 or player.global_position.z < 0.0:  # near close: the way home
		return ""
	if Vector2(hit.position.x - f.near.x, hit.position.z - f.near.z).length() > 1.3 or hit.position.y > 2.5:
		return ""
	aim = true
	return "Open till midnight · clock out after close" if not Clock.after_close() else "Customers still inside" if not shoppers.custs.is_empty() else "E — clock out and go home"


func on_e() -> bool:
	if not aim:
		return false
	if Clock.after_close() and shoppers.custs.is_empty():
		clock_out()
	return true


# ---- for the save

func snapshot() -> Dictionary:
	return { "stats": stats, "goals": goals, "rep": rep, "budget": budget }


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	stats.merge(d.stats, true)
	goals = d.goals.filter(func(g: Dictionary) -> bool: return GOALS.has(g.id)).map(func(g: Dictionary) -> Dictionary: return { "id": g.id, "n": int(g.n) })
	rep = d.rep
	budget = d.budget
