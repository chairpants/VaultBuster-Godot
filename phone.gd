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
## The overdue calls go the other way: look somebody up in the register's message center and they're on a post-it by
## the phone. E on it rings them. Who picks up depends on when: working people aren't home on a weekday afternoon (the
## machine gets it), weekend mornings people sleep in, and past their bedtime you'll wake them. What came of it is
## written on the note and on their record; Q on a note throws it out (postits, postitAdd, postitCall, phoneOutTick,
## memberHabits, callOutcome, CALL_SAY).

const NOT_YET := [["Twister", "1996-05-10", "1996-10-01"], ["Mission: Impossible", "1996-05-22", "1996-11-12"], ["Independence Day", "1996-07-02", "1996-11-22"],
	["Jerry Maguire", "1996-12-13", "1997-08-26"], ["Men in Black", "1997-07-02", "1997-11-25"], ["Titanic", "1997-12-19", "1998-09-01"]]  # in theaters, out on tape
const PRANKS := ["Uh, yeah, do you have Free Willy?|Then you better go free him! *click*", "Is your refrigerator running?|Then you better go catch it! *click*",
	"Do you have Lethal Weapon?|Freeze! FBI! *giggling, click*"]

var next := -1.0  # the hour of the next call
var ring = null  # ringing: { member, title, cat | kind, ..., t, rang }
var on_line = null  # on the line: the same, t counting down
var holds: Array = []  # promised: { member, title, at (the hour they come in), day, copy | null, by, coming, pulled }
var aim := ""  # "phone" | "holds" | "postit" | ""
var postits: Array = []  # { m, result ("" till they've been rung), at (the hour it was written), rz, node }
var out = null  # ringing out: { n, m, o, t, rings, said }
var aim_note = null

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
	_out_tick(dt)
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
		_dana_call(taker)  # nobody in the store needs them: they get it
	elif ring.t > 20.0:  # rang out
		var from := _who(ring)
		var back := {}  # what it was about, for ringing them back (a member's: nobody rings district back)
		if ring.member != null:
			back = { "num": ring.member.num, "kind": ring.get("kind", ""), "title": ring.get("title", ""), "cat": ring.get("cat", ""), "prank": ring.get("prank", ""), "film": ring.get("film", []) }
		$"../POS".message("%s MISSED CALL - %s%s" % [Clock.fmt_clock(Clock.h), "%s #%d (555-%04d)" % [from, ring.member.num, ring.member.num * 7919 % 10000] if ring.member != null else "DENNIS AT DISTRICT", " RE: LATE FEE" if ring.get("kind", "") == "fee" else " RE: %s" % ring.title if ring.has("title") else ""], back)
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


func _dana_call(taker: Node = null) -> void:  # Dana picks up: she knows the answers (and hangs up on pranks; the fee stands: not hers to waive), and tells the truth about what's in
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
	if taker != null and taker.fetch_hold(h, copy):  # off to the shelf for it
		return
	tapes.set_on_shelf(copy, false)  # (no way to that shelf: it's just on the tray)
	h.copy = copy
	_render()


func _unhandled_input(e: InputEvent) -> void:
	if held_note != null and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		stick_back()
		get_viewport().set_input_as_handled()
	if aim == "postit" and aim_note != null and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_Q:
		postit_toss(aim_note)
		get_viewport().set_input_as_handled()
	if on_line != null and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_1, KEY_2]:
		call_answer(1 if e.physical_keycode == KEY_1 else 2)
		get_viewport().set_input_as_handled()  # (not the tape in slot 1 or 2 as well)


# ---- post-its by the phone: the overdue calls

