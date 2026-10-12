extends Node
## The store kept between sessions: saved every ten seconds and on the way out, to user://store.json; picked up again
## at the start. F9 starts over (a fresh store).
## The web game keeps its store the same way (store/main.js, saveState: a JSON blob, every few seconds and on
## beforeunload); what's in it here is what's over here so far: the day and the hour, where you are, the lights, the
## doors and the pass-through, the back ladder, the cooler, the deadbolt, where the stool and the standee were put,
## and the tapes: what's out on rental and when it's due, what's in the Returns bin, what you're carrying, what's in
## the VCR, how far each tape's wound and which were stolen; the till; and the members' accounts (what
## they owe, how they feel about the place, who's banned). Whoever was in the store isn't: they've gone when you're back.
## Not when it's run with arguments (--check, --shot): those always start fresh, and leave the save alone.

const PATH := "user://store.json"

var _t := 0.0
var _live := false

@onready var main: Node3D = get_parent()


func _ready() -> void:
	_live = OS.get_cmdline_user_args().is_empty()
	if _live:
		call_deferred("load_store")


func _process(dt: float) -> void:
	_t += dt
	if _live and _t > 10.0:
		_t = 0.0
		save_store()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _live:
		save_store()


func _unhandled_input(e: InputEvent) -> void:
	if _live and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F9:  # a fresh store
		_live = false
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		get_tree().reload_current_scene()
		Clock.h = Clock.START
		Clock.day = 1
		Clock.warp = 0.0


func _xf(n: Node3D) -> Array:
	return [n.global_position.x, n.global_position.y, n.global_position.z, n.rotation.y] if n else []


func snapshot() -> Dictionary:
	var P: CharacterBody3D = main.get_node("Player")
	var L: Node = main.get_node("Lights")
	var F: Node = main.get_node("Fixtures")
	var Th: Node = main.get_node("Things")
	var T: Node = main.get_node("Tapes")
	var S: Node = main.get_node("Shoppers")
	var C: Node = main.get_node("Checkout")
	var wound := {}
	for t: Dictionary in T.tapes:
		if t.ep != 0 or t.at > 0.0:
			wound[t.k] = [t.ep, t.at]
	var at: Vector3 = Th._stood.at if Th.on_stool else P.global_position  # (sat down or on a ladder: where you were stood)
	if P.seat != null and not Th.on_stool:
		at = main.get_node("Interact").stood_at.get("at", at)
	return {
		"v": 1, "clock": { "h": Clock.h, "day": Clock.day },
		"player": [at.x, at.y, at.z, P.rotation.y],
		"lights": { "zones": L.zone_on, "lamps": L.lamps.map(func(l: Dictionary) -> bool: return l.on) },
		"doors": main.get_node("Interact").doors.map(func(d: Dictionary) -> bool: return d.open),
		"fixtures": { "flap": F.flap_open, "back": F.back_down },
		"things": { "cooler": Th.cooler_open, "locked": Th.locked, "cine": Th.cine_on, "stool": _xf(Th._stool), "cutout": _xf(Th._cutout) },
		"tapes": {
			"rented": S.rented.map(func(r: Array) -> Array: return [r[0].k, r[1], r[2], r[3] if r.size() > 3 else 0]),
			"bin": T.return_bin.map(func(t: Dictionary) -> String: return t.k),
			"inv": T.inv.map(func(t: Dictionary) -> String: return t.k), "sel": T.inv_sel,
			"playing": [T.playing.tape.k, T.playing.idx] if T.playing != null else [],
			"wound": wound,
			"lost": T.tapes.filter(func(t: Dictionary) -> bool: return t.get("lost", false)).map(func(t: Dictionary) -> String: return t.k),
			"rewinder": T.rewinder.tape.k if not T.rewinder.is_empty() and T.rewinder.tape != null else "",
			"dana": main.get_node("Staff").carry.map(func(t: Dictionary) -> String: return t.k),
		},
		"members": S.members.records(),
		"chores": main.get_node("Chores").snapshot(),
		"shift": main.get_node("Shift").snapshot(),
		"phone": main.get_node("Phone").snapshot(),
		"snacks": main.get_node("Snacks").snapshot(),
		"till": { "served": C.served, "rentals": C.rentals, "take": C.take, "score": C.score },
	}


func save_store() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snapshot()))


func load_store() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not d is Dictionary or d.get("v") != 1:
		return false
	apply(d)
	return true


