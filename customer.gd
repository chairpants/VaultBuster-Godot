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
## the roof as somewhere to get to. The crew's three (staff.gd), and each gets to know you on their own.

const ALLOWANCE := 15.0  # $ found in your jacket each morning (after the first)
const FLOOR := Vector3(-4.2, 0.1, 6.6)  # where you're walked back to
const LOT := Vector3(2.6, 0.3, -3.4)  # ...and out to

var wallet := 40.0
var owed := 0.0
var tab := 0.0  # what you've eaten and not paid for
var trust := 0.0
var strikes := 0
var today := 0  # times caught today
var banned := 0  # the day you were thrown out
var heat := 0.0
var card := false
var rented := {}  # tape key -> the day it's due (0: one you walked out with)
var day := {}  # the day's record
var aim := false  # the crosshair's on somebody on staff
var aim_emp = null
var aim_drop := false
var rec := {}  # the staff's pick for you today: { title, cat, by, day, done }
var ask := {}  # a shopper waiting on you: { k, cat, name, tries }
var thief = null  # the one you saw slide a tape under their jacket
var record := { "days": 0, "rented": 0, "caught": 0, "perfect": 0, "told": 0, "last": 0 }
var _ask_t := 45.0
var crew := {}  # how well each of them knows you: their name -> { k, day, n, named }
var fav := {}  # a favor somebody's asked: { kind: "msg" | "shelf", by, to, msg, reply, title, day, done, paid }
var app := {}  # your job application: { day, strikes, ans: "" | "yes" | "no", told, again }
var wary := {}  # who caught you today
var _fav_day := 0
var _hi_day := 0
var _hi_t := 0.0
var _drop: StaticBody3D
var _was_in := false

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
	return { "spent": 0.0, "fees": 0.0, "rented": 0, "returned": 0, "caught": 0, "stolen": 0, "found": 0.0, "helped": 0, "shelved": 0, "told": 0, "asked": 0, "cats": [], "in": false, "goals": [] }


func regular() -> bool:  # they know your name, and knock 10% off
	return trust >= 60.0


func status() -> String:  # for the HUD
	return "$%.2f on you · %s%s" % [wallet, "a regular" if regular() else "friendly" if trust >= 25.0 else "a new face", " · $%.2f owed" % owed if owed > 0.0 else ""] + $"../Trail".status() + ("\n" + list_line() if not day.goals.is_empty() else "")


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
	wary.clear()
	if not fav.is_empty() and not fav.done:
		fav = {}  # yesterday's favor's gone stale
	if not app.is_empty() and app.ans == "" and Clock.day > app.day:  # an application's been read
		app.ans = "yes" if trust >= 60.0 and strikes == app.strikes else "no"
		app.told = false
		hud.toast("The store called about your application: ask anyone on staff")
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
	return snappedf(_unpaid().reduce(func(a: float, t: Dictionary) -> float: return a + _price(t), 0.0) + owed + tab + (_snack().price(_snack().held.u) if _snack_due() else 0.0), 0.01)


func _snack() -> Node:
	return $"../Snacks"


