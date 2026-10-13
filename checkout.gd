extends Node
## The checkout: the same steps whether you or Dana ring them up. Card, tap it on the register, card back, take the
## tapes, desensitize each on the pad, take the cash, ring it up, tear off the receipt, change, receipt, tapes back.
## Skip the pad and the gates will tell you about it on their way out.
## From the web game's store/checkout.js (CO_STEPS, coStart, coAct, coSkip, how a sale's scored), pos.js (what a
## tape rents for: $3.99 a new release, $1.99 the rest) and store/tv.js (E on the register, the pad, the printer).
## Where the register, the pad and the printer are: data/interact.json.
## Members' accounts are in (members.gd): what's rung up goes on theirs, late fees are charged at the counter (or
## waived, with Q), and how it went is how they feel about the place after.
## Snacks and drinks off the racks are rung up with the tapes, or by themselves (no card, then: just the cash).
## Q on the customer mid-sale offers them a snack: some go and get one, and come back to pay.
## What each step puts in your hand is held out in front of you (their card, their tapes, the cash, the change, the
## receipt), the receipt feeds out of the printer as it prints, and the drawer slides out for the change. The pad's the
## one step that can be skipped (E on the customer for the cash instead): the tapes can still go over it any time till
## they're handed back, and whatever doesn't sets the gates off on the way out (-75 a tag). Leave somebody standing
## mid-sale half a minute and whoever's free on staff takes it over; 45 seconds, and they walk out (-100).
## Not over yet: the register's beeps and the printer's buzz.
## E on the register with no sale waiting on it logs in to its terminal (pos.gd).

const STEPS := [  # [id, where it's done]
	["card", "customer"], ["tap", "register"], ["cardBack", "customer"], ["fees", "customer"], ["tapes", "customer"], ["desens", "pad"],
	["cash", "customer"], ["ring", "register"], ["tear", "printer"], ["change", "customer"], ["receipt", "customer"], ["handback", "customer"],
]

const SIGNUP := [["form", "customer"], ["enroll", "register"], ["newcard", "customer"]]  # signing somebody up: their form, into the computer, their new card

var co = null  # the sale in hand: { by: "player" | "dana", cust, i, total, bill, change, start, idle }
var served := 0
var rentals := 0
var take := 0.0  # the day's rentals, in dollars
var score := 0
var aim := ""  # "register" | "pad" | "printer" | ""

var _at := {}
var _printing := 0.0
var _now := 0.0

@onready var shoppers: Node = $"../Shoppers"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things.register
	for k in ["pos", "pad", "printer"]:
		_at[k] = Vector3(r[k][0], r[k][1], r[k][2])
	_at.printer = SLOT + Vector3(0, -0.04, 0.03)  # (the export's is the middle of the printer and a metre of paper: well above it)
	_at.rate = r.rate
	_hand.position = HAND_AT
	_hand.rotation_order = EULER_ORDER_XYZ
	_hand.rotation = Vector3(0.1, -0.35, 0.05)
	_hand.visible = false
	_strip.visible = false
	$"../Player/Camera".add_child.call_deferred(_hand)
	_printer_build.call_deferred()
	_led_find.call_deferred()


func price(t: Dictionary) -> float:
	return _at.rate.new if t.n else _at.rate.catalog


func _process(dt: float) -> void:
	_now += dt
	_printing = maxf(0.0, _printing - dt)
	_printer_tick(dt)
	_hand_show()
	if co == null:
		return
	if not shoppers.custs.has(co.cust):  # (they've gone)
		co = null
		return
	co.idle += 0.0 if co.get("away", false) else dt  # (off getting the snack you talked them into: the clock's stopped)
	if co.by == "player" and co.idle > 30.0 and not co.get("away", false) and $"../Staff".clerk() != null:  # left standing there mid-sale: whoever's free on staff takes it over
		co.by = "dana"
		co.emp = $"../Staff".clerk()
		co.idle = 0.0
		hud.toast("%s took over ringing up %s" % [co.emp.first, co.cust.name])
	if co.by == "player" and co.idle > 45.0:  # ...and with nobody to: they give up on it
		var k: Dictionary = co.cust
		co = null
		score -= 100
		hud.toast("%s gave up on the checkout and walked out" % k.name)
		$"../Shift".stats.walkouts += 1
		shoppers.members.loyal(k.member, -15)
		k.c.set_mood("angry")
		k.c.hold_prop(null)
		k.c.hold_tape(k.tapes.size())
		k.c.set_pose("hold")
		shoppers.go(k, "leave", { "x": shoppers._door.x, "z": shoppers._door.y })


