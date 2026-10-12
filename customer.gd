extends Node
## Customer mode: the store from the other side of the counter. You don't work here. The store runs itself (Dana's
## on all day), and you come in off the lot with your own wallet. What you take off the shelves is the store's till
## you pay for it at the counter (E on whoever's on the register): walk out with it and the gates go off, or
## somebody sees you go, or (nobody looking) you get away with it. Behind the counter, the break room and the
## janitor's closet are staff only: anyone on staff who sees you back there wants you out (once, a warning back to
## the floor; then you're walked out and not let back in today). Being a good customer counts: the staff get to
## know a regular (slower to call you on things, and ten percent off), and lose it when you're caught.
## What you rent is yours for three nights: back through the Returns slot, a dollar a day late, a dollar if it's
## not rewound (the rewinders are on the counter). The store opens at ten; at midnight they want you out. The day
## ends when you sleep, on the cardboard bed round the back: then it's your day's slip, and the morning.
## From the web game's store/customer-mode.js (cm, cmStaffOnly, cmSees, cmPay, cmCaught, cmGotAway, cmRentReturn,
## cmMorning, cmOpenUp, cmSlip, cmTick, becomeCustomer). A simulation's store that fires you turns into this.
## The trail (keys, padlocks, notes, Ray's badge, money lying about) is trail.gd. Not over yet: the crew
## as people (three of them, favors, gossip, their picks, getting hired), the day's list, run-ins with other
## customers, a ticket for the show, the night drop, a drink spilled on purpose, what you eat before you've paid,
## the roof as somewhere to get to. The crew's three (staff.gd), without the rest of what makes them people.

const ALLOWANCE := 15.0  # $ found in your jacket each morning (after the first)
const FLOOR := Vector3(-4.2, 0.1, 6.6)  # where you're walked back to
const LOT := Vector3(2.6, 0.3, -3.4)  # ...and out to

var wallet := 40.0
var owed := 0.0
var trust := 0.0
var strikes := 0
var today := 0  # times caught today
var banned := 0  # the day you were thrown out
var heat := 0.0
var card := false
var rented := {}  # tape key -> the day it's due (0: one you walked out with)
var day := {}  # the day's record
var aim := false  # the crosshair's on the clerk

var _inside := false
var _alarm_was := false
var _check_t := 0.0
var _close_t := 0.0
var _door_hint := 0.0
var _night_hint := false
var _nagged := 0
var _opened := 0

@onready var main: Node = get_parent()
@onready var shift: Node = $"../Shift"
@onready var hud: CanvasLayer = $"../HUD"
@onready var player: CharacterBody3D = $"../Player"
@onready var tapes: Node = $"../Tapes"
@onready var staff: Node = $"../Staff"
@onready var shoppers: Node = $"../Shoppers"
@onready var checkout: Node = $"../Checkout"
@onready var things: Node = $"../Things"
@onready var lights: Node = $"../Lights"


func _ready() -> void:
	day = _fresh()


func _who() -> Node3D:  # whoever on staff's dealing with you: the one at the register, else anyone in
	var e = staff.anyone()
	if e == null:
		return null
	preload("res://staff.gd").speaker = e.first
	return e.dana


func seen() -> bool:  # by anyone on staff
	for e: Node in staff.crew:
		if sees(e.dana):
			preload("res://staff.gd").speaker = e.first
			return true
	return false


func on() -> bool:
	return shift.mode == "customer"


func _fresh() -> Dictionary:
	return { "spent": 0.0, "fees": 0.0, "rented": 0, "returned": 0, "caught": 0, "stolen": 0 }


func regular() -> bool:  # they know your name, and knock 10% off
	return trust >= 60.0


func status() -> String:  # for the HUD
	return "$%.2f on you · %s%s" % [wallet, "a regular" if regular() else "friendly" if trust >= 25.0 else "a new face", " · $%.2f owed" % owed if owed > 0.0 else ""] + $"../Trail".status()


func become(why := "") -> void:  # the store flips to this (a new customer-mode file; or fired from a simulation)
	shift.mode = "customer"
	shift.upg.merge({ "library": shift.LIBRARY.size(), "lib1": true, "lib2": true, "lib3": true, "cameras": true, "sign": true, "rewinders": true, "hire": true, "theater": true }, true)  # a store that's been going a while
	shift.stock_library()
	shift.open_theater()
	staff.customer_crew()
	for t: Dictionary in tapes.inv.duplicate():  # (what was in your arms is the store's)
		tapes.set_on_shelf(t, true)
	tapes.inv.clear()
	tapes.inv_stash()
	if why != "":
		hud.toast(why)
	morning()


