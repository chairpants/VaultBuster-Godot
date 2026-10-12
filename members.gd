extends RefCounted
## The store's members: the three hundred locals in the register's system. Everybody who walks in is one of them, and
## their member number is their seed, so the same member always looks and acts the same (shoppers.gd).
## From the web game's pos.js (the seeded customers: the same numbers and names as over there; owed, settle,
## setStatus, canVisit, loyal). In a sandbox everyone's a member from the start; a simulation starts with forty.
## Not over yet: the terminal that shows any of this, addresses and notes, incidents on a record, sign-ups.

const FIRST := ["JOHN", "MARY", "DAVID", "LISA", "MIKE", "KAREN", "STEVE", "SUSAN", "CHRIS", "AMY", "BRIAN", "DONNA", "KEVIN", "TINA", "JASON",
	"HEATHER", "SCOTT", "WENDY", "TODD", "DAWN", "GREG", "SHANNON", "RAY", "TRACY", "DOUG", "ANGELA", "PHIL", "KIM", "ERIC", "MELISSA", "RON", "JILL",
	"DANNY", "STACY", "TROY", "APRIL", "GARY", "NICOLE", "DEREK", "JENNY", "MARCUS", "BECKY", "LUIS", "ROSA", "ANDRE", "KEISHA", "DALE", "PAM"]  # (his / her names, alternating)
const LAST := ["SMITH", "JOHNSON", "MILLER", "DAVIS", "GARCIA", "WILSON", "ANDERSON", "TAYLOR", "THOMAS", "MOORE", "MARTIN", "JACKSON", "THOMPSON",
	"WHITE", "LOPEZ", "HARRIS", "CLARK", "LEWIS", "ROBINSON", "WALKER", "YOUNG", "ALLEN", "KING", "WRIGHT", "SCOTT", "HILL", "GREEN", "ADAMS",
	"BAKER", "NELSON", "CARTER", "MITCHELL", "ROBERTS", "TURNER", "PHILLIPS", "CAMPBELL", "PARKER", "EVANS", "EDWARDS", "COLLINS", "STEWART",
	"MORRIS", "MURPHY", "COOK", "ROGERS", "REED", "BAILEY", "KOWALSKI", "NGUYEN", "OKAFOR", "BRENNAN", "DELUCA"]
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
			"active": true, "owed": 0.0, "loyalty": 0.0, "last_visit": -9.0, "status": "", "until": 0 }
		for skip in 5:  # (their address, since when, lifetime rentals, the note on their account: the terminal's)
			_rnd()
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


func records() -> Dictionary:  # for the save: whoever's got anything on their account
	var out := {}
	for m: Dictionary in all:
		if m.owed > 0.0 or m.loyalty != 0.0 or m.status != "" or m.last_visit > -9.0:
			out[str(m.num)] = [m.owed, m.loyalty, m.last_visit, m.status, m.until]
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
