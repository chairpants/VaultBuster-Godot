extends Node
## Tapes: off the shelf into your hand, held up to look at, back into its slot; into the VCR and onto the screens.
## From the web game: store/tv.js (pickup, showTape, putBack, vcrUse, playEpisode, eject), store/checkout.js (what the
## crosshair's on: a tape's cover within 3.4 m, your own tape's empty slot within 8 cm of its middle; what a click
## does), store/shelves.js (setOnShelf), store/main.js (the words of the tips). Every copy's slot and episodes come
## from the web game too, in data/tapes.json (tests/export-glb.mjs --data).
##
## Click a tape: it comes off the shelf, held up to look at. Click again: it's in your hand. Right-click while you're
## still looking: back it goes. Click its empty slot: back it goes. Click with one in hand: held up again.
## E at the TV (within 4.5 m) or the theater's screen (9 m): in it goes, and plays on every screen (those two, and
## the monitors hung over the aisles); E again: out it comes.
##
## Different here:
## - The shelves are whole meshes, as in the web game, and a tape leaves one the same way (its corners pulled out of
##   sight); but which corners are a tape's is found by where they are, not by counting, since the level's meshes
##   aren't in the web game's order. The tape in your hand is those same triangles, lifted out: its own cover.
## - One tape at a time: there's no inventory yet, so a second won't come off the shelf while your hand's full.
## - A tape goes on from where it was wound to, to the second (the web game can't seek, so it restarts the episode).
## - No case on the coffee table, no picture settings.

const REACH := 3.4
const CELL := 0.25
const YELLOW := Color(1, 0.831, 0)
var HAND := Transform3D(Basis.from_euler(Vector3(0.05, -0.4, 0.06)), Vector3(0.3, -0.28, -0.55))  # carried
var LOOK := Transform3D(Basis.from_euler(Vector3(0, PI / 2, 0)), Vector3(0, 0, -0.34))  # held up, cover to you

var size := Vector3(0.032, 0.192, 0.105)  # TAPE: thick, tall, wide
var tapes: Array = []
var screens: Array = []
var hovered = null  # the tape the crosshair's on
var held = null
var inspecting := false  # held up in view (true) or carried (false)
var peek = null  # the tape you've only just picked up to look at: right-click still puts it back
var aim_slot := false
var aim_tv = null  # the screen the crosshair's on
var playing = null  # { tape, idx }

var _grid := {}  # cell -> [tape index]
var _verts := {}  # cell -> PackedInt32Array of (mesh, surface, vertex) triples: the level's corners near any slot
var _meshes: Array[MeshInstance3D] = []
var _arrays: Array = []  # per mesh: its surfaces' arrays
var _mats: Array = []
var _hand := Node3D.new()
var _hand_mesh := MeshInstance3D.new()
var _box := MeshInstance3D.new()
var _quads: Array[MeshInstance3D] = []

@onready var player: CharacterBody3D = $"../Player"
@onready var cam: Camera3D = $"../Player/Camera"
@onready var hud: CanvasLayer = $"../HUD"
@onready var video: Node = $"../Video"


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tapes.json"))
	size = Vector3(data.size.w, data.size.h, data.size.d)
	tapes = data.tapes
	screens = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).get("screens", [])
	var near := {}  # every cell a slot reaches into
	var region := AABB(_pos(tapes[0]), Vector3.ZERO)
	for i in tapes.size():
		var t: Dictionary = tapes[i]
		t.merge({ "off": false, "ep": 0, "at": 0.0 })
		var p := _pos(t)
		region = region.expand(p)
		_grid.get_or_add(_cell(p), []).append(i)
		for dx in [-0.08, 0.08]:
			for dy in [-0.11, 0.11]:
				for dz in [-0.08, 0.08]:
					near[_cell(p + Vector3(dx, dy, dz))] = true
	region = region.grow(0.3)
	var kept := 0
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not region.intersects(mi.global_transform * mi.get_aabb()):
			continue
		var surfaces := []
		var mats := []
		var any := false
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			surfaces.append(arrays)
			mats.append(mi.mesh.surface_get_material(s))
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in vs.size():
				var c := _cell(mi.global_transform * vs[v])
				if near.has(c):
					_verts.get_or_add(c, PackedInt32Array()).append_array([_meshes.size(), s, v])
					any = true
					kept += 1
		if any:
			_meshes.append(mi)
			_arrays.append(surfaces)
			_mats.append(mats)
	print("tapes: %d on the shelves, %d corners of %d meshes by their slots" % [tapes.size(), kept, _meshes.size()])
	_box.mesh = _wire_box()
	_box.visible = false
	add_child(_box)
	cam.add_child(_hand)
	_hand.add_child(_hand_mesh)
	_hand.visible = false
	var every: Array = screens.duplicate()
	every.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).get("minis", []))  # ...and the monitors hung over the aisles
	for sc: Dictionary in every:  # the picture, a hair in front of each screen: there while a tape's playing
		var q := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(sc.w, sc.h)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = video.texture
		m.albedo_color = Color(0.85, 0.85, 0.85)  # (the web game's -15%: blown-out whites were blinding)
		quad.material = m
		q.mesh = quad
		if sc.has("q"):
			q.basis = Basis(Quaternion(sc.q[0], sc.q[1], sc.q[2], sc.q[3]))
			q.position = Vector3(sc.p[0], sc.p[1], sc.p[2]) + q.basis.z * 0.006
		else:
			q.position = Vector3(sc.x, sc.y, sc.z) + Vector3(sin(sc.ry), 0, cos(sc.ry)) * 0.006
			q.rotation.y = sc.ry
		q.visible = false
		add_child(q)
		_quads.append(q)
	video.started.connect(_on_started)
	video.ended.connect(func() -> void: step_episode(1))
	video.failed.connect(func(why: String) -> void: hud.toast("⚠ " + why))


