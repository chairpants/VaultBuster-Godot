extends Node3D
## The phone: "do you have ... in?" Every couple of hours it rings. Answer (E) and a member asks after a title: 1,
## yes, you'll hold one for them; 2, sorry, all out. Promise a hold and a copy had better be on the holds shelf (E
## with it in hand) by the time they come in for it. Now and then it's something else: what time you close, a
## prank, somebody arguing a late fee, Dennis from district. Customers in the store come first: a call you miss
## while you're with someone costs nothing (they'll call back), but pick up while someone's waiting at the counter
## and they notice. Dana takes calls too, when nobody in the store needs her.
## From the web game's store/phone.js (CALLS, phoneCaller, phoneTick, phoneAnswer, callAnswer, callHud, holdPull,
## holdPlace, holdsRender, holdsTick, danaCall, ringBurst via ambience.gd). Whoever comes in for a hold asks for it
## at the counter (shoppers.gd). Where the phone and the holds tray are: data/interact.json.
## Not over yet: the overdue calls you make (the register's message center, post-its), the call list. Dana doesn't walk to the shelf for a hold she's promised: the copy's just on the tray.

const NOT_YET := [["Twister", "1996-05-10", "1996-10-01"], ["Mission: Impossible", "1996-05-22", "1996-11-12"], ["Independence Day", "1996-07-02", "1996-11-22"],
	["Jerry Maguire", "1996-12-13", "1997-08-26"], ["Men in Black", "1997-07-02", "1997-11-25"], ["Titanic", "1997-12-19", "1998-09-01"]]  # in theaters, out on tape
const PRANKS := ["Uh, yeah, do you have Free Willy?|Then you better go free him! *click*", "Is your refrigerator running?|Then you better go catch it! *click*",
	"Do you have Lethal Weapon?|Freeze! FBI! *giggling, click*"]

var next := -1.0  # the hour of the next call
var ring = null  # ringing: { member, title, cat | kind, ..., t, rang }
var on_line = null  # on the line: the same, t counting down
var holds: Array = []  # promised: { member, title, at (the hour they come in), day, copy | null, by, coming, pulled }
var aim := ""  # "phone" | "holds" | ""

var _at := Vector3.ZERO
var _tray := Vector3.ZERO
var _dennis := 0
var _stack := Node3D.new()

@onready var hud: CanvasLayer = $"../HUD"
@onready var shoppers: Node = $"../Shoppers"
@onready var checkout: Node = $"../Checkout"
@onready var tapes: Node = $"../Tapes"
@onready var staff: Node = $"../Staff"
@onready var shift: Node = $"../Shift"


func _ready() -> void:
	var T: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things
	_at = Vector3(T.phone[0], T.phone[1], T.phone[2])
	_tray = Vector3(T.holds[0], T.holds[1], T.holds[2])
	add_child(_stack)


func _busy() -> bool:  # somebody in the store needs you
	return checkout.co != null or shoppers.waiting() != null or not shoppers.line.is_empty() or not shoppers.asks.is_empty()


func _caller():  # mostly a member asking after a title; now and then one of the other calls a video store gets
	var ms: Array = shoppers.members.all
	if randf() < 0.35:
		var now := Time.get_unix_time_from_datetime_dict(Clock.date())
		var film: Array = NOT_YET.filter(func(f: Array) -> bool: return now >= Time.get_unix_time_from_datetime_string(f[1]) and now < Time.get_unix_time_from_datetime_string(f[2]))
		var owing: Array = ms.filter(func(m: Dictionary) -> bool: return m.owed > 0.0)
		var kinds := ["hours", "prank"]
		if not film.is_empty():
			kinds.append("notyet")
		if not owing.is_empty():
			kinds.append("fee")
		if _dennis != Clock.day and Clock.h > 15.0:
			kinds.append("dennis")
		var kind: String = kinds.pick_random()
		if kind == "dennis":
			_dennis = Clock.day
		return { "kind": kind, "film": film[0] if not film.is_empty() else [], "prank": PRANKS.pick_random(), "member": owing.pick_random() if kind == "fee" else null if kind == "dennis" else ms.pick_random() }
	var free: Array = ms.filter(func(m: Dictionary) -> bool: return shoppers.members.can_visit(m) and not shoppers.custs.any(func(k: Dictionary) -> bool: return k.member == m) and not holds.any(func(h: Dictionary) -> bool: return h.member == m))
	if free.is_empty():
		return null
	var m: Dictionary = free.pick_random()
	var t = shoppers.a_title(shoppers.customer_for(shoppers._imul(m.num, 2654435761), m.female).cats, 0.65)
	return { "member": m, "title": t.t, "cat": t.c } if t != null else null