const CALL_SAY := {
	"ok": ["It's in the car: I'll drop it off.", "Oh no, I thought I'd returned that! I'll look for it.", "Sorry! I'll bring it in.", "The kid hid it in the toy box. I'll bring it by."],
	"okNo": ["Yeah, yeah. I'll get to it.", "Huh. I'll have to look for it.", "Is that still out? Weird."],
	"late": ["It's kind of late to be calling... fine, I'll bring it in.", "We were just going to bed. Yes, I'll return it."],
	"dinner": ["We're eating dinner. I'll bring it in, okay?", "Can this wait? We're in the middle of dinner."],
	"morning": ["Mmf... it's Saturday morning... yeah, okay. Later.", "You woke me up. I'll bring it in. Bye."],
	"night": ["Do you know what time it is?! *click*", "It's the middle of the night! Don't call here this late! *click*"],
}


func postit_add(m: Dictionary, quiet := false, back := {}):  # the register: an overdue call looked up (or a missed one: back, what it was about) -> a note by the phone (one per member)
	if postits.any(func(n: Dictionary) -> bool: return n.m == m):
		return null
	var n := { "m": m, "result": "", "at": Clock.h, "rz": (randf() - 0.5) * 0.25, "node": null }
	if not back.is_empty():
		n.back = back
	postits.append(n)
	_postits_render()
	if not quiet:
		hud.toast("Jotted down a post-it to call %s (555-%04d): it's by the store phone. E on the phone (or the note) dials" % [shoppers.members.name_of(m), m.num * 7919 % 10000])
	return n


func _postit_at(i: int) -> Vector3:  # two rows of four by the phone, then on top
	return Vector3(-6.22 + (i % 8 % 4) * 0.09, _at.y - 0.0785 + (i / 8) * 0.0015, _at.z - 0.075 + (i % 8 / 4) * 0.15)


func _postits_render() -> void:  # stuck down flat on the cabinet top, handwritten (postitDraw, postitsLayout)
	var down := 0  # (the one in your hand leaves no gap)
	for n: Dictionary in postits:
		var i := down
		if n.node == null:
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.076, 0.076)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.hex(0xffea6eff)
			q.material = mat
			mi.mesh = q
			var l := Label3D.new()
			l.pixel_size = 0.00028
			l.font_size = 26
			l.outline_size = 0
			l.width = 250.0
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.position.z = 0.0005
			l.name = "Text"
			mi.add_child(l)
			add_child(mi)
			n.node = mi
		if not is_same(n, held_note):
			down += 1
			n.node.position = _postit_at(i)
			n.node.rotation = Vector3(-PI / 2.0, 0.0, n.rz)
		var text: Label3D = n.node.get_node("Text")
		var late: String = $"../POS".late_summary(n.m).to_lower()
		text.modulate = Color.hex(0xb3261eff) if n.result != "" else Color.hex(0x1b2f8cff)  # (rung: in red)
		if n.has("back"):
			late = "called, re: %s" % ("late fee" if n.back.kind == "fee" else n.back.title.to_lower() if n.back.title != "" else "?")
		text.text = "CALL: %s\n555-%04d\n%s%s" % [shoppers.members.name_of(n.m), n.m.num * 7919 % 10000, late if late != "" else "tape's back!", "\n" + n.result if n.result != "" else ""]


func habits(m: Dictionary) -> Dictionary:  # how a member's day goes (from their member #, so the same person keeps the same habits)
	var r := func(k: int) -> float: return float(shoppers._imul(m.num + k * 7919, 2654435761) & 0xffffffff) / 4294967296.0
	return { "works": r.call(1) < 0.68, "night_owl": r.call(2) < 0.15, "sleeps_in": r.call(3) < 0.55 }


