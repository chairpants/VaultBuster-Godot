extends Node
## Tony's arcade: two cabinets in the corner by his door, Space Invaders and Asteroids, playing their attract screens
## whenever you're near. E (a quarter, as a customer) steps you up to one, the view on its screen.
##   Space Invaders: A/D or the arrows move the cannon, Space fires (one shot on screen at a time). Five rows of eleven
##   march across and down, faster the fewer there are; they drop bombs; the bunkers crumble; the saucer crosses now
##   and then. Three lives; a cleared wave brings the next one in lower.
##   Asteroids: A/D turn, W thrust (it drifts: there's no brake), Space fires (four shots at once). A big rock splits in
##   two mediums, a medium in two smalls. Three ships; a cleared screen brings in one more rock than the last.
## E or Esc walks away; the high scores stay on the machines. And Tony sells you a slice ($1.50), as a customer.
## From the web game's tonys/arcade.js (arcadeStart, arcadeStop, siNew, siWave, siBunkers, siTick, siDraw, asNew,
## asWave, asRock, asFire, asTick, asDraw, invadersFrame, tonyTick's attract screens, tonyE) and tonys/inside.js (the
## cabinets, INVADER).

const GAMES := [["SPACE INVADERS", "#39ff5a"], ["ASTEROIDS", "#ffffff"]]  # [name, glow]
const W := 256
const H := 192
const SI := { "top": 30, "bunkerY": 148, "playerY": 176, "ground": 186 }
const SI_PTS := { "squid": 30, "crab": 20, "octo": 10 }
const AS_R := [0, 4, 8, 15]
const INVADER := {
	"squid": [["00011000", "00111100", "01111110", "11011011", "11111111", "00100100", "01011010", "10100101"], ["00011000", "00111100", "01111110", "11011011", "11111111", "01011010", "10000001", "01000010"]],
	"crab": [["00100000100", "00010001000", "00111111100", "01101110110", "11111111111", "10111111101", "10100000101", "00011011000"], ["00100000100", "10010001001", "10111111101", "11101110111", "11111111111", "01111111110", "00100000100", "01000000010"]],
	"octo": [["000011110000", "011111111110", "111111111111", "111001100111", "111111111111", "000110011000", "001101101100", "110000000011"], ["000011110000", "011111111110", "111111111111", "111001100111", "111111111111", "001110011100", "011001100110", "001100001100"]],
}
const TONY_X0 := 13.15
const SLICE := 1.5

var on := false
var scores := [0, 0]
var _i := 0
var _g := {}  # the game being played
var _from := {}  # where you were stood
var _screens: Array = []  # { vp, ctl, mesh, att, t, name, glow, stars }
var _aim := -1  # the cabinet the crosshair's on (or -2: Tony's counter)
var _t := 0.0
var _font := SystemFont.new()

@onready var player: CharacterBody3D = $"../Player"
@onready var hud: CanvasLayer = $"../HUD"
@onready var amb: Node = $"../Ambience"


func _ready() -> void:
	_font.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
	_font.font_weight = 700
	_build.call_deferred()


func _build() -> void:  # each cabinet's screen in the level, drawn from here instead
	for i in GAMES.size():
		var at := Vector3(TONY_X0 + 0.8, 1.42, 3.2 + i * 0.95)
		var mesh: MeshInstance3D = null
		for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
			var s := mi.get_aabb().size
			if absf(maxf(s.x, s.z) - 0.56) < 0.02 and absf(s.y - 0.42) < 0.03 and mi.global_position.distance_to(at) < 0.4:
				mesh = mi
		var vp := SubViewport.new()
		vp.size = Vector2i(W, H)
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var ctl := Control.new()
		ctl.size = Vector2(W, H)
		vp.add_child(ctl)
		var s := { "vp": vp, "ctl": ctl, "mesh": mesh, "att": {}, "t": 0.0, "name": GAMES[i][0], "glow": Color(GAMES[i][1]), "inv": { "x": 20.0, "y": 34.0, "dx": 4.0, "f": 0 } }
		ctl.draw.connect(_draw_screen.bind(i))
		_screens.append(s)
		if mesh != null:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_texture = vp.get_texture()
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.uv1_scale = Vector3(1, -1, 1)  # (the level's pictures are the other way up)
			m.uv1_offset = Vector3(0, 1, 0)
			mesh.material_override = m
		else:
			push_warning("%s's screen isn't where the web game has it in Tony's: it won't play" % GAMES[i][0])