# ---- what you're holding mid-checkout, held out in your hand like a carried tape: their card, the stack of tapes
# (their own covers), the cash, the change, the receipt; and your arm
# out to it (checkout.js: coHand, coHandShow; player.js: meHandFollow)

const HAND_AT := Vector3(0.26, -0.26, -0.5)

var _hand := Node3D.new()
var _hand_key := ""
var _near_k := 0.0
var _led: StandardMaterial3D  # the pad's own light: red, and green for a moment as a tape goes over it
var _led_t := 0.0


func _flat(w: float, h: float, color: Color, words := "", ink := Color.WHITE, px := 0.0006) -> MeshInstance3D:  # a card, a bill, a sheet: tipped back a little, a word or two on it
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.mesh.size = Vector3(w, h, 0.003)
	mi.mesh.material = StandardMaterial3D.new()
	mi.mesh.material.albedo_color = color
	mi.mesh.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.rotation.x = -0.25
	if words != "":
		var l := Label3D.new()
		l.text = words
		l.pixel_size = px
		l.font_size = 32
		l.outline_size = 0
		l.modulate = ink
		l.position.z = 0.002
		mi.add_child(l)
	_hand.add_child(mi)
	return mi


func _hand_show() -> void:
	var want: String = co.get("hand", "") if co != null and co.by == "player" else ""
	var key := want + ("".join(co.cust.tapes.map(func(t: Dictionary) -> String: return "1" if t.get("desens", false) else "0")) if want == "tapes" else "")
	var body = $"../Player".body
	if want != "" and body != null:  # your arm's out to it
		body.reach_to(_hand.global_transform * Vector3(0.0, -0.06, 0.04), 0, false)  # (a little under it and nearer: the thing sits up out of your fist)
	if key == _hand_key:
		return
	_hand_key = key
	for c in _hand.get_children():
		c.queue_free()
	_hand.visible = want != ""
	var tapes: Node = $"../Tapes"
	tapes._hand.visible = want == "" and tapes.held != null  # hands full with a sale: your own tape waits
	if want == "" and body != null:
		body.reach_to(null)
	match want:
		"card", "newcard":
			var card := _flat(0.086, 0.054, Color("#1b3fa0"), "VAULTBUSTER\nMEMBER", Color.WHITE, 0.00022)
			var stripe := MeshInstance3D.new()
			stripe.mesh = BoxMesh.new()
			stripe.mesh.size = Vector3(0.086, 0.0076, 0.0034)
			stripe.mesh.material = StandardMaterial3D.new()
			stripe.mesh.material.albedo_color = Color("#ffd400")
			stripe.mesh.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			stripe.position.y = -0.0102
			card.add_child(stripe)
			card.get_child(0).position.y = 0.011
		"cash", "change":
			_flat(0.156, 0.066, Color("#9cc795"), "$%.2f" % (co.bill if want == "cash" else co.change), Color("#3d6b3a"), 0.0007)
		"form":
			_flat(0.15, 0.21, Color("#fbfbf4"), "VAULTBUSTER VIDEO\nMEMBERSHIP APPLICATION\n\n%s" % co.cust.name, Color("#00349c"), 0.00028)
		"receipt":
			var slip := MeshInstance3D.new()
			slip.mesh = QuadMesh.new()
			slip.mesh.size = Vector2(0.07, 0.25)
			slip.mesh.material = _paper(1.0)
			slip.rotation = Vector3(-0.35, 0.3, 0)
			slip.position.y = 0.04
			_hand.add_child(slip)
		"tapes":
			for i in co.cust.tapes.size():  # fanned out a little, covers toward you
				var t: Dictionary = co.cust.tapes[i]
				var g := Node3D.new()
				g.position = Vector3(-0.05 + i * 0.045, i * 0.01, -0.03 - i * 0.012)
				g.rotation_order = EULER_ORDER_XYZ
				g.rotation = Vector3(-0.15, PI / 2.0 + 0.35 - i * 0.12, 0.08 * i)
				var mi := MeshInstance3D.new()
				mi.mesh = t.get("mesh")
				if mi.mesh == null:  # (never off its shelf's mesh: a plain black cassette)
					mi.mesh = BoxMesh.new()
					mi.mesh.size = tapes.size
				mi.rotation = Vector3(0, PI if t.get("flip", false) else 0.0, 0)
				mi.rotate_object_local(Vector3.BACK, t.get("lean", 0.0))
				g.add_child(mi)
				_hand.add_child(g)