func morning() -> void:  # in off the lot just before ten (cmMorning)
	Clock.h = Clock.OPEN - 0.25
	if Clock.day > 1:
		wallet += ALLOWANCE
		hud.toast("Found $%.2f in your jacket" % ALLOWANCE)
	var watched := PackedStringArray()  # what you took home got watched: two a night, each wound on to its end
	for t: Dictionary in tapes.inv:
		if rented.has(t.k) and watched.size() < 2 and tapes.is_rewound(t):
			tapes.set_wind_frac(t, 0.99)
			watched.append(t.t)
	if not watched.is_empty():
		hud.toast("Last night you watched %s. Rewind before you bring %s back" % [" and ".join(watched), "it" if watched.size() == 1 else "them"])
	today = 0
	heat = 0.0
	_close_t = 0.0
	_night_hint = false
	day = _fresh()
	if not things.locked:
		things.aim = "lock"
		things.on_e()
		things.aim = ""
	player.global_position = LOT
	player.rotation.y = PI
	_inside = false
	$"../Trail".morning()
	hud.toast("%s · day %d. The store opens at 10. You've got $%.2f on you" % [Clock.weekday(), Clock.day, wallet])


func _unpaid() -> Array:
	return tapes.inv.filter(func(t: Dictionary) -> bool: return not rented.has(t.k))


func _price(t: Dictionary) -> float:
	return checkout.price(t) * (0.9 if regular() else 1.0)


func total() -> float:
	return snappedf(_unpaid().reduce(func(a: float, t: Dictionary) -> float: return a + _price(t), 0.0) + owed, 0.01)


func sees(e: Node3D) -> bool:  # can they see you? Looking your way (or right next to you), close enough, the light on where you are, and nothing in between. Running, they hear you instead
	if e == null:
		return false
	var to := player.global_position - e.position
	to.y = 0.0
	var d := to.length()
	var crouch: bool = player.crouched
	var heard := not crouch and Input.is_physical_key_pressed(KEY_SHIFT) and player.velocity.length() > 1.0 and d < 5.0
	if d > (7.0 if crouch else 12.0):
		return false
	if not heard and not lights.zone_on.get(lights.zone_at(player.global_position), true) and d > 2.5:
		return false  # in the dark
	if not heard and d > 1.4 and (sin(e.rotation.y) * to.x + cos(e.rotation.y) * to.z) / d < 0.35:
		return false  # not looking your way
	var q := PhysicsRayQueryParameters3D.create(e.position + Vector3(0, 1.6, 0), player.global_position + Vector3(0, 1.0 if crouch and not heard else 1.6, 0))
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func staff_only() -> String:  # where a customer has no business being ("" if you're fine)
	var p := player.global_position
	if p.y > 3.3:
		return ""  # (nobody's up there to see)
	if p.x < -2.6 and p.z > 0.0 and p.z < 3.65:
		return "behind the counter"
	var z: String = lights.zone_at(p)
	return "in the %s" % lights.names.get(z, z) if z in ["breakroom", "closet"] else ""


func pay() -> void:  # E on whoever's on the register, across the counter from them (cmPay)
	var due := _unpaid()
	var sum := total()
	if sum <= 0.0:
		hud.toast("Dana: “%sLet me know if you need anything!”" % ("Hey, you! " if regular() else ""))
		return
	if checkout.co != null:
		hud.toast("Dana: “Be right with you, one sec.”")
		return
	if sum > wallet + 0.001:
		hud.toast("That comes to $%.2f. You've only got $%.2f on you" % [sum, wallet])
		return
	if not due.is_empty() and not card:  # first rental: they sign you up
		card = true
		hud.toast("Dana signs you up: “Here's your card. Don't lose it!”")
	for t: Dictionary in due:
		rented[t.k] = Clock.day + 3
		t.desens = true
	var was := regular()
	wallet -= sum
	shift.budget += sum
	checkout.served += 1
	checkout.rentals += due.size()
	checkout.take += sum
	shift.stats.fees_collected += owed
	day.spent += sum
	day.rented += due.size()
	day.fees += owed
	owed = 0.0
	trust = minf(100.0, trust + 4.0 + due.size())
	_who().set_mood("happy")
	hud.toast("Dana rings you up: $%.2f%s. “Thanks! Be kind, rewind.”%s" % [sum, " (regular's discount)" if was else "", " %d tape%s, due back day %d" % [due.size(), "" if due.size() == 1 else "s", Clock.day + 3] if not due.is_empty() else ""])
	if not was and regular():
		hud.toast("Dana: “You're in here all the time! I'll knock ten percent off from now on.”")