func _who(c: Dictionary) -> String:
	return shoppers.members.name_of(c.member) if c.member != null else "Dennis"


func _says(c: Dictionary) -> Array:  # [who's calling, what they say, answer 1, answer 2, which one's right (0: either)]
	var who: String = "%s #%d" % [shoppers.members.name_of(c.member), c.member.num] if c.member != null else "DENNIS · DISTRICT"
	match c.get("kind", ""):
		"hours": return [who, "What time do you close tonight?", "Midnight", "Ten o'clock", 1]
		"notyet":
			var d := Time.get_datetime_dict_from_datetime_string(c.film[2], false)
			return [who, "Is %s out on tape yet?" % c.film[0], "Not till %s %d: I'll put you on the list" % [["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.month - 1], d.day], "Yep, come on down", 1]
		"prank": return [who, c.prank.split("|")[0], "Yes, we do", "Hang up", 0]
		"fee": return [who, "About this $%.2f late fee: I dropped that tape off on time!" % c.member.owed, "I'll take it off this once", "Sorry, the fee stands", 0]
		"dennis": return [who, "Dennis, from district. Just checking in: how's today going over there?", "Going great", "Bit of a rough one", 2 if shift.stats.walkouts >= 2 or shift.stats.stolen > 0 else 1]
	return [who, "Hi, do you have %s in? (%s)" % [c.title, c.cat], "Yes, I'll hold one for you", "Sorry, we're all out", 0]


func _process(dt: float) -> void:  # phoneTick
	var open := Clock.h >= Clock.OPEN and Clock.h < Clock.LAST_IN
	if next < 0.0:
		next = maxf(Clock.h, Clock.OPEN) + 1.0 + randf() * 1.5
	if ring == null and on_line == null and open and Clock.h >= next:
		next = Clock.h + 2.0 + randf() * 1.5  # semi-infrequent: every two to three and a half hours
		var c = _caller()
		if c != null:
			c.t = 0.0
			c.rang = 0.0
			ring = c
			hud.toast("The phone's ringing (behind the counter)")
	_holds_tick(open)
	if ring == null:
		if on_line != null:  # on the line: they won't hold forever
			on_line.t -= dt
			if on_line.t <= 0.0:
				hud.toast("%s got tired of waiting on the line and hung up (-5)" % _who(on_line))
				checkout.score -= 5
				on_line = null
				hud.call_box("")
		return
	ring.t += dt
	if ring.t >= ring.rang:  # the US cadence: 2 s on, 4 s off
		ring.rang += 6.0
		$"../Ambience".ring(_at)
	var taker = staff.clerk()
	if ring.t > 6.0 and taker != null and taker.who.jobs.get("phone", 0) > 0 and checkout.co == null and shoppers.waiting() == null:
		preload("res://staff.gd").speaker = taker.first
		staff.xp(taker, "cha", 4.0)
		_dana_call()  # nobody in the store needs her: she gets it
	elif ring.t > 20.0:  # rang out
		var from := _who(ring)
		$"../POS".message("%s MISSED CALL - %s%s" % [Clock.fmt_clock(Clock.h), "%s #%d" % [from, ring.member.num] if ring.member != null else "DENNIS AT DISTRICT", " RE: LATE FEE" if ring.get("kind", "") == "fee" else " RE: %s" % ring.title if ring.has("title") else ""])
		if _busy():
			hud.toast("Missed a call from %s while you were with customers: they'll call back" % from)
			next = Clock.h + 0.4 + randf() * 0.4
		else:
			checkout.score -= 10
			if ring.member != null:
				shoppers.members.loyal(ring.member, -2)
			hud.toast("Missed a call from %s (-10)" % from)
		ring = null


func answer() -> void:  # E on the phone while it's ringing (phoneAnswer)
	staff.xp("you", "cha", 4.0)
	var waiting: Array = shoppers.asks.duplicate()
	if shoppers.waiting() != null:
		waiting.append(shoppers.waiting())
	for k: Dictionary in waiting:  # they're standing right there
		k.t -= 10.0
		shoppers.members.loyal(k.member, -2)
		k.c.set_mood("impatient")
		k.hi = 2.0
	if not waiting.is_empty():
		hud.toast("Picked up the phone with %s waiting at the counter" % ("a customer" if waiting.size() == 1 else "%d customers" % waiting.size()))
	on_line = ring
	on_line.t = 30.0
	ring = null
	var s := _says(on_line)
	hud.call_box("ON THE PHONE · %s\n“%s”\n1 %s   2 %s" % [s[0], s[1], s[2], s[3]])


func call_answer(key: int, by := "you"):  # 1 or 2 (callAnswer). -> the hold, if one was promised
	var c: Dictionary = on_line
	on_line = null
	hud.call_box("")
	var Who := "Dana" if by == "dana" else "You"
	var s := _says(c)
	var M: RefCounted = shoppers.members
	match c.get("kind", ""):
		"prank":
			hud.toast("Prank call. %s" % c.prank.split("|")[1] if key == 1 else "%s hung up on a prank caller" % Who)
		"fee":
			var owed: float = c.member.owed
			if key == 1:
				shift.stats.fees_waived += owed
				c.member.owed = 0.0
				M.loyal(c.member, 4)
				hud.toast("%s waived %s's $%.2f late fee over the phone" % [Who, _who(c), owed])
			else:
				M.loyal(c.member, -3)
				hud.toast("%s told %s the $%.2f late fee stands" % [Who, _who(c), owed])
		"hours", "notyet", "dennis":
			var right: bool = key == s[4]
			checkout.score += 5 if right else -10
			if c.member != null:
				M.loyal(c.member, 1 if right else -3)
			hud.toast("%s told %s: “%s”%s" % [Who, _who(c), s[1 + key], " (+5)" if right else ". Not quite right (-10)"])
		_:
			var in_now: bool = shoppers.on_shelf_copy(c.title) != null
			if key == 1:
				var at := minf(Clock.LAST_IN - 0.1, Clock.h + 1.0 + randf() * 1.2)
				var h := { "member": c.member, "title": c.title, "at": at, "day": Clock.day, "copy": null, "by": by, "coming": false, "pulled": null }
				holds.append(h)
				hud.toast("%s told %s there's a copy of %s on hold for them: they'll be in around %s%s" % [Who, _who(c), c.title, Clock.fmt_clock(at), ". Put a copy on the holds shelf" if by == "you" else ""])
				return h
			checkout.score += -10 if in_now else 10
			M.loyal(c.member, -3 if in_now else 1)
			hud.toast("%s told %s %s was all out, but there's one on the shelf (-10)" % [Who, _who(c), c.title] if in_now else "%s told %s %s is all out (+10)" % [Who, _who(c), c.title])
	return null


func _dana_call() -> void:  # Dana picks up: she knows the answers (and hangs up on pranks; the fee stands: not hers to waive), and tells the truth about what's in
	on_line = ring
	ring = null
	if on_line.has("kind"):
		var right: int = _says(on_line)[4]
		call_answer(right if right > 0 else 2, "dana")
		return
	var copy = shoppers.on_shelf_copy(on_line.title)
	if copy == null:
		call_answer(2, "dana")
		return
	var h = call_answer(1, "dana")
	tapes.set_on_shelf(copy, false)  # (the web game: she walks to the shelf for it. Here it's just on the tray)
	h.copy = copy
	_render()


func _unhandled_input(e: InputEvent) -> void:
	if on_line != null and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_1, KEY_2]:
		call_answer(1 if e.physical_keycode == KEY_1 else 2)
		get_viewport().set_input_as_handled()  # (not the tape in slot 1 or 2 as well)


# ---- holds

func hold_end(h: Dictionary) -> void:  # a hold's done with (picked up, or it fell through): off the books; an unclaimed copy goes back out
	holds.erase(h)
	if h.copy != null:
		tapes.set_on_shelf(h.copy, true)
		h.copy = null
	_render()


func _holds_tick(open: bool) -> void:  # callers come in for their holds
	if not open or $"../Things".locked:
		return
	for h: Dictionary in holds:
		if not h.coming and h.day == Clock.day and Clock.h >= h.at and not shoppers.custs.any(func(k: Dictionary) -> bool: return k.member == h.member):
			h.coming = true
			var k: Dictionary = shoppers.spawn(h.member)
			k.pickup = h
			k.thief = false
			k.returning = []
			k.c.hold_tape(0)
			k.c.set_pose("idle")


func new_day() -> void:  # whoever didn't make it in for theirs: they'll come today
	next = -1.0
	for h: Dictionary in holds:
		if h.day < Clock.day:
			h.day = Clock.day
			h.at = 11.0 + randf() * 3.0
			h.coming = false


func _render() -> void:  # the held tapes, stacked in the tray with a yellow slip on each
	for c in _stack.get_children():
		c.queue_free()
	var i := 0
	for h: Dictionary in holds:
		if h.copy == null:
			continue
		for part: Array in [[Vector3(tapes.size.y, tapes.size.x, tapes.size.z), Color(0.07, 0.07, 0.08), 0.0], [Vector3(0.1, 0.002, 0.07), Color.hex(0xfff59aff), tapes.size.x / 2.0 + 0.001]]:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = part[0]
			var m := StandardMaterial3D.new()
			m.albedo_color = part[1]
			box.material = m
			mi.mesh = box
			mi.position = _tray + Vector3((i % 2) * 0.012, tapes.size.x / 2.0 + i * tapes.size.x + part[2], 0.0)
			_stack.add_child(mi)
		i += 1


# ---- the crosshair on the phone or the holds tray (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = ""
	if shift.mode == "customer":
		return ""  # (not yours to answer)
	if not hit or hit_d > 2.4:
		return ""
	if hit.position.distance_to(_at) < 0.28:
		aim = "phone"
		return "E — answer the phone" if ring != null else "On the phone: 1 or 2 to answer them" if on_line != null else "The store phone"
	if hit.position.distance_to(_tray + Vector3(0, 0.08, 0)) < 0.3:
		aim = "holds"
		var open := holds.filter(func(h: Dictionary) -> bool: return h.copy == null)
		if tapes.held != null:
			var mine := open.filter(func(h: Dictionary) -> bool: return h.title == tapes.held.t)
			return "E — put %s on hold for %s" % [tapes.held.t, shoppers.members.name_of(mine[0].member)] if not mine.is_empty() else "The holds shelf\nnobody's asked for that one to be held"
		return "The holds shelf%s" % ("\nwanted: " + ", ".join(open.map(func(h: Dictionary) -> String: return h.title)) if not open.is_empty() else "")
	return ""


func on_e() -> bool:
	if aim == "phone":
		if ring != null:
			answer()
		return true
	if aim != "holds":
		return false
	if tapes.held != null:  # holdPlace
		var t: Dictionary = tapes.held
		var mine := holds.filter(func(h: Dictionary) -> bool: return h.copy == null and h.title == t.t)
		if mine.is_empty():
			hud.toast("Nobody's asked for that one to be held")
		else:
			tapes.release()
			mine[0].copy = t
			_render()
			checkout.score += 15
			staff.xp("you", "int", 5.0)
			hud.toast("Put %s on the holds shelf for %s (+15)" % [t.t, shoppers.members.name_of(mine[0].member)])
	else:  # holdPull: take down the one someone's at the counter for
		var ks: Array = shoppers.asks.filter(func(k: Dictionary) -> bool: return k.state == "asking" and k.want.kind == "hold" and k.want.hold.copy != null)
		if ks.is_empty():
			hud.toast("Those are for customers who come in for them")
		elif not tapes.inv_make_room():
			hud.toast("Hands full")
		else:
			var h: Dictionary = ks[0].want.hold
			h.pulled = h.copy
			h.copy = null
			_render()
			tapes._take(h.pulled)
	return true


# ---- for the save

func snapshot() -> Dictionary:
	return { "next": next, "holds": holds.map(func(h: Dictionary) -> Array: return [h.member.num, h.title, h.at, h.day, h.copy.k if h.copy != null else "", h.by]) }


func restore(d: Dictionary) -> void:
	next = d.get("next", -1.0)
	for a: Array in d.get("holds", []):
		var m = shoppers.members.by_num.get(int(a[0]))
		if m == null:
			continue
		var copy = null
		for t: Dictionary in tapes.tapes:
			if t.k == a[4]:
				copy = t
				tapes.set_on_shelf(t, false)
		holds.append({ "member": m, "title": a[1], "at": a[2], "day": int(a[3]), "copy": copy, "by": a[5], "coming": false, "pulled": null })
	_render()