func call_outcome(m: Dictionary, h: float, day: int) -> Dictionary:  # -> { pick: "machine" | "noanswer" | "answer", mood: "ok" | "annoyed" | "angry", woke, why } for a call at this hour, this weekday (0: Sunday)
	var hab := habits(m)
	var weekend := day == 0 or day == 6
	var bed := 25.0 if hab.night_owl else 23.5 if day == 5 or day == 6 else 22.5  # lights out (Friday and Saturday nights, a bit later)
	var home := 0.85
	if not weekend and hab.works and h >= 8.5 and h < 17.5:
		home = 0.1  # at work
	elif not weekend and h >= 17.5 and h < 18.5:
		home = 0.55  # on the way home
	elif weekend and h >= 11.5 and h < 18.0:
		home = 0.45  # out doing weekend things
	if randf() > home:
		return { "pick": "machine" if randf() < 0.85 else "noanswer", "why": "work" if not weekend and hab.works and h < 17.5 else "out" }
	var asleep := 0.85 if h >= bed else 0.3 if h >= bed - 0.75 else 0.7 if weekend and hab.sleeps_in and h < 10.5 else 0.3 if weekend and hab.sleeps_in and h < 11.5 else 0.0
	if randf() < asleep:  # you woke them up
		if randf() < 0.4:
			return { "pick": "machine" if randf() < 0.7 else "noanswer", "why": "asleep" }  # (slept through it)
		var late := h >= bed - 0.75
		return { "pick": "answer", "woke": true, "mood": ("angry" if h >= bed + 0.5 or randf() < 0.6 else "annoyed") if late else "annoyed" if randf() < 0.75 else "ok", "why": "night" if late else "morning" }
	var evening := h >= bed - 1.5
	var dinner := h >= 17.75 and h < 19.0
	return { "pick": "answer", "mood": ("annoyed" if randf() < 0.55 else "ok") if evening else "annoyed" if dinner and randf() < 0.25 else "ok", "why": "late" if evening else "dinner" if dinner else "" }


func _next_call():  # the first note there's still a call to make on today, or null
	for n: Dictionary in postits:
		if n.has("back") or (n.m.last_call != Clock.day and $"../POS".needs_call(n.m)):
			return n
	return null


func postit_call(n: Dictionary) -> void:  # E on a post-it: dial
	var m: Dictionary = n.m
	var who: String = shoppers.members.name_of(m)
	if ring != null:
		hud.toast("The phone's ringing: answer it first")
	elif on_line != null or out != null:
		hud.toast("You're already on the phone")
	elif n.has("back"):  # ringing back somebody who rang and got no answer: they pick up, and it's the call you missed (not the web game's: there they ring again themselves)
		on_line = { "member": m, "t": 30.0 }
		for k: String in ["kind", "title", "cat", "prank", "film"]:
			if n.back[k] is String and n.back[k] == "":
				continue
			on_line[k] = n.back[k]
		if on_line.has("title") and not on_line.has("kind"):
			pass  # (a tape they were after)
		elif not on_line.has("kind"):
			on_line.kind = "hours"
		var s := _says(on_line)
		hud.call_box("ON THE PHONE · %s\n“Oh, thanks for calling back. %s”\n1 %s   2 %s" % [s[0], s[1], s[2], s[3]])
		checkout.score += 5
		shoppers.members.loyal(m, 2)
		staff.xp("you", "cha", 4.0)
		postits.erase(n)
		n.node.queue_free()
		_postits_render()
	elif not $"../POS".needs_call(m):
		if n.result == "":
			n.result = "TAPE CAME BACK. NO NEED TO CALL"
			_postits_render()
		hud.toast("%s's not overdue anymore: hold E to peel the post-it off and toss it" % who)
	elif m.last_call == Clock.day:
		hud.toast("You've already called %s today: try again tomorrow" % who)
	else:
		var o := call_outcome(m, Clock.h, Clock.date().weekday)
		out = { "n": n, "m": m, "o": o, "t": 0.0, "rings": 1 + randi() % 3 if o.pick == "answer" else 3 if o.pick == "machine" else 5, "said": "" }
		_out_hud()


func _out_hud() -> void:
	if out == null:
		if on_line == null:
			hud.call_box("")
		return
	hud.call_box("CALLING · %s #%d · 555-%04d\n%s" % [shoppers.members.name_of(out.m), out.m.num, out.m.num * 7919 % 10000, out.said if out.said != "" else "Ringing… (%s)" % $"../POS".late_summary(out.m).to_lower()])


