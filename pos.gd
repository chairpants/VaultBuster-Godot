extends CanvasLayer
## VaultBuster POS/NET: the register's terminal, a menu-driven rental system. E on the register (when there's no
## sale waiting on it) logs you in. Type a selection or a command and ENTER; ESC goes back a screen; F10 logs off.
## The store keeps running while you're at it.
## Inventory (title search, sections, the returns bin, replacement copies for what's been stolen), members (lookup,
## all accounts, overdue and late fees), reports (rentals out, the daily summary, messages: the calls that were
## missed), supplies (cases of snacks and drinks, in the cupboards tomorrow morning), the preview station, and the
## security gates (arm, disarm, silence the alarm).
## From the web game's pos.js: the same screens (listScreen, prompt, titleDetail, custDetail, MENU, mainMenu's
## commands) over this store's tapes and members, and painted as it paints them: the blue screen, its colours, the
## frame, the logo, the key bar, scanlines (the font's VT323, in fonts/). It's on a screen over the game here.
## The arrows walk a list's records or the menu's lines (ENTER opens the highlighted one), and the mouse does the same:
## what it's over is highlighted, a click picks it or presses a key on the bar, the wheel turns pages.
## Not over yet: the picture on the register's own monitor, the sale window,
## SYSRESET (F9 does that). An order's in boxes by the front doors next morning (snacks.gd); a replacement tape's in the returns bin.

const COLS := 80
const BODY := 22  # body rows under the header

var open := false
var notes: Array = []  # the message center: [{ day, text, read }]
var replacements: Array = []  # ordered, here tomorrow: tapes

var _screen := {}  # { title, lines: Callable -> Array[String], prompt, submit: Callable(String), pager }
var _stack: Array = []
var _input := ""
var _msg := ""
var _text := Label.new()  # (the screen's lines as plain text: what the tests read)
var _titles := {}  # title -> its copies
var _blink := 0.0

@onready var main: Node = get_parent()
@onready var tapes: Node = $"../Tapes"
@onready var shoppers: Node = $"../Shoppers"
@onready var shift: Node = $"../Shift"
@onready var snacks: Node = $"../Snacks"
@onready var player: CharacterBody3D = $"../Player"


func _ready() -> void:
	layer = 6
	visible = false
	var dim := ColorRect.new()  # the store, dimmed behind it
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	add_child(_view)
	_view.draw.connect(_paint)
	_font = load(FONT) if ResourceLoader.exists(FONT) else null
	if _font == null:  # (not imported yet: straight off the disk; and with no file at all, whatever monospace there is)
		_font = FontFile.new()
		if _font.load_dynamic_font(FONT) != OK:
			_font = SystemFont.new()
			_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	if _font is FontFile:  # (what VT323 hasn't got, the title bar's arrow for one: from whatever monospace there is)
		var more := SystemFont.new()
		more.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		_font.fallbacks = [more]
	var grad := Gradient.new()  # the tube's falloff toward its corners
	grad.offsets = PackedFloat32Array([0.337, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)])
	_vignette.gradient = grad
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(0.5, 1.45)
	for k: String in MARKS:
		_re[k] = RegEx.create_from_string(MARKS[k])


# ---- formatting, and the store's data

func L(s, n: int) -> String:
	return str(s).rpad(n).left(n)


func R(s, n: int) -> String:
	return str(s).lpad(n).right(n)


func _date(day: int) -> String:
	var first := Time.get_unix_time_from_datetime_dict({ "year": 1996, "month": 9, "day": 30, "hour": 12, "minute": 0, "second": 0 })
	var d := Time.get_datetime_dict_from_unix_time(first + (day - 1) * 86400)
	return "%02d/%02d/%s" % [d.month, d.day, str(d.year).right(2)]


func _copies(title: String) -> Array:
	if _titles.is_empty():
		for t: Dictionary in tapes.tapes:
			_titles.get_or_add(t.t, []).append(t)
	return _titles.get(title, [])


func _in(title: String) -> int:
	return _copies(title).filter(func(c: Dictionary) -> bool: return not c.off).size()


func _rental(c: Dictionary) -> Variant:  # [tape, out, due, member #], or null
	for r: Array in shoppers.rented:
		if r[0] == c:
			return r
	return null


func _late(r: Array) -> int:
	return maxi(0, Clock.day - int(r[2]))


func _fees(m: Dictionary) -> float:  # on the account, plus what the late ones out now are running up
	var f: float = m.owed
	for r: Array in shoppers.rentals_of(m):
		f += _late(r) * (2.0 if r[0].n else 1.0)
	return f


func _full(m: Dictionary) -> String:
	return "%s, %s" % [m.last, m.first]


func _phone(m: Dictionary) -> String:
	return "555-%04d" % (m.num * 7919 % 10000)


func _status(c: Dictionary) -> String:
	var r: Variant = _rental(c)
	if c.get("lib", false):
		return "NOT CARRIED (LIBRARY UPGRADE)"
	if c.get("lost", false):
		return "LOST - STOLEN"
	if c == tapes.held:
		return "IN HAND (STAFF)"
	if tapes.return_bin.has(c):
		return "IN RETURNS BIN"
	if tapes.playing != null and tapes.playing.tape == c:
		return "IN LOUNGE VCR"
	if r != null and r.size() > 3:
		return "OUT #%d DUE %s%s" % [r[3], _date(r[2]), " LATE %dD" % _late(r) if _late(r) > 0 else ""]
	return "UNACCOUNTED" if c.off else "ON SHELF"


# ---- the overdue calls (pos.js: CALL_DAYS, LOST_DAYS, lateOf, toCall, needsCall, lateSummary, recordCall, callScreen)

const CALL_DAYS := 5  # this late, and somebody ought to ring them
const LOST_DAYS := 14  # ...and this late, after two calls, the tape's billed as lost


func late_of(m: Dictionary) -> Array:
	return shoppers.rentals_of(m).filter(func(r: Array) -> bool: return _late(r) >= CALL_DAYS)


func needs_call(m: Dictionary) -> bool:  # (a promise not kept in two days: back on the list)
	return not late_of(m).is_empty() and m.promise < Clock.day - 2


func to_call() -> Array:  # the worst first
	var out: Array = shoppers.members.all.filter(needs_call)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _worst(a) > _worst(b))
	return out


func _worst(m: Dictionary) -> int:
	return late_of(m).reduce(func(a: int, r: Array) -> int: return maxi(a, _late(r)), 0)


func late_summary(m: Dictionary) -> String:
	var n := late_of(m).size()
	return "%d TAPE%s %dD LATE" % [n, "" if n == 1 else "S", _worst(m)] if n > 0 else ""


func record_call(m: Dictionary, promise: bool, result: String) -> void:
	m.calls += 1
	m.last_call = Clock.day
	m.last_result = result.to_upper()
	if promise:
		m.promise = Clock.day
		$"../HUD".toast("Called %s about their overdue tape%s: they'll bring %s in" % [shoppers.members.name_of(m), "" if shoppers.rentals_of(m).size() == 1 else "s", "it" if shoppers.rentals_of(m).size() == 1 else "them"])


func _call_screen(m: Dictionary) -> void:
	_go({ "title": "OVERDUE CALL - %s #%d" % [_full(m), m.num], "prompt": "L TO BILL AS LOST, ESC",
		"lines": func() -> Array:
			var out: Array = ["", " MEMBER...: %s  #%d" % [_full(m), m.num], " PHONE....: %s" % _phone(m), " LOYALTY..: %s" % ("REGULAR" if m.loyalty > 30.0 else "UNHAPPY" if m.loyalty < -30.0 else "OK"), "", " OVERDUE:"]
			for r: Array in late_of(m):
				out.append("   %s %s  %s" % [L(r[0].t.to_upper(), 44), R("%d DAYS" % _late(r), 8), R("$%.2f" % (_late(r) * (2.0 if r[0].n else 1.0)), 8)])
			out.append_array(["", " CALLS....: %d%s" % [m.calls, "  (LAST %s)" % _date(m.last_call) if m.calls > 0 else ""]])
			if m.last_result != "":
				out.append(" LAST CALL: %s" % m.last_result)
			out.append(" CALLED TODAY. TRY AGAIN TOMORROW." if m.last_call == Clock.day else " A POST-IT'S BY THE STORE PHONE: CALL THEM FROM THERE.")
			if m.promise > -9:
				out.append(" PROMISED.: %s - NOT IN YET" % _date(m.promise))
			out.append_array(["", " L: BILL THE TAPES AS LOST (REPLACEMENT COST GOES ON THEIR ACCOUNT)" if _worst(m) >= LOST_DAYS and m.calls >= 2 else " (BILL AS LOST: AFTER %d DAYS AND 2 CALLS)" % LOST_DAYS])
			return out,
		"submit": func(v: String) -> void:
			if v != "L":
				_msg = "L TO BILL AS LOST. CALL FROM THE STORE PHONE."
			elif _worst(m) < LOST_DAYS or m.calls < 2:
				_msg = "NOT YET: %d DAYS LATE AND 2 CALLS FIRST." % LOST_DAYS
			else:
				for r: Array in late_of(m):  # what it costs to replace, and the fee it ran up, on their account; the copy's a lost one now (B reorders it)
					m.owed = snappedf(m.owed + (64.95 if r[0].n else 24.95) + _late(r) * (2.0 if r[0].n else 1.0), 0.01)
					shoppers.rented.erase(r)
					r[0].lost = true
				m.promise = -9
				_back()
				_msg = "BILLED AS LOST. REORDER FROM B - REPLACEMENT COPIES." })


