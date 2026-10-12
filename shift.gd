extends Node
## The shift, start to finish. Two goals a day, something to aim at ($20 and 50 points each, at close). After close,
## with the customers gone, E on the front doors clocks you out: the closing walk-through (what's been left undone),
## the day's goals, the store's reputation moved by how it went, and the slip. Then the next morning: 9:00, the doors
## locked, you just inside them, an hour to get things ready.
## From the web game's store/shift.js (shiftStats, GOALS, dayGoals, goalState, repStars, repMult, repProgress) and
## store/title.js (clockOut, beginShift, nextShift). A better name brings more people in (shoppers.gd's rush).
## And what the store's bought with its budget, on the register (UPGRADES, upgBuy, LIBRARY): a new store carries
## only part of the library, and has no cameras, no signs, slow rewinders.
## Different here: sleeping it off on the cardboard after close ends the day the same way.
## And the two ways to run a store (title.js's modes): a sandbox, or a simulation, which starts with $300, forty
## members and nobody on staff, pays wages, grows by word of mouth (people coming in to sign up), and fires you
## after three nights in the red (and then you're a customer: customer.gd, the third way).
## And the theater's show (SHOW, showTick, showSet, ticketChance): the theater's an upgrade.
## Not over yet: what isn't here to count (snack upsells, burnt-out lights, empty rack
## spots, wages), whose points were whose.

const W := 34  # the slip's width
const GOALS := {  # two a day. n: how many, by the day (the yes/no ones have none)
	"serve": ["Ring up %d customers", 6, 2.0, 30], "rent": ["Rent out %d tapes", 8, 3.0, 40],
	"noWalk": ["Nobody walks out"], "tidy": ["A clean closing check"],
	"signup": ["Sign up %d new members", 1, 0.3334, 4], "upsell": ["Sell %d snacks at the counter", 2, 0.5, 8],  # (simulation only)
}

var stats := {}
var goals: Array = []  # today's: [{ id, n }]
var rep := 50.0  # the store's reputation, 0..100 (1-5 stars)
var budget := 10000.0  # (a sandbox store's: a fat one)
var report := false
var upg := { "library": 0 }  # what the store's bought (the register's U): id -> true; library: how many tiers of it are in

const LIBRARY := [  # the library comes in tiers, each after the one before: the sections a new store doesn't carry yet
	["Kids & Educational", "Holiday", "Reality TV", "Music", "Broadcast Blocks"], ["Classic Sitcoms", "Sketch Comedy & Late Night"], ["Anime", "Horror & Anthology", "MonsterVision"]]
const UPGRADES := [  # [id, name, cost, what it is] (the ones that do something here yet)
	["hire", "HIRE AN EMPLOYEE", 250.0, "3 APPLICANTS TO CHOOSE FROM"], ["theater", "OPEN THE THEATER", 600.0, "UNLOCK THE LOBBY AND THE AUDITORIUM"],
	["lib1", "LIBRARY UPGRADE 1", 200.0, "KIDS, HOLIDAY, REALITY TV, MUSIC"], ["lib2", "LIBRARY UPGRADE 2", 350.0, "CLASSIC SITCOMS, SKETCH & LATE NIGHT"],
	["lib3", "LIBRARY UPGRADE 3", 500.0, "ANIME, HORROR ANTHOLOGY, MONSTERVISION"], ["cameras", "SECURITY CAMERAS", 450.0, "EVERY SHOPLIFTER ON TAPE; FEWER TRY"],
	["sign", "ANTI-THEFT SIGNAGE", 60.0, "\"SHOPLIFTERS WILL BE PROSECUTED\""], ["rewinders", "HIGH-SPEED REWINDERS", 300.0, "HALF THE TIME"], ["ad", "NEWSPAPER AD", 120.0, "+REPUTATION (ONE A DAY)"]]