func caught(why: String) -> void:  # why: "staff" (somewhere you shouldn't be) | "theft" (cmCaught)
	var taken := _unpaid()
	for t: Dictionary in taken:  # the store's things go back to the store
		tapes.inv.erase(t)
		tapes.return_bin.append(t)
	if tapes.held != null and taken.has(tapes.held):
		tapes.release()
	tapes.inv_stash()
	heat = 0.0
	strikes += 1
	today += 1
	day.caught += 1
	trust = maxf(0.0, trust - (40.0 if why == "theft" else 15.0))
	if _who() != null:
		_who().set_mood("angry")
	shoppers.silence_alarm()
	if why == "staff" and today == 1:
		hud.toast("Dana: “Whoa, you can't be back here. Employees only.” They walk you back out to the floor")
		player.global_position = FLOOR
		player.rotation.y = -PI / 2.0
	else:
		banned = Clock.day
		hud.toast("Dana: “Hey! You didn't pay for that.” They take it back and walk you out. Don't come back today" if why == "theft" else "Dana: “Okay, that's it. Out.” You're walked out, and not welcome back today")
		player.global_position = LOT
		player.rotation.y = PI
		_inside = false


func _rent_return(t: Dictionary) -> void:  # a rental back (the returns slot, its shelf): late fees, and was it rewound (cmRentReturn)
	var due: int = rented[t.k]
	rented.erase(t.k)
	day.returned += 1
	var late := maxi(0, Clock.day - due) if due > 0 else 0
	owed += late * 1.0
	hud.toast("Returned %s%s" % [t.t, " · %d day%s late ($%.2f owed)" % [late, "" if late == 1 else "s", late * 1.0] if late > 0 else ""])
	if due > 0 and not tapes.is_rewound(t):
		owed += 1.0
		hud.toast("Dana: “Aw, %s's not rewound. That's $1.00, sorry. The rewinders are right there on the counter!”" % t.t)


func _process(dt: float) -> void:  # cmTick
	if not on() or shift.report:
		return
	var p := player.global_position
	var dana: Node3D = _who()
	if things.locked and Clock.h >= Clock.OPEN and Clock.h < Clock.CLOSE and _opened != Clock.day:  # whoever opened unlocks at ten (cmOpenUp)
		_opened = Clock.day
		things.aim = "lock"
		things.on_e()
		things.aim = ""
		hud.toast("10:00 AM — %s flips the sign: they're open" % (preload("res://staff.gd").speaker if _who() != null else "somebody"))
	var inside := p.y > 3.3 or (p.z > 0.05 and p.z < 46.0 and absf(p.x) < 12.7)
	if _inside and not inside and not _unpaid().is_empty():  # out through the doors with something you haven't paid for
		if seen():
			caught("theft")
		else:  # nobody saw: it's yours now (cmGotAway)
			for t: Dictionary in _unpaid():
				rented[t.k] = 0
				t.desens = true
				shift.stats.stolen += 1
				day.stolen += 1
			hud.toast("Nobody saw a thing. It's yours now")
	if not _inside and inside and _nagged != Clock.day and banned != Clock.day:  # in the door with something overdue: they mention it
		var late := rented.values().filter(func(due: int) -> bool: return due > 0 and Clock.day > due).size()
		if late > 0:
			_nagged = Clock.day
			hud.toast("Dana: “Hey, just so you know, %s overdue!”" % ("one of your tapes is" if late == 1 else "%d of your tapes are" % late))
	_inside = inside
	var alarm: bool = shoppers.alarm_on and absf(p.z - shoppers.GATE_Z) < 1.5 and not _unpaid().is_empty()  # the gates going off as you walk through them: everyone's eyes on you
	if alarm and not _alarm_was and dana != null:
		caught("theft")
	_alarm_was = alarm
	var where := staff_only()  # staff only: seen back there, the meter fills (slower for someone they know); out of sight it drains. Full: caught
	var seen_now := where != "" and seen()
	if seen_now:
		if heat == 0.0:
			_who().set_mood("shock")
			hud.toast("Dana: “%sCan I help you?”" % ("Uh, hey... " if regular() else "Hey! "))
		heat = minf(1.0, heat + dt / (1.1 * (1.0 + trust / 100.0)))
		if heat >= 1.0:
			caught("staff")
	else:
		heat = maxf(0.0, heat - dt * 0.35)
	hud.call_box(("SEEN · " + preload("res://staff.gd").speaker.to_upper() + "  %s" if seen_now else "STAFF ONLY · " + where.to_upper() + "  %s") % ("█".repeat(roundi(heat * 10.0)) + "░".repeat(10 - roundi(heat * 10.0))) if where != "" or heat > 0.0 else "")
	var shut: bool = banned == Clock.day or things.locked  # locked out: the doors don't open for you, and say so
	things._block.get_child(0).disabled = not (things.locked or (banned == Clock.day and not inside))
	_door_hint -= dt
	if not inside and shut and Vector2(p.x - 0.9, p.z).length() < 1.3 and _door_hint <= 0.0:
		_door_hint = 4.0
		hud.toast("You've been thrown out for today" if banned == Clock.day else "CLOSED · open 10 AM to midnight" if Clock.after_close() else "CLOSED · opens at 10 AM")
	_check_t -= dt
	if _check_t <= 0.0:  # every half second: a rental back in the returns slot (or on its shelf) is returned, late fees and all
		_check_t = 0.5
		for t: Dictionary in tapes.tapes:
			if rented.has(t.k) and (tapes.return_bin.has(t) or not t.off):
				_rent_return(t)
	if Clock.after_close():  # the end of the night: they want you out of the store, and walk you out if you hang about
		if not inside:
			_close_t = 0.0
			if not _night_hint:
				_night_hint = true
				hud.toast("Closed for the night. The day's over when you sleep: there's a cardboard bed round the back")
		elif p.y < 3.3:
			if _close_t == 0.0:
				hud.toast("Dana: “We're closed! Time to head out.”")
			_close_t += dt
			if _close_t > 25.0:
				hud.toast("They walk you to the door. Good night!")
				player.global_position = LOT
				player.rotation.y = PI
				_close_t = 0.0