# ---- at the machine

func take_aim(hit: Dictionary, hit_d: float) -> String:  # (interact.gd) a cabinet; or, as a customer, Tony's counter
	_aim = -1
	if on or not hit or hit_d > 2.0:
		return ""
	var at: Vector3 = hit.position
	for i in _screens.size():
		if Vector2(at.x - (TONY_X0 + 0.4), at.z - (3.2 + i * 0.95)).length() < 0.45 and at.y > 0.9 and at.y < 1.95:
			_aim = i
			return "E — play %s%s" % [GAMES[i][0], "\na quarter a game" if _customer() else ""]
	if _customer() and at.x > 13.5 and at.x < 19.0 and absf(at.z - 7.3) < 0.6 and at.y < 1.4:
		_aim = -2
		return "E — a slice ($%.2f)" % SLICE
	return ""


func _customer() -> bool:
	return $"../Shift".mode == "customer"


func on_e() -> bool:  # (interact.gd) -> it was ours
	if _aim == -2:
		var c: Node = $"../Customer"
		if Clock.h < 11.0 or Clock.h >= 23.0:
			hud.toast("Tony's is closed. 11 to 11, says the door")
		elif c.wallet < SLICE:
			hud.toast("A slice is $%.2f. You've got $%.2f" % [SLICE, c.wallet])
		else:
			c.wallet -= SLICE
			var tony = $"../People".tony
			if tony != null:
				tony.set_mood("happy")
			hud.toast("Tony: “Pepperoni, comin' up.” Hot, greasy, perfect. You eat it standing at the counter")
		return true
	if _aim >= 0 and not on:
		start(_aim)
		return true
	return false


func start(i: int) -> void:  # a quarter in, and you're at the machine: its screen in front of you (arcadeStart)
	if _customer():
		var c: Node = $"../Customer"
		if c.wallet < 0.25:
			hud.toast("It takes a quarter. You don't have one")
			return
		c.wallet -= 0.25
	_i = i
	_g = _as_new() if GAMES[i][0] == "ASTEROIDS" else _si_new()
	on = true
	var cam: Camera3D = player.get_node("Camera")
	_from = { "at": player.global_position, "yaw": player.rotation.y, "pitch": cam.rotation.x, "fov": cam.fov }
	player.set_physics_process(false)
	player.global_position = Vector3(TONY_X0 + 1.4, 0.0, 3.2 + i * 0.95)
	player.rotation.y = PI / 2.0
	cam.rotation.x = atan2(1.42 - 1.65, 0.64) - 0.02
	cam.fov = 50.0
	_beep(880.0, 0.15, "square", 0.04, 440.0)
	hud.toast("A / D turn · W thrust · SPACE fire · E to walk away" if GAMES[i][0] == "ASTEROIDS" else "A / D or ← → move · SPACE fire · E to walk away")


func stop() -> void:  # arcadeStop
	if not on:
		return
	on = false
	var cam: Camera3D = player.get_node("Camera")
	player.global_position = _from.at
	player.rotation.y = _from.yaw
	cam.rotation.x = _from.pitch
	cam.fov = _from.fov
	player.set_physics_process(true)
	var name: String = GAMES[_i][0]
	if _g.score > scores[_i]:
		scores[_i] = _g.score
		hud.toast("%s: %d. A new high score!" % [name, _g.score])
	else:
		hud.toast("%s: %d. Game over, man" % [name, _g.score])


func _unhandled_input(e: InputEvent) -> void:  # (siKey) at the machine it has the keyboard
	if not on or not (e is InputEventKey or e is InputEventMouseMotion):
		return
	get_viewport().set_input_as_handled()  # (and the mouse doesn't look away from the screen)
	if not e is InputEventKey or not e.pressed or e.echo:
		return
	if e.physical_keycode in [KEY_E, KEY_ESCAPE, KEY_Q]:
		stop()
	elif e.physical_keycode == KEY_SPACE:
		if GAMES[_i][0] == "ASTEROIDS":
			_as_fire(_g)
		elif _g.shot == null and _g.dead <= 0.0 and _g.over <= 0.0:
			_g.shot = Vector2(_g.px, SI.playerY - 4)
			_beep(1200.0, 0.08, "square", 0.03, -800.0)