func _snack_due() -> bool:  # one in your hand you haven't paid for (or started on)
	return _snack().held != null and not _snack().held.paid


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
		day.cats.append(t.c)
		if rec.get("day", 0) == Clock.day and not rec.done and rec.title == t.t:  # took them up on it
			rec.done = true
			trust = minf(100.0, trust + 3.0)
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
	tab = 0.0
	if _snack_due():
		_snack().held.paid = true
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
	if _snack_due():  # (back on the rack)
		_snack().set_out(_snack().held.u, false)
		_snack().held = null
	tab = 0.0
	heat = 0.0
	strikes += 1
	today += 1
	day.caught += 1
	trust = maxf(0.0, trust - (40.0 if why == "theft" else 15.0))
	wary[preload("res://staff.gd").speaker] = true  # (whoever caught you keeps an eye on you today)
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
	if _inside and not inside and (not _unpaid().is_empty() or _snack_due() or tab > 0.0):  # out through the doors with something you haven't paid for
		if seen():
			caught("theft")
		else:  # nobody saw: it's yours now (cmGotAway)
			for t: Dictionary in _unpaid():
				rented[t.k] = 0
				t.desens = true
				shift.stats.stolen += 1
				day.stolen += 1
			if _snack_due():
				_snack().held.paid = true
				day.stolen += 1
			tab = 0.0
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
		if _drop == null:
			_build_drop()
		if inside and p.y < 3.3:
			day["in"] = true
		_day_check()
		_ask_tick(0.5)
		_thief_tick()
		for t: Dictionary in tapes.tapes:
			if rented.has(t.k) and (tapes.return_bin.has(t) or not t.off):
				_rent_return(t)
	if inside and not _was_in:  # a hello by name as you come in
		_hi_t = 20.0
	_was_in = inside
	_hi_t -= dt
	if _hi_t > 0.0 and _hi_day != Clock.day and not Clock.after_close():
		for e: Node in staff.crew:
			if e.dana != null and _knows(e).k >= 2 and not wary.has(e.first) and e.dana.position.distance_to(p) < 7.0 and sees(e.dana):
				_hi_day = Clock.day
				e.dana.set_mood("happy")
				hud.toast("%s: “Hey, %s!”" % [e.first, you()])
				break
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
	rows.append(line)
	rows.append_array(_day_end())
	rows.append_array([row.call("WALKED OUT WITH", "%d THING%s" % [day.stolen, "" if day.stolen == 1 else "S"] if day.stolen > 0 else "NOTHING"),
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

func take_aim(from: Vector3, dir: Vector3, hit_d: float) -> String:  # anyone on staff
	aim = false
	aim_emp = null
	if not on():
		return ""
	var best := 3.2
	for e: Node in staff.crew:
		if e.dana == null:
			continue
		var to: Vector3 = e.dana.position + Vector3(0, 1.1, 0) - from
		var t := to.dot(dir)
		if t > 0.2 and t < best and t < hit_d + 0.6 and (to - dir * t).length() < 0.45:
			best = t
			aim_emp = e
	if aim_emp == null:
		return ""
	aim = true
	var name: String = aim_emp.first
	if thief != null and thief.sneaking:
		return "%s\nE — point out %s, the tape under the jacket" % [name, thief.name.get_slice(" ", 0)]
	if _pending(aim_emp) and total() <= 0.0:
		return name + "\n" + staff_tip(aim_emp)
	if _at_register(aim_emp) and total() > 0.0:
		return name + "\nE — pay $%.2f%s" % [total(), " ($%.2f in late fees)" % owed if owed > 0.0 else ""]
	return name + "\n" + staff_tip(aim_emp)


func _at_register(e: Node) -> bool:
	return e.state == "post" and e._path.is_empty()


func on_e() -> bool:
	if not aim:
		return false
	var e: Node = aim_emp
	preload("res://staff.gd").speaker = e.first
	if thief != null and thief.sneaking:
		tell(e)
	elif _pending(e) and total() <= 0.0:  # (something between you: even across the counter)
		talk(e)
	elif _at_register(e) and total() > 0.0:
		pay()
		_met(e)
	elif total() > 0.0 or Clock.after_close():
		hud.toast("Dana: “%s”" % ("We're closed, sorry!" if Clock.after_close() else "I can ring you up at the register!"))
	else:
		talk(e)
	return true


# ---- ask them what's good: whoever you talk to has a pick for you, once a day. Rent it and they'll remember (cmRecommend)

func recommend(e: Node) -> void:
	if rec.get("day", 0) == Clock.day:
		hud.toast("Dana: “%s”" % ("Did you like %s?" % rec.title if rec.done else "Seriously, %s. %s. You won't regret it." % [rec.title, rec.cat]))
		return
	var films: Array = tapes.tapes.filter(func(t: Dictionary) -> bool: return t.e.size() == 1 and not t.off and not t.get("lib", false))
	if films.is_empty():
		hud.toast("Dana: “Finding everything okay?”")
		return
	var t: Dictionary = films[(31 * Clock.day + e.first.unicode_at(0) * 7 + 3) * 16807 % films.size()]
	rec = { "title": t.t, "cat": t.c, "by": e.first, "day": Clock.day, "done": false }
	hud.toast("Dana: “Have you seen %s? It's over in %s. Trust me.”" % [t.t, t.c])


func helped(t: Dictionary) -> void:  # a good customer: a misshelved tape put back where it goes is noticed, more if someone sees you do it (cmHelped)
	if not on():
		return
	var by := seen()
	trust = minf(100.0, trust + (4.0 if by else 2.0))
	day.shelved += 1
	if fav.get("kind", "") == "shelf" and not fav.done:  # (any misshelved tape you put back will do)
		fav.done = true
		hud.toast("That's the favor for %s. Go tell them" % fav.by)
	hud.toast("Dana: “Oh, thanks! People just stick them anywhere.”" if by else "Put %s back where it goes" % t.t)


# ---- the day's list: three little things to do on your day off, and your record (CM_DAY_GOALS, cmDayGoals, cmDayCheck, cmDayEnd)

func _goal_text(g: Dictionary) -> String:
	return { "cat": "Rent a tape from %s" % g.get("cat", ""), "pick": "Ask the staff what's good, and rent it", "money": "Find some money lying around",
		"help": "Help another customer find a movie", "shelve": "Put a misshelved tape back", "clean": "Don't get caught anywhere today" }[g.id]


func _goal_got(g: Dictionary) -> bool:
	match g.id:
		"cat": return day.cats.has(g.cat)
		"pick": return rec.get("day", 0) == Clock.day and rec.done
		"money": return day.found > 0.0
		"help": return day.helped > 0
		"shelve": return day.shelved > 0
	return day["in"] and day.caught == 0  # "clean": counted at the end of the day


func _day_goals() -> void:  # the morning's list: three, different every day
	var ids := ["cat", "pick", "money", "help", "shelve", "clean"]
	ids.shuffle()
	day.goals = []
	for id: String in ids.slice(0, 3):
		var g := { "id": id, "done": false, "miss": false }
		if id == "cat":
			var cats := {}
			for t: Dictionary in tapes.tapes:
				if not t.off and not t.get("lib", false):
					cats[t.c] = true
			g.cat = cats.keys().pick_random() if not cats.is_empty() else "Comedy"
		day.goals.append(g)


func _day_check(at_close := false) -> void:  # anything on the list just done, or blown?
	if day.goals.is_empty():
		_day_goals()
	for g: Dictionary in day.goals:
		if g.done or g.miss:
			continue
		if g.id == "clean":
			g.miss = day.caught > 0
			if at_close and not g.miss and _goal_got(g):
				g.done = true
		elif _goal_got(g):
			g.done = true
		if g.done:  # one off the list: the staff notice the good customer
			trust = minf(100.0, trust + 3.0)
			hud.toast("✓ %s%s" % [_goal_text(g), ". That's today's whole list!" if day.goals.all(func(q: Dictionary) -> bool: return q.done) else ""])
		elif at_close:
			g.miss = true


func list_line() -> String:
	return "   ".join(day.goals.map(func(g: Dictionary) -> String: return "%s %s" % ["✓" if g.done else "✗" if g.miss else "☐", _goal_text(g)]))


func _day_end() -> Array:  # the slip's lines: today's list, and your record
	_day_check(true)
	var r := record
	if r.last != Clock.day:
		r.last = Clock.day
		var n: int = day.goals.filter(func(g: Dictionary) -> bool: return g.done).size()
		if day["in"]:
			r.days += 1
			if n == day.goals.size():
				r.perfect += 1
		r.rented += day.rented
		r.caught += day.caught
		r.told += day.told
	var W: int = shift.W
	var row := func(k: String, v) -> String: return k + " " + ".".repeat(maxi(1, W - k.length() - str(v).length() - 2)) + " " + str(v)
	var rows: Array = ["TODAY'S LIST"]
	for g: Dictionary in day.goals:
		rows.append(("  %s %s" % ["✓" if g.done else "✗", _goal_text(g).to_upper()]).left(W))
	rows.append_array(["-".repeat(W), "YOUR RECORD", row.call("  DAYS IN THE STORE", r.days), row.call("  TAPES RENTED", r.rented), row.call("  TIMES CAUGHT", r.caught if r.caught > 0 else "NEVER")])
	if r.told > 0:
		rows.append(row.call("  SHOPLIFTERS POINTED OUT", r.told))
	rows.append_array([row.call("  WHOLE LISTS DONE", r.perfect), "-".repeat(W)])
	return rows


# ---- run-ins: a shopper who wants to know what's good, and one with a tape up their jacket (cmCustAskTick ... cmCustTell)

func _ask_tick(dt: float) -> void:
	var p := player.global_position
	if not ask.is_empty():  # waiting on you
		var k: Dictionary = ask.k
		if not shoppers.custs.has(k) or k.state != "cmAsk":
			ask = {}
			return
		k.ry = atan2(p.x - k.c.position.x, p.z - k.c.position.z)
		if k.hi <= 0.0:
			k.c.set_mood("ask")
		if k.t <= 0.0 or k.c.position.distance_to(p) > 9.0 or not _inside:
			_ask_end(k, "%s: “Never mind, I'll keep looking.”" % ask.name)
		return
	_ask_t -= dt
	if not _inside or p.y > 3.3 or staff_only() != "" or banned == Clock.day or Clock.h >= Clock.LAST_IN or day.asked >= 3 or _ask_t > 0.0:
		return
	for k: Dictionary in shoppers.custs:
		var d: float = k.c.position.distance_to(p)
		if not k.kid and not k.thief and not k.get("cm_asked", false) and k.state == "browse" and not k.who.cats.is_empty() and k.holding < k.who.max_tapes and d > 0.8 and d < 5.0:
			k.cm_asked = true  # a shopper turns to you: what's good?
			k.state = "cmAsk"
			k.path = []
			k.t = 45.0
			k.c.set_pose("hold" if k.holding > 0 else "idle")
			k.c.set_mood("ask")
			ask = { "k": k, "cat": k.who.cats.pick_random(), "name": k.name.get_slice(" ", 0), "tries": 0 }
			day.asked += 1
			_ask_t = (90.0 + randf() * 120.0) * (0.5 if day.goals.any(func(g: Dictionary) -> bool: return g.id == "help" and not g.done) else 1.0)
			hud.toast("%s: “Hey, you look like you know movies. Anything good in %s?” (find one, and E on them with it in hand)" % [ask.name, ask.cat])
			return
	_ask_t = 3.0  # (nobody near: in a bit)


func _ask_end(k: Dictionary, say := "") -> void:  # back to their browsing
	ask = {}
	if say != "":
		hud.toast(say)
	if shoppers.custs.has(k) and k.state == "cmAsk":
		k.c.set_mood("browse")
		k.state = "browse"
		k.t = 0.0


func cust_tip(k: Dictionary) -> String:  # the hover tip on another customer, if it's one of these
	if ask.get("k") == k:
		return "%s\nwants something in %s · E with a tape in hand" % [k.name, ask.cat]
	if thief == k and k.sneaking:
		return "%s\na tape under the jacket · E — give them a look" % k.name
	return ""


func cust_e(k: Dictionary) -> bool:  # E on another customer -> true if it was one of these
	var name: String = k.name.get_slice(" ", 0)
	if thief == k and k.sneaking:  # you look at them, then at the jacket
		var what := _bust(k)
		if seen():
			trust = minf(100.0, trust + 2.0)
		hud.toast("You catch %s's eye and look at the jacket. %s comes out onto the returns cart, and they're gone" % [name, what])
		return true
	if ask.get("k") != k:
		return false
	var t = tapes.held
	if t == null:
		hud.toast("%s: “Something in %s, maybe?” (bring them a tape, and E with it in hand)" % [name, ask.cat])
		return true
	if rented.has(t.k):
		hud.toast("%s: “Oh, that one's yours. Is there another copy on the shelf?”" % name)
		return true
	if randf() >= (0.85 if t.c == ask.cat else 0.6 if k.who.cats.has(t.c) else 0.15):
		k.c.set_mood("meh")
		k.hi = 1.6
		ask.tries += 1
		if ask.tries >= 2:
			_ask_end(k, "%s: “Nah... thanks anyway. I'll keep looking.”" % name)
		else:
			hud.toast("%s: “%s? Hmm, not really my thing.”" % [name, t.t])
		return true
	tapes.release()
	k.tapes.append(t)
	k.holding = k.tapes.size()
	k.c.hold_tape(mini(3, k.holding))
	k.c.set_pose("hold")
	k.c.set_mood("love")
	k.hi = 2.0
	ask = {}
	k.state = "browse"
	k.stops_left = 0
	shoppers._done(k)  # ...and off to pay for it
	day.helped += 1
	shoppers.members.loyal(k.member, 2)
	var by := seen()
	trust = minf(100.0, trust + (3.0 if by else 1.0))
	hud.toast("%s: “%s? Ooh, okay. I'll give it a try, thanks!”%s" % [name, t.t, " (%s saw that)" % preload("res://staff.gd").speaker if by else ""])
	return true


func _thief_tick() -> void:
	if thief != null:  # the one you saw: still going, or out the door with it
		if not shoppers.custs.has(thief) or not thief.sneaking or thief.c.position.z < 0.0:
			thief = null
		return
	if not _inside or player.global_position.y > 3.3:
		return
	for k: Dictionary in shoppers.custs:  # one in view, close enough to see what they're doing
		if not k.sneaking or k.get("cm_spotted", false) or k.tapes.is_empty() or k.c.position.z < 0.5 or k.c.position.distance_to(player.global_position) > 9.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.5, 0), k.c.position + Vector3(0, 1.5, 0))
		q.exclude = [player.get_rid()]
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		k.cm_spotted = true
		thief = k
		hud.toast("%s just slid a tape under their jacket and is making for the door. Tell somebody on staff? (E on them)" % k.name.get_slice(" ", 0))
		return