# ---- the receipt: printed at "ring it up", feeding up out of the printer's slot toward you, top of the slip first,
# curling back over under its own weight the longer it gets; torn off, handed over (printReceipt, printerTick,
# receiptTear; lobby.js: the strip). And the till's drawer, which slides out for the change

const SLOT := Vector3(-4.62, 1.178, 3.93)  # the printer's paper slot (lobby.js: PRN_AT, on the worktop)
const SLIP := 0.25  # how long a receipt is

var drawer_open := 0.0
var _strip := MeshInstance3D.new()
var _slip_view := SubViewport.new()
var _slip_text := Label.new()
var _print_dur := 0.9
var _drawer: Node3D
var _drawer_z := 0.0


func printer_moved(xf: Transform3D) -> void:  # set down somewhere else on the counter (counter.gd): the slot, and the slip out of it, go with it
	_strip.position = xf * Vector3(0, 0.098, -0.028)
	var s := _strip.scale
	_strip.basis = xf.basis.orthonormalized() * Basis.from_euler(Vector3(-0.2, PI, 0), EULER_ORDER_XYZ)
	_strip.scale = s
	_at.printer = xf * Vector3(0, 0.058, 0.002)


func _paper(shown: float) -> StandardMaterial3D:  # the slip's picture; shown: how much of it, from the top, is out
	var m := StandardMaterial3D.new()
	m.albedo_texture = _slip_view.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.82, 0.82, 0.82)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3(1, shown, 1)
	return m


func _printer_build() -> void:
	_slip_view.size = Vector2i(128, 460)
	_slip_view.disable_3d = true
	_slip_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_slip_view)
	var sheet := ColorRect.new()  # thermal paper
	sheet.color = Color("#f4f1e6")
	sheet.size = Vector2(128, 460)
	_slip_view.add_child(sheet)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
	_slip_text.add_theme_font_override("font", font)
	_slip_text.add_theme_font_size_override("font_size", 10)
	_slip_text.add_theme_color_override("font_color", Color("#2a2a30"))
	_slip_text.add_theme_constant_override("line_spacing", 0)
	_slip_text.position = Vector2(6, 10)
	_slip_view.add_child(_slip_text)
	var st := SurfaceTool.new()  # the strip: a metre of it, 7 cm wide, sagging back as the square of its length (scaled to what's out)
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 17:
		var y := i / 16.0
		for x: float in [-0.035, 0.035]:
			st.set_uv(Vector2(x / 0.07 + 0.5, 1.0 - y))
			st.add_vertex(Vector3(x, y, 0.16 * y * y))
	_strip.mesh = st.commit()
	_strip.material_override = _paper(0.0)
	_strip.position = SLOT
	_strip.rotation_order = EULER_ORDER_XYZ
	_strip.rotation = Vector3(-0.2, PI, 0)
	add_child(_strip)
	for n: Node3D in $"../World".find_children("*", "Node3D", true, false):  # the till: the group that sits just under the worktop, behind the register
		if not n is MeshInstance3D and not n is CollisionObject3D and n.get_child_count() > 1 and n.global_position.distance_to(Vector3(-5.45, 0.95, 3.64)) < 0.03:
			_drawer = n
			_drawer_z = n.global_position.z
	print("checkout: the till's drawer %s" % ("found (%d parts)" % _drawer.get_child_count() if _drawer != null else "not found"))
	if _drawer == null:
		push_warning("the register's drawer isn't where the web game has it: it won't slide out")


