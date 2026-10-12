extends RefCounted
## Finding a way round the store: a grid over the floor with everything solid marked off, A* across it, the path
## pulled straight where it can be.
## From the web game's store/shoppers.js (NAV, navGrid, navPath). The solid things are the web game's own floor boxes
## (data/interact.json, nav), as they stand in a fresh store: moving the level's furniture in Godot doesn't move them.

var cell := 0.25
var x0 := 0.0
var z0 := 0.0
var nx := 0
var nz := 0
var g := PackedByteArray()  # blocked, with walking room round things
var hard := PackedByteArray()  # the things themselves


func _init(d: Dictionary) -> void:
	cell = d.cell
	x0 = d.x0
	z0 = d.z0
	nx = ceili((d.x1 - x0) / cell)
	nz = ceili((d.z1 - z0) / cell)
	g.resize(nx * nz)
	hard.resize(nx * nz)
	var pad: float = d.pad
	for c: Array in d.colliders:  # [x0, x1, z0, z1]
		var i0 := maxi(0, ceili((c[0] - pad - x0) / cell - 0.5))
		var i1 := mini(nx - 1, floori((c[1] + pad - x0) / cell - 0.5))
		var k0 := maxi(0, ceili((c[2] - pad - z0) / cell - 0.5))
		var k1 := mini(nz - 1, floori((c[3] + pad - z0) / cell - 0.5))
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1):
				g[k * nx + i] = 1
		var h0 := maxi(0, floori((c[0] - x0) / cell))  # every cell it touches: a wall is never skipped over
		var h1 := mini(nx - 1, floori((c[1] - x0) / cell))
		var q0 := maxi(0, floori((c[2] - z0) / cell))
		var q1 := mini(nz - 1, floori((c[3] - z0) / cell))
		for k in range(q0, q1 + 1):
			for i in range(h0, h1 + 1):
				hard[k * nx + i] = 1


func at(x: float, z: float) -> int:
	var i := floori((x - x0) / cell)
	var k := floori((z - z0) / cell)
	return -1 if i < 0 or k < 0 or i >= nx or k >= nz else k * nx + i


func open_at(x: float, z: float) -> bool:
	var n := at(x, z)
	return n >= 0 and g[n] == 0


func xy(n: int) -> Vector2:
	return Vector2(x0 + (n % nx + 0.5) * cell, z0 + (n / nx + 0.5) * cell)


func reachable_from(x: float, z: float) -> PackedByteArray:  # flood fill: what can actually be walked to from there
	var reach := PackedByteArray()
	reach.resize(g.size())
	var q := [at(x, z)]
	if q[0] < 0:
		return reach
	reach[q[0]] = 1
	while not q.is_empty():
		var n: int = q.pop_back()
		var i := n % nx
		for m: int in [n + 1 if i + 1 < nx else -1, n - 1 if i > 0 else -1, n + nx, n - nx]:
			if m >= 0 and m < reach.size() and reach[m] == 0 and g[m] == 0:
				reach[m] = 1
				q.append(m)
	return reach


func _near(x: float, z: float) -> int:  # a blocked start or goal: the nearest open cell you could step to, never through anything solid
	var i := clampi(floori((x - x0) / cell), 0, nx - 1)
	var k := clampi(floori((z - z0) / cell), 0, nz - 1)
	var n0 := k * nx + i
	if g[n0] == 0:
		return n0
	var seen := { n0: true }
	var q := [n0]
	var h := 0
	while h < q.size() and h < 400:
		var n: int = q[h]
		h += 1
		var ni := n % nx
		for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			if ni + d[0] < 0 or ni + d[0] >= nx:
				continue
			var m: int = n + d[1] * nx + d[0]
			if m < 0 or m >= g.size() or seen.has(m) or (hard[m] == 1 and hard[n] == 0):  # (already inside something: work out of it, but never into the next thing)
				continue
			if g[m] == 0:
				return m
			seen[m] = true
			q.append(m)
	return -1


var _extra := {}  # cells shut for this one path: somebody standing in the way


func path(ax: float, az: float, bx: float, bz: float, standing: Array = []) -> Array:  # A* (8-way, binary heap), then string-pulled to straight runs. [] if there's no way. standing: [Vector2, ...] to go round, a body's width each
	_extra = {}
	for s: Vector2 in standing:
		var r := 0.22 + 0.3
		for k in range(maxi(0, ceili((s.y - r - z0) / cell - 0.5)), mini(nz - 1, floori((s.y + r - z0) / cell - 0.5)) + 1):
			for i in range(maxi(0, ceili((s.x - r - x0) / cell - 0.5)), mini(nx - 1, floori((s.x + r - x0) / cell - 0.5)) + 1):
				_extra[k * nx + i] = true
	_extra.erase(at(ax, az))  # (never where they're standing themselves)
	var s := _near(ax, az)
	var e := _near(bx, bz)
	if s < 0 or e < 0:
		return []
	var cost := PackedFloat32Array()
	cost.resize(g.size())
	cost.fill(INF)
	var from := PackedInt32Array()
	from.resize(g.size())
	from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(g.size())
	var heap: Array = [[0.0, s]]
	var ei := e % nx
	var ek := e / nx
	cost[s] = 0.0
	while not heap.is_empty():
		var top: Array = heap[0]  # pop
		var last: Array = heap.pop_back()
		if not heap.is_empty():
			heap[0] = last
			var i := 0
			while true:
				var m := i
				for c in [2 * i + 1, 2 * i + 2]:
					if c < heap.size() and heap[c][0] < heap[m][0]:
						m = c
				if m == i:
					break
				var sw: Array = heap[i]
				heap[i] = heap[m]
				heap[m] = sw
				i = m
		var n: int = top[1]
		if closed[n] == 1:
			continue
		closed[n] = 1
		if n == e:
			break
		var ni := n % nx
		for d: Array in [[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0], [1, 1, 1.414], [1, -1, 1.414], [-1, 1, 1.414], [-1, -1, 1.414]]:
			if ni + d[0] < 0 or ni + d[0] >= nx:
				continue
			var m: int = n + d[1] * nx + d[0]
			if m < 0 or m >= g.size() or g[m] == 1 or closed[m] == 1 or _extra.has(m):
				continue
			if d[0] != 0 and d[1] != 0 and (g[n + d[0]] == 1 or g[n + d[1] * nx] == 1):
				continue  # no cutting a corner
			var c: float = cost[n] + d[2]
			if c + 1e-6 < cost[m]:
				cost[m] = c
				from[m] = n
				var dx := absi(m % nx - ei)
				var dz := absi(m / nx - ek)
				heap.append([c + maxi(dx, dz) + 0.414 * mini(dx, dz), m])  # push
				var j := heap.size() - 1
				while j > 0 and heap[(j - 1) / 2][0] > heap[j][0]:
					var up: Array = heap[j]
					heap[j] = heap[(j - 1) / 2]
					heap[(j - 1) / 2] = up
					j = (j - 1) / 2
	if from[e] < 0 and e != s:
		return []
	var cells: Array[Vector2] = []
	var n := e
	while n >= 0:
		cells.push_front(xy(n))
		n = from[n]
	var out: Array = [cells[0]]
	for i in range(1, cells.size()):
		if not _clear(out[-1], cells[i]):
			out.append(cells[i - 1])
	out.append(Vector2(bx, bz))
	if not open_at(bx, bz):
		out[-1] = cells[-1]
	return out


func _clear(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / 0.1)
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if not open_at(p.x, p.y):
			return false
	return true