var _stocked := false
var mode := "sandbox"  # "sandbox": Dana on staff, $10,000, everyone a member. "simulation": a bare-bones store, $300, no staff, forty members: build it up with what it earns
var growth := { "pending": 0, "prospects": 0, "t": 30.0 }  # simulation: new members who'll come in to sign up (pending: tomorrow's)
var red_nights := 0  # simulation: closing nights in a row with the store in the red (three, and you're fired)
var _loaded := false
const Menu := preload("res://menu.gd")

# tonight's feature: pick a film on the register; customers buy tickets at checkout; ticket holders come in at 7:45
# and take their seats. It has to be playing by 8:15, or it's refunds all round
const SHOW := { "at": 20.0, "grace": 0.25, "len": 1.75, "ticket": 4.0 }
var show := { "title": "", "day": 0, "sold": 0, "status": "", "spawned": 0 }  # status: "" | arriving | late | on | failed | done
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
	return { "visitors": 0, "returns": 0, "walkouts": 0, "stolen": 0, "caught": 0, "fees_collected": 0.0, "fees_waived": 0.0, "snack_take": 0.0, "tickets": 0, "refunds": 0.0, "signups": 0, "upsells": 0 }


func sim() -> bool:
	return mode == "simulation"


func start(m: String) -> void:  # a new store, in this mode
	mode = m
	if m == "customer":  # (you don't work here: customer.gd)
		mode = "sandbox"
		main.get_node("Customer").become.call_deferred()
	if not sim():
		upg.hire = true  # (Dana's on staff)
		return
	budget = 300.0
	growth.pending = 2  # a couple of curious locals on day one
	shoppers.members.start_small(40)
	for line: String in ["Your store's bare bones for now: no staff, the theater's locked, and part of the library's still to come",
			"Everything it earns goes in the budget. Spend it on the register: U for upgrades, O to order snacks",
			"Reputation builds a night at a time: an A shift moves it most, and a new star takes a few good nights in a row"]:
		hud.toast(line)
	_morning()


func _morning() -> void:  # simulation: word got around, and yesterday's library order's in
	if upg.get("lib_due", 0) > 0:
		upg.library = upg.lib_due
		upg.lib_due = 0
		stock_library()
		hud.toast("The distributor's been: more tapes on the shelves")
	if sim() and growth.pending > 0:
		growth.prospects += growth.pending
		growth.pending = 0
		growth.t = 30.0
		hud.toast("Word's getting around: %d %s might come in to sign up today" % [growth.prospects, "people" if growth.prospects > 1 else "person"])


func owned(id: String) -> bool:
	return upg.get(id, false)


func lib_locked(cat: String) -> bool:  # a section the store doesn't carry yet
	for i in range(int(upg.library), LIBRARY.size()):
		if LIBRARY[i].has(cat):
			return true
	return false


func stock_library() -> void:  # what's carried on the shelves, what isn't in its slots (libUnlock, the other way too)
	tapes.batch = true
	for t: Dictionary in tapes.tapes:
		var lock := lib_locked(t.c)
		if lock and not t.get("lib", false) and not t.off:
			tapes.set_on_shelf(t, false)
			t.lib = true
		elif not lock and t.get("lib", false):
			t.lib = false
			tapes.set_on_shelf(t, true)
	tapes.batch = false
	tapes.commit()