func _print_receipt() -> void:
	var k: Dictionary = co.cust
	var w := 19  # characters across
	var mid := func(t: String) -> String: return " ".repeat(maxi(0, (w - t.length()) / 2)) + t
	var lr := func(a: String, b: String) -> String: return a.left(w - b.length() - 1).rpad(w - b.length()) + b
	var d := Clock.date()
	var out: Array = [mid.call("VAULTBUSTER"), mid.call("VIDEO #0417"), "", mid.call("%02d/%02d/%s  %s" % [d.month, d.day, str(d.year).right(2), Clock.fmt_clock(Clock.h)])]
	if not k.tapes.is_empty():
		out.append(mid.call("MEMBER #%d" % k.member.num))
	out.append_array(["", "-".repeat(w)])
	for t: Dictionary in k.tapes:
		out.append(lr.call(t.t.to_upper(), "$%.2f" % price(t)))
	for u: Dictionary in k.snacks:
		out.append(lr.call(u.n.to_upper(), "$%.2f" % $"../Snacks".price(u)))
	if co.fees > 0.0:
		out.append(lr.call("LATE FEES", "$%.2f" % co.fees))
	if k.get("tickets", 0) > 0:
		out.append(lr.call("SHOW TIX x%d" % k.tickets, "$%.2f" % (k.tickets * $"../Shift".SHOW.ticket)))
	out.append_array(["-".repeat(w), lr.call("TOTAL", "$%.2f" % co.total), lr.call("CASH", "$%.2f" % co.bill), lr.call("CHANGE", "$%.2f" % co.change)])
	if not k.tapes.is_empty():
		var due: int = Clock.day + (2 if k.tapes.any(func(t: Dictionary) -> bool: return t.n) else 5)  # (the soonest of them)
		out.append_array(["", mid.call("DUE BACK %s" % $"../POS"._date(due).left(5)), mid.call("BY MIDNIGHT")])
	out.append_array(["", mid.call("BE KIND, REWIND!"), mid.call("THANK YOU")])
	_slip_text.text = "\n".join(out)
	_slip_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var who = "you" if co.by == "player" else co.get("emp")
	_print_dur = 0.9 * maxf(0.6, 1.0 - 0.02 * (preload("res://staff.gd").lv(who, "dex") - 1)) if who != null else 0.9
	_printing = _print_dur
	_strip.visible = true
	_strip.scale = Vector3(1, 0.001, 0.001)


func pad_flash() -> void:  # a tape's gone over the pad: its light's green for a moment (core.js: desensFlash)
	_led_t = 0.6


func _led_find() -> void:  # the level's own: the little red light on the pad
	for m: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null or m.get_aabb().get_longest_axis_size() > 0.04 or m.global_position.distance_to(_at.pad) > 0.25:
			continue
		var mat := m.mesh.surface_get_material(0)
		if mat is StandardMaterial3D and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mat.albedo_color.r > 0.8 and mat.albedo_color.g < 0.4:
			_led = mat.duplicate()  # (its own: whatever else is that red stays red)
			m.material_override = _led
	if _led == null:
		push_warning("the desensitizer's light isn't where the web game has it: it won't turn green")


func _printer_tick(dt: float) -> void:
	_led_t = maxf(0.0, _led_t - dt)
	if _led != null:
		_led.albedo_color = Color("#2bff6a") if _led_t > 0.0 else Color("#ff3020")  # the slip feeds out; a sale that fell through leaves nothing hanging. The drawer eases in and out
	if co == null:
		_strip.visible = false
		drawer_open = 0.0
	elif _strip.visible:
		var f := clampf(1.0 - _printing / _print_dur, 0.001, 1.0)
		_strip.scale = Vector3(1, SLIP * f, SLIP * f)
		_strip.material_override.uv1_scale.y = f  # only the top of the slip is out so far
	if _drawer != null:
		_drawer.global_position.z += (_drawer_z - drawer_open * 0.26 - _drawer.global_position.z) * minf(1.0, dt * 12.0)