func _out_tick(dt: float) -> void:  # ringing out, then whoever (or whatever) picks up (phoneOutTick)
	if out == null:
		return
	if out.said != "":  # what they said stays up a moment
		out.t -= dt
		if out.t <= 0.0:
			out = null
			_out_hud()
		return
	out.t += dt
	if out.t < out.rings * 3.0:
		return
	var m: Dictionary = out.m
	var o: Dictionary = out.o
	var loy: float = m.loyalty / 250.0
	var promise := false
	var say := ""
	var note := ""
	if o.pick == "noanswer":
		say = "It rings and rings. Nobody's home, and no machine."
		note = "NO ANSWER"
	elif o.pick == "machine":
		promise = randf() < 0.25
		say = "“Hi, you've reached the %ss. Leave a message at the beep.” You leave one." % m.last.capitalize()
		note = "MACHINE. LEFT A MESSAGE"
	elif o.mood == "angry":
		promise = randf() < 0.1
		say = "“%s”" % CALL_SAY.night.pick_random()
		note = "WOKE THEM UP. HUNG UP ON ME" if o.get("woke", false) else "HUNG UP ON ME"
		shoppers.members.loyal(m, -15)
		checkout.score -= 15
	elif o.mood == "annoyed":
		promise = randf() < 0.45 + loy
		shoppers.members.loyal(m, -6)
		say = "“%s”" % CALL_SAY.get(o.why, CALL_SAY.late).pick_random()
		note = "%sANNOYED. %s" % ["WOKE THEM. " if o.get("woke", false) else "", "SAYS THEY'LL BRING IT" if promise else "NO PROMISES"]
	else:
		promise = randf() < 0.8 + loy
		shoppers.members.loyal(m, 1)
		say = "“%s”" % (CALL_SAY.ok if promise else CALL_SAY.okNo).pick_random()
		note = "SPOKE TO THEM. BRINGING IT IN" if promise else "SPOKE TO THEM. NO PROMISES"
	var at := Clock.fmt_clock(Clock.h)
	out.n.result = "%s - %s" % [at, note]
	_postits_render()
	$"../POS".record_call(m, promise, "%s %s" % [at, note])
	staff.xp("you", "cha", 6.0)
	if not promise:
		hud.toast("Called %s about their overdue tape: %s" % [shoppers.members.name_of(m), note.to_lower()])
	out.said = say
	out.t = 4.5
	_out_hud()


var held_note = null  # the post-it you've peeled off: in your hand


func holdable() -> bool:  # E held on a note: peeled off (a tap dials)
	return aim == "postit" and aim_note != null and held_note == null and not (out != null and out.n == aim_note)


func peel() -> void:  # hold E: off the cabinet, in your hand (postitPickUp)
	if not holdable():
		return
	held_note = aim_note
	var node: Node3D = held_note.node
	node.get_parent().remove_child(node)
	$"../Player/Camera".add_child(node)
	node.position = Vector3(0.17, -0.15, -0.38)
	node.rotation = Vector3(-0.35, 0.15, 0.08)
	node.scale = Vector3.ONE * 1.15
	_postits_render()
	hud.toast("Peeled off the post-it · E on a wastebasket to toss it · right-click (or E on the phone) to stick it back")


func stick_back() -> void:  # back down by the phone (postitPutBack)
	if held_note == null:
		return
	var node: Node3D = held_note.node
	node.get_parent().remove_child(node)
	add_child(node)
	node.scale = Vector3.ONE
	held_note = null
	_postits_render()


func held_e() -> bool:  # E with a note in your hand: into the wastebasket you're looking at, or back by the phone. -> it was the note's to take
	if held_note == null:
		return false
	var chores: Node = $"../Chores"
	if chores.aim.has("bin"):
		postit_toss(held_note, chores.aim.bin)
	elif aim == "phone" or aim == "postit":
		stick_back()
	else:
		return false  # (anything else E does, it still does)
	return true