func _key(a: Key, b: Key) -> bool:
	return Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b)


func _beep(f: float, d := 0.06, wave := "square", vol := 0.05, slide := 0.0) -> void:  # siBeep: from the machine
	amb.tone(Vector3(TONY_X0 + 0.5, 1.3, 3.2 + _i * 0.95), f, d, wave, vol, slide)


func _process(dt: float) -> void:  # tonyTick: the game being played, and (anyone near) the attract screens
	if on:
		if GAMES[_i][0] == "ASTEROIDS":
			_as_tick(minf(dt, 0.05))
		else:
			_si_tick(minf(dt, 0.05))
		_redraw(_i)
	if player.global_position.distance_to(Vector3(17, 0, 4)) > 16.0:
		return
	_t += dt
	for i in _screens.size():
		var s: Dictionary = _screens[i]
		s.t -= dt
		if s.t > 0.0 or (on and i == _i):
			continue
		s.t = 0.1
		if s.name == "ASTEROIDS":
			if s.att.is_empty():
				s.att = { "rocks": [3, 3, 2, 2, 1, 1].map(func(z: int) -> Dictionary: return _as_rock(randf() * W, randf() * H, z)), "score": 0 }
			for r: Dictionary in s.att.rocks:
				r.x = fposmod(r.x + r.vx * 0.1, W)
				r.y = fposmod(r.y + r.vy * 0.1, H)
				r.a += r.rot * 0.1
		else:
			var v: Dictionary = s.inv
			v.f ^= 1
			v.x += v.dx
			if v.x < 6.0 or v.x + 8 * 22 > W - 6:
				v.dx = -v.dx
				v.x += v.dx
				v.y += 6.0
				if v.y > 90.0:
					v.y = 34.0
		_redraw(i)


func _redraw(i: int) -> void:
	var s: Dictionary = _screens[i]
	s.ctl.queue_redraw()
	s.vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# ---- Space Invaders

func _si_new() -> Dictionary:
	var g := { "score": 0, "lives": 3, "wave": 0, "px": W / 2.0, "dead": 0.0, "over": 0.0, "ufo": null, "ufoT": 18.0 + randf() * 10.0, "boom": [] }
	_si_wave(g)
	_si_bunkers(g)
	return g


func _si_wave(g: Dictionary) -> void:  # a fresh formation (each wave starts a step lower, up to a point)
	g.inv = []
	var y0: float = SI.top + 8 + mini(4, g.wave) * 6
	var kinds := ["squid", "crab", "crab", "octo", "octo"]
	for r in kinds.size():
		var kind: String = kinds[r]
		for c in 11:
			g.inv.append({ "kind": kind, "x": 24.0 + c * 16 + (2.0 if kind == "squid" else 0.5 if kind == "crab" else 0.0), "y": y0 + r * 14, "w": 8.0 if kind == "squid" else 11.0 if kind == "crab" else 12.0, "alive": true })
	g.dx = 2.0
	g.stepT = 0.0
	g.frame = 0
	g.note = 0
	g.bombs = []
	g.shot = null
	g.bombT = 1.0


func _si_bunkers(g: Dictionary) -> void:  # four bunkers, each a grid of cells that bullets chip away
	g.bunk = []
	for i in 4:
		var cells := PackedByteArray()
		cells.resize(22 * 16)
		for y in 16:
			for x in 22:
				cells[y * 22 + x] = 0 if (y < 3 and (x < 3 - y or x > 18 + y)) or (y > 10 and x > 6 and x < 15) else 1
		g.bunk.append({ "x": 32 + i * 56, "y": SI.bunkerY, "cells": cells })


func _chip(g: Dictionary, x: float, y: float, r: int) -> bool:
	for b: Dictionary in g.bunk:
		if x < b.x - 2 or x > b.x + 24 or y < b.y - 2 or y > b.y + 18:
			continue
		var lx := floori(x - b.x)
		var ly := floori(y - b.y)
		if lx >= 0 and lx < 22 and ly >= 0 and ly < 16 and b.cells[ly * 22 + lx]:
			for yy in range(-r, r + 1):
				for xx in range(-r, r + 1):
					var X := lx + xx
					var Y := ly + yy
					if X >= 0 and X < 22 and Y >= 0 and Y < 16 and randf() < 0.8:
						b.cells[Y * 22 + X] = 0
			return true
	return false