func inbox() -> int:  # what's waiting in the message center: calls not made today, unread notes
	return to_call().filter(func(m: Dictionary) -> bool: return m.last_call != Clock.day).size() + notes.filter(func(n: Dictionary) -> bool: return not n.read).size()


func message(text: String) -> void:  # a note in the message center
	notes.append({ "day": Clock.day, "text": text.to_upper(), "read": false })
	if notes.size() > 40:
		notes.pop_front()


# ---- screens

func _go(s: Dictionary) -> void:
	if not _screen.is_empty():
		_stack.append(_screen)
	_screen = s
	_input = ""
	_msg = ""


func _back() -> void:
	_input = ""
	_msg = ""
	if _stack.is_empty():
		log_off()
	else:
		_screen = _stack.pop_back()


func _list(title: String, head: String, items: Array, row: Callable, on_pick: Callable, empty := "NO RECORDS FOUND.") -> Dictionary:  # a paged, numbered pick list
	var per := BODY - 2
	var page := [0]
	var pages := maxi(1, ceili(float(items.size()) / per))
	var pick := { "cur": 0, "n": items.size() if on_pick.is_valid() else 0, "per": per, "page": page }  # the arrows walk the records (turning pages as needed); ENTER opens the highlighted one
	return { "title": "%s  (%d RECORD%s)" % [title, items.size(), "" if items.size() == 1 else "S"], "pager": true, "prompt": "RECORD # OR N/P" if on_pick.is_valid() else "N/P OR ESC", "pick": pick,
		"lines": func() -> Array:
			if items.is_empty():
				return ["", " " + empty]
			var out: Array = [HEAD + head]
			for i in range(page[0] * per, mini(items.size(), page[0] * per + per)):
				out.append(row.call(items[i], i + 1))
			while out.size() < per + 1:
				out.append("")
			out.append(R("PAGE %d OF %d " % [page[0] + 1, pages], COLS - 1))
			return out,
		"submit": func(v: String) -> void:
			if v == "N":
				if page[0] < pages - 1:
					page[0] += 1
					pick.cur = page[0] * per
				else:
					_msg = "LAST PAGE."
			elif v == "P":
				if page[0] > 0:
					page[0] -= 1
					pick.cur = page[0] * per
				else:
					_msg = "FIRST PAGE."
			elif on_pick.is_valid() and v.is_valid_int() and int(v) >= 1 and int(v) <= items.size():
				on_pick.call(items[int(v) - 1])
			else:
				_msg = "INVALID SELECTION." }


func _ask(title: String, label: String, help: String, on_value: Callable) -> Dictionary:
	return { "title": title, "prompt": label, "lines": func() -> Array: return ["", " " + help],
		"submit": func(v: String) -> void:
			if v != "":
				on_value.call(v)
			else:
				_msg = "ENTRY REQUIRED." }


func _info(title: String, lines: Callable) -> Dictionary:
	return { "title": title, "prompt": "ESC TO RETURN", "lines": lines, "submit": func(_v: String) -> void: _back() }


const TITLE_HEAD := "      TITLE                                SECTION              CPY  IN"


func _title_row(t: String, n: int) -> String:
	return " %s  %s %s %s %s" % [R(n, 3), L(t.to_upper(), 36), L(_copies(t)[0].c.to_upper(), 20), R(_copies(t).size(), 3), R(_in(t), 3)]


func _title_detail(t: String) -> void:
	var cs := _copies(t)
	var is_new: bool = cs[0].n
	_go({ "title": ("TITLE INQUIRY - %s" % t.to_upper()).left(COLS - 4), "prompt": "COPY # FOR RENTER, ESC",
		"lines": func() -> Array:
			var out: Array = [(" TITLE....: %s" % t.to_upper()).left(COLS), " SECTION..: %s        FORMAT: %s" % [cs[0].c.to_upper(), "TV SERIES, %d EP" % cs[0].e.size() if cs[0].e.size() > 1 else "FEATURE"],
				" CLASS....: %s" % ("NEW RELEASE  2-NIGHT $3.99   LATE $2.00/DAY" if is_new else "CATALOG  5-NIGHT $1.99   LATE $1.00/DAY"),
				" STOCK....: %d COPIES, %d IN / %d OUT" % [cs.size(), _in(t), cs.size() - _in(t)]]
			for h: Dictionary in main.get_node("Phone").holds.filter(func(h: Dictionary) -> bool: return h.title == t):
				out.append((" REQUEST..: HOLD FOR %s, IN ~%s" % [_full(h.member), Clock.fmt_clock(h.at)]).left(COLS))
			out.append_array(["", "  COPY  STATUS"])
			for i in mini(12, cs.size()):
				out.append("  %02d    %s" % [i + 1, _status(cs[i])])
			if cs.size() > 12:
				out.append("  ... %d MORE" % (cs.size() - 12))
			return out,
		"submit": func(v: String) -> void:
			var c: Variant = cs[int(v) - 1] if v.is_valid_int() and int(v) >= 1 and int(v) <= cs.size() else null
			var r: Variant = _rental(c) if c != null else null
			if r != null and r.size() > 3 and shoppers.members.by_num.has(r[3]):
				_member_detail(shoppers.members.by_num[r[3]])
			else:
				_msg = "COPY IS NOT CHECKED OUT." if c != null else "INVALID SELECTION." })


const MEMBER_HEAD := "       MEMBR  NAME                       PHONE     OUT      FEES"


func _member_row(m: Dictionary, n: int) -> String:
	return " %s  %s  %s %s %s  %s" % [R(n, 3), R(m.num, 6), L(_full(m), 26), L(_phone(m), 9), R(shoppers.rentals_of(m).size(), 3), R("$%.2f" % _fees(m) if _fees(m) > 0.0 else "-", 8)]


func _member_detail(m: Dictionary) -> void:
	_go({ "title": "MEMBER INQUIRY - #%d" % m.num, "prompt": "RENTAL # FOR TITLE, ESC",
		"lines": func() -> Array:
			var rs: Array = shoppers.rentals_of(m)
			var stars := "*".repeat(roundi((m.loyalty + 100.0) / 40.0)).rpad(5, ".")
			var out: Array = [" MEMBER #.: %d" % m.num, " NAME.....: %s" % _full(m), " PHONE....: %s" % _phone(m),
				" STATUS...: %s" % ("*** ARRESTED - DO NOT RENT ***" if m.status == "arrested" else "*** MEMBERSHIP CANCELLED ***" if m.status == "cancelled" else "*** BANNED UNTIL %s ***" % _date(m.until) if m.status == "banned" and m.until > Clock.day
					else "FEES DUE $%.2f - COLLECT BEFORE RENTAL" % _fees(m) if _fees(m) > 0.0 else "ACTIVE" if not rs.is_empty() else "GOOD STANDING"),
				" LOYALTY..: %s  %s" % [stars, "REGULAR" if m.loyalty >= 40.0 else "UNHAPPY" if m.loyalty <= -40.0 else ""], "",
				"  #   OUT      DUE      TITLE                                 LATE FEE" if not rs.is_empty() else "  NO RENTALS OUT."]
			for i in mini(9, rs.size()):
				out.append("  %d   %s%s%s%s" % [i + 1, L(_date(rs[i][1]), 9), L(_date(rs[i][2]), 9), L(rs[i][0].t.to_upper(), 38), "$%.2f" % (_late(rs[i]) * (2.0 if rs[i][0].n else 1.0)) if _late(rs[i]) > 0 else "-"])
			return out,
		"submit": func(v: String) -> void:
			var rs: Array = shoppers.rentals_of(m)
			if v.is_valid_int() and int(v) >= 1 and int(v) <= rs.size():
				_title_detail(rs[int(v) - 1][0].t)
			else:
				_msg = "INVALID SELECTION." })


func _find_titles(q: String) -> Array:
	_copies("")
	return _titles.keys().filter(func(t: String) -> bool: return q in t.to_upper())


func _find_members(q: String) -> Array:
	return shoppers.members.all.filter(func(m: Dictionary) -> bool: return str(m.num) == q or q in _full(m) or _phone(m).ends_with(q))