func postit_toss(n: Dictionary, bin = null) -> void:  # crumpled, into a wastebasket (the one given; Q on a note: the nearest)
	if out != null and out.n == n:
		return
	if held_note == n:
		held_note = null
	postits.erase(n)
	n.node.queue_free()
	_postits_render()
	if bin == null:
		var bins: Array = $"../Chores".bins.duplicate()
		bins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a.x - _at.x, a.z - _at.z).length() < Vector2(b.x - _at.x, b.z - _at.z).length())
		bin = bins[0] if not bins.is_empty() else null
	if bin != null:
		$"../Chores".trash_add(bin, 1)
	hud.toast("Tossed the post-it for %s" % shoppers.members.name_of(n.m))


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
	var near = null  # (the note the crosshair's nearest, a little past its edges: they're small)
	for n: Dictionary in postits.filter(func(x: Dictionary) -> bool: return not is_same(x, held_note)):
		if hit.position.distance_to(n.node.position) < 0.075 and (near == null or hit.position.distance_to(n.node.position) < hit.position.distance_to(near.node.position)):
			near = n
	for n: Dictionary in ([near] if near != null else []):
		if true:
			aim = "postit"
			aim_note = n
			return "E — call %s (555-%04d)\n%s · hold E peels it off" % [shoppers.members.name_of(n.m), n.m.num * 7919 % 10000, n.result if n.result != "" else "returning their call" if n.has("back") else $"../POS".late_summary(n.m).to_lower()]
	if hit.position.distance_to(_at) < 0.28:
		aim = "phone"
		return "E — answer the phone" if ring != null else "On the phone: 1 or 2 to answer them" if on_line != null else "On the phone" if out != null else "E — call %s (the next post-it)\n%d post-it%s beside the phone" % [shoppers.members.name_of(_next_call().m), postits.size(), "" if postits.size() == 1 else "s"] if _next_call() != null else "The store phone\n%s" % ("%d post-it%s beside it, nobody left to ring today" % [postits.size(), "" if postits.size() == 1 else "s"] if not postits.is_empty() else "overdue and missed calls: log in at the register and open MESSAGES")
	if hit.position.distance_to(_tray + Vector3(0, 0.08, 0)) < 0.3:
		aim = "holds"
		var open := holds.filter(func(h: Dictionary) -> bool: return h.copy == null)
		if tapes.held != null:
			var mine := open.filter(func(h: Dictionary) -> bool: return h.title == tapes.held.t)
			return "E — put %s on hold for %s" % [tapes.held.t, shoppers.members.name_of(mine[0].member)] if not mine.is_empty() else "The holds shelf\nnobody's asked for that one to be held"
		return "The holds shelf%s" % ("\nwanted: " + ", ".join(open.map(func(h: Dictionary) -> String: return h.title)) if not open.is_empty() else "")
	return ""


func on_e() -> bool:
	if aim == "postit":
		if not is_same(aim_note, held_note):
			postit_call(aim_note)
		return true
	if aim == "phone":
		if ring != null:
			answer()
		elif on_line == null and out == null and _next_call() != null:  # (not the web game's: there it's the post-it or nothing)
			postit_call(_next_call())
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
	return { "next": next, "postits": postits.map(func(n: Dictionary) -> Array: return [n.m.num, n.result, n.at, n.rz, n.get("back", {})]), "holds": holds.map(func(h: Dictionary) -> Array: return [h.member.num, h.title, h.at, h.day, h.copy.k if h.copy != null else "", h.by]) }


func restore(d: Dictionary) -> void:
	next = d.get("next", -1.0)
	for a: Array in d.get("postits", []):
		var pm = shoppers.members.by_num.get(int(a[0]))
		if pm != null:
			postits.append({ "m": pm, "result": a[1], "at": a[2], "rz": a[3], "node": null })
			if a.size() > 4 and not a[4].is_empty():
				postits[-1].back = a[4]
	_postits_render()
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