func _si_tick(dt: float) -> void:
	var g := _g
	var alive: Array = g.inv.filter(func(v: Dictionary) -> bool: return v.alive)
	if g.over > 0.0:
		g.over -= dt
		if g.over <= 0.0:
			stop()
		return
	if g.dead > 0.0:
		g.dead -= dt
		if g.dead <= 0.0:
			g.dead = 0.0
			if g.lives <= 0:
				g.over = 3.0
				_beep(220.0, 0.8, "sawtooth", 0.05, -150.0)
	else:  # the cannon
		var mv := float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT))
		g.px = clampf(g.px + mv * 70.0 * dt, 10.0, W - 10.0)
	g.stepT -= dt  # the march: a step at a time, quicker as they thin out, the four-note bass with it
	if g.stepT <= 0.0 and not alive.is_empty():
		g.stepT = maxf(0.03, 0.55 * alive.size() / 55.0)
		g.frame ^= 1
		var min_x: float = alive.map(func(v: Dictionary) -> float: return v.x).min()
		var max_x: float = alive.map(func(v: Dictionary) -> float: return v.x + v.w).max()
		if (g.dx > 0.0 and max_x + g.dx > W - 6) or (g.dx < 0.0 and min_x + g.dx < 6):
			g.dx = -g.dx
			for v: Dictionary in alive:
				v.y += 6.0
		else:
			for v: Dictionary in alive:
				v.x += g.dx
		_beep([98.0, 87.0, 78.0, 73.0][g.note % 4], 0.09, "square", 0.06)
		g.note += 1
		if alive.map(func(v: Dictionary) -> float: return v.y + 8).max() >= SI.playerY - 4 and g.over <= 0.0:
			g.lives = 0
			g.dead = 1.2
			g.boom.append({ "x": g.px, "y": SI.playerY, "t": 1.2, "big": true })
			_beep(140.0, 0.6, "sawtooth", 0.06, -100.0)
		for v: Dictionary in alive:  # (they trample the bunkers)
			for b: Dictionary in g.bunk:
				if v.y + 8 > b.y:
					for y in 16:
						for x in 22:
							var cx: float = b.x + x
							var cy: float = b.y + y
							if cx >= v.x and cx < v.x + v.w and cy >= v.y and cy < v.y + 8:
								b.cells[y * 22 + x] = 0
	if alive.is_empty() and g.dead <= 0.0:
		g.wave += 1
		_si_wave(g)
		_si_bunkers(g)
		_beep(660.0, 0.3, "triangle", 0.05, 330.0)
	g.bombT -= dt  # their bombs: from the bottom one in a column (toward the cannon, more often than not)
	if g.bombT <= 0.0 and not alive.is_empty() and g.dead <= 0.0 and g.bombs.size() < 3:
		g.bombT = 0.5 + randf() * 0.9
		var cols := {}
		for v: Dictionary in alive:
			var k := roundi(v.x / 16.0)
			if not cols.has(k) or v.y > cols[k].y:
				cols[k] = v
		var shooters: Array = cols.values()
		var near: Array = shooters.filter(func(v: Dictionary) -> bool: return absf(v.x + v.w / 2.0 - g.px) < 30.0)
		var v: Dictionary = (near if not near.is_empty() and randf() < 0.5 else shooters).pick_random()
		g.bombs.append({ "x": v.x + v.w / 2.0, "y": v.y + 8.0, "t": 0.0 })
	for bm: Dictionary in g.bombs.duplicate():
		bm.y += 70.0 * dt
		bm.t += dt
		if _chip(g, bm.x, bm.y + 3, 2) or bm.y > SI.ground:
			g.bombs.erase(bm)
			continue
		if g.dead <= 0.0 and absf(bm.x - g.px) < 8.0 and bm.y + 3 > SI.playerY - 4 and bm.y < SI.playerY + 4:  # hit: the cannon blows up
			g.bombs.erase(bm)
			g.lives -= 1
			g.dead = 1.4
			g.bombs = []
			g.boom.append({ "x": g.px, "y": SI.playerY, "t": 1.4, "big": true })
			_beep(160.0, 0.7, "sawtooth", 0.07, -120.0)
	if g.shot != null:  # your shot: into an invader, the saucer, a bunker, a bomb, or off the top
		var sh: Vector2 = g.shot
		sh.y -= 230.0 * dt
		g.shot = sh
		var hit = null
		for v: Dictionary in alive:
			if sh.x >= v.x - 1 and sh.x <= v.x + v.w + 1 and sh.y <= v.y + 8 and sh.y + 4 >= v.y:
				hit = v
				break
		var bomb = null
		for b: Dictionary in g.bombs:
			if absf(b.x - sh.x) < 3.0 and absf(b.y - sh.y) < 5.0:
				bomb = b
		if hit != null:
			hit.alive = false
			g.score += SI_PTS[hit.kind]
			g.boom.append({ "x": hit.x + hit.w / 2.0, "y": hit.y + 4, "t": 0.25 })
			g.shot = null
			_beep(400.0, 0.12, "sawtooth", 0.05, -300.0)
		elif g.ufo != null and absf(sh.x - g.ufo.x) < 9.0 and sh.y < 30.0:
			var pts: int = [50, 100, 150, 300].pick_random()
			g.score += pts
			g.boom.append({ "x": g.ufo.x, "y": 24.0, "t": 1.0, "pts": pts })
			g.ufo = null
			g.shot = null
			_beep(900.0, 0.4, "square", 0.05, -700.0)
		elif bomb != null:
			g.bombs.erase(bomb)
			g.shot = null
		elif _chip(g, sh.x, sh.y, 1) or sh.y < SI.top - 8:
			g.shot = null
	if g.ufo == null:
		g.ufoT -= dt
		if g.ufoT <= 0.0:
			var d := 1.0 if randf() < 0.5 else -1.0
			g.ufo = { "x": -12.0 if d > 0.0 else W + 12.0, "d": d }
			g.ufoT = 20.0 + randf() * 15.0
	if g.ufo != null:
		g.ufo.x += g.ufo.d * 40.0 * dt
		if int(_t * 10.0) % 2 == 1 and randf() < 0.3:
			_beep(roundf(6.0 + 2.0 * sin(_t * 20.0)) * 100.0, 0.05, "sine", 0.015)
		if g.ufo.x < -16.0 or g.ufo.x > W + 16.0:
			g.ufo = null
	for b: Dictionary in g.boom.duplicate():
		b.t -= dt
		if b.t <= 0.0:
			g.boom.erase(b)
	_t += dt