func _pick(key: String) -> bool:  # a menu selection. -> false if there's no such thing
	match key:
		"1": _go(_ask("INVENTORY - TITLE SEARCH", "TITLE (OR PART)", "ENTER ANY PART OF A TITLE.  EXAMPLE: ALIEN", func(q: String) -> void: _go(_list("TITLE SEARCH: %s" % q, TITLE_HEAD, _find_titles(q), _title_row, _title_detail))))
		"2":
			_copies("")
			var cats := {}
			for t: String in _titles:
				cats.get_or_add(_titles[t][0].c, []).append(t)
			var names: Array = cats.keys()
			names.sort()
			_go(_list("SECTIONS", "      SECTION                        TITLES  COPIES  OUT", names,
				func(c: String, n: int) -> String:
					var cp := 0
					var inn := 0
					for t: String in cats[c]:
						cp += _copies(t).size()
						inn += _in(t)
					return " %s  %s %s  %s  %s" % [R(n, 3), L(c.to_upper(), 30), R(cats[c].size(), 6), R(cp, 6), R(cp - inn, 3)],
				func(c: String) -> void: _go(_list(c.to_upper(), TITLE_HEAD, cats[c], _title_row, _title_detail))))
		"3": _go(_ask("MEMBER LOOKUP", "NAME, MEMBER # OR PHONE", "LAST NAME, PART OF A NAME, 5-DIGIT MEMBER #, OR LAST 4 OF PHONE.", func(q: String) -> void: _go(_list("MEMBER SEARCH: %s" % q, MEMBER_HEAD, _find_members(q), _member_row, _member_detail))))
		"4": _go(_list("ALL MEMBERS", MEMBER_HEAD, shoppers.members.all, _member_row, _member_detail))
		"5":
			var od: Array = shoppers.members.all.filter(func(m: Dictionary) -> bool: return _fees(m) > 0.0)
			od.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _fees(a) > _fees(b))
			_go(_list("OVERDUE ACCOUNTS", MEMBER_HEAD, od, _member_row, _member_detail, "NO OVERDUE ACCOUNTS. NICE."))
		"6":
			var out: Array = shoppers.rented.filter(func(r: Array) -> bool: return r.size() > 3 and shoppers.members.by_num.has(r[3]))
			out.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
			_go(_list("RENTALS OUT", "      TITLE                              MEMBER               DUE      LATE", out,
				func(r: Array, n: int) -> String: return " %s  %s %s %s %s" % [R(n, 3), L(r[0].t.to_upper(), 34), L(_full(shoppers.members.by_num[r[3]]), 20), _date(r[2]), R("%dD" % _late(r), 4) if _late(r) > 0 else "   -"],
				func(r: Array) -> void: _member_detail(shoppers.members.by_num[r[3]])))
		"7":
			var bin := {}
			for t: Dictionary in tapes.return_bin:
				bin[t.t] = true
			_go(_list("RETURNS BIN", TITLE_HEAD, bin.keys(), _title_row, _title_detail, "RETURNS BIN IS EMPTY."))
		"8":
			_copies("")
			var all_c: int = tapes.tapes.size()
			var in_c: int = tapes.tapes.filter(func(t: Dictionary) -> bool: return not t.off).size()
			var today: Array = shoppers.rented.filter(func(r: Array) -> bool: return r[1] == Clock.day)
			var od: Array = shoppers.rented.filter(func(r: Array) -> bool: return _late(r) > 0)
			var owing: Array = shoppers.members.all.filter(func(m: Dictionary) -> bool: return _fees(m) > 0.0)
			var fees: float = owing.reduce(func(a: float, m: Dictionary) -> float: return a + _fees(m), 0.0)
			_go(_info("DAILY SUMMARY - %s" % _date(Clock.day), func() -> Array: return [
				" TITLES IN SYSTEM........ %s      MEMBERS............ %s" % [R(_titles.size(), 8), R(shoppers.members.all.size(), 8)],
				" COPIES IN SYSTEM........ %s      ACCOUNTS W/ FEES... %s" % [R(all_c, 8), R(owing.size(), 8)],
				" COPIES ON SHELF......... %s      LATE FEES OWED..... %s" % [R(in_c, 8), R("$%.2f" % fees, 8)],
				" COPIES OUT.............. %s      RETURNS BIN........ %s" % [R(all_c - in_c, 8), R(tapes.return_bin.size(), 8)],
				" OVERDUE COPIES.......... %s" % R(od.size(), 8), "",
				" RENTALS TODAY........... %s      STORE BUDGET....... %s" % [R(today.size(), 8), R("$%.2f" % shift.budget, 10)]]))
		"M":
			var items: Array = notes.duplicate()
			items.reverse()
			items = to_call() + items  # (who wants ringing about a tape, then the notes)
			_go(_list("MESSAGE CENTER", "      WHAT", items,
				func(it: Dictionary, n: int) -> String:
					if it.has("num"):
						return " %s  %s %s" % [R(n, 3), L("CALLED" if it.last_call == Clock.day else "CALL", 6), L("%s #%d - %s%s" % [_full(it), it.num, late_summary(it), " (%d CALL%s)" % [it.calls, "" if it.calls == 1 else "S"] if it.calls > 0 else ""], 66)]
					return " %s  %s %s" % [R(n, 3), L("NOTE" if it.read else "NEW", 6), L("%s %s" % [_date(it.day), it.text], 66)],
				func(it: Dictionary) -> void:
					if it.has("num"):  # (a post-it goes by the phone)
						$"../Phone".postit_add(it)
						_call_screen(it)
						return
					it.read = true
					_go({ "title": "MESSAGE", "prompt": "D TO DELETE, ESC TO RETURN", "lines": func() -> Array: return ["", " " + _date(it.day), "", " " + it.text],
						"submit": func(v: String) -> void:
							if v == "D":
								notes.erase(it)
								_back()
							_back() }),
				"NO MESSAGES. NOBODY TO CALL."))
		"9": _go(_info("PREVIEW STATION", func() -> Array: return ["", " VCR......: PLAYING", " TAPE.....: %s" % tapes.playing.tape.t.to_upper(), " SECTION..: %s" % tapes.playing.tape.c.to_upper()] if tapes.playing != null else ["", " VCR......: EMPTY", "", " INSERT A TAPE AT THE LOUNGE TV TO PREVIEW IT."]))
		"H": _go(_info("HELP", func() -> Array: return [" FROM THE MAIN MENU YOU CAN TYPE A NUMBER, OR A COMMAND:", "",
				"   FIND <TITLE>     TITLE SEARCH            MEMBER <NAME|#>   MEMBER LOOKUP",
				"   OVERDUE          LATE FEE REPORT         OUT               RENTALS OUT",
				"   RETURNS          RETURNS BIN             REPORT            DAILY SUMMARY",
				"   VER              VERSION                 LOGOFF / EXIT     END SESSION",
				"   SUPPLIES         ORDER SNACKS/DRINKS     REPLACE           ORDER LOST COPIES",
				"   MESSAGES         MISSED CALLS, NOTES     GATES             THE GATE SYSTEM", "",
				" ESC GOES BACK ONE SCREEN. F10 LOGS OFF FROM ANYWHERE.", "",
				" SYSTEM PROBLEMS? CALL DENNIS (DISTRICT) - DO NOT REBOOT THE SERVER."]))
		"S":
			_go({ "title": "SECURITY GATE SYSTEM", "prompt": "Y TO CHANGE, ESC TO CANCEL",
				"lines": func() -> Array:
					var armed: bool = shoppers.gates_armed
					return ["", " SYSTEM STATUS..: %s" % ("ARMED" if armed else "*** DISARMED ***"), " ZONE...........: ENTRY LANE (3 PEDESTALS)", " ALARM..........: %s" % ("SOUNDING" if shoppers.alarm_on else "QUIET"), "",
						" DISARM THE GATES? TAGGED TAPES WILL PASS THROUGH WITHOUT AN ALARM." if armed else " RE-ARM THE GATES?", "",
						" STORE POLICY: GATES STAY ARMED DURING BUSINESS HOURS." if armed else " REMEMBER TO RE-ARM BEFORE OPENING."],
				"submit": func(v: String) -> void:
					if v != "Y":
						_msg = "TYPE Y TO CHANGE."
						return
					shoppers.gates_armed = not shoppers.gates_armed
					if not shoppers.gates_armed:
						shoppers.silence_alarm()
					_back()
					_msg = "GATES ARMED." if shoppers.gates_armed else "GATES DISARMED - NO ALARMS WILL SOUND." })
		"A":
			if not shoppers.alarm_on:
				return false
			_go({ "title": "SECURITY GATE CONTROL", "prompt": "Y TO SILENCE, ESC TO CANCEL",
				"lines": func() -> Array: return ["", " GATE STATUS....: ALARM", " ZONE...........: ENTRY LANE (3 PEDESTALS)", " CAUSE..........: ACTIVE SECURITY TAG DETECTED", "",
					" SILENCE THE ALARM AND RESET THE GATES?", "", " REMEMBER: CHECK THE CUSTOMER'S RECEIPT BEFORE THEY LEAVE."],
				"submit": func(v: String) -> void:
					if v != "Y":
						_msg = "TYPE Y TO SILENCE."
						return
					shoppers.silence_alarm()
					_back()
					_msg = "GATE ALARM SILENCED. GATES RE-ARMED." })
		"B":
			var lost: Array = tapes.tapes.filter(func(t: Dictionary) -> bool: return t.get("lost", false))
			_go(_list("LOST / STOLEN COPIES - BUDGET $%.2f" % shift.budget, "      TITLE                                        CLASS           COST", lost,
				func(c: Dictionary, n: int) -> String: return " %s  %s %s %s" % [R(n, 3), L(c.t.to_upper(), 44), L("NEW RELEASE" if c.n else "CATALOG", 12), R("$%.2f" % (64.95 if c.n else 24.95), 7)],
				func(c: Dictionary) -> void:
					var cost := 64.95 if c.n else 24.95  # studio pricing: new releases come in at rental-market prices
					_go({ "title": "ORDER REPLACEMENT", "prompt": "Y TO ORDER, ESC TO CANCEL",
						"lines": func() -> Array: return ["", (" TITLE....: %s" % c.t.to_upper()).left(COLS), " COST.....: $%.2f" % cost, " BUDGET...: $%.2f" % shift.budget, "",
							" ARRIVES WITH TOMORROW'S DELIVERY - IN THE RETURNS BIN." if shift.budget >= cost else " *** INSUFFICIENT BUDGET ***"],
						"submit": func(v: String) -> void:
							if v != "Y":
								_msg = "TYPE Y TO ORDER."
							elif shift.budget < cost:
								_msg = "INSUFFICIENT BUDGET."
							else:
								if c.get("lost", false):
									shift.budget -= cost
									c.lost = false
									replacements.append(c)
								_back()
								_back()
								_msg = "ORDERED: %s. BUDGET NOW $%.2f." % [c.t.to_upper(), shift.budget] }),
				"NO LOST COPIES ON FILE."))
		"O":
			var items := {}
			for u: Dictionary in snacks.units:
				if not items.has(u.n):
					items[u.n] = { "name": u.n, "drink": u.k != "", "spots": 0, "out": 0 }
				items[u.n].spots += 1
				items[u.n].out += int(not u.out)
			_go(_list("SUPPLIES - BUDGET $%.2f" % shift.budget, "      ITEM                       TYPE    RACK   STOCK  ON ORDER    CASE", items.values(),
				func(x: Dictionary, n: int) -> String: return " %s  %s %s %s %s %s %s" % [R(n, 3), L(x.name, 26), L("DRINK" if x.drink else "SNACK", 6), R("%d/%d" % [x.out, x.spots], 6), R(snacks.backstock[x.name], 6), R(snacks.orders.get(x.name, "-"), 9), R("$%.2f" % ((0.6 if x.drink else 0.45) * snacks.CASE_QTY), 7)],
				func(x: Dictionary) -> void:
					var case_cost: float = snappedf((0.6 if x.drink else 0.45) * snacks.CASE_QTY, 0.01)  # wholesale: about half of what they sell for
					_go({ "title": "ORDER SUPPLIES", "prompt": "CASES (1-9), ESC TO CANCEL",
						"lines": func() -> Array: return ["", " ITEM.....: %s (%s)" % [x.name, "DRINK" if x.drink else "SNACK"], " ON RACKS.: %d OF %d SPOTS" % [x.out, x.spots], " IN STOCK.: %d" % snacks.backstock[x.name], " ON ORDER.: %d" % snacks.orders.get(x.name, 0),
							" CASE.....: %d FOR $%.2f" % [snacks.CASE_QTY, case_cost], " BUDGET...: $%.2f" % shift.budget, "", " ORDERS ARRIVE WITH TOMORROW MORNING'S DELIVERY."],
						"submit": func(v: String) -> void:
							var n := int(v) if v.is_valid_int() else 0
							if n < 1 or n > 9:
								_msg = "ENTER 1-9 CASES."
							elif shift.budget < n * case_cost:
								_msg = "INSUFFICIENT BUDGET."
							else:
								shift.budget -= n * case_cost
								snacks.orders[x.name] = snacks.orders.get(x.name, 0) + n * snacks.CASE_QTY
								_back()
								_back()
								_msg = "ORDERED %d CASE%s OF %s. BUDGET NOW $%.2f." % [n, "S" if n > 1 else "", x.name, shift.budget] }),
				"NO SUPPLIES ON FILE."))
		"U":
			_go(_list("UPGRADES - BUDGET $%.2f" % shift.budget, "      UPGRADE                                                         COST", shift.UPGRADES,
				func(u: Array, n: int) -> String: return " %s  %s %s %s" % [R(n, 3), L(u[1] + (" *" if (shift.owned(u[0]) and u[0] != "hire") else ""), 23), L("INSTALLED" if (shift.owned(u[0]) and u[0] != "hire") else "RAN TODAY" if u[0] == "ad" and shift.upg.get("ad_day", 0) == Clock.day else u[3], 37), R("$%.2f" % u[2], 7)],
				func(u: Array) -> void:
					if u[0] == "hire":
						_hire_screen()
						return
					_go({ "title": "PURCHASE UPGRADE", "prompt": "Y TO BUY, ESC TO CANCEL",
						"lines": func() -> Array: return ["", " UPGRADE..: %s" % u[1], " WHAT.....: %s" % u[3], " COST.....: $%.2f" % u[2], " BUDGET...: $%.2f" % shift.budget],
						"submit": func(v: String) -> void:
							if v != "Y":
								_msg = "TYPE Y TO BUY."
							elif shift.budget < u[2]:
								_msg = "INSUFFICIENT BUDGET."
							else:
								var err: String = shift.buy(u[0])
								if err != "":
									_msg = err
								else:
									shift.budget -= u[2]
									_back()
									_back()
									_msg = "PURCHASED: %s. BUDGET NOW $%.2f." % [u[1], shift.budget] }),
				"NO UPGRADES AVAILABLE."))
		"T":
			_copies("")
			var films: Array = _titles.keys().filter(func(t: String) -> bool: return _titles[t][0].e.size() == 1 and _in(t) > 0)
			films.sort()
			var f: Dictionary = shift.show
			_go(_list(("THEATER - %s" % ("%s: %s (%d SOLD)" % ["TONIGHT" if f.day == Clock.day else "TOMORROW", f.title.to_upper(), f.sold] if f.title != "" and f.day >= Clock.day else "NO FEATURE SET")).left(COLS - 20), "      FILM", films,
				func(t: String, n: int) -> String: return " %s  %s" % [R(n, 3), L(t.to_upper(), 60)],
				func(t: String) -> void:
					var err: String = shift.set_show(t)
					_back()
					_msg = err if err != "" else "FEATURE SET: %s AT 8 PM. TICKETS $4.00 AT THE REGISTER." % t.to_upper(),
				"THE THEATER ISN'T OPEN YET." if not shift.owned("theater") else "NO FILMS ON THE SHELF."))
		"W":  # the staff's week: each one's hours by the day (part time: up to 25 a week)
			var st: Node = main.get_node("Staff")
			_go({ "title": "STAFF - WEEKLY SCHEDULE", "prompt": "# DAY FROM-TO (OR OFF)  EX: 1 FRI 17-22",
				"lines": func() -> Array:
					var out: Array = ["  #  NAME          " + "".join(Clock.WEEKDAYS.map(func(d: String) -> String: return L(d, 7))) + " HRS   RATE"]
					for i in st.roster.size():
						var w: Dictionary = st.roster[i]
						var days := ""
						for d in 7:
							var bits: Array = range(15).filter(func(b: int) -> bool: return (int(w.sched[d]) >> b) & 1 == 1)
							days += L("%d-%d" % [9 + bits[0], 10 + bits[-1]] if not bits.is_empty() else "--", 7)
						out.append("  %d  %s%s %s  %s" % [i + 1, L(w.first + " " + w.last, 14), days, R(st.hours(w), 3), R("$%.2f" % st.rate(w), 6)])
					if st.roster.is_empty():
						out.append("  NOBODY ON STAFF YET: HIRE SOMEONE (U)")
					return out,
				"submit": func(v: String) -> void:
					var a := v.split(" ", false)
					var i := int(a[0]) - 1 if a.size() == 3 and a[0].is_valid_int() else -1
					var d: int = Clock.WEEKDAYS.find(a[1]) if a.size() == 3 else -1
					if i < 0 or i >= st.roster.size() or d < 0:
						_msg = "EXAMPLE: 1 FRI 17-22   OR: 1 FRI OFF"
						return
					var mask := 0
					if a[2] != "OFF":
						var h := a[2].split("-")
						if h.size() != 2 or not h[0].is_valid_int() or not h[1].is_valid_int() or int(h[0]) < 9 or int(h[1]) > 24 or int(h[1]) <= int(h[0]):
							_msg = "HOURS 9 TO 24, FROM-TO."
							return
						for b in range(int(h[0]) - 9, int(h[1]) - 9):
							mask |= 1 << b
					var was: int = st.roster[i].sched[d]
					st.roster[i].sched[d] = mask
					if st.hours(st.roster[i]) > 25:
						st.roster[i].sched[d] = was
						_msg = "PART TIME: 25 HOURS A WEEK AT MOST."
					else:
						_msg = "SCHEDULE UPDATED." })
		"J":  # the job board: what each of them gets to first when there's more than one thing to do
			var st: Node = main.get_node("Staff")
			_go({ "title": "STAFF JOBS - 1 FIRST, 4 LAST, 0 NEVER", "prompt": "# JOB PRIORITY  EX: 1 RETURNS 1",
				"lines": func() -> Array:
					var out: Array = ["  #  NAME          " + "".join(st.JOBS.keys().map(func(j: String) -> String: return L(st.JOBS[j][0], 10)))]
					for i in st.roster.size():
						var w: Dictionary = st.roster[i]
						out.append("  %d  %s%s" % [i + 1, L(w.first + " " + w.last, 14), "".join(st.JOBS.keys().map(func(j: String) -> String: return L(str(w.jobs.get(j, 0)) if w.jobs.get(j, 0) > 0 else "X", 10)))])
					if st.roster.is_empty():
						out.append("  NOBODY ON STAFF YET: HIRE SOMEONE (U)")
					return out,
				"submit": func(v: String) -> void:
					var a := v.split(" ", false)
					var i := int(a[0]) - 1 if a.size() == 3 and a[0].is_valid_int() else -1
					var job := ""
					for j: String in st.JOBS:
						if a.size() == 3 and st.JOBS[j][0].begins_with(a[1]):
							job = j
					if i < 0 or i >= st.roster.size() or job == "" or not a[2].is_valid_int() or int(a[2]) < 0 or int(a[2]) > 4:
						_msg = "EXAMPLE: 1 RETURNS 1   (0 = NEVER)"
					else:
						st.roster[i].jobs[job] = int(a[2])
						_msg = "JOB BOARD UPDATED." })
		"0": log_off()
		_: return false
	return true