func _bust(k: Dictionary) -> String:  # the tapes come back out of the jacket, and they're on their way
	var what: String = k.tapes[0].t if k.tapes.size() == 1 else "%d tapes" % k.tapes.size()
	tapes.return_bin.append_array(k.tapes)
	k.tapes = []
	k.holding = 0
	k.tagged = false
	k.sneaking = false
	k.thief = false
	k.c.hold_tape(0)
	k.c.set_mood("shock")
	k.hi = 2.0
	if thief == k:
		thief = null
	shoppers.go(k, "leave", { "x": shoppers._door.x, "z": shoppers._door.y })
	return what


func tell(e: Node) -> void:  # E on someone on staff with a shoplifter in sight: you point them out
	var k: Dictionary = thief
	var what := _bust(k)
	e.dana.set_mood("angry")
	trust = minf(100.0, trust + 8.0)
	day.told += 1
	hud.toast("You point %s out to %s, who heads them off at the door: “The jacket. Come on.” Out comes %s. “Thanks. Seriously.”" % [k.name.get_slice(" ", 0), e.first, what])


# ---- the night drop: a steel box on the walk left of the doors, for when they're shut or you'd rather not go in (cmRentBuild, cmRentDrop)

const DROP := Vector3(-2.75, 0.0, -0.4)


