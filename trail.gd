extends Node3D
## Customer mode's trail. Some doors are locked, some things padlocked, and what opens them is out there somewhere:
## the break room's key (hidden somewhere a customer can get at), a note in the break room with most of the
## combination to Ray's locker (the last number's on his time card), his employee badge in the locker, his PIN on
## a post-it under something behind the counter, and, logged into the register as Ray, the manager's message with
## the combination to the roof hatch, and the janitor's key under the cash tray. Each opens the way to the next,
## and it all leads up to the roof. Where things are hidden, and the codes, are this store file's own.
## Every hiding place is a place to look (E), and most turn up nothing, or a quarter. Money turns up too: a few
## dropped bills each day, change in the trash. Anyone on staff who sees you rummaging thinks a bit less of you.
## From the web game's store/customer-mode.js (ITEMS, KEYED, COMBOS, cmComboKey, SEARCHES, cmTrailSet, cmMoneyDrop,
## cmPickUp, cmSearch, cmSearchBin, cmNotice, the badge terminal: cmTermOpen, cmNoSale, cmTermDraw, cmTermKey).
## Different here: what you've found is a list (N shows it, notes and all), not things in your nine pockets, and
## the hiding places aren't marked by anything you can see.
## Not over yet: the staff being wary of you the day after, the drawer coming up short, teeing off from the roof.

const ITEMS := { "breakKey": "Break room key", "closetKey": "Janitor's key", "comboNote": "Folded note", "badge": "Ray's employee badge", "pinNote": "Post-it", "printout": "Register printout" }
const NOTHING := ["Nothing. A gum wrapper", "Nothing but lint", "Nothing there", "Just dust", "A bottle cap. Nothing useful", "Nothing. Somebody's old receipt"]
const MONEY_SPOTS := [[-9, -3], [5.5, -2.5], [-3, -6.4], [9, -6.8], [12, -1.1], [-6, -0.9], [-3.6, 13.5], [4.2, 17], [7.8, 21.6], [-1.4, 24.6], [6.5, 9.4], [-4.8, 26.4], [3.2, 26.2], [9.6, 12.8]]
const LOCKER := Vector3(2.49, 0.93, 31.32)  # the padlock on Ray's locker

var seed_ := 0
var items: Array = []  # what's in your pockets (ids)
var found := {}  # id -> true: found for good
var searched := {}  # today's: bins, dropped money
var hatch := false  # the roof hatch's padlock is off
var logged_in := false
var roof := false  # you've made it up there
var aim := {}  # { spot } | { bill } | { locker } | { register }
var term = null  # at the register as Ray: { page, pin, msg }

var _spots := {}  # id -> { area, search, at, r, gives }
var _codes := { "locker": "", "hatch": "", "pin": "" }
var _notes := {}  # item id -> what's written on it
var _key_at := ""
var _typed := ""
var _typing := ""  # which padlock you're looking at
var _bills: Array = []  # { id, node, cash }
var _pin_tries := 0
var _locked_day := 0
var _took_cash := 0
var _panel := Label.new()
var _layer := CanvasLayer.new()
var _show_notes := false
var _closers := {}

@onready var main: Node = get_parent()
@onready var cm: Node = $"../Customer"
@onready var hud: CanvasLayer = $"../HUD"
@onready var player: CharacterBody3D = $"../Player"
@onready var checkout: Node = $"../Checkout"
@onready var interact: Node = $"../Interact"
@onready var fixtures: Node = $"../Fixtures"


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_panel.add_theme_font_override("font", font)
	_panel.add_theme_font_size_override("font_size", 16)
	_panel.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	_panel.add_theme_color_override("font_outline_color", Color.BLACK)
	_panel.add_theme_constant_override("outline_size", 8)
	_panel.position = Vector2(60, 150)
	_layer.add_child(_panel)
	add_child(_layer)


func on() -> bool:
	return cm.on()