func pad_target():  # what the pad would do right now: mid-sale, from taking their tapes till you hand them back, theirs (whatever step you're on); otherwise the next live tape you're carrying, the one in hand first. -> the tape | {} (all done) | null (nothing to do it to)
	var tapes: Node = $"../Tapes"
	var mine: Array = co.cust.tapes if co != null and co.by == "player" and co.get("kind", "") != "signup" and co.i > STEPS.map(func(s: Array) -> String: return s[0]).find("tapes") and not co.cust.tapes.is_empty() else ([tapes.held] if tapes.held != null else []) + tapes.inv.filter(func(t: Dictionary) -> bool: return t != tapes.held)
	if mine.is_empty():
		return null
	var live: Array = mine.filter(func(t: Dictionary) -> bool: return not t.get("desens", false))
	return live[0] if not live.is_empty() else {}


func pad_use() -> void:  # E on the pad (padUse)
	var t = pad_target()
	if t == null or t.is_empty():
		hud.toast("Everything in hand is already desensitized" if t != null else "Nothing to desensitize")
	elif co != null and co.by == "player" and co.cust.tapes.has(t) and step()[0] == "desens":
		act("pad")  # right on cue: the checkout moves along
	else:  # out of order (skipped for the cash, back after the change), or a tape of your own
		t.desens = true
		pad_flash()
		$"../Staff".xp("you", "dex", 1.0)
		hud.toast("Desensitized: %s" % t.t)
		if co != null:
			co.idle = 0.0


func step() -> Array:  # the step the sale's at: [id, where], or [] if there's no sale
	return _steps()[co.i] if co != null and co.i < _steps().size() else []


func _steps() -> Array:
	return SIGNUP if co != null and co.get("kind", "") == "signup" else STEPS


func tip() -> String:  # what the step in hand wants doing
	if co == null:
		return ""
	if co.get("away", false):
		return "they're grabbing a snack…"
	var n: int = co.cust.tapes.size()
	var what: String = co.cust.tapes[0].t if n == 1 else "%d tapes" % n
	match step()[0]:
		"form": return "take their sign-up form"
		"enroll": return "enter them into the computer"
		"newcard": return "hand them their new member card"
		"card": return "take their member card"
		"tap": return "tap the member card on the register"
		"cardBack": return "hand their card back"
		"fees": return "charge the $%.2f in late fees (Q waives them)" % co.cust.member.owed
		"tapes": return "take %s" % what
		"desens":
			var left: Array = co.cust.tapes.filter(func(t: Dictionary) -> bool: return not t.get("desens", false))
			return "desensitize %s%s" % [left[0].t, " (%d of %d)" % [n - left.size() + 1, n] if n > 1 else ""]
		"cash": return "take the cash · $%.2f due" % co.total
		"ring": return "ring it up · $%.2f in%s" % [co.bill, ", $%.2f change" % co.change if co.change > 0.0 else ""]
		"tear": return "wait for the receipt to print" if _printing > 0.0 else "tear off the receipt"
		"change": return "give $%.2f change" % co.change
		"receipt": return "hand them the receipt"
		"handback": return "hand over %s" % (what if n > 0 else "their snacks")
	return ""


func start(by: String, cust: Dictionary) -> void:  # coStart
	if cust.get("prospect", false):  # not buying: signing up
		co = { "by": by, "cust": cust, "kind": "signup", "i": 0, "total": 0.0, "bill": 0.0, "change": 0.0, "start": _now, "idle": 0.0, "pts": 0, "fees": 0.0 }
		cust.state = "checkout"
		cust.c.set_mood("happy")
		cust.c.set_pose("wait")
		return
	var total := 0.0
	for t: Dictionary in cust.tapes:
		total += price(t)
	for u: Dictionary in cust.snacks:
		total += $"../Snacks".price(u)
	var show: Dictionary = $"../Shift".show
	if not cust.get("moviegoer", false) and not cust.has("tickets"):  # "two for tonight's show while you're at it"
		var want := (2 if randf() < 0.4 else 1) if randf() < $"../Shift".ticket_chance() else 0
		cust.tickets = clampi(want, 0, 10 - show.sold)
	total += cust.get("tickets", 0) * $"../Shift".SHOW.ticket
	var bill := 50.0
	for b in [1.0, 5.0, 10.0, 20.0, 50.0]:
		if b >= total:
			bill = b
			break
	if randf() < 0.25:
		bill = total  # exact change now and then
	co = { "by": by, "cust": cust, "i": 0, "total": total, "bill": bill, "change": snappedf(bill - total, 0.01), "start": _now, "idle": 0.0, "pts": 0, "fees": 0.0 }
	shoppers.regular_says(cust, "counter", "you" if by == "player" else "dana")
	cust.state = "checkout"
	cust.c.set_mood("happy")
	cust.c.set_pose("wait")
	_skip()