func _build_drop() -> void:
	_drop = StaticBody3D.new()
	_drop.position = DROP
	for part: Array in [[Vector3(0.56, 0.84, 0.42), Vector3(0, 0.48, 0), 0x1b3fa0ff], [Vector3(0.56, 0.2, 0.42), Vector3(0, 0.98, 0), 0x1b3fa0ff], [Vector3(0.4, 0.13, 0.02), Vector3(0, 0.8, -0.215), 0x15171aff], [Vector3(0.48, 0.12, 0.012), Vector3(0, 0.6, -0.215), 0xffd400ff]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.hex(part[2])
		box.material = m
		mi.mesh = box
		mi.position = part[1]
		_drop.add_child(mi)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.15, 0.46)
	shape.shape = bs
	shape.position = Vector3(0, 0.57, 0)
	_drop.add_child(shape)
	add_child(_drop)


func drop_aim(hit: Dictionary, hit_d: float) -> String:
	aim_drop = on() and _drop != null and hit and hit_d < 2.4 and hit.position.distance_to(DROP + Vector3(0, 0.6, 0)) < 0.75 and player.global_position.z < 0.0
	if not aim_drop:
		return ""
	return ("E — drop %s down the chute" % tapes.held.t if tapes.held != null else "The night drop") + "\nvideo returns%s" % (" · before 10 AM, it counts as yesterday" if Clock.h < Clock.OPEN else "")