func setup() -> void:  # from the store file's seed: the codes, and which spot holds what (cmTrailSet)
	if seed_ == 0:
		seed_ = 1 + randi() % 2147483000
	var sd := [seed_]
	var rnd := func() -> float:
		sd[0] = (sd[0] * 16807) % 2147483647
		return sd[0] / 2147483647.0
	var pick := func(a: Array): return a[int(rnd.call() * a.size())]
	_codes.locker = str(100 + int(rnd.call() * 900))
	_codes.hatch = str(1000 + int(rnd.call() * 9000))
	_codes.pin = str(1000 + int(rnd.call() * 9000))
	var T: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).things
	var reg: Dictionary = T.register
	_spots = {
		"cushions": ["public", "between the couch cushions", Vector3(0.0, 0.5, 23.3), 0.6], "coffee": ["public", "under the coffee table", Vector3(0.0, 0.22, 24.44), 0.3],
		"tank": ["public", "under the toilet tank lid", Vector3(10.25, 0.82, 32.79), 0.22], "bin:restroom": ["public", "", Vector3.ZERO, 0.0], "bin:lobby": ["public", "", Vector3.ZERO, 0.0],
		"jacket": ["break", "the jean jacket's pockets", Vector3(2.17, 1.3, 31.97), 0.22], "vest": ["break", "the spare vest's pocket", Vector3(2.17, 1.38, 32.66), 0.2],
		"pizza": ["break", "under the empty Tony's box", Vector3(4.22, 0.79, 31.67), 0.22], "timecard": ["break", "the time cards in the rack", Vector3(6.88, 1.32, 30.0), 0.24],
		"keyboard": ["counter", "under the register keyboard", Vector3(-5.45, 1.14, 3.72), 0.16], "pad": ["counter", "under the desensitizer pad", Vector3(reg.pad[0], reg.pad[1], reg.pad[2]), 0.15],
		"printer": ["counter", "around the receipt printer", Vector3(reg.printer[0], reg.printer[1], reg.printer[2]), 0.15],
	}
	var ids := func(area: String) -> Array: return _spots.keys().filter(func(k: String) -> bool: return _spots[k][0] == area)
	_key_at = pick.call(ids.call("public"))
	var note_at: String = pick.call(ids.call("break").filter(func(k: String) -> bool: return k != "timecard"))
	var pin_at: String = pick.call(ids.call("counter"))
	var L: String = _codes.locker
	_notes = { "comboNote": "Ray —\nYour locker combo starts\n%s - %s - ?\nThe last number's on your time\ncard, like ALWAYS. Don't make\nme come find you!!      — D" % [L[0], L[1]],
		"pinNote": "RAY\nPIN %s\n(DON'T TELL MGR)" % " - ".join(_codes.pin.split("")),
		"printout": "MSG FROM: MGR\n----------------------\nROOF HATCH LOCK IS\n%s\nAC GUY THURS. NOBODY\nELSE GOES UP THERE.\n----------------------" % " - ".join(_codes.hatch.split("")) }
	for id: String in _spots:
		var gives := {}
		if id == _key_at:
			gives = { "item": "breakKey", "found": "A key on a red tag: BREAK RM. Somebody's going to be looking for that" }
		elif id == note_at:
			gives = { "item": "comboNote", "cash": 1.0, "found": "A folded note (and a dollar)" }
		elif id == pin_at:
			gives = { "item": "pinNote", "found": "A post-it with a number on it, stuck where nobody'd see it" }
		elif id == "timecard":
			gives = { "info": "Ray's time card, in the rack. In the corner, in pencil, circled: %s" % L[2] }
		else:
			gives = { "cash": 0.25 if rnd.call() < 0.25 else 0.0, "nothing": pick.call(NOTHING) }
		_spots[id].append(gives)


func has(id: String) -> bool:
	return items.has(id)


func give(id: String) -> void:  # into your pockets (cmGive)
	items.append(id)
	found[id] = true
	if _notes.has(id):
		hud.toast("%s:  %s" % [ITEMS[id], _notes[id].replace("\n", " / ")])


func _spent() -> void:  # used up: the note once the locker's open, the post-it once you're logged in, the printout once the hatch is
	for id: String in items.duplicate():
		if (id == "comboNote" and found.has("combo:locker")) or (id == "pinNote" and logged_in) or (id == "printout" and hatch):
			items.erase(id)
			hud.toast("Tossed the %s: you won't need it again" % ITEMS[id].to_lower())


