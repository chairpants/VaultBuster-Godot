extends CanvasLayer
## VaultBuster POS/NET: the register's terminal, a menu-driven rental system. E on the register (when there's no
## sale waiting on it) logs you in. Type a selection or a command and ENTER; ESC goes back a screen; F10 logs off.
## The store keeps running while you're at it.
## Inventory (title search, sections, the returns bin, replacement copies for what's been stolen), members (lookup,
## all accounts, overdue and late fees), reports (rentals out, the daily summary, messages: the calls that were
## missed), supplies (cases of snacks and drinks, in the cupboards tomorrow morning), the preview station, and the
## security gates (arm, disarm, silence the alarm).
## From the web game's pos.js: the same screens (listScreen, prompt, titleDetail, custDetail, MENU, mainMenu's
## commands) over this store's tapes and members. It's all on a screen over the game here, in one colour.
## Not over yet: the picture on the register's own monitor, the login's badge-and-password show, the sale window,
## the overdue calls and their post-its, the theater's feature, the upgrades that have nothing to switch on yet, the staff's schedule, SYSRESET (F9 does
## that), deliveries as boxes by the door (an order's just in the cupboards, a replacement tape in the returns bin).

const COLS := 80
const BODY := 20  # body rows under the header

var open := false
var notes: Array = []  # the message center: [{ day, text, read }]
var replacements: Array = []  # ordered, here tomorrow: tapes