func drop_e() -> bool:
	if not aim_drop:
		return false
	var t = tapes.held
	if t == null:
		hud.toast("Tapes go down the chute: take one in hand")
		return true
	if rented.get(t.k, 0) > 0 and Clock.h < Clock.OPEN and Clock.day > rented[t.k]:
		rented[t.k] += 1  # before they've opened: last night's
	tapes.release()
	tapes.return_bin.append(t)
	hud.toast("Down the chute: %s. Clunk" % t.t)
	if rented.has(t.k):
		_rent_return(t)  # (checked in now: nobody's waiting on the slot to notice)
	return true


# ---- for the save

func snapshot() -> Dictionary:
	return { "wallet": wallet, "owed": owed, "tab": tab, "trust": trust, "strikes": strikes, "today": today, "banned": banned, "card": card, "rented": rented, "day": day, "opened": _opened, "rec": rec, "record": record, "crew": crew, "fav": fav, "app": app, "fav_day": _fav_day }


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	wallet = d.wallet
	owed = d.owed
	tab = d.get("tab", 0.0)
	trust = d.trust
	strikes = int(d.strikes)
	today = int(d.today)
	banned = int(d.banned)
	card = d.card
	_opened = int(d.get("opened", 0))
	day.merge(d.day, true)
	rec = d.get("rec", {})
	crew = d.get("crew", {})
	fav = d.get("fav", {})
	app = d.get("app", {})
	_fav_day = int(d.get("fav_day", 0))
	record.merge(d.get("record", {}), true)
	for k: String in record:
		record[k] = int(record[k])
	for k in ["rented", "returned", "caught", "stolen", "helped", "shelved", "told", "asked"]:
		day[k] = int(day[k])
	for k: String in d.rented:
		rented[k] = int(d.rented[k])