func notice(n: float) -> void:  # a little noise out on the floor: whoever sees it thinks a bit less of you (cmNotice)
	if cm.seen():
		cm.trust = maxf(0.0, cm.trust - n)


func status() -> String:
	return " · " + ", ".join(items.map(func(id: String) -> String: return ITEMS[id])) if not items.is_empty() else ""


func morning() -> void:  # the day's dropped money: a few bills on the lot and the floor, where nobody's noticed yet (cmMoneyDrop). And the back's locked up overnight
	searched.clear()
	_pin_tries = 0
	for b: Dictionary in _bills:
		b.node.queue_free()
	_bills.clear()
	var sd := [104729 * Clock.day + 7]
	var rnd := func() -> float:
		sd[0] = (sd[0] * 16807) % 2147483647
		return sd[0] / 2147483647.0
	var spots := MONEY_SPOTS.duplicate()
	spots.shuffle()
	for i in 2 + int(rnd.call() * 3.0):
		var cash := 5.0 if rnd.call() < 0.12 else 1.0
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 0.004, 0.066)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.hex(0xc9d6b4ff)
		box.material = m
		mi.mesh = box
		mi.position = Vector3(spots[i][0], main.get_node("Shoppers")._floor_y(Vector3(spots[i][0], 0.5, spots[i][1])) + 0.006, spots[i][1])
		mi.rotation.y = rnd.call() * TAU
		add_child(mi)
		_bills.append({ "id": "money%d-%d" % [Clock.day, i], "node": mi, "cash": cash })
	for d: Dictionary in _keyed().values():
		if d.open:
			interact.toggle_door(d)
		d.by_you = false


func _keyed() -> Dictionary:  # the doors you need a key for (staff walk through them all day: a door left open is a way in)
	var out := {}
	for d: Dictionary in interact.doors:
		if d.push:
			continue
		var mid := Vector2((d.shut.x0 + d.shut.x1) / 2.0, (d.shut.z0 + d.shut.z1) / 2.0)
		if mid.distance_to(Vector2(5.0, 29.8)) < 0.6:
			out["breakKey"] = d
		elif mid.distance_to(Vector2(11.0, 28.9)) < 0.6:
			out["closetKey"] = d
	return out


func door(d: Dictionary) -> bool:  # E on a door, as a customer -> true if that's dealt with (locked, and you've no key)
	if not on():
		return false
	var keyed := _keyed()
	for key: String in keyed:
		if keyed[key] == d:
			if not d.open and not has(key):
				d.rattle = 0.35
				$"../Ambience".door("wood", "rattle", interact._door_at(d))
				hud.toast("Locked. The %s needs a key" % ("break room" if key == "breakKey" else "janitor's closet"))
				return true
			d.by_you = not d.open  # (one you unlocked yourself stays open)
	return false


func hatch_locked() -> bool:  # a customer: the hatch up top's padlocked
	if not on() or hatch or player.global_position.y > 3.3:
		return false
	hud.toast("The roof hatch · a combination padlock. Type the numbers")
	return true


func search_bin(b: Dictionary) -> void:  # a trash can: once a day, worth a look (change, now and then) (cmSearchBin)
	if _key_at == "bin:" + b.id and not found.has(_key_at):
		give("breakKey")
		found[_key_at] = true
		hud.toast("You dig through the %s. Under the paper towels: a key on a red tag, BREAK RM" % b.name)
		notice(4.0)
		return
	if searched.has(b.id):
		hud.toast("Already been through that one today")
		return
	searched[b.id] = true
	var r := fposmod((7919 * Clock.day + b.id.length() * 31 + b.n) * 16807.0, 2147483647.0) / 2147483647.0
	var cash: float = [0.25, 0.5, 0.35, 1.0, 0.75][int(r * 100.0) % 5] if r < 0.35 else 0.0
	cm.wallet += cash
	hud.toast("You dig through the %s: $%.2f in change" % [b.name, cash] if cash > 0.0 else "You dig through the %s. Nothing but trash" % b.name)
	notice(4.0)