func slip() -> Array:  # the end of your day, on the same slip the staff get (cmSlip)
	var W: int = shift.W
	var row := func(k: String, v) -> String: return k + " " + ".".repeat(maxi(1, W - k.length() - str(v).length() - 2)) + " " + str(v)
	var line := "-".repeat(W)
	var late := rented.values().filter(func(due: int) -> bool: return due > 0 and Clock.day >= due).size()
	var rows: Array = ["YOUR DAY".lpad(21), ("%s · DAY %d" % [Clock.weekday(), Clock.day]).lpad(22), "",
		row.call("SPENT AT THE STORE", "$%.2f" % day.spent), row.call("  INCL. LATE FEES", "$%.2f" % day.fees), row.call("IN YOUR WALLET", "$%.2f" % wallet), line,
		row.call("TAPES RENTED", day.rented), row.call("TAPES RETURNED", day.returned), row.call("TAPES OUT", rented.size())]
	if late > 0:
		rows.append(row.call("  DUE BACK BY TOMORROW", late))
	if owed > 0.0:
		rows.append(row.call("LATE FEES OWED", "$%.2f" % owed))
	rows.append_array([line, row.call("WALKED OUT WITH", "%d THING%s" % [day.stolen, "" if day.stolen == 1 else "S"] if day.stolen > 0 else "NOTHING"),
		row.call("CAUGHT", "%d TIME%s" % [day.caught, "" if day.caught == 1 else "S"] if day.caught > 0 else "NEVER"),
		row.call("THE STAFF THINK YOU'RE", "A REGULAR" if regular() else "FRIENDLY" if trust >= 25.0 else "A NEW FACE"), line])
	var home: Array = tapes.inv.filter(func(t: Dictionary) -> bool: return rented.has(t.k))
	if not home.is_empty():
		rows.append("TAKING HOME TONIGHT")
		for t: Dictionary in home:
			rows.append("  " + t.t.to_upper().left(W - 2))
	rows.append_array(["", "SEE YOU TOMORROW".lpad(25), "", "E — the next day".lpad(25)])
	return rows


# ---- the crosshair on the clerk (called from interact.gd)

func take_aim(from: Vector3, dir: Vector3, hit_d: float) -> String:
	aim = false
	var body := _who() if on() else null
	if body == null:
		return ""
	var name: String = preload("res://staff.gd").speaker
	var to: Vector3 = body.position + Vector3(0, 1.1, 0) - from
	var t := to.dot(dir)
	if t < 0.2 or t > 3.2 or t > hit_d + 0.6 or (to - dir * t).length() > 0.45:
		return ""
	aim = true
	if staff.clerk() == null:
		return name
	return name + "\nE — pay $%.2f%s" % [total(), " (%s late fees)" % ("$%.2f in" % owed) if owed > 0.0 else ""] if total() > 0.0 else name + "\nE — say hi"


func on_e() -> bool:
	if not aim:
		return false
	if staff.clerk() != null:
		_who()
		pay()
	return true


# ---- for the save

func snapshot() -> Dictionary:
	return { "wallet": wallet, "owed": owed, "trust": trust, "strikes": strikes, "today": today, "banned": banned, "card": card, "rented": rented, "day": day, "opened": _opened }


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	wallet = d.wallet
	owed = d.owed
	trust = d.trust
	strikes = int(d.strikes)
	today = int(d.today)
	banned = int(d.banned)
	card = d.card
	_opened = int(d.get("opened", 0))
	day.merge(d.day, true)
	for k: String in d.rented:
		rented[k] = int(d.rented[k])