# ---- the staff, as people. Each of them gets to know you on their own (a day at a time: talk to them, or have them
# ring you up), apart from what the store thinks of you. Known a couple of days, they've got your name and a word
# about their day; a bit better, a small favor, and something for it (a tip about the trail). And a regular they
# know well can ask for an application: an answer a morning later, and a yes puts you on staff
# (cmStaffMet, cmStaffFavorAsk, cmStaffHint, cmStaffThanks, cmStaffLine, cmStaffTalk, cmStaffTip, cmStaffJoin).
# Not over yet: them talking about you among themselves (they don't chat yet), a ticket on the house.

const NAMES := ["Sam", "Alex", "Chris", "Pat", "Jamie", "Casey", "Robin", "Terry", "Jordan", "Lee", "Corey", "Jesse"]
const MSGS := [["your mom called. Call her back", "Ugh. Thanks"], ["the manager wants you to call him", "Oh no. What did I do"], ["your ride's running late tonight", "Great. Thanks for telling me"],
	["you left your headlights on", "Oh, come on. Thanks"], ["it's your turn to take the trash out", "It is NOT. ...Fine"], ["Tony's is doing two-for-one tonight", "Now we're talking"]]


func you() -> String:  # your name (the one in marker on your card)
	return NAMES[$"../Trail".seed_ % NAMES.size()]


func _knows(e: Node) -> Dictionary:
	if not crew.has(e.first):
		crew[e.first] = { "k": 0, "day": 0, "n": 0, "named": false }
	return crew[e.first]


func _met(e: Node) -> void:  # talked to, or rung up by: once a day, they know you a little better
	var s := _knows(e)
	if int(s.day) == Clock.day or wary.has(e.first):
		return
	s.day = Clock.day
	s.k = int(s.k) + 1


func _pending(e: Node) -> bool:  # something between you and this one
	return (app.get("ans", "") != "" and (not app.told or app.ans == "yes")) or (fav.get("kind", "") == "msg" and fav.to == e.first and not fav.done) or (fav.get("by", "") == e.first and fav.done and not fav.get("paid", false))


func staff_tip(e: Node) -> String:  # the hover tip's second line, on one of them
	var s := _knows(e)
	if app.get("ans", "") == "yes" and app.told:
		return "E — take the job"
	if fav.get("kind", "") == "msg" and fav.to == e.first and not fav.done:
		return "E — pass on %s's message" % fav.by
	if fav.get("by", "") == e.first and fav.done and not fav.get("paid", false):
		return "E — tell them it's done"
	return "keeping an eye on you" if wary.has(e.first) else "knows your name" if int(s.k) >= 2 else "knows your face" if int(s.k) > 0 else "knows you by now" if regular() else "on staff"