# ---- Asteroids

func _as_rock(x: float, y: float, size: int) -> Dictionary:
	var verts: Array = []
	for k in 10:
		var a := k / 10.0 * TAU
		var r: float = AS_R[size] * (0.75 + randf() * 0.4)
		verts.append(Vector2(cos(a) * r, sin(a) * r))
	var sp := (0.3 + randf() * 0.5) * (4 - size) * 9.0
	var a := randf() * TAU
	return { "x": x, "y": y, "vx": cos(a) * sp, "vy": sin(a) * sp, "size": size, "verts": verts, "rot": (randf() - 0.5) * 2.0, "a": 0.0 }


func _as_new() -> Dictionary:
	var g := { "score": 0, "lives": 3, "wave": 0, "ship": { "x": W / 2.0, "y": H / 2.0, "a": -PI / 2.0, "vx": 0.0, "vy": 0.0, "thrust": false }, "shots": [], "dead": 0.0, "safe": 2.0, "over": 0.0, "beatT": 0.0, "beat": 0, "debris": [] }
	_as_wave(g)
	return g


func _as_wave(g: Dictionary) -> void:
	g.rocks = []
	for k in 4 + g.wave:
		var e := randf() < 0.5
		g.rocks.append(_as_rock(randf() * W if e else (0.0 if randf() < 0.5 else float(W)), (0.0 if randf() < 0.5 else float(H)) if e else randf() * H, 3))


func _as_fire(g: Dictionary) -> void:
	if g.dead > 0.0 or g.over > 0.0 or g.shots.size() >= 4:
		return
	var s: Dictionary = g.ship
	g.shots.append({ "x": s.x + cos(s.a) * 6, "y": s.y + sin(s.a) * 6, "vx": s.vx + cos(s.a) * 150, "vy": s.vy + sin(s.a) * 150, "t": 0.9 })
	_beep(1500.0, 0.06, "square", 0.025, -900.0)


func _d2(a: Dictionary, b: Dictionary) -> float:  # distance squared, round the wrap
	var dx := absf(a.x - b.x)
	var dy := absf(a.y - b.y)
	dx = minf(dx, W - dx)
	dy = minf(dy, H - dy)
	return dx * dx + dy * dy