# ---- the crosshair on any of it (called from interact.gd)

func take_aim(hit: Dictionary, hit_d: float) -> String:
	aim = {}
	_typing = "hatch" if on() and fixtures.aim == "hatch" and not hatch and player.global_position.y < 3.3 else ""
	if not on() or not hit or hit_d > 2.4:
		return ""
	var at: Vector3 = hit.position
	for b: Dictionary in _bills:
		if at.distance_to(b.node.position) < 0.2:
			aim = { "bill": b }
			return "E — pick it up"
	if at.distance_to(LOCKER) < 0.3:
		aim = { "locker": true }
		if not found.has("combo:locker"):
			_typing = "locker"
			return "Ray's locker · a combination padlock\ntype the numbers: %s" % " ".join(range(3).map(func(i: int) -> String: return _typed[i] if i < _typed.length() else "_"))
		return "E — take Ray's employee badge\nRay's locker, open" if not found.has("badge") else "Ray's locker\nopen"
	if at.distance_to(checkout._at.pos) < 0.42:
		aim = { "register": true }
		return "E — log in to the register (Ray's badge)" if has("badge") or logged_in else "The register\nlogged out. It wants an employee badge"
	for id: String in _spots:
		var s: Array = _spots[id]
		if s[3] > 0.0 and not found.has(id) and at.distance_to(s[2]) < s[3]:
			aim = { "spot": id }
			return "E — look %s" % s[1]
	return ""


func on_e() -> bool:
	if term != null:
		term = null
		return true
	if aim.is_empty():
		return false
	if aim.has("bill"):
		var b: Dictionary = aim.bill
		cm.wallet += b.cash
		b.node.queue_free()
		_bills.erase(b)
		hud.toast("A five, folded up on the floor. Finders keepers" if b.cash > 1.0 else "A dollar bill. Finders keepers")
	elif aim.has("locker"):
		if not found.has("combo:locker"):
			hud.toast("Type the combination on the number keys")
		elif not found.has("badge"):
			give("badge")
			hud.toast("Took Ray's employee badge")
		else:
			hud.toast("Ray's locker. Nothing else in there worth taking")
	elif aim.has("register"):
		var p := player.global_position
		if not (has("badge") or logged_in):
			hud.toast("The register's logged out. It wants an employee badge")
		elif not (p.x < -2.6 and p.z > 0.0 and p.z < 3.65):
			hud.toast("You'd have to be behind the counter to use it")
		elif _locked_day == Clock.day:
			hud.toast("The register's locked: SEE MANAGER. Not today")
		else:
			term = { "page": "menu" if logged_in else "login", "pin": "", "msg": "" }
	elif aim.has("spot"):  # a place to look: what's there (if anything), and it's searched (cmSearch)
		var id: String = aim.spot
		var s: Array = _spots[id]
		var g: Dictionary = s[4]
		var p := player.global_position
		if s[0] == "counter" and not (p.x < -2.6 and p.z > 0.0 and p.z < 3.65):
			hud.toast("You can't get at it from this side of the counter")
			return true
		found[id] = true
		cm.wallet += g.get("cash", 0.0)
		if g.has("item"):
			give(g.item)
			hud.toast("You search %s. %s" % [s[1], g.found])
		elif g.has("info"):
			hud.toast(g.info)
		else:
			hud.toast("You search %s. %s" % [s[1], "A quarter. %s else" % g.nothing.get_slice(".", 0) if g.cash > 0.0 else g.nothing])
		if s[0] != "public" or g.has("item"):
			notice(2.0)
	return true


func _digit(d: String) -> void:  # a digit typed at a padlock (cmComboKey)
	var code: String = _codes[_typing]
	_typed += d
	if _typed.length() < code.length():
		return
	if _typed != code:
		_typed = ""
		hud.toast("The shackle doesn't budge")
		return
	_typed = ""
	if _typing == "hatch":
		hatch = true
		hud.toast("The padlock on the hatch drops open. The roof's yours")
	else:
		found["combo:locker"] = true
		hud.toast("The padlock clicks open. Ray's locker: a can of Skoal, a Walkman, and his employee badge")
	_spent()