func buy(id: String) -> String:  # upgBuy. -> "" if bought, else why not
	if id.begins_with("lib"):  # (a sandbox: straight onto the shelves)
		var n := int(id.right(1))
		if int(upg.library) != n - 1:
			return "ALREADY INSTALLED." if int(upg.library) >= n else "LIBRARY UPGRADE %d FIRST." % (n - 1)
		if upg.get("lib_due", 0) > 0:
			return "ALREADY ORDERED."
		upg[id] = true
		if sim():  # the distributor stocks the shelves overnight
			upg.lib_due = n
			hud.toast("Ordered library upgrade %d: the tapes arrive tomorrow morning" % n)
			return ""
		upg.library = n
		stock_library()
		hud.toast("Library upgrade %d: more tapes on the shelves" % n)
		return ""
	if id == "ad":
		if upg.get("ad_day", 0) == Clock.day:
			return "AN AD ALREADY RAN TODAY."
		upg.ad_day = Clock.day
		rep = minf(100.0, rep + (3.0 if sim() else 8.0))
		if sim():
			growth.pending += 4
		hud.toast("Ran an ad in the paper: expect some new members tomorrow" if sim() else "Ran an ad in the paper: the word's getting out")
		return ""
	if owned(id):
		return "ALREADY INSTALLED."
	upg[id] = true
	if sim() and id == "theater":
		growth.pending += 6  # a theater brings people in
	open_theater()
	hud.toast("The theater's open for business" if id == "theater" else "Installed: %s" % id)
	return ""


func open_theater() -> void:  # bought: the lobby's door comes unchained, and people can find their way in
	if not owned("theater"):
		return
	for d: Dictionary in main.get_node("Interact").doors:
		if d.push and d.locked:
			d.locked = false
			for body in d.pivot.find_children("*", "CollisionObject3D", true, false):
				body.queue_free()
			shoppers.open_way(d.shut)


func film_on() -> bool:
	return show.title != "" and tapes.playing != null and not main.get_node("Video").paused and tapes.playing.tape.t == show.title


func set_show(title: String) -> String:  # from the register: today's 8 PM if there's time to sell tickets, else tomorrow's (showSet). -> "" or why not
	if not owned("theater"):
		return "THE THEATER ISN'T OPEN YET."
	var day := Clock.day if Clock.h < 18.0 else Clock.day + 1
	if show.day == day and show.sold > 0:
		return "TICKETS ALREADY SOLD FOR %s." % show.title.to_upper()
	show = { "title": title, "day": day, "sold": 0, "status": "", "spawned": 0 }
	hud.toast("Tonight's feature%s: %s at 8 PM" % ["" if day == Clock.day else " (tomorrow)", title])
	return ""


func ticket_chance() -> float:
	return 0.12 * (0.8 + rep / 250.0) if show.title != "" and show.day == Clock.day and show.status == "" and Clock.h < SHOW.at - 0.3 else 0.0


func _show_tick() -> void:  # showTick
	if show.title == "" or show.day != Clock.day or show.status in ["failed", "done"]:
		return
	var h := Clock.h
	var goers: Array = shoppers.custs.filter(func(k: Dictionary) -> bool: return k.get("moviegoer", false))
	if show.status == "" and h >= SHOW.at - 0.25:
		show.status = "arriving"
		hud.toast("Ticket holders arriving for %s (%d)" % [show.title, show.sold] if show.sold > 0 else "No tickets sold for %s tonight" % show.title)
		if show.sold == 0:
			show.status = "done"
			return
	if show.status == "arriving" and show.spawned < show.sold and h >= SHOW.at - 0.25 + show.spawned * 0.02:  # they trickle in
		var k: Dictionary = shoppers.spawn()
		k.moviegoer = true
		k.returning = []
		k.thief = false
		k.c.hold_tape(0)
		k.c.set_pose("idle")
		show.spawned += 1
	if show.status == "arriving" and h >= SHOW.at:
		show.status = "on" if film_on() else "late"
		hud.toast("Showtime: %s is playing" % show.title if film_on() else "8:00 — %s should be starting! Put it in the VCR" % show.title)
	if show.status == "late":
		if film_on():
			show.status = "on"
			hud.toast("%s started late" % show.title)
		elif h >= SHOW.at + SHOW.grace:  # refunds, and a lot of unhappy people
			show.status = "failed"
			budget -= show.sold * SHOW.ticket
			stats.refunds += show.sold * SHOW.ticket
			checkout.score -= 20 * show.sold
			for k: Dictionary in goers:
				shoppers.members.loyal(k.member, -6)
				k.c.set_mood("angry")
				k.hi = 2.0
				if k.state == "thWatch":
					k.t = 0.0
				elif not k.state in ["thRow", "thSitDown", "thRowOut"]:
					shoppers.go(k, "leave", { "x": shoppers._door.x, "z": shoppers._door.y })
			hud.toast("%s never started: refunded %d ticket%s (-$%.2f)" % [show.title, show.sold, "" if show.sold == 1 else "s", show.sold * SHOW.ticket])
	if show.status == "on" and h >= SHOW.at + SHOW.len:
		show.status = "done"
		checkout.score += 10 * goers.size()
		for k: Dictionary in goers:
			shoppers.members.loyal(k.member, 3)
			if k.state == "thWatch":
				k.t = 0.0
		hud.toast("%s let out: %d happy moviegoer%s (+%d)" % [show.title, goers.size(), "" if goers.size() == 1 else "s", 10 * goers.size()])