func _as_tick(dt: float) -> void:
	var g := _g
	var s: Dictionary = g.ship
	_t += dt
	if g.over > 0.0:
		g.over -= dt
		if g.over <= 0.0:
			stop()
		return
	if g.dead > 0.0:  # waiting for the next ship: till its time's up and the middle's clear
		g.dead -= dt
		if g.dead <= 0.0:
			if g.lives <= 0:
				g.over = 3.0
				_beep(200.0, 0.8, "sawtooth", 0.05, -120.0)
			elif g.rocks.all(func(r: Dictionary) -> bool: return _d2(r, { "x": W / 2.0, "y": H / 2.0 }) > 1600.0):
				g.dead = 0.0
				g.safe = 2.0
				s.merge({ "x": W / 2.0, "y": H / 2.0, "a": -PI / 2.0, "vx": 0.0, "vy": 0.0 }, true)
			else:
				g.dead = 0.1
	else:
		var turn := float(_key(KEY_D, KEY_RIGHT)) - float(_key(KEY_A, KEY_LEFT))
		var thrust := _key(KEY_W, KEY_UP)
		s.a += turn * 4.2 * dt
		s.thrust = thrust
		if thrust:
			s.vx += cos(s.a) * 120.0 * dt
			s.vy += sin(s.a) * 120.0 * dt
			if randf() < dt * 20.0:
				_beep(60.0 + randi() % 4 * 10.0, 0.05, "sawtooth", 0.02)
		var sp := Vector2(s.vx, s.vy).length()
		if sp > 140.0:
			s.vx *= 140.0 / sp
			s.vy *= 140.0 / sp
		s.vx *= 1.0 - 0.35 * dt
		s.vy *= 1.0 - 0.35 * dt
		s.x = fposmod(s.x + s.vx * dt, W)
		s.y = fposmod(s.y + s.vy * dt, H)
		g.safe = maxf(0.0, g.safe - dt)
	for r: Dictionary in g.rocks:
		r.x = fposmod(r.x + r.vx * dt, W)
		r.y = fposmod(r.y + r.vy * dt, H)
		r.a += r.rot * dt
	for sh: Dictionary in g.shots.duplicate():
		sh.x = fposmod(sh.x + sh.vx * dt, W)
		sh.y = fposmod(sh.y + sh.vy * dt, H)
		sh.t -= dt
		if sh.t <= 0.0:
			g.shots.erase(sh)
			continue
		for r: Dictionary in g.rocks:
			if _d2(r, sh) < AS_R[r.size] * AS_R[r.size]:
				g.shots.erase(sh)
				g.rocks.erase(r)
				g.score += [0, 100, 50, 20][r.size]
				if r.size > 1:
					for k in 2:
						g.rocks.append(_as_rock(r.x, r.y, r.size - 1))
				for k in 8:
					var a := randf() * TAU
					var v := 20.0 + randf() * 40.0
					g.debris.append({ "x": r.x, "y": r.y, "vx": cos(a) * v, "vy": sin(a) * v, "t": 0.5 })
				_beep([0.0, 900.0, 400.0, 160.0][r.size], 0.18, "sawtooth", 0.05, -80.0)
				break
	if g.dead <= 0.0 and g.safe <= 0.0 and g.over <= 0.0:
		for r: Dictionary in g.rocks:
			if _d2(r, s) < pow(AS_R[r.size] + 4.0, 2.0):
				g.lives -= 1
				g.dead = 1.8
				for k in 14:
					var a := randf() * TAU
					var v := 10.0 + randf() * 50.0
					g.debris.append({ "x": s.x, "y": s.y, "vx": cos(a) * v, "vy": sin(a) * v, "t": 1.2 })
				_beep(120.0, 0.7, "sawtooth", 0.07, -80.0)
				break
	for d: Dictionary in g.debris.duplicate():
		d.x += d.vx * dt
		d.y += d.vy * dt
		d.t -= dt
		if d.t <= 0.0:
			g.debris.erase(d)
	if g.rocks.is_empty():
		g.wave += 1
		_as_wave(g)
	g.beatT -= dt
	if g.beatT <= 0.0:  # thump... thump (quicker as it clears)
		g.beatT = maxf(0.25, 0.9 * minf(1.0, g.rocks.size() / 10.0))
		_beep(55.0 if g.beat % 2 else 62.0, 0.1, "square", 0.06)
		g.beat += 1