func _skip() -> void:  # past any step this sale doesn't need
	if co != null and co.get("kind", "") == "signup":
		return
	while co != null and co.i < STEPS.size() and ((STEPS[co.i][0] == "change" and co.change <= 0.0) or (STEPS[co.i][0] == "fees" and co.cust.member.owed <= 0.0) or (STEPS[co.i][0] in ["card", "tap", "cardBack", "fees", "tapes", "desens"] and co.cust.tapes.is_empty())):  # (just snacks: no card, no tapes)
		co.i += 1
	if co != null:  # what they're holding out for this one
		var id: String = step()[0] if not step().is_empty() else ""
		co.cust.c.hold_prop("card" if id == "card" else "cash" if id == "cash" else null)


func act(at: String) -> bool:  # do the step in hand, if it's done here (coAct)
	if co == null or co.get("away", false):
		return false
	var s := step()
	if s.is_empty():
		return false
	if s[1] != at:
		if at == "customer" and s[0] == "desens":  # (skipping the pad: on to the cash, and the gates will have something to say)
			co.i += 1
			s = step()
		else:
			return false
	if s[0] == "tear" and _printing > 0.0:
		return false
	co.idle = 0.0
	var k: Dictionary = co.cust
	var again := false
	match s[0]:
		"form":
			k.c.hold_prop(null)
			co.hand = "form"
		"enroll":
			k.member.active = true
			co.hand = "newcard"
		"newcard":
			var pts := 40 + maxi(0, roundi(40.0 - (_now - co.start)))
			if co.by == "player":
				$"../Staff".xp("you", "cha", 10.0)
			score += pts
			$"../Shift".stats.signups += 1
			shoppers.members.loyal(k.member, 5)
			hud.toast("%s %s (#%d): a new member (+%d)" % ["Dana signed up" if co.by == "dana" else "Signed up", k.name, k.member.num, pts])
			k.prospect = false
			k.c.hold_prop("card")
			k.c.set_mood("love")
			k.hi = 1.8
			co = null
			shoppers.leave_line(k)
			k.path = []
			k.state = "signedUp"
			k.t = 1.5
			return true
		"tap":  # their account comes up
			var m: Dictionary = k.member
			var late: int = shoppers.rentals_of(m).filter(func(r: Array) -> bool: return r[2] < Clock.day).size()
			if co.by == "player":
				hud.toast("#%d %s: %s" % [m.num, k.name, ", ".join(PackedStringArray(["$%.2f in late fees due" % m.owed if m.owed > 0.0 else "", "%d tape%s out late" % [late, "" if late == 1 else "s"] if late > 0 else ""].filter(func(x: String) -> bool: return x != ""))) if m.owed > 0.0 or late > 0 else "account OK"])
		"card":
			co.hand = "card"
		"cardBack":
			co.hand = ""
		"cash":
			co.hand = "cash"
		"tear":
			_strip.visible = false
			co.hand = "change" if co.change > 0.0 else "receipt"
		"change":
			co.hand = "receipt"
			drawer_open = 0.0
		"receipt":
			drawer_open = 0.0
			k.c.hold_prop("receipt")
			co.hand = "tapes" if not k.tapes.is_empty() else ""
		"fees":
			fees(true)
		"tapes":
			k.c.hold_tape(0)
			co.hand = "tapes"
		"desens":
			for t: Dictionary in k.tapes:
				if not t.get("desens", false):
					t.desens = true
					pad_flash()
					break
			again = k.tapes.any(func(t: Dictionary) -> bool: return not t.get("desens", false))
		"ring":
			served += 1
			rentals += k.tapes.size()
			take += co.total
			if k.get("tickets", 0) > 0:  # (sold)
				$"../Shift".show.sold += k.tickets
				$"../Shift".stats.tickets += k.tickets
			for u: Dictionary in k.snacks:
				$"../Shift".stats.snack_take += $"../Snacks".price(u)
			$"../Shift".budget += co.total
			for t: Dictionary in k.tapes:  # on their account: a new release is out two nights, the rest five
				shoppers.rented.append([t, Clock.day, Clock.day + (2 if t.n else 5), k.member.num])
			co.hand = ""
			drawer_open = 1.0
			_print_receipt()
		"handback":  # done: how'd that go (yours, or Dana's)
			var secs: float = _now - co.start
			var missed: int = k.tapes.filter(func(t: Dictionary) -> bool: return not t.get("desens", false)).size()
			var got: int = 100 + maxi(0, roundi((90.0 - secs) * 2.0)) + co.pts - 75 * missed
			if co.by == "player":
				$"../Staff".xp("you", "dex", 10.0)
			shoppers.members.loyal(k.member, 7 if secs < 40.0 else 4)
			score += got
			k.c.hold_tape(k.tapes.size())
			k.tagged = missed > 0  # anything still tagged sets the gates off
			k.paid = true
			hud.toast("%s %s: %s, $%.2f%s (+%d)" % ["Dana rang up" if co.by == "dana" else "Rang up", k.name, _bought(k), co.total, ", %d tag%s missed" % [missed, "" if missed == 1 else "s"] if missed else "", got])
			k.snacks = []
			k.c.hold_prop("receipt")
			k.c.set_mood("thanks")
			k.c.set_pose("hold")
			k.state = "paid"
			k.t = 1.8
			co = null
			return true
	if not again:
		co.i += 1
		_skip()
	return true