func _hint() -> String:  # what they know about the trail: the next thing you haven't found
	var tr: Node = $"../Trail"
	if not tr.found.has(tr._key_at) and not tr.has("breakKey"):
		var where: String = tr._spots[tr._key_at][1]
		return "Ray lost the break room key again. If I had to bet? %s" % (where.capitalize() if where != "" else "It went out with the %s trash" % tr._key_at.get_slice(":", 1))
	if not tr.found.has("combo:locker"):
		return "Ray can't ever remember his locker combination. He writes the last number on his time card, I swear"
	if not tr.logged_in:
		return "Ray's got his register PIN on a post-it somewhere behind the counter. If the manager ever finds it..."
	if not tr.found.has("drawerKey"):
		return "You know where the janitor's key lives? In the register drawer, under the tray. Don't ask me why"
	if not tr.hatch:
		return "The manager left a message about the roof on the register. Nobody's supposed to go up there"
	return ""


func _line(e: Node) -> String:  # a word about their day: what's going on first, then what they're like
	var s := _knows(e)
	var top: String = "dex"
	for k: String in e.SKILLS:
		if e.lv(e, k) > e.lv(e, top):
			top = k
	var others: Array = staff.crew.filter(func(o: Node) -> bool: return o != e and o.dana != null)
	var chores: Node = $"../Chores"
	var all: Array = []
	if chores.messes.size() > 0:
		all.append("It's a mess in here today. I'll get to it. I'll get to it" if chores.messes.size() > 2 else "Somebody spilled something again. Story of my life")
	if shift.show.title != "" and shift.show.day == Clock.day and Clock.h < shift.SHOW.at:
		all.append("We're showing %s at eight. Tickets at the register" % shift.show.title)
	if shoppers.custs.size() >= 5:
		all.append("Crazy in here today, huh?")
	all.append({ "cha": "I could talk movies all day. Seriously, try me", "int": "I've seen every tape in Horror. Some of them twice", "dex": "I can rewind four tapes and ring somebody up at the same time. It's a gift",
		"str": "I moved every shelf in this place last month. My back hasn't forgiven me", "con": "Double shift tomorrow. I don't even mind anymore", "wis": "You can always tell who's going to bring their tapes back late. Always" }[top])
	if not others.is_empty():
		all.append("I was just telling %s about %s" % [others[0].first, ["the new releases", "last night's game", "that customer with the dog", "the manager's memo", "Tony's garlic knots"][(Clock.day + int(s.n)) % 5]])
	if int(s.k) >= 4:
		all.append("You're in here more than I am. We should put your picture up by the register")
	s.n = int(s.n) + 1
	return all[int(s.n) % all.size()]