# ---- the screens

func _text(c: Control, at: Vector2, t: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var w := 0.0 if align == HORIZONTAL_ALIGNMENT_LEFT else _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(_font, at - Vector2(w if align == HORIZONTAL_ALIGNMENT_RIGHT else w / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _sprite(c: Control, rows: Array, x: float, y: float, k: float, color: Color) -> void:
	for j in rows.size():
		var r: String = rows[j]
		for i in r.length():
			if r[i] == "1":
				c.draw_rect(Rect2(roundf(x + i * k), roundf(y + j * k), k, k), color)


func _draw_screen(i: int) -> void:
	var s: Dictionary = _screens[i]
	var c: Control = s.ctl
	var playing := on and i == _i
	if s.name == "ASTEROIDS":
		_as_draw(c, _g if playing else s.att, not playing)
	elif playing:
		_si_draw(c, _g)
	else:
		_invaders_attract(c, s)


func _si_draw(c: Control, g: Dictionary) -> void:
	var green := Color("#39ff5a")
	c.draw_rect(Rect2(0, 0, W, H), Color("#05050c"))
	_text(c, Vector2(6, 11), "SCORE<1> %04d" % g.score, 10, Color.WHITE)
	_text(c, Vector2(W - 6, 11), "HI-SCORE %04d" % maxi(scores[0], g.score), 10, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	for v: Dictionary in g.inv:
		if v.alive:
			_sprite(c, INVADER[v.kind][g.frame], v.x, v.y, 1.0, Color.WHITE)
	if g.ufo != null:
		var u: float = g.ufo.x
		for r: Array in [[u - 8, 22, 16, 4], [u - 5, 19, 10, 3], [u - 2, 17, 4, 2]]:
			c.draw_rect(Rect2(r[0], r[1], r[2], r[3]), Color("#ff3b30"))
	for b: Dictionary in g.bunk:
		for y in 16:
			for x in 22:
				if b.cells[y * 22 + x]:
					c.draw_rect(Rect2(b.x + x, b.y + y, 1, 1), green)
	if g.dead <= 0.0 or int(g.dead * 10.0) % 2 == 1:
		c.draw_rect(Rect2(roundf(g.px) - 7, SI.playerY - 1, 14, 5), green)
		c.draw_rect(Rect2(roundf(g.px) - 1, SI.playerY - 4, 2, 3), green)
	if g.shot != null:
		c.draw_rect(Rect2(roundf(g.shot.x), roundf(g.shot.y), 1, 4), Color.WHITE)
	for bm: Dictionary in g.bombs:
		for k in 4:
			c.draw_rect(Rect2(roundf(bm.x) + (1 if (int(bm.t * 12.0) + k) % 2 else -1), roundf(bm.y) + k * 2, 1, 2), Color.WHITE)
	for b: Dictionary in g.boom:
		if b.has("pts"):
			_text(c, Vector2(b.x, 26), str(b.pts), 10, Color("#ff3b30"), HORIZONTAL_ALIGNMENT_CENTER)
			continue
		var n := 14 if b.get("big", false) else 8
		for k in n:
			var a := float(k) / n * TAU
			c.draw_rect(Rect2(roundf(b.x + cos(a) * (7.0 if n == 14 else 4.0)), roundf(b.y + sin(a) * (4.0 if n == 14 else 3.0)), 1, 1), green if n == 14 else Color.WHITE)
	c.draw_rect(Rect2(0, SI.ground, W, 1), green)
	_text(c, Vector2(6, H - 1), str(maxi(0, g.lives)), 10, Color.WHITE)
	for k in maxi(0, g.lives - 1):
		c.draw_rect(Rect2(18 + k * 18, H - 5, 12, 4), green)
		c.draw_rect(Rect2(23 + k * 18, H - 7, 2, 2), green)
	if g.over > 0.0:
		_text(c, Vector2(W / 2.0, H / 2.0), "GAME OVER", 16, Color("#ff3b30"), HORIZONTAL_ALIGNMENT_CENTER)


func _as_draw(c: Control, g: Dictionary, attract: bool) -> void:
	var ink := Color("#e8f0ff")
	c.draw_rect(Rect2(0, 0, W, H), Color("#03030a"))
	for r: Dictionary in g.get("rocks", []):
		var pts := PackedVector2Array()
		for v: Vector2 in r.verts:
			pts.append(Vector2(r.x, r.y) + v.rotated(r.a))
		pts.append(pts[0])
		c.draw_polyline(pts, ink, 1.0)
	for sh: Dictionary in g.get("shots", []):
		c.draw_rect(Rect2(roundf(sh.x), roundf(sh.y), 1.5, 1.5), ink)
	for d: Dictionary in g.get("debris", []):
		c.draw_rect(Rect2(roundf(d.x), roundf(d.y), 1, 1), ink)
	var s = g.get("ship")
	if s != null and g.dead <= 0.0 and g.over <= 0.0 and (g.safe <= 0.0 or int(g.safe * 8.0) % 2 == 1):
		var pt := func(r: float, a: float) -> Vector2: return Vector2(s.x + cos(s.a + a) * r, s.y + sin(s.a + a) * r)
		c.draw_polyline(PackedVector2Array([pt.call(7, 0.0), pt.call(6, 2.5), pt.call(3, PI), pt.call(6, -2.5), pt.call(7, 0.0)]), ink, 1.0)
		if s.thrust and randf() < 0.7:
			c.draw_polyline(PackedVector2Array([pt.call(3.5, 2.6), pt.call(8, PI), pt.call(3.5, -2.6)]), ink, 1.0)
	_text(c, Vector2(6, 14), "%5d" % g.get("score", 0), 12, ink)
	_text(c, Vector2(W / 2.0, 12), "%05d" % maxi(maxi(scores[1], g.get("score", 0)), 10000), 9, ink, HORIZONTAL_ALIGNMENT_CENTER)
	for k in maxi(0, g.get("lives", 0) - (0 if g.get("dead", 0.0) > 0.0 or s == null else 1)):
		var x := 10.0 + k * 9
		c.draw_polyline(PackedVector2Array([Vector2(x, 19), Vector2(x + 3, 27), Vector2(x - 3, 27), Vector2(x, 19)]), ink, 1.0)
	if g.get("over", 0.0) > 0.0:
		_text(c, Vector2(W / 2.0, H / 2.0), "GAME OVER", 16, ink, HORIZONTAL_ALIGNMENT_CENTER)
	if attract:
		_text(c, Vector2(W / 2.0, H * 0.42), "ASTEROIDS", 20, ink, HORIZONTAL_ALIGNMENT_CENTER)
		if int(_t * 2.0) % 2:
			_text(c, Vector2(W / 2.0, H * 0.62), "INSERT COIN", 12, ink, HORIZONTAL_ALIGNMENT_CENTER)


func _invaders_attract(c: Control, s: Dictionary) -> void:
	var green := Color("#39ff5a")
	var v: Dictionary = s.inv
	c.draw_rect(Rect2(0, 0, W, H), Color("#05050c"))
	_text(c, Vector2(8, 14), "SCORE<1>  %04d" % scores[0], 11, Color.WHITE)
	_text(c, Vector2(W - 8, 14), "HI-SCORE  %05d" % maxi(scores[0], 20000), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	var kinds := ["squid", "crab", "crab", "octo", "octo"]
	for r in kinds.size():
		for col in 8:
			_sprite(c, INVADER[kinds[r]][v.f], v.x + col * 22 + (2.0 if kinds[r] == "squid" else 0.0), v.y + r * 13, 1.4, Color.WHITE)
	for b in 4:
		var bx := 22.0 + b * 60
		c.draw_rect(Rect2(bx, H - 46, 26, 12), green)
		c.draw_rect(Rect2(bx + 3, H - 49, 20, 3), green)
		c.draw_rect(Rect2(bx + 8, H - 38, 10, 4), Color("#05050c"))
	var cx := W / 2.0 + sin(_t * 1.3) * 70.0
	c.draw_rect(Rect2(cx - 8, H - 22, 16, 5), green)
	c.draw_rect(Rect2(cx - 2, H - 26, 4, 4), green)
	c.draw_rect(Rect2(0, H - 12, W, 1), green)
	if int(_t * 2.0) % 2:
		_text(c, Vector2(W / 2.0, H - 2), "INSERT  COIN", 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)


func snapshot() -> Dictionary:
	return { "scores": scores }


func restore(d: Dictionary) -> void:
	scores = d.get("scores", [0, 0]).map(func(x) -> int: return int(x))