func _bought(k: Dictionary) -> String:
	var parts := PackedStringArray()
	if not k.tapes.is_empty():
		parts.append("1 tape" if k.tapes.size() == 1 else "%d tapes" % k.tapes.size())
	if not k.snacks.is_empty():
		parts.append("1 snack" if k.snacks.size() == 1 else "%d snacks" % k.snacks.size())
	if k.get("tickets", 0) > 0:
		parts.append("1 show ticket" if k.tickets == 1 else "%d show tickets" % k.tickets)
	return ", ".join(parts)


func fees(charge: bool) -> void:  # late fees on their account: charge them (money, a grumpier customer) or waive them (goodwill) (coFees)
	var m: Dictionary = co.cust.member
	var amt: float = m.owed
	m.owed = 0.0
	co.cust.hi = 1.6
	shoppers.members.loyal(m, (-2 if co.by == "player" and preload("res://staff.gd").has("you", "cha", 5) else -3) if charge else 6)  # (Smooth Talker: half the sting)
	if charge:
		co.fees += amt
		$"../Shift".stats.fees_collected += amt
		co.pts += 20
		co.total = snappedf(co.total + amt, 0.01)  # a new total, what they hand over, the change (coRebill)
		var bills: Array = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0].filter(func(b: float) -> bool: return b >= co.total)
		co.bill = co.total if randf() < 0.25 else bills[0] if not bills.is_empty() else ceilf(co.total / 20.0) * 20.0
		co.change = snappedf(co.bill - co.total, 0.01)
		co.cust.c.set_mood("meh")
		hud.toast("%s %s their late fees ($%.2f)" % ["Dana charged" if co.by == "dana" else "Charged", co.cust.name, amt])
	else:
		$"../Shift".stats.fees_waived += amt
		co.cust.c.set_mood("love")
		hud.toast("Waived %s's $%.2f in late fees" % [co.cust.name, amt])


func _unhandled_input(e: InputEvent) -> void:  # Q at the counter: waive their late fees (coQ)
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_Q and co != null and co.by == "player" and shoppers.aim == co.cust and not co.get("away", false):
		if step()[0] == "fees":
			fees(false)
			co.i += 1
			_skip()
		else:
			offer()