func talk(e: Node) -> void:  # E on one of them, away from a sale: whatever's between you, else a pick, else small talk
	var s := _knows(e)
	var me := you()
	if fav.get("kind", "") == "msg" and fav.to == e.first and not fav.done:  # the message, passed on
		fav.done = true
		_met(e)
		e.dana.set_mood("shock")
		hud.toast("You tell %s %s. %s: “%s. Tell %s thanks.”" % [e.first, fav.msg, e.first, fav.reply, fav.by])
		return
	if fav.get("by", "") == e.first and fav.done and not fav.get("paid", false):  # the favor, done: what they owe you
		fav.paid = true
		s.k = int(s.k) + 1
		trust = minf(100.0, trust + 5.0)
		e.dana.set_mood("love")
		var hint := _hint()
		hud.toast("%s: “Thanks, %s. I owe you one. %s”" % [e.first, me, "Here's something: %s." % hint if hint != "" else "Seriously."])
		return
	if wary.has(e.first):
		e.dana.set_mood("angry")
		hud.toast("%s: “Mm-hm. I've got my eye on you.”" % e.first)
		return
	if app.get("ans", "") != "" and not app.told:  # the answer to your application
		app.told = true
		_met(e)
		if app.ans == "no":
			app.again = Clock.day + 5
			e.dana.set_mood("meh")
			hud.toast("%s: “Hey, %s... the manager went with somebody else. Sorry. Try again next week?”" % [e.first, me])
		else:
			e.dana.set_mood("love")
			hud.toast("%s: “%s! The manager read your application. You're hired, if you want it. We're short today: say the word and grab a vest.” (E again to take the job)" % [e.first, me])
		return
	if app.get("ans", "") == "yes" and app.told:
		join()
		return
	var met: bool = int(s.day) != Clock.day
	_met(e)
	if int(s.k) >= 2 and not s.named:
		s.named = true
		e.dana.set_mood("happy")
		hud.toast("%s: “I'm %s, by the way. %s”" % [e.first, e.first, "And you're %s, right? It's on your card." % me if card else "And you are?” “%s.” “Nice to meet you, %s." % [me, me]])
		return
	if rec.get("day", 0) != Clock.day:  # (their pick: once a day)
		recommend(e)
		return
	if regular() and int(s.k) >= 4 and not $"../Trail".has("badge") and (app.is_empty() or (app.ans == "no" and app.told and Clock.day >= app.get("again", 0))):  # a job application (not with Ray's badge in your pocket)
		app = { "day": Clock.day, "strikes": strikes, "ans": "", "told": false }
		e.dana.set_mood("happy")
		hud.toast("%s: “You know we're hiring, right? You're in here more than half of us. Here, fill this out, I'll give it to the manager.” You hand it back. “Give it a day.”" % e.first)
		return
	if fav.is_empty() and _fav_day != Clock.day and int(s.k) >= 3:  # known well enough: once a day (store-wide), a small favor
		var others: Array = staff.crew.filter(func(o: Node) -> bool: return o != e and o.dana != null)
		var chores: Node = $"../Chores"
		if Clock.day % 2 == 1 and not others.is_empty():  # pass a message on to whoever else is in
			var m: Array = MSGS[(Clock.day + e.first.length()) % MSGS.size()]
			fav = { "kind": "msg", "by": e.first, "to": others[0].first, "msg": m[0], "reply": m[1], "day": Clock.day, "done": false }
			hud.toast("%s: “%s, do me a favor? If you see %s, tell them %s. I can't leave the counter.”" % [e.first, me, others[0].first, m[0]])
		else:  # a tape somebody stuck in the wrong spot: back where it goes
			if chores.strays.is_empty():
				var on_shelf: Array = tapes.tapes.filter(func(t: Dictionary) -> bool: return not t.off and not t.get("lib", false) and not tapes._corners(t).is_empty())
				var t: Dictionary = on_shelf[(Clock.day * 31) % on_shelf.size()]
				var near: Array = on_shelf.filter(func(o: Dictionary) -> bool: return o.c != t.c)
				tapes.set_on_shelf(t, false)
				chores.misshelve(t, null, near[(Clock.day * 17) % near.size()])
			var st: Dictionary = chores.strays[0]
			fav = { "kind": "shelf", "by": e.first, "title": st.copy.t, "day": Clock.day, "done": false }
			hud.toast("%s: “%s, do me a favor? Somebody stuck %s in the wrong section. If you're over there, put it back where it goes?”" % [e.first, me, st.copy.t])
		_fav_day = Clock.day
		e.dana.set_mood("happy")
		return
	hud.toast("%s: “%s%s.”" % [e.first, "Hey, %s! " % me if met and int(s.k) >= 2 else "", _line(e).trim_suffix(".")])


func join() -> void:  # hired: the vest, the name tag, the other side of the counter. What you had on you goes back (rentals returned)
	for t: Dictionary in tapes.inv.duplicate():
		tapes.return_bin.append(t)
	if tapes.held != null:
		tapes.release()
	tapes.inv.clear()
	tapes.inv_stash()
	for t: Dictionary in tapes.tapes:
		if rented.has(t.k) and t.off and not tapes.return_bin.has(t):
			tapes.return_bin.append(t)
	rented.clear()
	app = {}
	shift.mode = "sandbox"
	for i in staff.roster.size():  # (back to their own weeks)
		var w: Dictionary = staff.roster[i]
		w.sched = [0, 0, 0, 0, 0, 0, 0]
		for k in 5:
			w.sched[(3 + i * 2 + k) % 7] |= 31 << (3 if i % 2 == 1 else 8)
	hud.call_box("")
	things._block.get_child(0).disabled = not things.locked
	hud.toast("Took the job. You work here now")