func _main_menu() -> Dictionary:
	return { "title": "MAIN MENU", "prompt": "SELECTION OR COMMAND", "menu": true,
		"lines": func() -> Array:
			var unread := inbox()
			var left := [" INVENTORY", "  1  TITLE SEARCH", "  2  BROWSE BY SECTION", "  7  RETURNS BIN QUEUE", "  B  REPLACEMENT COPIES", " MEMBERS", "  3  MEMBER LOOKUP", "  4  ALL ACCOUNTS", "  5  OVERDUE / LATE FEES",
				" REPORTS", "  6  RENTALS OUT", "  8  DAILY SUMMARY", "  M  MESSAGES%s" % (" (%d NEW)" % unread if unread > 0 else "")]
			var right := [" STORE", "  O  ORDER SUPPLIES", "  U  STORE UPGRADES", "  T  TONIGHT'S FEATURE", "  W  STAFF SCHEDULE", "  J  STAFF JOBS", "  9  PREVIEW STATION", " SECURITY", "  S  GATE SYSTEM", " SYSTEM", "  H  HELP / COMMANDS", "  0  LOG OFF"]
			if shoppers.alarm_on:
				right.append("  A  *** SILENCE GATE ALARM ***")
			var out: Array = [""]
			for i in left.size():
				out.append(L(left[i], 40) + (right[i] if i < right.size() else ""))
			var late: int = shoppers.rented.filter(func(r: Array) -> bool: return _late(r) > 0).size()
			out.append_array(["", " %d MEMBERS · %d OVERDUE · %d IN RETURNS%s" % [shoppers.members.all.size(), late, tapes.return_bin.size(), "" if shoppers.gates_armed else " · GATES DISARMED"]])
			return out,
		"submit": func(v: String) -> void:
			var cmd := v.get_slice(" ", 0)
			var arg := v.substr(cmd.length()).strip_edges()
			if _pick(v):
				return
			if cmd in ["FIND", "INV"] and arg != "":
				_go(_list("TITLE SEARCH: %s" % arg, TITLE_HEAD, _find_titles(arg), _title_row, _title_detail))
			elif cmd in ["MEMBER", "CUST"] and arg != "":
				_go(_list("MEMBER SEARCH: %s" % arg, MEMBER_HEAD, _find_members(arg), _member_row, _member_detail))
			elif cmd == "VER":
				_msg = "POS/NET 2.3 (C) 1993 VIDEOTRAK SYSTEMS INC.  LICENSED TO VAULTBUSTER VIDEO #0417"
			else:
				var alias: String = { "OVERDUE": "5", "OUT": "6", "RETURNS": "7", "REPORT": "8", "HELP": "H", "?": "H", "LOGOFF": "0", "EXIT": "0", "LOGOUT": "0", "SUPPLIES": "O", "ORDER": "O", "MESSAGES": "M", "MSGS": "M", "GATES": "S", "REPLACE": "B", "UPGRADES": "U", "UPGRADE": "U", "THEATER": "T", "FEATURE": "T", "SCHEDULE": "W", "STAFF": "W", "JOBS": "J" }.get(cmd, "")
				if alias == "" or not _pick(alias):
					_msg = "UNKNOWN COMMAND: %s.  TYPE H FOR HELP." % v }


