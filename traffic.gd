extends RefCounted
## Everybody moving out there and in here, and who gives way: the one place the people and the cars find out about
## each other. Each frame every mover says where it is (person / car / stand), and asks how to take its next step:
## walk() for people (where they want to go, and how fast: back comes the step's velocity, bent round whoever's in
## the way), blocked() for cars (is there anything in the road ahead, or behind, backing up).
##
## Who gives way to whom:
##   - people and people: both step aside, each to their own right, so two meeting head-on slide past each other.
##     The one lower down (RANK) does more of it; you can't be steered, so everybody goes round you. Anybody stood
##     still gets walked round.
##   - cars and people: a car stops for anybody in its road (braking: cars.gd eases off for it). People don't step
##     out in front of a moving car: they wait at the edge of its road, and hurry clear if they're already in it,
##     and step quicker across the lanes when anything's moving in the lot. Parked cars are solid.
##   - cars and cars: cars.gd's own (the car ahead; two that'd each wait on the other: the first one in goes).
##   - backing out: a car that's waited a moment to back out claims the space it needs (claim()). Cars stop short of
##     it, people step out of it or wait at its edge, till it's backed out.
##
## ponytail: every mover against every other, each frame. Fine for the store's couple of dozen; a grid of who's
## near whom if it ever has hundreds.

const RANK := { "player": 4, "customer": 3, "walker": 2, "staff": 1 }
const SPACE := 0.35  # elbow room past their shoulders
const LOOK := 2.5  # seconds ahead they see somebody coming
const DRIVE_Z := Vector2(-8.4, -1.8)  # the lot's two lanes, curb to the stalls (cars.gd: LANE)

static var _people := {}  # id -> { p, v, r, rank, s (the sidestep, eased), f (the frame it was said) }
static var _cars := {}  # id -> { p, fwd (the nose), hl, hw (half long, half wide), v (m/s along fwd: - backing), f }
static var _claims := {}  # id -> { c, ax (along), h (half extents: along, across) }


static func _now() -> int:
	return Engine.get_process_frames()


static func _fresh(e: Dictionary) -> bool:
	return _now() - int(e.f) <= 2


static func person(id: int, p: Vector2, v: Vector2, kind: String, r := 0.25) -> void:  # where they are, how they're moving
	var e: Dictionary = _people.get(id, { "s": Vector2.ZERO })
	e.p = p
	e.v = v
	e.r = r
	e.rank = RANK[kind]
	e.f = _now()
	_people[id] = e


static func car(id: int, p: Vector2, ry: float, size: Vector2, v: float) -> void:  # ry: its yaw (the nose is local +x); size: long, wide; v: - backing
	_cars[id] = { "p": p, "fwd": Vector2(cos(ry), -sin(ry)), "hl": size.x / 2.0, "hw": size.y / 2.0, "v": v, "f": _now() }


static func claim(id: int, c = null, ax := Vector2.RIGHT, h := Vector2.ZERO) -> void:  # a backing car's space (null: done with it)
	if c == null:
		_claims.erase(id)
	else:
		_claims[id] = { "c": c, "ax": ax, "h": h }


static func gone(id: int) -> void:
	_people.erase(id)
	_cars.erase(id)
	_claims.erase(id)


static func _in_rect(q: Vector2, c: Vector2, ax: Vector2, h: Vector2, pad: float) -> bool:
	var d := q - c
	return absf(d.dot(ax)) < h.x + pad and absf(d.dot(Vector2(-ax.y, ax.x))) < h.y + pad


# ---- people