func _pos(t: Dictionary) -> Vector3:
	return Vector3(t.p[0], t.p[1], t.p[2])


func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).floor())


func _local(t: Dictionary, world: Vector3) -> Vector3:  # in the tape's own frame: x through it, y up it, z across it
	return Basis(Vector3.UP, -t.ry) * (world - _pos(t))


func _wire_box() -> ArrayMesh:  # the highlight: the tape's edges, in yellow (turned per tape to match its shelf)
	var h := size / 2.0
	var pts := PackedVector3Array()
	for a in 3:
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var p := Vector3.ZERO
				p[(a + 1) % 3] = s1 * h[(a + 1) % 3]
				p[(a + 2) % 3] = s2 * h[(a + 2) % 3]
				p[a] = -h[a]
				pts.append(p)
				p[a] = h[a]
				pts.append(p)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = YELLOW
	mesh.surface_set_material(0, m)
	return mesh


# ---- a tape's corners in the shelves' meshes

func _corners(t: Dictionary) -> Array:  # [[mesh, surface, vertex], ...], found once
	if t.has("v"):
		return t.v
	var out := []
	var seen := {}
	var p := _pos(t)
	for dx in [-0.08, 0.08]:
		for dy in [-0.11, 0.11]:
			for dz in [-0.08, 0.08]:
				var c := _cell(p + Vector3(dx, dy, dz))
				if seen.has(c) or not _verts.has(c):
					continue
				seen[c] = true
				var list: PackedInt32Array = _verts[c]
				for k in range(0, list.size(), 3):
					var vs: PackedVector3Array = _arrays[list[k]][list[k + 1]][Mesh.ARRAY_VERTEX]
					var l := _local(t, _meshes[list[k]].global_transform * vs[list[k + 2]])
					# (deeper than the tape behind it: they tip back 10 degrees against the backing board, so the top's 3 cm further in)
					if l.x > -size.x / 2.0 - 0.045 and l.x < size.x / 2.0 + 0.012 and absf(l.y) < size.y / 2.0 + 0.012 and absf(l.z) < size.z / 2.0 + 0.008:
						out.append([list[k], list[k + 1], list[k + 2]])
	t.v = out
	return out


func set_on_shelf(t: Dictionary, on: bool) -> void:  # show / hide one copy in the shelves' meshes (setOnShelf)
	if t.off == not on:
		return
	var corners := _corners(t)
	if not on and not t.has("mesh"):
		t.mesh = _lift(t, corners)
	var touched := {}
	if not on:
		t.saved = []
	for i in corners.size():
		var c: Array = corners[i]
		var vs: PackedVector3Array = _arrays[c[0]][c[1]][Mesh.ARRAY_VERTEX]
		if on:
			vs[c[2]] = t.saved[i]
		else:
			t.saved.append(vs[c[2]])
			vs[c[2]] = _meshes[c[0]].global_transform.affine_inverse() * Vector3(0, -10, 0)  # collapsed, under the floor
		_arrays[c[0]][c[1]][Mesh.ARRAY_VERTEX] = vs
		touched[c[0]] = true
	for m: int in touched:
		var mesh := ArrayMesh.new()
		for s in _arrays[m].size():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays[m][s])
			mesh.surface_set_material(s, _mats[m][s])
		_meshes[m].mesh = mesh
	t.off = not on