# ---- the calendar: the days that matter in a video store, every year. Some busier (New Year's Eve), some dead (Super
# Bowl Sunday), and some that pull people to one section for the weeks before (horror for Halloween, the holiday shelf
# through December) (holidays, season)

func _day_at(y: int, m: int, d: int) -> int:  # days since 1970
	return int(Time.get_unix_time_from_datetime_dict({ "year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0 }) / 86400)


func _nth_dow(y: int, m: int, dow: int, n: int) -> int:  # the nth such weekday of the month
	var first: int = Time.get_datetime_dict_from_unix_time(_day_at(y, m, 1) * 86400).weekday
	return _day_at(y, m, 1) + posmod(dow - first, 7) + 7 * (n - 1)


func _holidays(y: int) -> Array:  # [day, label, rush, the sections it pulls toward, for how many days before]
	var thanks := _nth_dow(y, 11, 4, 4)
	var feb1: int = Time.get_datetime_dict_from_unix_time(_day_at(y, 2, 1) * 86400).weekday
	return [[_day_at(y, 10, 31), "HALLOWEEN", 1.25, ["Horror", "Horror & Anthology"], 14], [thanks - 1, "LONG WKND", 1.25, [], 0], [thanks, "THANKSGIV.", 0.6, [], 0],
		[_day_at(y, 12, 25), "CHRISTMAS", 0.5, ["Holiday", "Family & Kids"], 24], [_day_at(y, 12, 31), "NEW YEAR'S", 1.4, [], 0],
		[_day_at(y, 2, 1) - 1 - posmod(feb1 - 1, 7), "SUPER BOWL", 0.6, [], 0], [_day_at(y, 2, 14), "VALENTINE", 1.2, ["Drama", "Comedy"], 3]]  # (the last Sunday of January)


var _season := {}


func season() -> Dictionary:  # today: { today: [labels], rush, lean: [sections] } (worked out once a day)
	if _season.get("day", 0) == Clock.day:
		return _season
	var d := Clock.date()
	var now := _day_at(d.year, d.month, d.day)
	_season = { "day": Clock.day, "today": [], "rush": 1.0, "lean": [] }
	for h: Array in _holidays(d.year - 1) + _holidays(d.year) + _holidays(d.year + 1):
		if h[0] == now:
			_season.today.append(h)
			_season.rush *= h[2]
		if not h[3].is_empty() and now <= h[0] and h[0] - now <= h[4]:
			_season.lean.append_array(h[3])
	return _season


func rep_stars() -> int:
	return clampi(roundi(1.0 + rep / 25.0), 1, 5)


func rep_mult() -> float:
	return 0.7 + rep / 100.0 * 0.6


func _stars(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(5 - n)


func day_goals() -> Array:
	var ids: Array = GOALS.keys().filter(func(id: String) -> bool: return id != "signup" or sim())
	ids.shuffle()
	return ids.slice(0, 2).map(func(id: String) -> Dictionary: return { "id": id, "n": mini(GOALS[id][3], GOALS[id][1] + int(GOALS[id][2] * Clock.day)) if GOALS[id].size() > 1 else 0 })


func goal_state(g: Dictionary, chk = null) -> Dictionary:  # -> { text, mark: "✓" | "✗" | "☐", have }
	var counted: bool = GOALS[g.id].size() > 1
	var text: String = GOALS[g.id][0] % g.n if counted else GOALS[g.id][0]
	if counted:
		var got: int = checkout.served if g.id == "serve" else stats.signups if g.id == "signup" else stats.upsells if g.id == "upsell" else checkout.rentals
		return { "text": text, "mark": "✓" if got >= g.n else "✗" if chk != null else "☐", "have": "%d/%d" % [mini(got, g.n), g.n] }
	var holds: bool = stats.walkouts == 0 if g.id == "noWalk" else chk == null or chk.bin + chk.strays + chk.messes + chk.trash + chk.lights == 0  # (the yes/no ones only count once the day's done, but fail as soon as they fail)
	return { "text": text, "mark": "✗" if not holds else "✓" if chk != null else "☐", "have": "" }


func goal_line() -> String:  # for the HUD
	if mode == "customer":
		return main.get_node("Customer").status()
	return "   ".join(goals.map(func(g: Dictionary) -> String:
		var s := goal_state(g)
		return "%s %s%s" % [s.mark, s.text, " " + s.have if s.have != "" else ""]))


func _row(k: String, v) -> String:
	return k + " " + ".".repeat(maxi(1, W - k.length() - str(v).length() - 2)) + " " + str(v)


func clock_out() -> void:  # clockOut: the shift slip (what came in, what walked out, a grade)
	report = true
	_t = 0.0
	player.set_physics_process(false)
	if mode == "customer":  # (your own day's slip)
		_slip.text = "\n".join(main.get_node("Customer").slip())
		_layer.visible = true
		return
	var chk := { "bin": tapes.return_bin.size(), "strays": chores.strays.size(), "messes": chores.messes.size(), "lights": chores.dead.size(),
		"trash": chores.bins.filter(func(b: Dictionary) -> bool: return b.n >= b.cap * 0.75).size() + chores.bags_down.size() + chores.bag_carry.size() }  # the closing walk-through
	chk.empty = main.get_node("Snacks").empty_spots().size()
	var chk_pts: int = -10 * (chk.bin + chk.strays + chk.messes + chk.trash + chk.lights) - 2 * chk.empty
	checkout.score += chk_pts
	var gs := goals.map(func(g: Dictionary) -> Dictionary: return goal_state(g, chk))
	var met := gs.filter(func(g: Dictionary) -> bool: return g.mark == "✓").size()
	budget += 20.0 * met
	checkout.score += 50 * met
	var s := stats
	var tried: int = checkout.served + s.walkouts
	var sc: float = (100.0 * checkout.served / tried if tried > 0 else 100.0) - 15.0 * s.stolen
	var grade := "A" if sc >= 93.0 else "B" if sc >= 85.0 else "C" if sc >= 75.0 else "D" if sc >= 60.0 else "F"
	var rep_d := 0 if s.visitors == 0 else clampi({ "A": 5, "B": 3, "C": 1, "D": -2, "F": -5 }[grade] - 2 * s.stolen - (chk.messes + chk.trash) / 2 - (3 if s.refunds > 0.0 else 0) + (2 if show.status == "done" and show.sold > 0 else 0), -10, 8)
	rep = clampf(rep + rep_d, 0.0, 100.0)
	var sim_rows: Array = []
	if sim():  # the staff's pay for the day (their scheduled hours, $7 each); the red; word of mouth
		var hrs := 0
		var wages := 0.0
		var st: Node = main.get_node("Staff")
		for w: Dictionary in st.roster:  # by the hour, each at their own rate
			hrs += st.hours(w, Clock.date().weekday)
			wages += st.hours(w, Clock.date().weekday) * st.rate(w)
		budget -= wages
		red_nights = red_nights + 1 if budget < 0.0 else 0
		if red_nights > 0:
			hud.toast(["The owner called: the store's in the red. Three nights of that and you're done here", "The owner called again: one more night in the red and you're fired", "The owner came by at close. You're fired"][mini(red_nights, 3) - 1])
		var wom: int = ({ "A": 3, "B": 2, "C": 1 }.get(grade, 0) + int(rep_stars() >= 4) + int(rep_stars() >= 5)) if s.visitors > 0 else 0  # a good night gets talked about
		growth.pending += wom
		growth.prospects = growth.prospects / 2  # whoever meant to come in today and didn't: half of them lose interest
		var members: int = shoppers.members.all.filter(func(m: Dictionary) -> bool: return m.active).size()
		var next_m: Array = [50, 75, 100, 125, 150].filter(func(k: int) -> bool: return k > members)
		if wages > 0.0:
			sim_rows.append(_row("STAFF WAGES (%d HRS)" % hrs, "-$%.2f" % wages))
		sim_rows.append_array([_row("NEW MEMBERS SIGNED UP", s.signups), _row("WORD OF MOUTH: TOMORROW", "+%d" % growth.pending), _row("MEMBERS", "%d (NEXT: %d)" % [members, next_m[0]] if not next_m.is_empty() else str(members))])
		if red_nights > 0:
			sim_rows.append(_row("NIGHTS IN THE RED", "%d OF 3" % mini(red_nights, 3)))
		if red_nights >= 3:
			sim_rows.append_array(["", "YOU'RE FIRED.".lpad(23), "THE OWNER WANTS YOUR KEYS".lpad(29)])
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
		_row("TAPES RENTED", checkout.rentals), _row("RETURNS CHECKED IN", s.returns), _row("SNACK UPSELLS", s.upsells),
		_row("SHOPLIFTERS CAUGHT", s.caught), _row("TAPES STOLEN", s.stolen), line,
		_row("RENTALS", "$%.2f" % (checkout.take - s.fees_collected - s.snack_take - s.tickets * SHOW.ticket)), _row("SNACKS", "$%.2f" % s.snack_take), _row("SHOW TICKETS", "$%.2f" % (s.tickets * SHOW.ticket - s.refunds)), _row("LATE FEES", "$%.2f" % s.fees_collected),
		_row("FEES WAIVED", "$%.2f" % s.fees_waived), _row("TOTAL TAKE", "$%.2f" % checkout.take), _row("STORE BUDGET", "$%.2f" % budget), line, "CLOSING CHECK",
		_row("  LEFT IN RETURNS BIN", chk.bin), _row("  MISSHELVED TAPES", chk.strays), _row("  MESSES", chk.messes), _row("  BURNT-OUT LIGHTS", chk.lights), _row("  TRASH NOT TAKEN OUT", chk.trash), _row("  EMPTY RACK SPOTS", chk.empty), _row("  POINTS", chk_pts), line, "DAY GOALS",
	]
	for g: Dictionary in gs:
		rows.append(_row(("  %s %s" % [g.mark, g.text]).left(W - 8), "+$20" if g.mark == "✓" else "-"))
	rows.append_array([line, "", _row("REPUTATION", "%s %s" % [_stars(n), "%+d" % rep_d if rep_d != 0 else "="])])
	rows.append_array(next)
	rows.append_array(sim_rows)
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
	for e: Node in st.crew:
		e.send_home()
	for k: Dictionary in shoppers.custs.duplicate():  # anyone still in at close went home too (unpaid tapes back on the shelf)
		if not k.paid:
			for t: Dictionary in k.tapes:
				tapes.set_on_shelf(t, true)
			k.tapes = []
		k.tagged = false
		shoppers._gone(k)
	shoppers.silence_alarm()
	main.get_node("Phone").new_day()
	main.get_node("POS").deliver()  # yesterday's orders
	var sn := season()
	for h: Array in sn.today:
		hud.toast("It's circled on the calendar: %s. %s" % [h[1], "Expect a crowd" if h[2] > 1.0 else "Expect a quiet one"])
	if not sn.lean.is_empty():
		hud.toast("Seasonal: %s is renting more than usual" % ("the holiday shelf" if sn.lean.has("Holiday") else "horror" if sn.lean.has("Horror") else " and ".join(sn.lean).to_lower()))
	_morning()
	var th: Node = main.get_node("Things")
	if not th.locked:
		th.aim = "lock"
		th.on_e()
		th.aim = ""
	player.global_position = Vector3(0.0, 0.1, 1.4)
	player.rotation.y = PI
	if mode != "customer":
		hud.toast("%s · day %d. Doors open at 10 — unlock them when you're ready" % [Clock.weekday(), Clock.day])


func next_shift() -> void:
	report = false
	_layer.visible = false
	player.set_physics_process(true)
	var fired := red_nights >= 3  # tomorrow you're back, on the other side of the counter
	red_nights = 0 if fired else red_nights
	Clock.day += 1
	begin_shift()
	if fired:
		main.get_node("Customer").become("The owner let you go: three nights in the red.")
	elif mode == "customer":
		main.get_node("Customer").morning()
	var sv: Node = main.get_node("Save")
	if sv._live:
		sv.save_store()


func _process(dt: float) -> void:
	_t += dt
	if not _stocked and _t > 0.3:  # (once the save's been read, if there is one)
		_stocked = true
		if not OS.get_cmdline_user_args().is_empty():
			upg.library = LIBRARY.size()  # (the tests: a full library)
		if not _loaded:
			start(Menu.pending_mode if OS.get_cmdline_user_args().is_empty() else "sandbox")
			Menu.pending_mode = "sandbox"
		elif not sim() and not upg.has("hire"):
			upg.hire = true  # (a sandbox from before hiring was a thing: Dana's there)
		stock_library()
		open_theater()
	_show_tick()


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
	if mode == "customer":
		return ""  # (you don't clock out: your day ends when you sleep)
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
	return { "stats": stats, "goals": goals, "rep": rep, "budget": budget, "upg": upg, "show": show, "mode": mode, "growth": growth, "red": red_nights,
		"active": shoppers.members.all.filter(func(m: Dictionary) -> bool: return m.active).map(func(m: Dictionary) -> int: return m.num) if sim() else [] }


func restore(d: Dictionary) -> void:
	_loaded = true
	if d.is_empty():
		upg = { "library": LIBRARY.size(), "lib1": true, "lib2": true, "lib3": true, "cameras": true, "sign": true, "rewinders": true }  # (a store from before any of this: it has everything)
		return
	stats.merge(d.stats, true)
	goals = d.goals.filter(func(g: Dictionary) -> bool: return GOALS.has(g.id)).map(func(g: Dictionary) -> Dictionary: return { "id": g.id, "n": int(g.n) })
	rep = d.rep
	budget = d.budget
	mode = d.get("mode", "sandbox")
	growth.merge(d.get("growth", {}), true)
	for k in ["pending", "prospects"]:
		growth[k] = int(growth[k])
	red_nights = int(d.get("red", 0))
	if sim():
		var on := {}
		for num in d.get("active", []):
			on[int(num)] = true
		for m: Dictionary in shoppers.members.all:
			m.active = on.has(m.num)
	if d.has("show"):
		show = d.show
		for k in ["day", "sold", "spawned"]:
			show[k] = int(show[k])
	upg = d.get("upg", { "library": LIBRARY.size(), "lib1": true, "lib2": true, "lib3": true, "cameras": true, "sign": true, "rewinders": true })  # (a store saved back when a sandbox had everything: it keeps it)