func rebill() -> void:  # the total changed (a snack added): new total, what they hand over, the change (coRebill)
	var k: Dictionary = co.cust
	var total: float = co.fees + k.get("tickets", 0) * $"../Shift".SHOW.ticket
	for t: Dictionary in k.tapes:
		total += price(t)
	for u: Dictionary in k.snacks:
		total += $"../Snacks".price(u)
	co.total = snappedf(total, 0.01)
	var bills: Array = [1.0, 5.0, 10.0, 20.0, 50.0, 100.0].filter(func(b: float) -> bool: return b >= co.total)
	co.bill = co.total if randf() < 0.25 else bills[0] if not bills.is_empty() else ceilf(co.total / 20.0) * 20.0
	co.change = snappedf(co.bill - co.total, 0.01)


func offer() -> void:  # "grab a snack for the movie?": they'll go get it and come back to pay (coOffer)
	var cash_at := STEPS.map(func(s: Array) -> String: return s[0]).find("cash")
	var racks: Array = $"../Snacks".spots.filter(func(s: Dictionary) -> bool: return s.units.any(func(u: Dictionary) -> bool: return not u.out))
	if co.get("kind", "") == "signup" or co.get("offered", false) or co.i > cash_at or racks.is_empty():
		return
	var k: Dictionary = co.cust
	var Staff := preload("res://staff.gd")
	co.offered = true
	k.hi = 1.6
	var sweet := fposmod(k.who.seed * 0.6180339887, 1.0)  # (a sweet tooth: how easily a snack's talked up)
	var yes := randf() < 0.12 + 0.6 * sweet + 0.025 * (Staff.lv("you", "cha") - 1) - (0.3 if not k.snacks.is_empty() else 0.0) - (0.2 if k.c.mood in ["impatient", "angry"] else 0.0)
	$"../Staff".xp("you", "cha", 6.0 if yes else 1.0)
	if not yes:
		k.c.set_mood("meh")
		hud.toast("Offered %s a snack: “No thanks, I'm good”" % k.name)
		return
	$"../Shift".stats.upsells += 1
	hud.toast("Offered %s a snack: “Ooh, yeah. Hang on a sec”" % k.name)
	co.away = true
	k.upsell = true
	k.snacks_before = k.snacks.size()
	k.hi = 0.0
	k.c.hold_prop(null)
	k.c.set_mood("happy")
	k.c.set_pose("hold" if k.holding > 0 else "idle")
	racks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a.x - shoppers._counter.x, a.z - shoppers._counter.z).length() < Vector2(b.x - shoppers._counter.x, b.z - shoppers._counter.z).length())
	shoppers.go(k, "snack", racks[0])  # the nearest rack with anything left


# ---- the crosshair on the register, the pad or the printer (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = ""
	if $"../Shift".mode == "customer":
		return ""  # (not yours to work)
	if not hit or hit_d > 2.4:
		return ""
	var at: Vector3 = hit.position
	var mine: bool = co != null and co.by == "player"
	var near := ""  # the register, the pad or the printer: whichever the crosshair's landed nearest, within its reach
	for z: Array in [["pad", _at.pad, 0.3], ["printer", _at.printer, 0.34], ["printer", _strip.global_transform * Vector3(0, 0.6, 0.06), 0.2 if _strip.visible else 0.0], ["register", _at.pos, 0.55]]:
		if at.distance_to(z[1]) < z[2] and (near == "" or at.distance_to(z[1]) / z[2] < _near_k):
			near = z[0]
			_near_k = at.distance_to(z[1]) / z[2]
	if near == "pad":
		aim = "pad"
		var t = pad_target()
		return "E — %s" % tip() if mine and step()[1] == "pad" else "E — desensitize %s" % t.t if t != null and not t.is_empty() else "The desensitizer pad%s" % ("\neverything in hand's been over it" if t != null else "")
	if near == "printer":
		aim = "printer"
		return ("Printing…" if _printing > 0.0 else "E — tear off the receipt") if mine and step()[0] == "tear" else "Receipt printer"
	if near == "register":
		aim = "register"
		return "E — %s" % tip() if mine and step()[1] == "register" else "E — log in to the register (silence the gate alarm)" if shoppers.alarm_on else "E — log in to the register"
	return ""


func on_e() -> bool:
	if aim == "":
		return false
	if aim == "pad":
		pad_use()
	elif co != null and co.by == "player" and step()[1] == aim:
		act(aim)
	elif aim == "register":  # nothing of yours waiting on it: the terminal
		$"../POS".log_in()
	return true