func _lift(t: Dictionary, corners: Array) -> ArrayMesh:  # the tape's own triangles, out of the shelves' meshes, about its middle
	var mesh := ArrayMesh.new()
	var by := {}  # [mesh, surface] -> { vertex: true }
	for c: Array in corners:
		by.get_or_add([c[0], c[1]], {})[c[2]] = true
	var cover_x := 0.0  # the foot of the cover: which face of the tape it's on
	var lean := 0.0
	for key: Array in by:
		var mine: Dictionary = by[key]
		var src: Array = _arrays[key[0]][key[1]]
		var xf := _meshes[key[0]].global_transform
		var rot := Basis(Vector3.UP, -t.ry) * xf.basis.orthonormalized()
		var index := {}
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var has_n: bool = src[Mesh.ARRAY_NORMAL] != null
		var has_uv: bool = src[Mesh.ARRAY_TEX_UV] != null
		var has_c: bool = src[Mesh.ARRAY_COLOR] != null
		for v: int in mine:
			index[v] = vs.size()
			vs.append(_local(t, xf * sv[v]))
			if has_n:
				ns.append(rot * src[Mesh.ARRAY_NORMAL][v])
			if has_uv:
				uvs.append(src[Mesh.ARRAY_TEX_UV][v])
			if has_c:
				cols.append(src[Mesh.ARRAY_COLOR][v])
		var tris := PackedInt32Array()
		if src[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
			for k in range(0, idx.size(), 3):
				if mine.has(idx[k]) and mine.has(idx[k + 1]) and mine.has(idx[k + 2]):
					tris.append_array([index[idx[k]], index[idx[k + 1]], index[idx[k + 2]]])
		else:
			for k in range(0, sv.size(), 3):
				if mine.has(k) and mine.has(k + 1) and mine.has(k + 2):
					tris.append_array([index[k], index[k + 1], index[k + 2]])
		if tris.is_empty():
			continue
		out[Mesh.ARRAY_VERTEX] = vs
		out[Mesh.ARRAY_INDEX] = tris
		if has_n:
			out[Mesh.ARRAY_NORMAL] = ns
		if has_uv:
			out[Mesh.ARRAY_TEX_UV] = uvs
		if has_c:
			out[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var mat: Material = _mats[key[0]][key[1]]
		if has_c and mat is BaseMaterial3D and not mat.vertex_color_use_as_albedo:  # the case: its cover's colour, painted on its corners
			mat = mat.duplicate()
			mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		if has_uv and vs.size() <= 8:  # the cover: which face it's on, and how far it tips
			var top := Vector3.ZERO
			var bottom := Vector3.ZERO
			for v in vs:
				if v.y > 0.0:
					top += v
				else:
					bottom += v
			cover_x = bottom.x
			lean = atan2((top.x - bottom.x) * 2.0 / vs.size(), size.y)
	t.flip = cover_x > 0.0  # (in the hand the cover's turned to the -x face, as the web game's is)
	t.lean = lean
	return mesh


# ---- in your hand

func pickup(t: Dictionary) -> void:  # off the shelf, held up to look at
	set_on_shelf(t, false)
	show_tape(t)
	inspecting = true


func show_tape(t: Dictionary) -> void:  # the tape in your hand (fresh off the shelf, or back out of the VCR)
	held = t
	inspecting = false
	_hand_mesh.mesh = t.get("mesh")
	_hand_mesh.rotation = Vector3(0, PI if t.get("flip", false) else 0.0, 0)
	_hand_mesh.rotate_object_local(Vector3.BACK, t.get("lean", 0.0))  # upright, not tipped the way it sat
	_hand.transform = HAND
	_hand.visible = true


func release() -> void:  # clears the hand without touching the shelf (into the VCR)
	held = null
	inspecting = false
	peek = null
	_hand.visible = false


func put_back() -> void:  # back into its own shelf slot
	if held != null:
		set_on_shelf(held, true)
	release()


func _process(dt: float) -> void:
	if held != null:
		_hand.transform = _hand.transform.interpolate_with(LOOK if inspecting else HAND, minf(1.0, dt * 14.0))
	if playing != null and not video.url.is_empty():  # the tape winds forward as it plays
		playing.tape.ep = playing.idx
		playing.tape.at = video.position


func _unhandled_input(e: InputEvent) -> void:
	if not e is InputEventMouseButton or not e.pressed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or player.fly:
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:  # right click puts down what's in hand, if it's only being looked at
		if held != null and held == peek:
			put_back()
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if held != null and inspecting:  # tuck the held-up tape back in hand (it's yours now)
			inspecting = false
			peek = null
		elif aim_slot:  # slotted back into its own spot on the shelf
			put_back()
		elif hovered != null:
			if held != null:
				hud.toast("One tape at a time for now: put that one back first")
			else:
				pickup(hovered)
				peek = hovered
		elif held != null:  # hold it up to look at it
			inspecting = true


# ---- what the crosshair's on (called from interact.gd, after the doors); returns the tip, "" if it's nothing of ours

func clear_aim() -> void:
	hovered = null
	aim_slot = false
	aim_tv = null
	_box.visible = false


func aim(from: Vector3, dir: Vector3, hit: Dictionary, hit_d: float) -> String:
	clear_aim()
	if held != null and inspecting:
		return "%s\n%s\nClick — keep it · Right-click — put it back" % [held.t, ("New Releases · " if held.n else "") + held.c]
	if held != null and held.off:  # its own empty slot: within 8 cm of the middle of it, nothing solid in front
		var at := _pos(held) - from
		var t := at.dot(dir)
		aim_slot = t > 0.3 and t < REACH and (at - dir * t).length() < 0.08 and hit_d > t - 0.15
		if aim_slot:
			_show_box(held)
			return "Click — put %s back" % held.t
	if hit and hit_d < REACH:  # a tape: the one whose slot the crosshair lands in (and that's really there)
		var best := INF
		var c := _cell(hit.position)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for i: int in _grid.get(c + Vector3i(dx, dy, dz), []):
						var t: Dictionary = tapes[i]
						var l := _local(t, hit.position)
						if not t.off and absf(l.x) < 0.06 and absf(l.y) < size.y / 2.0 + 0.01 and absf(l.z) < size.z / 2.0 + 0.012 and l.length() < best:
							best = l.length()
							hovered = t
		if hovered != null and _corners(hovered).is_empty():
			hovered = null  # (out on rental when the level was made: an empty slot)
		if hovered != null:
			_show_box(hovered)
			return "%s\n%s" % [hovered.t, hovered.c]
	for sc: Dictionary in screens:  # a screen: you have to actually be looking at it
		var n := Vector3(sin(sc.ry), 0, cos(sc.ry))
		var facing := dir.dot(n)
		if facing > -0.01:
			continue
		var t: float = (Vector3(sc.x, sc.y, sc.z) - from).dot(n) / facing
		var on := from + dir * t - Vector3(sc.x, sc.y, sc.z)
		if t > 0.0 and t < sc.reach and t < hit_d + 0.2 and absf(on.dot(Vector3(cos(sc.ry), 0, -sin(sc.ry)))) < sc.w / 2.0 and absf(on.y) < sc.h / 2.0:
			aim_tv = sc
			if held != null:
				return "Press E to insert “%s” into the TV" % held.t
			return "Press E to eject the tape" if playing != null else "Pick up a tape from the shelves to play it here"
	return ""


func _show_box(t: Dictionary) -> void:
	_box.position = _pos(t)
	_box.rotation.y = t.ry
	_box.visible = true


# ---- the VCR

func vcr_use() -> void:  # E on the TV or the theater's screen: one tape, every screen
	if held != null:
		var tape: Dictionary = held
		var old = playing.tape if playing != null else null
		play_episode(tape.ep, tape)  # it plays from wherever it's wound to
		release()  # the tape leaves your hand...
		if old != null:
			show_tape(old)  # ...and the one that was in there comes out into it
	elif playing != null:
		eject()


func play_episode(idx: int, tape: Dictionary = playing.tape if playing != null else {}) -> void:
	if tape.is_empty():
		return
	idx = clampi(idx, 0, tape.e.size() - 1)
	var at: float = tape.at if idx == tape.ep else 0.0
	playing = { "tape": tape, "idx": idx }
	tape.ep = idx
	hud.toast("Loading: %s…" % tape.t)
	video.play_episode(tape.e[idx], at)
	for q in _quads:
		q.visible = true


func _on_started() -> void:
	if playing == null:
		return
	var bits: PackedStringArray = playing.tape.e[playing.idx][1].split(" - ")
	var has_code := bits.size() > 1 and RegEx.create_from_string("(?i)S\\d+E\\d+").search(bits[1]) != null
	var code := bits[1] + " · " if has_code else ""
	var ep_name := " - ".join(bits.slice(2 if has_code else 1))
	hud.toast("Now Playing: %s — %s%s" % [playing.tape.t, code, ep_name if ep_name != "" else playing.tape.e[playing.idx][1]])


func step_episode(d: int) -> void:  # the next one on the tape, when one runs out
	if playing == null:
		return
	if playing.idx + d >= playing.tape.e.size():
		playing.tape.at = 0.0  # run out: it sits in the machine, wound to the end
		for q in _quads:
			q.visible = false
		return
	playing.tape.at = 0.0
	play_episode(playing.idx + d)


func eject() -> void:
	var tape: Dictionary = playing.tape
	video.stop()
	playing = null
	for q in _quads:
		q.visible = false
	if held == null:
		show_tape(tape)  # the tape comes back out into your hand, not the shelf
	else:
		set_on_shelf(tape, true)  # hands full: it goes home (the web game: to Returns)
		hud.toast("%s went back on its shelf" % tape.t)
