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
## Not over yet: sign-ups, the snack offer and the snack offer, show
## tickets, the drawer opening, the receipt coming out of the printer, the terminal's own screens.
## E on the register with no sale waiting on it logs in to its terminal (pos.gd).

const STEPS := [  # [id, where it's done]
	["card", "customer"], ["tap", "register"], ["cardBack", "customer"], ["fees", "customer"], ["tapes", "customer"], ["desens", "pad"],
	["cash", "customer"], ["ring", "register"], ["tear", "printer"], ["change", "customer"], ["receipt", "customer"], ["handback", "customer"],
]

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
	_at.rate = r.rate


func price(t: Dictionary) -> float:
	return _at.rate.new if t.n else _at.rate.catalog


func _process(dt: float) -> void:
	_now += dt
	_printing = maxf(0.0, _printing - dt)
	if co == null:
		return
	if not shoppers.custs.has(co.cust):  # (they've gone)
		co = null
		return
	co.idle += dt
	if co.by == "player" and co.idle > 45.0:  # left standing there mid-sale: they give up on it
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


func step() -> Array:  # the step the sale's at: [id, where], or [] if there's no sale
	return STEPS[co.i] if co != null and co.i < STEPS.size() else []


func tip() -> String:  # what the step in hand wants doing
	if co == null:
		return ""
	var n: int = co.cust.tapes.size()
	var what: String = co.cust.tapes[0].t if n == 1 else "%d tapes" % n
	match step()[0]:
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
	while co != null and co.i < STEPS.size() and ((STEPS[co.i][0] == "change" and co.change <= 0.0) or (STEPS[co.i][0] == "fees" and co.cust.member.owed <= 0.0) or (STEPS[co.i][0] in ["card", "tap", "cardBack", "fees", "tapes", "desens"] and co.cust.tapes.is_empty())):  # (just snacks: no card, no tapes)
		co.i += 1
	if co != null:  # what they're holding out for this one
		var id: String = step()[0] if not step().is_empty() else ""
		co.cust.c.hold_prop("card" if id == "card" else "cash" if id == "cash" else null)


func act(at: String) -> bool:  # do the step in hand, if it's done here (coAct)
	if co == null:
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
		"tap":  # their account comes up
			var m: Dictionary = k.member
			var late: int = shoppers.rentals_of(m).filter(func(r: Array) -> bool: return r[2] < Clock.day).size()
			if co.by == "player":
				hud.toast("#%d %s: %s" % [m.num, k.name, ", ".join(PackedStringArray(["$%.2f in late fees due" % m.owed if m.owed > 0.0 else "", "%d tape%s out late" % [late, "" if late == 1 else "s"] if late > 0 else ""].filter(func(x: String) -> bool: return x != ""))) if m.owed > 0.0 or late > 0 else "account OK"])
		"fees":
			fees(true)
		"tapes":
			k.c.hold_tape(0)
		"desens":
			for t: Dictionary in k.tapes:
				if not t.get("desens", false):
					t.desens = true
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
			_printing = 2.2
		"handback":  # done: how'd that go (yours, or Dana's)
			var secs: float = _now - co.start
			var missed: int = k.tapes.filter(func(t: Dictionary) -> bool: return not t.get("desens", false)).size()
			var got: int = 100 + maxi(0, roundi((90.0 - secs) * 2.0)) + co.pts - 75 * missed
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
	shoppers.members.loyal(m, -3 if charge else 6)
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
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_Q and co != null and co.by == "player" and step()[0] == "fees" and shoppers.aim == co.cust:
		fees(false)
		co.i += 1
		_skip()


# ---- the crosshair on the register, the pad or the printer (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = ""
	if not hit or hit_d > 2.4:
		return ""
	var at: Vector3 = hit.position
	var mine: bool = co != null and co.by == "player"
	if at.distance_to(_at.pad) < 0.22:
		aim = "pad"
		return "E — %s" % tip() if mine and step()[1] == "pad" else "The desensitizer pad"
	if at.distance_to(_at.printer) < 0.22:
		aim = "printer"
		return ("Printing…" if _printing > 0.0 else "E — tear off the receipt") if mine and step()[0] == "tear" else "Receipt printer"
	if at.distance_to(_at.pos) < 0.42:
		aim = "register"
		return "E — %s" % tip() if mine and step()[1] == "register" else "E — log in to the register (silence the gate alarm)" if shoppers.alarm_on else "E — log in to the register"
	return ""


func on_e() -> bool:
	if aim == "":
		return false
	if co != null and co.by == "player" and step()[1] == aim:
		act(aim)
	elif aim == "register":  # nothing of yours waiting on it: the terminal
		$"../POS".log_in()
	return true