# ---- on and off, the keyboard, the screen

func log_in() -> void:
	open = true
	visible = true
	_stack.clear()
	_screen = _main_menu()
	_input = ""
	_msg = ""
	_login = 0.0 if OS.get_cmdline_user_args().is_empty() else -1.0  # (the tests are in at once)
	_menu_cur = 0
	if OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # the screen takes clicks
	player.set_physics_process(false)


func log_off() -> void:
	open = false
	visible = false
	_screen = {}
	_stack.clear()
	if OS.get_cmdline_user_args().is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_physics_process(true)


func type(v: String) -> void:  # a line typed and ENTER (the tests' way in, too)
	_msg = ""
	_input = ""
	_screen.submit.call(v.to_upper().strip_edges())


func _unhandled_input(e: InputEvent) -> void:
	if not open:
		return
	get_viewport().set_input_as_handled()  # (the terminal has the keyboard, and the mouse)
	if e is InputEventMouse and _login < 0.0:  # the mouse: what it's over is highlighted, a click's as good as typing it, the wheel turns a list's pages
		var cell := Vector2i(((e.position - _view.position) / _cell).floor())
		var over: Array = _hits.filter(func(h: Dictionary) -> bool: return h.r == cell.y and cell.x >= h.c0 and cell.x <= h.c1)
		if e is InputEventMouseMotion and not over.is_empty() and over[0].has("pick"):
			if _screen.get("menu", false):
				_menu_cur = over[0].pick
			else:
				_screen.pick.cur = over[0].pick
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not over.is_empty():
			over[0].act.call()
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP] and _screen.get("pager", false):
			type("N" if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else "P")
		return
	if not (e is InputEventKey and e.pressed) or (_login >= 0.0 and e.keycode != KEY_F10):
		return
	match e.keycode:
		KEY_F10: log_off()
		KEY_ESCAPE: _back()
		KEY_ENTER, KEY_KP_ENTER: _enter()
		KEY_BACKSPACE: _input = _input.left(-1)
		KEY_UP, KEY_DOWN: _arrow(1 if e.keycode == KEY_DOWN else -1, 0)
		KEY_PAGEDOWN, KEY_RIGHT:
			if _screen.get("pager", false):
				type("N")
			else:
				_arrow(0, 1)
		KEY_PAGEUP, KEY_LEFT:
			if _screen.get("pager", false):
				type("P")
			else:
				_arrow(0, -1)
		_:
			if e.unicode >= 32 and e.unicode < 127 and _input.length() < 40:
				_input += char(e.unicode).to_upper()


func _enter() -> void:  # ENTER: what's typed; or, with nothing typed, whatever's highlighted
	if _input == "" and _screen.get("menu", false) and _menu_cur < _menu_items.size():
		type(_menu_items[_menu_cur].key)
	elif _input == "" and _screen.get("pick", {}).get("n", 0) > 0:
		type(str(_screen.pick.cur + 1))
	else:
		type(_input)