func _term_key(k: int) -> void:  # the register, logged in as Ray: what the store knows (cmTermKey)
	if k in [KEY_E, KEY_Q, KEY_ESCAPE]:
		term = null
		return
	term.msg = ""
	var digit := k - KEY_0 if k >= KEY_0 and k <= KEY_9 else -1
	match term.page:
		"login":
			if digit >= 0:
				term.pin += str(digit)
			if term.pin.length() == 4:
				if term.pin == _codes.pin:
					logged_in = true
					term.page = "menu"
					hud.toast("Logged into the register as Ray")
					_spent()
				else:
					_pin_tries += 1
					if _pin_tries >= 3:
						_locked_day = Clock.day
						_pin_tries = 0
						term = null
						hud.toast("INVALID PIN. TERMINAL LOCKED: SEE MANAGER. It won't take another try today")
						return
					term.msg = "INVALID PIN"
				term.pin = ""
		"menu":
			if digit >= 1 and digit <= 4:
				term.page = ["msgs", "you", "sched", "drawer"][digit - 1]
				if term.page == "drawer":  # NO SALE: the drawer pops with a ding, and anyone close enough hears it
					for e: Node in main.get_node("Staff").crew:
						if e.dana != null and e.dana.position.distance_to(player.global_position) < 9.0:
							cm.heat = minf(0.95, cm.heat + 0.45)
							e.dana.set_mood("shock")
		"drawer":
			if k == KEY_B:
				term.page = "menu"
			elif k == KEY_K and not found.has("drawerKey"):
				give("closetKey")
				found["drawerKey"] = true
				term.msg = "THE JANITOR'S KEY. (it's in your pocket)"
			elif k == KEY_M and _took_cash != Clock.day:
				_took_cash = Clock.day
				cm.wallet += 20.0
				main.get_node("Shift").budget -= 20.0
				cm.day.stolen += 1
				term.msg = "A TWENTY. (nobody saw. probably)"
		"msgs":
			if k == KEY_B:
				term.page = "menu"
			elif k == KEY_P:
				if has("printout") or hatch:
					term.msg = "PAPER JAM. (you don't need it anyway)" if hatch else "ALREADY PRINTED"
				else:
					give("printout")
					term.msg = "PRINTED. (it's in your pocket)"
		"you":
			if k == KEY_B:
				term.page = "menu"
			elif k == KEY_W and cm.owed > 0.0:
				term.msg = "WAIVED $%.2f" % cm.owed
				cm.owed = 0.0
		_:
			if k == KEY_B:
				term.page = "menu"


func _term_text() -> String:
	var st: Node = main.get_node("Staff")
	var head := "VAULTBUSTER VIDEO #0417      %s\n%s\n" % ["SIGN IN " if term.page == "login" else "USER: RAY", "=".repeat(38)]
	var body := ""
	match term.page:
		"msgs": body = "MESSAGES (1)\n\nFROM: MGR\nRE: roof\n\nRoof hatch lock is %s.\nAC guy Thurs. NOBODY else goes\nup there. I mean it.\n\n[P] PRINT IT   [B] BACK" % "-".join(_codes.hatch.split(""))
		"you": body = "CUSTOMER LOOKUP: WALK-IN\n\nRENTALS OUT ...... %d\nFEES OWED ........ $%.2f\nTRUST ............ %s\n\n%s[B] BACK" % [cm.rented.size(), cm.owed, "REGULAR" if cm.regular() else "FRIENDLY" if cm.trust >= 25.0 else "NEW FACE", "[W] WAIVE FEES   " if cm.owed > 0.0 else ""]
		"sched":
			body = "TODAY'S SCHEDULE\n\n"
			for w: Dictionary in st.roster:
				var bits: Array = range(15).filter(func(b: int) -> bool: return (int(w.sched[Clock.date().weekday]) >> b) & 1 == 1)
				body += "%s %s\n" % [w.first.to_upper().rpad(10), "%s - %s" % [Clock.fmt_clock(9.0 + bits[0]), Clock.fmt_clock(10.0 + bits[-1])] if not bits.is_empty() else "OFF"]
			body += "\n[B] BACK"
		"login": body = "BADGE ..... RAY (ACCEPTED)\nPIN ....... %s\n\nTYPE THE PIN ON THE NUMBER KEYS\n%s\n[E] CANCEL" % [" ".join(range(4).map(func(i: int) -> String: return "*" if i < term.pin.length() else "_")), "%d TRIES LEFT\n" % (3 - _pin_tries) if _pin_tries > 0 else ""]
		"drawer": body = "NO SALE\n\nTHE DRAWER'S OPEN. TWENTIES, TENS,\nROLLS OF QUARTERS%s.\n\n%s%s[B] SHUT THE DRAWER" % ["" if found.has("drawerKey") else ", AND UNDER THE\nTRAY: A STEEL KEY ON A YELLOW TAG", "" if found.has("drawerKey") else "[K] TAKE THE KEY\n", "" if _took_cash == Clock.day else "[M] TAKE A TWENTY\n"]
		_: body = "[1] MESSAGES\n[2] CUSTOMER LOOKUP\n[3] SCHEDULE\n[4] NO SALE (OPEN THE DRAWER)\n\n[E] LOG OUT"
	return head + body + ("\n\n> " + term.msg if term.msg != "" else "")