func apply(d: Dictionary) -> void:
	var P: CharacterBody3D = main.get_node("Player")
	var L: Node = main.get_node("Lights")
	var F: Node = main.get_node("Fixtures")
	var Th: Node = main.get_node("Things")
	var T: Node = main.get_node("Tapes")
	var S: Node = main.get_node("Shoppers")
	var C: Node = main.get_node("Checkout")
	Clock.h = d.clock.h
	Clock.day = int(d.clock.day)
	Clock.warp = 0.0
	P.global_position = Vector3(d.player[0], d.player[1] + 0.05, d.player[2])
	P.rotation.y = d.player[3]
	for z: String in d.lights.zones:  # (straight to it: no warming up)
		if L.zone_on.has(z):
			L.zone_on[z] = d.lights.zones[z]
			L.zone_lvl[z] = 1.0 if d.lights.zones[z] else 0.0
			for p: StandardMaterial3D in L._panels.get(z, []):
				p.albedo_color = L.PANEL_ON if d.lights.zones[z] else L.PANEL_OFF
	for i in mini(L.lamps.size(), d.lights.lamps.size()):
		L.set_lamp(L.lamps[i], d.lights.lamps[i])
	var doors: Array = main.get_node("Interact").doors
	for i in mini(doors.size(), d.doors.size()):
		doors[i].open = d.doors[i]
		doors[i].a = doors[i].openA if d.doors[i] and not doors[i].push else 0.0
	F.flap_open = d.fixtures.flap
	F.back_down = d.fixtures.back
	if F.back_down and F._slide:
		F._slide.position.y = 0.0
	Th.cooler_open = d.things.cooler
	Th.cine_on = d.things.cine
	if d.things.locked != Th.locked:
		Th.aim = "lock"
		Th.on_e()
		Th.aim = ""
	for pair in [[Th._stool, d.things.stool], [Th._cutout, d.things.cutout]]:
		if pair[0] and pair[1].size() == 4:
			pair[0].global_position = Vector3(pair[1][0], pair[1][1], pair[1][2])
			pair[0].rotation.y = pair[1][3]
	var by_key := {}
	for t: Dictionary in T.tapes:
		by_key[t.k] = t
	for k: String in d.tapes.wound:
		if by_key.has(k):
			by_key[k].ep = int(d.tapes.wound[k][0])
			by_key[k].at = d.tapes.wound[k][1]
	T.batch = true  # every tape that's off the shelf, taken off it in one go
	S.rented.clear()
	for r: Array in d.tapes.rented:
		if by_key.has(r[0]):
			T.set_on_shelf(by_key[r[0]], false)
			S.rented.append([by_key[r[0]], int(r[1]), int(r[2]), int(r[3]) if r.size() > 3 and S.members.by_num.has(int(r[3])) else S.members.all.pick_random().num])  # (out before there were members: on somebody's account)
	T.return_bin.clear()
	for k: String in d.tapes.bin:
		if by_key.has(k):
			T.set_on_shelf(by_key[k], false)
			T.return_bin.append(by_key[k])
	var carried := []
	for k: String in d.tapes.inv:
		if by_key.has(k):
			T.set_on_shelf(by_key[k], false)
			carried.append(by_key[k])
	var in_vcr = by_key.get(d.tapes.playing[0]) if d.tapes.playing.size() == 2 else null
	if in_vcr != null:
		T.set_on_shelf(in_vcr, false)
	for k: String in d.tapes.get("lost", []):  # stolen: gone for good
		if by_key.has(k):
			T.set_on_shelf(by_key[k], false)
			by_key[k].lost = true
	var extra: Array = d.tapes.get("dana", []).duplicate()  # (what was in the rewinder or Dana's arms: into the bin)
	if d.tapes.get("rewinder", "") != "":
		extra.append(d.tapes.rewinder)
	for k: String in extra:
		if by_key.has(k):
			T.set_on_shelf(by_key[k], false)
			T.return_bin.append(by_key[k])
	T.batch = false
	T.commit()
	T.inv.clear()
	T.inv_stash()
	for t: Dictionary in carried:
		T._take(t)
	if d.tapes.sel >= 0 and d.tapes.sel < T.inv.size():
		T.inv_select(int(d.tapes.sel))
	elif not T.inv.is_empty():
		T.inv_stash()
	if in_vcr != null:
		T.play_episode(int(d.tapes.playing[1]), in_vcr)  # (on from where it had got to)
	S.members.restore(d.get("members", {}))
	main.get_node("Chores").restore(d.get("chores", {}))
	main.get_node("Shift").restore(d.get("shift", {}))
	main.get_node("Phone").restore(d.get("phone", {}))
	main.get_node("Snacks").restore(d.get("snacks", {}))
	C.served = int(d.till.served)
	C.rentals = int(d.till.rentals)
	C.take = d.till.take
	C.score = int(d.till.score)