func _arrow(down: int, across: int) -> void:  # the arrows: up and down the records or the menu, across to the menu's other column (about level)
	if _screen.get("menu", false) and not _menu_items.is_empty():
		var here: Dictionary = _menu_items[mini(_menu_cur, _menu_items.size() - 1)]
		if down != 0:
			_menu_cur = posmod(_menu_cur + down, _menu_items.size())
		elif (across > 0) != (here.side == 1):
			var best := _menu_cur
			for i in _menu_items.size():
				if _menu_items[i].side != here.side and (best == _menu_cur or absi(_menu_items[i].r - here.r) < absi(_menu_items[best].r - here.r)):
					best = i
			_menu_cur = best
	elif down != 0 and _screen.get("pick", {}).get("n", 0) > 0:
		var pk: Dictionary = _screen.pick
		pk.cur = clampi(pk.cur + down, 0, pk.n - 1)
		pk.page[0] = pk.cur / pk.per


func _process(dt: float) -> void:
	if not open or _screen.is_empty():
		return
	_blink += dt
	if _login >= 0.0:  # the badge, the password, a beat to verify, and in
		_login += dt
		if _login >= 1.25:
			_login = -1.0
			_msg = "BADGE ACCEPTED. WELCOME BACK. LAST LOGIN: %s 21:47 ON TTY01" % _date(Clock.day - 1)
	_text.text = "\n".join(_screen.lines.call().map(func(l) -> String: return str(l)))
	var vp := get_viewport().get_visible_rect().size  # 80 x 30 cells, twice as tall as wide: the monitor's 4:3
	var h := maxi(12, int(minf(vp.y * 0.92 / ROWS, vp.x * 0.92 / COLS * 2.0)) / 2 * 2)
	_cell = Vector2(h / 2.0, h)
	_view.position = ((vp - Vector2(COLS, ROWS) * _cell) / 2.0).floor()
	_frame()
	_view.queue_redraw()


# ---- the screen itself, as pos.js draws it: a grid of cells, each a character with its own colours, painted with the
# frame's lines as strokes, scanlines and the tube's dark corners (blankGrid, put, tint, box, rule, logo, statusBar,
# headerBig, headerSmall, keyBar, footer, colorLine, loginScreen, frame, boxLines, paint)

const ROWS := 30
const FONT := "res://fonts/VT323-Regular.ttf"
const P := {  # the DOS-app palette: blue screen, light grey text, bright white values, cyan labels and frames, yellow headings, green money, red warnings
	"bg": Color("#0000aa"), "fg": Color("#c8c8d8"), "hi": Color("#ffffff"), "yel": Color("#ffff55"), "cyan": Color("#55ffff"), "dcyan": Color("#00aaaa"), "grn": Color("#55ff55"),
	"red": Color("#ff5555"), "gray": Color("#8a8ad0"), "blk": Color("#000000"), "deep": Color("#000077"), "shadow": Color("#000044") }