func _unhandled_input(e: InputEvent) -> void:
	if not on() or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k: int = e.physical_keycode
	if term != null:
		_term_key(k)
		get_viewport().set_input_as_handled()
	elif _typing != "" and k >= KEY_0 and k <= KEY_9:
		_digit(str(k - KEY_0))
		get_viewport().set_input_as_handled()
	elif k == KEY_N:
		_show_notes = not _show_notes


func _process(dt: float) -> void:
	_layer.visible = on() and (term != null or _show_notes or _typing == "hatch")
	if not on():
		return
	if _spots.is_empty():
		setup()
	if _typing == "":
		_typed = ""  # (looked away: start the combination over)
	if term != null:
		_panel.text = _term_text()
	elif _typing == "hatch":
		_panel.text = "The roof hatch · a combination padlock\ntype the numbers: %s" % " ".join(range(4).map(func(i: int) -> String: return _typed[i] if i < _typed.length() else "_"))
	elif _show_notes:
		_panel.text = "IN YOUR POCKETS · N to put them away\n\n" + ("\n\n".join(items.map(func(id: String) -> String: return ITEMS[id].to_upper() + ("\n" + _notes[id] if _notes.has(id) else ""))) if not items.is_empty() else "Nothing but your wallet")
	if player.global_position.y > 3.3 and not roof:
		roof = true
		hud.toast("You made it up on the roof. Nobody knows you're here")
	var staff_near := func(at: Vector2) -> bool: return main.get_node("Staff").crew.any(func(e: Node) -> bool: return e.dana != null and Vector2(e.dana.position.x, e.dana.position.z).distance_to(at) < 1.8)
	for d: Dictionary in _keyed().values():  # a door on a closer: one the staff left open swings shut once nobody's in it (unless you unlocked it yourself)
		var mid := Vector2((d.shut.x0 + d.shut.x1) / 2.0, (d.shut.z0 + d.shut.z1) / 2.0)
		if not d.open or d.get("by_you", false) or Vector2(player.global_position.x, player.global_position.z).distance_to(mid) < 1.6 or staff_near.call(mid):
			_closers[mid] = 0.0
		else:
			_closers[mid] = _closers.get(mid, 0.0) + dt
			if _closers[mid] > 3.0:
				_closers[mid] = 0.0
				interact.toggle_door(d)


# ---- for the save

func snapshot() -> Dictionary:
	return { "seed": seed_, "items": items, "found": found.keys(), "searched": searched.keys(), "hatch": hatch, "in": logged_in, "roof": roof, "locked": _locked_day, "cash": _took_cash }


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	seed_ = int(d.seed)
	items = d.items
	for k: String in d.found:
		found[k] = true
	for k: String in d.searched:
		searched[k] = true
	hatch = d.hatch
	logged_in = d["in"]
	roof = d.roof
	_locked_day = int(d.locked)
	_took_cash = int(d.cash)