static func walk(id: int, p: Vector2, want: Vector2, speed: float, kind: String, dt: float, open := Callable(), r := 0.25) -> Vector2:  # want: the way to the next point (unit) -> the step's velocity
	var rank: int = RANK[kind]
	var right := Vector2(-want.y, want.x)  # (they face +z with their right at -x)
	var v := want * speed
	var side := Vector2.ZERO
	var slow := 1.0
	var hurry := 1.0
	var e: Dictionary = _people.get(id, { "s": Vector2.ZERO })
	var near: Array = []  # who they're going round
	var boxed := false  # somebody in the way and no room either side of them
	for oid: int in _people:
		var o: Dictionary = _people[oid]
		if oid == id or not _fresh(o):
			continue
		var d: Vector2 = o.p - p
		var dist := d.length()
		if dist > 3.5:
			continue
		var reach: float = r + o.r + SPACE
		if dist < r + o.r:  # (on top of each other: apart)
			side -= d / maxf(dist, 0.01) * (1.0 if o.rank >= rank else 0.3)
		var rv: Vector2 = v - o.v
		var rs := rv.length_squared()
		if rs < 1e-4 or d.dot(rv) <= 0.0:
			continue  # not closing on each other
		var t := minf(d.dot(rv) / rs, LOOK)
		var miss := (d - rv * t).length()
		if miss >= reach:
			continue
		var still: bool = o.v.length_squared() < 0.0025
		var share := 1.0 if still else 0.5 if o.rank == rank else 0.85 if o.rank > rank else 0.15  # who does the moving
		var urg := (1.0 - t / LOOK) * (0.5 + 0.5 * (reach - miss) / reach)
		var lat := d.dot(right)
		var pick := -signf(lat) if absf(lat) > 0.06 else 1.0  # which side to go round them on: away from the side they're on (dead ahead, keep right),
		var pass_k := 0.0  # if there's room beside them there; else the other side (judged by where they stand, so no dithering)
		for k: float in [pick, -pick]:
			var by: Vector2 = o.p + right * k * (r + o.r + 0.08)
			if not open.is_valid() or open.call(by.x, by.y):
				pass_k = k
				break
		if pass_k == 0.0:
			boxed = boxed or (still and d.dot(want) > 0.0)
			continue
		side += right * pass_k * share * urg * 1.6
		near.append(o)
		var theirs: bool = o.rank > rank or (o.rank == rank and lat > 0.3 and absf(o.v.normalized().dot(want)) < 0.7)  # the right of way: rank, then (paths crossing) whoever's coming from your right
		if not still and d.dot(want) > 0.0 and theirs and dist < reach + 1.2:  # let them by
			slow = minf(slow, clampf((dist - r - o.r - SPACE) / 1.2, 0.0, 1.0))
	# the cars: out of a moving one's road, never into it; round the parked ones
	for cid: int in _cars:
		var c: Dictionary = _cars[cid]
		if not _fresh(c):
			continue
		var d: Vector2 = p - c.p
		if d.length() > 25.0:
			continue
		var across := Vector2(-c.fwd.y, c.fwd.x)
		var lat := d.dot(across)
		if absf(c.v) < 0.2:  # stopped (or parked): solid, that's all
			var al: float = d.dot(c.fwd)
			if absf(al) < c.hl + r + 0.1 and absf(lat) < c.hw + r + 0.1:
				var push: Vector2 = c.fwd * signf(al) if c.hl - absf(al) < c.hw - absf(lat) else across * signf(lat)
				side += push * 2.0
			continue
		var go: Vector2 = c.fwd * signf(c.v)
		var ahead := d.dot(go)
		var road: float = c.hl + 1.0 + absf(c.v) * 2.5  # its road: the length of it, and where it'll be in a couple of seconds
		var wide: float = c.hw + 0.6 + r
		if ahead > -c.hl and ahead < road and absf(lat) < wide:  # in it: clear out, quick, the short way
			side += across * (signf(lat) if absf(lat) > 0.05 else signf(want.dot(across)) if absf(want.dot(across)) > 0.05 else 1.0) * 2.5
			hurry = 1.7
		else:
			var q := p + v * 1.2
			var qd: Vector2 = q - c.p
			if qd.dot(go) > -c.hl and qd.dot(go) < road and absf(qd.dot(across)) < wide:
				slow = 0.0  # about to step out in front of it: wait at the edge
		if p.y > DRIVE_Z.x and p.y < DRIVE_Z.y:
			hurry = maxf(hurry, 1.35)  # out on the lanes with cars about: step lively
	for kid: int in _claims:  # a car backing out: give it the room
		var k: Dictionary = _claims[kid]
		if _in_rect(p, k.c, k.ax, k.h, r):
			side += (p - k.c).normalized() * 2.0
			hurry = maxf(hurry, 1.5)
		elif _in_rect(p + v * 1.0, k.c, k.ax, k.h, r):
			slow = 0.0
	e.s = e.s.lerp(side.limit_length(1.4), minf(1.0, dt * 5.0))  # (eased: a drift aside, not a jerk)
	var out: Vector2 = (want + e.s).normalized() * speed * slow * hurry
	if boxed and slow > 0.0:  # no room either side of them: wait a moment, then squeeze by ("pardon me")
		e.wait = e.get("wait", 0.0) + dt
		out = want * speed * 0.4 if e.wait > 1.2 else Vector2.ZERO
	else:
		e.wait = 0.0
		if slow > 0.0 and open.is_valid() and not open.call(p.x + out.normalized().x * 0.3, p.y + out.normalized().y * 0.3):  # drifting aside into a shelf: less aside, sliding along it
			for f: float in [0.5, 0.25, 0.0]:
				var u: Vector2 = (want + e.s * f).normalized()
				if f == 0.0 or open.call(p.x + u.x * 0.3, p.y + u.y * 0.3):
					out = u * speed * slow * hurry
					break
	var mag := out.length()
	if mag > 0.001:  # the heading eased (a tenth of a second): turns, not twitches
		e.u = (e.get("u", out / mag) as Vector2).lerp(out / mag, minf(1.0, dt * 10.0)).normalized()
		out = e.u * mag
	_people[id] = e
	person(id, p, out, kind, r)
	return out


# ---- cars

static func blocked(id: int, back: bool, speed: float) -> bool:  # anybody in its road (and not claimed by somebody backing out)?
	if not _cars.has(id):
		return false
	var me: Dictionary = _cars[id]
	var go: Vector2 = me.fwd * (-1.0 if back else 1.0)
	var across := Vector2(-go.y, go.x)
	var road: float = me.hl + 1.2 + absf(speed) * 1.0 + speed * speed / 8.0  # stopping room for its speed
	for oid: int in _people:
		var o: Dictionary = _people[oid]
		if not _fresh(o):
			continue
		var d: Vector2 = o.p - me.p
		var ahead := d.dot(go)
		if ahead > me.hl * 0.5 and ahead < road and absf(d.dot(across)) < me.hw + 0.45 + o.r:
			return true
	for kid: int in _claims:
		if kid == id:
			continue
		var k: Dictionary = _claims[kid]
		if _in_rect(me.p, k.c, k.ax, k.h, 0.0):
			continue  # (already in it: on through and out)
		var s: float = me.hl
		while s < road:
			if _in_rect(me.p + go * s, k.c, k.ax, k.h, me.hw):
				return true
			s += 0.6
	return false