const FONT5 := {  # the logo's 5x7 letters
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"], "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"] }
const LOGO := "VAULTBUSTER"
const RAMP := ["#ffff88", "#ffff55", "#ffee33", "#ffcc22", "#ffaa11", "#ff8800", "#ff6600"]  # yellow running to orange
const TAG := "·  V I D E O   ·   P O S / N E T   2 . 3  ·"
const HEAD := "\a"  # (in front of a body line: it's a column heading)
const MARKS := {  # what a body line's coloured by
	"label": "^(\\s*[A-Z#][A-Z #/.'-]*?\\.{2,}:)", "money": "\\$-?[\\d,]+\\.\\d\\d", "page": "PAGE \\d+ OF \\d+", "good": "\\bON SHELF\\b|\\bREGULAR\\b|GOOD STANDING|\\bINSTALLED\\b",
	"bad": "\\bLATE \\d+D\\b|LOST - STOLEN|\\bUNHAPPY\\b|\\bDISARMED\\b|\\*\\*\\*[^*]*\\*\\*\\*", "num": "\\d+",
	"msg_bad": "INVALID|UNKNOWN|INSUFFICIENT|REQUIRED|NOT |NO SUCH|FULL|FIRST|CAN'T|PART TIME", "msg_good": "ORDERED|PURCHASED|SET:|ARMED|ACCEPTED|SILENCED|WELCOME|CLEARED|SAVED|HIRED|UPDATED" }

var _view := Control.new()
var _font: Font
var _vignette := GradientTexture2D.new()
var _re := {}
var _cell := Vector2(10, 20)
var _login := -1.0  # seconds into the login's show (-1: logged in)
var _ch := PackedStringArray()  # the grid, row by row
var _fg := PackedColorArray()
var _bg := PackedColorArray()
var _px := {}  # cell -> [top half, bottom half]: the logo's pixels
var _hits: Array = []  # what a click lands on: { r, c0, c1, act, pick (which record or menu line it is) }
var _menu_items: Array = []  # the main menu's lines, in order: { key, r, c0, c1, side }
var _menu_cur := 0  # ...and the one that's highlighted


func _put(r: int, c: int, text: String, fg = null, bg = null) -> void:
	for i in text.length():
		if r < 0 or r >= ROWS or c + i < 0 or c + i >= COLS:
			continue
		var k := r * COLS + c + i
		_ch[k] = text[i]
		_px.erase(k)
		if fg != null:
			_fg[k] = fg
		if bg != null:
			_bg[k] = bg


func _tint(r: int, c0: int, c1: int, fg = null, bg = null) -> void:
	for c in range(maxi(0, c0), mini(COLS - 1, c1) + 1):
		if fg != null:
			_fg[r * COLS + c] = fg
		if bg != null:
			_bg[r * COLS + c] = bg


func _center(r: int, text: String, fg = null, bg = null, c0 := 0, c1 := COLS - 1) -> void:
	_put(r, c0 + (c1 - c0 + 1 - text.length()) / 2, text, fg, bg)


func _box(r0: int, c0: int, r1: int, c1: int, dbl: bool, fg: Color) -> void:  # an outline
	var b := "═║╔╗╚╝" if dbl else "─│┌┐└┘"
	_put(r0, c0, b[2] + b[0].repeat(c1 - c0 - 1) + b[3], fg)
	_put(r1, c0, b[4] + b[0].repeat(c1 - c0 - 1) + b[5], fg)
	for r in range(r0 + 1, r1):
		_put(r, c0, b[1], fg)
		_put(r, c1, b[1], fg)


func _rule(r: int, c0: int, c1: int, kind: String, fg: Color) -> void:  # a divider across a box: "dbl" ╠═╣ · "mid" ╟─╢ · "single" ├─┤
	var b := "╠═╣" if kind == "dbl" else "╟─╢" if kind == "mid" else "├─┤"
	_put(r, c0, b[0] + b[1].repeat(c1 - c0 - 1) + b[2], fg)


func _logo(r0: int, c0: int) -> void:  # VAULTBUSTER in 5x7 pixel letters with a drop shadow: 8 pixel rows = 4 rows of half-block cells
	var on := func(x: int, y: int) -> bool: return y >= 0 and y < 7 and x >= 0 and x / 6 < LOGO.length() and x % 6 < 5 and FONT5[LOGO[x / 6]][y][x % 6] == "1"
	for row in 4:
		for x in LOGO.length() * 6:
			var px: Array = [P.bg, P.bg]
			for half in 2:
				var y := row * 2 + half
				px[half] = Color(RAMP[y]) if on.call(x, y) else P.shadow if on.call(x - 1, y - 1) else P.bg
			if px[0] != P.bg or px[1] != P.bg:
				_px[(r0 + row) * COLS + c0 + x] = px


func _money(v: float) -> String:
	return "$%.2f" % v


func _status_bar(r: int) -> void:  # who, when, money: split by bars
	var c := 2
	for part: Array in [["EMP 0042", P.hi], ["TERM 01", P.fg], ["%s %s" % [Clock.weekday().left(3).to_upper(), _date(Clock.day)], P.yel], [Clock.fmt_clock(Clock.h), P.yel],
			["BUDGET %s" % _money(shift.budget), P.red if shift.budget < 0.0 else P.grn], ["*".repeat(shift.rep_stars()).rpad(5, "."), P.yel]]:
		if c > 2:
			_put(r, c, "│", P.dcyan)
			c += 2
		_put(r, c, part[0], part[1])
		c += part[0].length() + 1


func _key_bar(r: int, keys: Array) -> void:  # [cap, label, what a click on it does]: a black strip under the frame, cyan key caps
	_tint(r, 0, COLS - 1, P.fg, P.blk)
	var c := 1
	for k: Array in keys:
		_put(r, c, " %s " % k[0], P.blk, P.dcyan)
		_put(r, c + k[0].length() + 2, " " + k[1], P.hi, P.blk)
		_hits.append({ "r": r, "c0": c, "c1": c + k[0].length() + k[1].length() + 2, "act": k[2] })
		c += k[0].length() + k[1].length() + 5


func _color_line(r: int, l: String) -> void:  # a body line: plain text, coloured by what it looks like
	if l.begins_with(HEAD):  # a column heading
		_tint(r, 1, COLS - 2, P.yel, P.deep)
		_put(r, 1, l.substr(1).left(COLS - 2), P.yel)
		return
	var t := l.left(COLS - 2)
	_put(r, 1, t, P.fg)
	var lab: RegExMatch = _re.label.search(t)  # " TITLE....: value"
	if lab != null:
		_tint(r, 1, lab.get_end(), P.cyan)
		_tint(r, 1 + lab.get_end(), COLS - 2, P.hi)
	for mark: Array in [["money", P.grn], ["page", P.gray], ["good", P.grn], ["bad", P.red]]:
		for m: RegExMatch in _re[mark[0]].search_all(t):
			_tint(r, 1 + m.get_start(), m.get_end(), mark[1])


func _menu(top: int, lines: Array) -> void:  # the main menu: two boxed columns of what there is, the store's numbers under them
	_menu_items.clear()
	for side in 2:
		var c0 := 41 if side == 1 else 2
		var c1 := 77 if side == 1 else 38
		var r := top
		for l: String in lines.slice(1, lines.size() - 2):
			var t := (l.substr(40) if side == 1 else l.left(40)).strip_edges(false, true)
			if t == "":
				continue
			if not t.begins_with("  "):  # a group's name, on the box's own line
				_put(r, c0, ("┌" if r == top else "├") + "─".repeat(c1 - c0 - 1) + ("┐" if r == top else "┤"), P.dcyan)
				_put(r, c0 + 2, " %s " % t.strip_edges(), P.yel)
			else:
				var urgent := t.contains("***") or t.contains("NEW)")
				_put(r, c0, "│", P.dcyan)
				_put(r, c1, "│", P.dcyan)
				_put(r, c0 + 2, t.substr(2, 1), P.red if urgent else P.yel)
				_put(r, c0 + 5, t.substr(5).replace("*", "").strip_edges(), (P.red if fmod(_blink, 1.06) < 0.53 else P.hi) if urgent else P.hi)
				_menu_items.append({ "key": t.substr(2, 1), "r": r, "c0": c0 + 1, "c1": c1 - 1, "side": side })
			r += 1
		_put(r, c0, "└" + "─".repeat(c1 - c0 - 1) + "┘", P.dcyan)
	_menu_cur = mini(_menu_cur, _menu_items.size() - 1)
	for i in _menu_items.size():  # the highlighted one on a grey bar; any of them takes a click
		var it: Dictionary = _menu_items[i]
		if i == _menu_cur:
			_tint(it.r, it.c0, it.c1, P.bg, P.fg)
		_hits.append({ "r": it.r, "c0": it.c0, "c1": it.c1, "act": type.bind(it.key), "pick": i })
	var facts: String = lines[-1].strip_edges()
	_put(top + 15, 2, facts, P.cyan)
	for m: RegExMatch in _re.num.search_all(facts):
		_tint(top + 15, 2 + m.get_start(), 1 + m.get_end(), P.hi)
	for m: RegExMatch in _re.bad.search_all(facts):
		_tint(top + 15, 2 + m.get_start(), 1 + m.get_end(), P.red)


func _login_screen() -> void:  # what the monitor shows till you're in
	var step := 0
	for at: float in [0.0, 0.16, 0.23, 0.3, 0.37, 0.44, 0.51, 0.58, 0.95]:
		step += int(_login >= at)
	_logo(2, (COLS - LOGO.length() * 6) / 2)
	_center(6, TAG, P.cyan)
	var x0 := 19
	var x1 := 60
	_box(8, x0, 14, x1, false, P.dcyan)
	_center(8, " SECURE LOGIN ", P.yel, null, x0, x1)
	var fields := [["STORE.....:", "#0417  ELM ST PLAZA", P.hi], ["TERMINAL..:", "REGISTER 01", P.hi], ["EMPLOYEE..:", "0042  (BADGE)" if step >= 1 else "____", P.hi if step >= 1 else P.gray],
		["PASSWORD..:", "*".repeat(mini(6, step - 1)).rpad(6, "_") if step >= 2 else "______", P.hi if step >= 2 else P.gray],
		["STATUS....:", "ACCESS GRANTED" if step >= 9 else "VERIFYING..." if step >= 8 else "READY", P.grn if step >= 9 else P.yel if step >= 8 else P.fg]]
	for i in fields.size():
		_put(9 + i, x0 + 3, fields[i][0], P.cyan)
		_put(9 + i, x0 + 4 + fields[i][0].length(), fields[i][1], fields[i][2])
	_rule(20, 0, COLS - 1, "mid", P.dcyan)
	var late: int = shoppers.rented.filter(func(r: Array) -> bool: return _late(r) > 0).size()
	var tonight: bool = shift.show.title != "" and shift.show.day == Clock.day
	var rows := [[21, 2, "RETURNS BIN", R(tapes.return_bin.size(), 3), P.hi], [22, 2, "OVERDUE....", R(late, 3), P.red if late > 0 else P.hi], [23, 2, "MEMBERS....", R(shoppers.members.all.size(), 3), P.hi],
		[24, 2, "MESSAGES...", R(inbox(), 3), P.red if inbox() > 0 else P.hi], [21, 24, "TONIGHT...", "%s 8PM" % shift.show.title.to_upper().left(26) if tonight else "NO FEATURE", P.hi if tonight else P.gray],
		[22, 24, "GATES.....", "*** ALARM ***" if shoppers.alarm_on else "ARMED" if shoppers.gates_armed else "DISARMED", P.grn if shoppers.gates_armed and not shoppers.alarm_on else P.red],
		[23, 24, "BUDGET....", _money(shift.budget), P.red if shift.budget < 0.0 else P.grn]]
	for f: Array in rows:
		_put(f[0], f[1], f[2], P.cyan)
		_put(f[0], f[1] + f[2].length() + 1, f[3], f[4])
	var when := "%s %s" % [Clock.weekday().left(3).to_upper(), _date(Clock.day)]
	_put(21, COLS - 3 - when.length(), when, P.yel)
	_put(22, COLS - 3 - Clock.fmt_clock(Clock.h).length(), Clock.fmt_clock(Clock.h), P.yel)
	_put(23, COLS - 21, "SCO UNIX 3.2 · TTY01", P.gray)
	_put(ROWS - 3, 2, "LAST LOGIN: %s 21:47 ON TTY01" % _date(Clock.day - 1), P.gray)
	_key_bar(ROWS - 1, [])


func _frame() -> void:  # the grid for this moment
	_ch.resize(COLS * ROWS)
	_fg.resize(COLS * ROWS)
	_bg.resize(COLS * ROWS)
	_ch.fill(" ")
	_fg.fill(P.fg)
	_bg.fill(P.bg)
	_px.clear()
	_hits.clear()
	_box(0, 0, ROWS - 2, COLS - 1, true, P.dcyan)
	if _login >= 0.0:
		_login_screen()
		return
	var lines: Array = _screen.lines.call()
	var big: bool = _screen.get("menu", false)
	var top := 9 if big else 3
	if big:  # the main menu: the logo up top
		_logo(1, (COLS - LOGO.length() * 6) / 2)
		_center(5, TAG, P.cyan)
		_rule(6, 0, COLS - 1, "dbl", P.dcyan)
		_status_bar(7)
		_rule(8, 0, COLS - 1, "mid", P.dcyan)
		_menu(top, lines)
	else:  # everywhere else: the name in the top border, the screen's title on a bar
		_put(0, 2, " VAULTBUSTER ", P.yel)
		_put(0, 15, " POS/NET 2.3 ", P.cyan)
		var right := " EMP 0042 │ %s %s │ %s " % [_date(Clock.day), Clock.fmt_clock(Clock.h), _money(shift.budget)]
		_put(0, COLS - 2 - right.length(), right, P.fg)
		_tint(1, 1, COLS - 2, P.blk, P.dcyan)
		_put(1, 2, "► " + str(_screen.title).left(COLS - 6), P.blk, P.dcyan)
		_rule(2, 0, COLS - 1, "mid", P.dcyan)
		for i in mini(lines.size(), ROWS - 5 - top):  # the body runs down to the footer's divider
			_color_line(top + i, str(lines[i]))
		var pk: Dictionary = _screen.get("pick", {})
		for i in range(pk.page[0] * pk.per, mini(pk.n, (pk.page[0] + 1) * pk.per)) if pk.get("n", 0) > 0 else []:  # a list's records: the highlighted one on a grey bar; any of them takes a click
			var r: int = top + 1 + i - pk.page[0] * pk.per
			if i == pk.cur:
				_tint(r, 1, COLS - 2, P.bg, P.fg)
			_hits.append({ "r": r, "c0": 1, "c1": COLS - 2, "act": type.bind(str(i + 1)), "pick": i })
	_rule(ROWS - 5, 0, COLS - 1, "mid", P.dcyan)
	if _msg != "":
		_put(ROWS - 4, 2, _msg.left(COLS - 4), P.red if _re.msg_bad.search(_msg) != null else P.grn if _re.msg_good.search(_msg) != null else P.yel)
	var label := "%s: " % _screen.get("prompt", "SELECTION")
	_put(ROWS - 3, 2, label, P.cyan)
	_put(ROWS - 3, 2 + label.length(), _input + ("█" if fmod(_blink, 1.06) < 0.53 else " "), P.hi)
	_key_bar(ROWS - 1, ([["N", "NEXT", type.bind("N")], ["P", "PREV", type.bind("P")]] if _screen.get("pager", false) else []) + [["ENTER", "OK", _enter], ["ESC", "BACK", _back], ["F10", "LOG OFF", log_off]])


func _strokes(ch: String, l: float, t: float, w: float, h: float, d: float) -> Array:  # a box-drawing character as lines: [x0, y0, x1, y1]... ([] if it isn't one)
	var r := l + w
	var b := t + h
	var cx := roundf(l + w / 2.0)
	var cy := roundf(t + h / 2.0)
	match ch:
		"─": return [[l, cy, r, cy]]
		"│": return [[cx, t, cx, b]]
		"┌": return [[cx, cy, r, cy], [cx, cy, cx, b]]
		"┐": return [[l, cy, cx, cy], [cx, cy, cx, b]]
		"└": return [[cx, t, cx, cy], [cx, cy, r, cy]]
		"┘": return [[cx, t, cx, cy], [l, cy, cx, cy]]
		"├": return [[cx, t, cx, b], [cx, cy, r, cy]]
		"┤": return [[cx, t, cx, b], [l, cy, cx, cy]]
		"═": return [[l, cy - d, r, cy - d], [l, cy + d, r, cy + d]]
		"║": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, b]]
		"╔": return [[cx - d, cy - d, r, cy - d], [cx - d, cy - d, cx - d, b], [cx + d, cy + d, r, cy + d], [cx + d, cy + d, cx + d, b]]
		"╗": return [[l, cy - d, cx + d, cy - d], [cx + d, cy - d, cx + d, b], [l, cy + d, cx - d, cy + d], [cx - d, cy + d, cx - d, b]]
		"╚": return [[cx - d, t, cx - d, cy + d], [cx - d, cy + d, r, cy + d], [cx + d, t, cx + d, cy - d], [cx + d, cy - d, r, cy - d]]
		"╝": return [[cx + d, t, cx + d, cy + d], [l, cy + d, cx + d, cy + d], [cx - d, t, cx - d, cy - d], [l, cy - d, cx - d, cy - d]]
		"╠": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, cy - d], [cx + d, cy - d, r, cy - d], [cx + d, b, cx + d, cy + d], [cx + d, cy + d, r, cy + d]]
		"╣": return [[cx + d, t, cx + d, b], [cx - d, t, cx - d, cy - d], [l, cy - d, cx - d, cy - d], [cx - d, b, cx - d, cy + d], [l, cy + d, cx - d, cy + d]]
		"╟": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, b], [cx + d, cy, r, cy]]
		"╢": return [[cx - d, t, cx - d, b], [cx + d, t, cx + d, b], [l, cy, cx - d, cy]]
	return []