var _screen := {}  # { title, lines: Callable -> Array[String], prompt, submit: Callable(String), pager }
var _stack: Array = []
var _input := ""
var _msg := ""
var _text := Label.new()
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
	var blue := ColorRect.new()
	blue.color = Color.hex(0x0000aaff)
	blue.set_anchors_preset(Control.PRESET_CENTER)
	blue.custom_minimum_size = Vector2(840, 600)
	blue.position = -blue.custom_minimum_size / 2.0
	add_child(blue)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_text.add_theme_font_override("font", font)
	_text.add_theme_font_size_override("font_size", 17)
	_text.add_theme_color_override("font_color", Color.hex(0xc8c8d8ff))
	_text.position = Vector2(14, 8)
	blue.add_child(_text)


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
	return { "title": "%s  (%d RECORD%s)" % [title, items.size(), "" if items.size() == 1 else "S"], "pager": true, "prompt": "RECORD # OR N/P" if on_pick.is_valid() else "N/P OR ESC",
		"lines": func() -> Array:
			if items.is_empty():
				return ["", " " + empty]
			var out: Array = [head]
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
				else:
					_msg = "LAST PAGE."
			elif v == "P":
				if page[0] > 0:
					page[0] -= 1
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
			_go(_list("MESSAGE CENTER", "      WHAT", items,
				func(it: Dictionary, n: int) -> String: return " %s  %s %s" % [R(n, 3), L("NOTE" if it.read else "NEW", 6), L("%s %s" % [_date(it.day), it.text], 66)],
				func(it: Dictionary) -> void:
					it.read = true
					_go({ "title": "MESSAGE", "prompt": "D TO DELETE, ESC TO RETURN", "lines": func() -> Array: return ["", " " + _date(it.day), "", " " + it.text],
						"submit": func(v: String) -> void:
							if v == "D":
								notes.erase(it)
								_back()
							_back() }),
				"NO MESSAGES."))
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
				func(u: Array, n: int) -> String: return " %s  %s %s %s" % [R(n, 3), L(u[1] + (" *" if shift.owned(u[0]) else ""), 23), L("INSTALLED" if shift.owned(u[0]) else "RAN TODAY" if u[0] == "ad" and shift.upg.get("ad_day", 0) == Clock.day else u[3], 37), R("$%.2f" % u[2], 7)],
				func(u: Array) -> void:
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
		"0": log_off()
		_: return false
	return true


func _main_menu() -> Dictionary:
	return { "title": "MAIN MENU", "prompt": "SELECTION OR COMMAND",
		"lines": func() -> Array:
			var unread := notes.filter(func(n: Dictionary) -> bool: return not n.read).size()
			var left := [" INVENTORY", "  1  TITLE SEARCH", "  2  BROWSE BY SECTION", "  7  RETURNS BIN QUEUE", "  B  REPLACEMENT COPIES", " MEMBERS", "  3  MEMBER LOOKUP", "  4  ALL ACCOUNTS", "  5  OVERDUE / LATE FEES",
				" REPORTS", "  6  RENTALS OUT", "  8  DAILY SUMMARY", "  M  MESSAGES%s" % (" (%d NEW)" % unread if unread > 0 else "")]
			var right := [" STORE", "  O  ORDER SUPPLIES", "  U  STORE UPGRADES", "  9  PREVIEW STATION", " SECURITY", "  S  GATE SYSTEM", " SYSTEM", "  H  HELP / COMMANDS", "  0  LOG OFF"]
			if shoppers.alarm_on:
				right.insert(5, "  A  *** SILENCE GATE ALARM ***")
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
				var alias: String = { "OVERDUE": "5", "OUT": "6", "RETURNS": "7", "REPORT": "8", "HELP": "H", "?": "H", "LOGOFF": "0", "EXIT": "0", "LOGOUT": "0", "SUPPLIES": "O", "ORDER": "O", "MESSAGES": "M", "MSGS": "M", "GATES": "S", "REPLACE": "B", "UPGRADES": "U", "UPGRADE": "U" }.get(cmd, "")
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
	player.set_physics_process(false)


func log_off() -> void:
	open = false
	visible = false
	_screen = {}
	_stack.clear()
	player.set_physics_process(true)


func type(v: String) -> void:  # a line typed and ENTER (the tests' way in, too)
	_msg = ""
	_input = ""
	_screen.submit.call(v.to_upper().strip_edges())


func _unhandled_input(e: InputEvent) -> void:
	if not open:
		return
	get_viewport().set_input_as_handled()  # (the terminal has the keyboard, and the mouse)
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_F10: log_off()
		KEY_ESCAPE: _back()
		KEY_ENTER, KEY_KP_ENTER: type(_input)
		KEY_BACKSPACE: _input = _input.left(-1)
		KEY_PAGEDOWN, KEY_RIGHT:
			if _screen.get("pager", false):
				type("N")
		KEY_PAGEUP, KEY_LEFT:
			if _screen.get("pager", false):
				type("P")
		_:
			if e.unicode >= 32 and e.unicode < 127 and _input.length() < 40:
				_input += char(e.unicode).to_upper()


func _process(dt: float) -> void:
	if not open or _screen.is_empty():
		return
	_blink += dt
	var rows: Array = [L(" VAULTBUSTER  POS/NET 2.3", 40) + R("%s %s %s  BUDGET $%.2f " % [Clock.weekday(), _date(Clock.day), Clock.fmt_clock(Clock.h), shift.budget], 40),
		" ► " + _screen.title, "─".repeat(COLS)]
	var body: Array = _screen.lines.call()
	for i in BODY + 1:
		rows.append(str(body[i]).left(COLS) if i < body.size() else "")
	rows.append_array(["─".repeat(COLS), " " + _msg, " %s: %s%s" % [_screen.prompt, _input, "█" if fmod(_blink, 1.06) < 0.53 else " "], "",
		" ENTER  SELECT    ESC  BACK    F10  LOG OFF%s" % ("    ←/→  PAGE" if _screen.get("pager", false) else "")])
	_text.text = "\n".join(rows)


# ---- the morning's delivery, the save

func deliver() -> void:  # yesterday's orders (called when the day begins)
	for t: Dictionary in replacements:
		tapes.return_bin.append(t)
	var cases := 0
	for k: String in snacks.orders:
		snacks.backstock[k] += snacks.orders[k]
		cases += snacks.orders[k] / snacks.CASE_QTY
	if not replacements.is_empty() or cases > 0:
		$"../HUD".toast("The morning's delivery: %s" % " and ".join(PackedStringArray([("%d replacement tape%s in the returns bin" % [replacements.size(), "" if replacements.size() == 1 else "s"]) if not replacements.is_empty() else "", ("%d case%s in the stock cupboards" % [cases, "" if cases == 1 else "s"]) if cases > 0 else ""].filter(func(x: String) -> bool: return x != ""))))
	replacements.clear()
	snacks.orders.clear()


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
