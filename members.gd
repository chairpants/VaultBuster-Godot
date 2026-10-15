extends RefCounted
## The store's members: the three hundred locals in the register's system. Everybody who walks in is one of them, and
## their member number is their seed, so the same member always looks and acts the same (shoppers.gd).
## From the web game's pos.js (the seeded customers: the same numbers and names as over there; owed, settle,
## setStatus, canVisit, loyal). In a sandbox everyone's a member from the start; a simulation starts with forty.
## Each has an address, a year they joined, a note on the account now and then, and whatever's gone on the record since.

const FIRST := ["JOHN", "MARY", "DAVID", "LISA", "MIKE", "KAREN", "STEVE", "SUSAN", "CHRIS", "AMY", "BRIAN", "DONNA", "KEVIN", "TINA", "JASON",
	"HEATHER", "SCOTT", "WENDY", "TODD", "DAWN", "GREG", "SHANNON", "RAY", "TRACY", "DOUG", "ANGELA", "PHIL", "KIM", "ERIC", "MELISSA", "RON", "JILL",
	"DANNY", "STACY", "TROY", "APRIL", "GARY", "NICOLE", "DEREK", "JENNY", "MARCUS", "BECKY", "LUIS", "ROSA", "ANDRE", "KEISHA", "DALE", "PAM"]  # (his / her names, alternating)
const LAST := ["SMITH", "JOHNSON", "MILLER", "DAVIS", "GARCIA", "WILSON", "ANDERSON", "TAYLOR", "THOMAS", "MOORE", "MARTIN", "JACKSON", "THOMPSON",
	"WHITE", "LOPEZ", "HARRIS", "CLARK", "LEWIS", "ROBINSON", "WALKER", "YOUNG", "ALLEN", "KING", "WRIGHT", "SCOTT", "HILL", "GREEN", "ADAMS",
	"BAKER", "NELSON", "CARTER", "MITCHELL", "ROBERTS", "TURNER", "PHILLIPS", "CAMPBELL", "PARKER", "EVANS", "EDWARDS", "COLLINS", "STEWART",
	"MORRIS", "MURPHY", "COOK", "ROGERS", "REED", "BAILEY", "KOWALSKI", "NGUYEN", "OKAFOR", "BRENNAN", "DELUCA"]
const STREETS := ["MAPLE AVE", "OAK ST", "ELM ST", "CEDAR LN", "PINE RIDGE RD", "LAKEVIEW DR", "2ND ST", "MAIN ST", "HIGHLAND AVE", "SUNSET BLVD",
	"WILLOW CT", "BIRCH WAY", "PARK PL", "RIVER RD", "HILLCREST DR", "ORCHARD LN", "MILL ST", "CHESTNUT ST", "FAIRVIEW AVE", "BROOKSIDE DR"]
const NOTES := ["", "", "", "", "", "PAYS IN QUARTERS", "DAMAGED TAPE 03/96 - PAID", "NO R-RATED (PARENT REQUEST)", "HORROR FAN - CALL ON NEW ARRIVALS",
	"BOUNCED CHECK 11/95 - CASH ONLY", "EMPLOYEE FAMILY", "REWIND FEE WAIVED 2X - LAST WARNING", "ON RESERVE LIST FOR NEW RELEASES",
	"ALWAYS ASKS FOR STAFF PICKS", "RETURNED TAPE IN WRONG CASE 2X", "ACCT FROZEN ONCE - FEES PAID 07/96"]
const RENT_MAX := 3  # tapes out at once, per member

var all: Array = []  # { num, first, last, female, heavy, owed, loyalty, last_visit, status, until }
var by_num := {}

var _seed := 0x5eed1996


func _rnd() -> float:  # pos.js's rnd(): the same seed, the same people
	_seed = (_seed + 0x6D2B79F5) & 0xffffffff
	var t: int = ((_seed ^ (_seed >> 15)) * (1 | _seed)) & 0xffffffff
	t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xffffffff)) & 0xffffffff) ^ t
	return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0


func _init() -> void:
	for i in 300:
		var num := 10001 + int(_rnd() * 38999)
		while by_num.has(num):
			num = 10001 + int(_rnd() * 38999)
		var first: String = FIRST[int(_rnd() * FIRST.size())]
		var m := { "num": num, "first": first, "female": FIRST.find(first) % 2 == 1, "last": LAST[int(_rnd() * LAST.size())],
			"active": true, "owed": 0.0, "loyalty": 0.0, "last_visit": -9.0, "status": "", "until": 0,
			"calls": 0, "last_call": -1, "last_result": "", "promise": -9 }  # (the overdue calls: how many, the day of the last, what came of it, the day they said they'd bring it in)
		m.addr = "%d %s" % [12 + int(_rnd() * 9859), STREETS[int(_rnd() * STREETS.size())]]
		m.since = 1987 + int(_rnd() * 10)
		m.lifetime = 3 + int(_rnd() * 638)
		m.notes = NOTES[int(_rnd() * NOTES.size())]
		m.incidents = []  # [day, what]: the last few show on the account
		m.likes = ""  # (what they go for, once somebody's noticed: shoppers.gd)
		m.heavy = _rnd() < 0.2
		by_num[num] = m
		all.append(m)


func start_small(n: int) -> void:  # a simulation's store: a small base to start, the rest sign up over time
	for m: Dictionary in all:
		m.active = false
	var pool := all.duplicate()
	pool.shuffle()
	for m: Dictionary in pool.slice(0, n):
		m.active = true


func name_of(m: Dictionary) -> String:
	return "%s %s" % [m.first.capitalize(), m.last.capitalize()]


func can_visit(m: Dictionary) -> bool:  # status: "banned" (till a day) | "cancelled" | "arrested" | ""
	return m.active and not m.status in ["cancelled", "arrested"] and not (m.status == "banned" and m.until > Clock.day)


func loyal(m: Dictionary, d: float) -> void:  # how they feel about the store: -100..100
	m.loyalty = clampf(m.loyalty + d, -100.0, 100.0)


func incident(m: Dictionary, what: String) -> void:  # on their record (pos.js: incident)
	m.incidents.append([Clock.day, what.to_upper()])


func records() -> Dictionary:  # for the save: whoever's got anything on their account
	var out := {}
	for m: Dictionary in all:
		if m.owed > 0.0 or m.loyalty != 0.0 or m.status != "" or m.last_visit > -9.0 or m.calls > 0 or not m.incidents.is_empty():
			out[str(m.num)] = [m.owed, m.loyalty, m.last_visit, m.status, m.until, m.calls, m.last_call, m.last_result, m.promise, m.get("car"), m.incidents, m.likes, m.since]
	return out


func restore(d: Dictionary) -> void:
	for k: String in d:
		var m: Dictionary = by_num.get(int(k), {})
		if not m.is_empty():
			m.owed = d[k][0]
			m.loyalty = d[k][1]
			m.last_visit = d[k][2]
			m.status = d[k][3]
			m.until = int(d[k][4])
			if d[k].size() > 8:
				m.calls = int(d[k][5])
				m.last_call = int(d[k][6])
				m.last_result = d[k][7]
				m.promise = int(d[k][8])
			if d[k].size() > 9 and d[k][9] != null:  # (what they drive, or false: on foot)
				m.car = d[k][9]
			if d[k].size() > 12:
				m.incidents = d[k][10].map(func(x: Array) -> Array: return [int(x[0]), x[1]])
				m.likes = d[k][11]
				m.since = int(d[k][12])