func _paint() -> void:
	if _ch.size() != COLS * ROWS:
		return  # (shown before its first frame's been laid out)
	var w := _cell.x
	var h := _cell.y
	var size := Vector2(COLS * w, ROWS * h)
	var lw := maxf(1.0, roundf(h / 13.0))
	var d := maxf(2.0, roundf(w * 0.2))
	var px := int(h)
	var base := (h - _font.get_height(px)) / 2.0 + _font.get_ascent(px)
	_view.draw_rect(Rect2(Vector2(-14, -14), size + Vector2(28, 28)), Color("#111114"))  # the monitor's bezel
	_view.draw_rect(Rect2(Vector2.ZERO, size), P.bg)
	for r in ROWS:
		for c in COLS:
			var k := r * COLS + c
			var at := Vector2(c * w, r * h)
			if _px.has(k):
				_view.draw_rect(Rect2(at, Vector2(w, h / 2.0)), _px[k][0])
				_view.draw_rect(Rect2(at + Vector2(0, h / 2.0), Vector2(w, h / 2.0)), _px[k][1])
				continue
			if _bg[k] != P.bg:
				_view.draw_rect(Rect2(at, _cell), _bg[k])
			var ch := _ch[k]
			if ch == " ":
				continue
			if ch == "█":
				_view.draw_rect(Rect2(at, _cell), _fg[k])
				continue
			var segs := _strokes(ch, at.x, at.y, w, h, d)
			for s: Array in segs:  # (square ends, so corners meet)
				var horiz: bool = s[1] == s[3]
				_view.draw_rect(Rect2(minf(s[0], s[2]) - (0.0 if horiz else lw / 2.0), minf(s[1], s[3]) - (lw / 2.0 if horiz else 0.0), absf(s[2] - s[0]) + (0.0 if horiz else lw), absf(s[3] - s[1]) + (lw if horiz else 0.0)), _fg[k])
			if segs.is_empty():
				_view.draw_char(_font, at + Vector2((w - _font.get_char_size(ch.unicode_at(0), px).x) / 2.0, base), ch, px, _fg[k])
	for y in range(2, int(size.y), 3):  # scanlines
		_view.draw_rect(Rect2(0, y, size.x, 1), Color(0, 0, 0, 0.13))
	_view.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false)


# ---- the morning's delivery, the save

func deliver() -> void:  # yesterday's orders (called when the day begins)
	for t: Dictionary in replacements:
		tapes.return_bin.append(t)
	var cases: int = snacks.deliver()
	if not replacements.is_empty() or cases > 0:
		$"../HUD".toast("The morning's delivery: %s" % " and ".join(PackedStringArray([("%d replacement tape%s in the returns bin" % [replacements.size(), "" if replacements.size() == 1 else "s"]) if not replacements.is_empty() else "", ("%d box%s by the front door" % [cases, "" if cases == 1 else "es"]) if cases > 0 else ""].filter(func(x: String) -> bool: return x != ""))))
	replacements.clear()


func snapshot() -> Dictionary:
	return { "notes": notes, "replacements": replacements.map(func(t: Dictionary) -> String: return t.k), "orders": snacks.orders, "armed": shoppers.gates_armed }


func restore(d: Dictionary) -> void:
	notes = d.get("notes", [])
	for n: Dictionary in notes:
		n.day = int(n.day)
	for k: String in d.get("orders", {}):
		snacks.orders[k] = int(d.orders[k])
	shoppers.gates_armed = d.get("armed", true)
	for t: Dictionary in tapes.tapes:
		if d.get("replacements", []).has(t.k):
			replacements.append(t)
			t.lost = false


func _hire_screen() -> void:  # three applicants to choose from; each hire costs more than the last (hireOpen, hirePick)
	var st: Node = main.get_node("Staff")
	var cost: float = st.hire_cost()
	if st.roster.size() >= st.STAFF_MAX:
		_msg = "THE STAFF ROOM'S FULL (%d)." % st.STAFF_MAX
		return
	if shift.budget < cost:
		_msg = "INSUFFICIENT BUDGET: $%.2f TO HIRE." % cost
		return
	var apps: Array = [st.applicant(), st.applicant(), st.applicant()]
	_go({ "title": "THREE APPLICANTS - $%.2f TO HIRE ONE" % cost, "prompt": "1-3 TO HIRE, ESC FOR NOT NOW",
		"lines": func() -> Array:
			var out: Array = ["", "  #  NAME                " + "".join(st.SKILLS.keys().map(func(k: String) -> String: return L(st.SKILLS[k][0], 5))) + "  AN HOUR"]
			for i in 3:
				out.append("  %d  %s%s  $%.2f" % [i + 1, L(apps[i].first + " " + apps[i].last, 20), "".join(st.SKILLS.keys().map(func(k: String) -> String: return L(apps[i].skills[k][0], 5))), st.rate(apps[i])])
			out.append_array(["", "  UP TO 25 HOURS A WEEK. THEY START RIGHT NOW; SET THEIR WEEK UNDER W."])
			return out,
		"submit": func(v: String) -> void:
			if not v in ["1", "2", "3"]:
				_msg = "1, 2 OR 3."
				return
			var a: Dictionary = apps[int(v) - 1]
			shift.budget -= cost
			shift.upg.hire = true
			st.hires += 1
			st.hire(a)
			_back()
			_back()
			_msg = "HIRED: %s %s. BUDGET NOW $%.2f." % [a.first.to_upper(), a.last.to_upper(), shift.budget] })
