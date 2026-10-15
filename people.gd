extends Node3D
## The people: the cast (people/people.glb, people.json and a face sheet each: the web game's tests/export-glb.mjs
## --people writes them), and for now the ones going by out front.
## From the web game's store/shoppers.js (walkerMake, walkerTick): folks walk past on the sidewalk without coming in,
## one every 18 to 58 seconds by day (rarer after dark and in the rain), four at most, at their own pace, a quicker step
## after dark. They're not customers: just people on a path.
## And next door's own comings and goings (the pizza place: in empty-handed, out with a box), and what the weather
## does to anybody out in it (umbrellas up, a run for it, snow on their shoulders): env and pace, below, which the
## customers (shoppers.gd) go by too.

const Person := preload("res://person.gd")
const Traffic := preload("res://traffic.gd")
const SIDEWALK_Z := -0.95

var cast := {}  # { moods, who: [{ height, build, female, gait }] }
var walkers: Array[Dictionary] = []  # { c, path: [[x, z], ...], speed }

var _templates: Array[Node3D] = []
var _faces: Array[Texture2D] = []
var _holder: Node3D
var _tony_holder: Node3D
var _next := 4.0

@onready var weather: Node3D = $"../Weather"


func _ready() -> void:
	cast = JSON.parse_string(FileAccess.get_file_as_string("res://people/people.json"))
	var scene: PackedScene = load("res://people/people.glb")
	if scene == null:
		push_warning("people/people.glb isn't imported yet: open the project in the editor once")
		return
	_holder = scene.instantiate()
	$"../Room".light(_holder)  # lit as everything else is: by where they're standing
	for i in cast.who.size():
		if not _holder.has_node("p%d" % i):
			break  # (people.json's ahead of the imported people.glb: open the project in the editor once)
		_templates.append(_holder.get_node("p%d" % i))
		_faces.append(load("res://people/face_%d.png" % i))
	if ResourceLoader.exists("res://people/tony.glb") and _templates.size() == cast.who.size():  # Tony, from next door, in what he wears (the export's --tony): one more on the end of the cast
		_tony_holder = load("res://people/tony.glb").instantiate()
		$"../Room".light(_tony_holder)
		var i: int = cast.who.size()
		if _tony_holder.has_node("p%d" % i):
			cast.who.append(JSON.parse_string(FileAccess.get_file_as_string("res://people/tony.json")))
			_templates.append(_tony_holder.get_node("p%d" % i))
			_faces.append(load("res://people/face_%d.png" % i))


var _glow: MeshInstance3D


func _glow_build() -> void:
	var img := Image.create(256, 192, false, Image.FORMAT_RGBA8)
	for y in 192:
		var v := 1.0 - (y + 0.5) / 192.0  # (how far out from the storefront: the quad's top edge is the far one)
		for x in 256:
			var u := (x + 0.5) / 256.0 * 2.0 - 1.0
			var a := maxf(0.0, 1.0 - pow(absf(u), 2.5)) * exp(-v * 2.6) * minf(1.0, v * 20.0)
			img.set_pixel(x, y, Color(1.0, (180.0 + 40.0 * (1.0 - v)) / 255.0, 110.0 / 255.0, a))
	_glow = MeshInstance3D.new()
	_glow.mesh = QuadMesh.new()
	_glow.mesh.size = Vector2(9.0, 6.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.disable_fog = true
	_glow.material_override = m
	_glow.rotation.x = -PI / 2.0
	_glow.position = Vector3(PIZZA_DOOR.x + 0.5, 0.03, -3.0)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)


func _exit_tree() -> void:
	if _holder:
		_holder.free()
	if _tony_holder:
		_tony_holder.free()


func spawn(i := -1) -> Node3D:  # one of the cast (a random one), standing at the origin
	if _templates.is_empty():
		return null
	if i < 0:  # (anybody: not the staff, and not you)
		i = range(_templates.size()).filter(func(k: int) -> bool: return not cast.who[k].has("staff")).pick_random()
	var c: Node3D = _templates[i].duplicate()
	c.set_script(Person)
	add_child(c)
	c.setup(cast.who[i], _faces[i], cast.moods, i)
	return c


var tony: Node3D  # behind his counter next door

const TONY_AT := Vector3(16.2, 0.0, 8.3)  # (tonys/inside.js: "Tony himself, behind the counter")


func _tony() -> void:  # the level has him as he stood when it was exported, a statue: out he goes, and a live one in his place
	for n: Node in $"../World".find_children("*", "Node3D", true, false):
		if n.global_position.distance_to(TONY_AT) < 0.03:
			n.visible = false
			for body in n.find_children("*", "CollisionObject3D", true, false):
				body.queue_free()
			break
	var men: Array = range(cast.who.size()).filter(func(i: int) -> bool: return not cast.who[i].female and not cast.who[i].has("staff"))
	var own: Array = range(cast.who.size()).filter(func(i: int) -> bool: return cast.who[i].get("staff", "") == "Tony")
	tony = spawn(own[0] if not own.is_empty() else men[4417 % men.size()])  # (himself; or, a cast exported before he was in it, one of them standing in)
	tony.position = TONY_AT
	tony.rotation.y = PI
	tony.set_mood("neutral")


# ---- the weather on anyone out there (customers in the lot, people going by): snow settles on their head and
# shoulders (melting off once they're inside), the wind leans on them and they lean into it, a gust shoves them a step
# (or turns an umbrella inside out), the cold and the wet hunch them up, and with no umbrella in the rain a hand goes
# up over their head (shoppers.js: npcEnv, npcPace). k: their record (a customer's, a walker's)

func env(k: Dictionary, c: Node3D, out: bool, dt: float) -> void:
	var w: Vector2 = weather.blow
	var rain: float = weather.k if weather.kind == "rain" else 0.0
	var snow: float = weather.k if weather.kind == "snow" else 0.0
	var umb: bool = c.prop == "umbrella"
	k.snow = clampf(k.get("snow", 0.0) + ((0.0 if umb else dt * snow * 0.045) if out else -dt * 0.03), 0.0, 1.0)  # ~25 s of heavy snow to cover them; ~30 s indoors to melt
	c.set_snow(k.snow)
	c.wind = w if out else Vector2.ZERO
	var wet := out and rain > 0.25 and not umb
	k.soak_t = k.get("soak_t", 0.0) + dt if wet else 0.0 if out else k.get("soak_t", 0.0)
	if k.soak_t > 1.5:
		k.soaked = true
	var cold := maxf(snow * 0.9, maxf(0.6 if wet else 0.0, minf(1.0, maxf(0.0, w.length() - 3.0) / 6.0) * 0.7)) if out else 0.0
	k.hunch = k.get("hunch", 0.0) + (cold - k.get("hunch", 0.0)) * minf(1.0, dt * 2.0)
	c.hunch = k.hunch
	c.shield = wet and not k.get("box", false)
	if out and weather.gust > 0.6 and w.length() > 5.0 and not k.get("gusted", false):  # a gust: a stumble sideways, maybe the umbrella goes
		k.gusted = true
		if randf() < 0.6:
			c.stagger(1.0 if w.x * cos(c.rotation.y) - w.y * sin(c.rotation.y) >= 0.0 else -1.0)
		if umb and randf() < 0.35:
			c.umbrella_flip()
	elif weather.gust < 0.3:
		k.gusted = false


func pace(k: Dictionary, c: Node3D, speed: float, u: Vector2, dt: float) -> float:  # their speed through the weather, walking u; the wind carries them sideways a little
	var w: Vector2 = weather.blow
	var along := w.dot(u)
	speed *= clampf(1.0 + along * 0.04, 0.55, 1.3)  # fighting a headwind, helped along by a tailwind
	var side := (w - along * u) * 0.025 * dt  # (the path steers them back)
	c.position += Vector3(side.x, 0.0, side.y)
	if weather.kind == "rain" and weather.k > 0.25 and c.prop != "umbrella":
		speed = maxf(speed * 1.9, 2.3 if k.get("box", false) else 2.9)  # caught out: run for it (carefully, with a pizza)
	elif weather.cover > 0.3:
		speed *= 0.85  # short careful steps on the snow
	return speed


# ---- out front: people going by, and the pizza place next door. They park (or walk up) and head in empty-handed, up
# the aisle to a spot at Tony's counter, wait there for the order, and come back out with a pizza box and go home;
# busy at lunch and dinner. None of them are our customers: just people on a path (shoppers.js: walkerMake,
# walkerBox, walkerInTonys, pizzaRun, walkerTick)

const PIZZA_DOOR := Vector2(15.6, -0.75)
const TONY_SPOTS := [14.4, 15.3, 16.2, 17.1, 18.0]  # along his counter
const TONY_COUNTER_Z := 7.3

var _pizza_t := 20.0
var _tony_taken: Array = []


func walker(path: Array, then := Callable()) -> Dictionary:  # somebody on a path: [where they start, ...]; then: what they do at the end of it (nothing: they're gone)
	var c := spawn()
	c.position = Vector3(path[0].x, floor_y(path[0]), path[0].y)
	c.set_mood("neutral")
	var w := { "c": c, "path": path.slice(1), "speed": 1.1 + randf() * 0.5, "then": then, "box": false, "umb": false, "umb_own": randf() < 0.55, "wait": -1.0, "after": Callable() }
	walkers.append(w)
	return w


func floor_y(at: Vector2) -> float:  # the lot and the road sit a curb lower than the walk and the grass (core.js: pavedAt)
	if at.y < -13.8 and at.y > -20.4:
		return -0.12
	if at.y < -1.8 and at.y > -12.3:
		return -0.12 if at.x > -24.74 and at.x < 29.06 else 0.0
	return -0.12 if at.y <= -12.3 and at.y >= -13.8 and ((at.x > -25.04 and at.x < -19.44) or (at.x > 23.76 and at.x < 29.36)) else 0.0


func _box(w: Dictionary, on: bool) -> void:  # a pizza box, carried flat
	var box: MeshInstance3D = null
	if on:
		box = MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		box.mesh.size = Vector3(0.4, 0.05, 0.4)
		box.mesh.material = StandardMaterial3D.new()
		box.mesh.material.albedo_color = Color("#e8dcc4")
		var label := MeshInstance3D.new()
		label.mesh = QuadMesh.new()
		label.mesh.size = Vector2(0.22, 0.12)
		label.mesh.material = StandardMaterial3D.new()
		label.mesh.material.albedo_color = Color("#c8312a")
		label.rotation.x = -PI / 2.0
		label.position.y = 0.026
		box.add_child(label)
		$"../Room".light(box)
	w.c.hold_item(box)
	w.c.set_pose("hold" if on else "idle")
	w.box = on


func _gone(w: Dictionary) -> void:
	w.c.queue_free()
	walkers.erase(w)


func _in_tonys(w: Dictionary, secs: float, home: Array, car) -> void:  # in through the door, up the aisle past the tables, waiting at the counter (facing Tony), then back out with the box and home (to their car, which then goes)
	var free: Array = TONY_SPOTS.filter(func(x: float) -> bool: return not x in _tony_taken)
	var x: float = free.pick_random() if not free.is_empty() else TONY_SPOTS.pick_random()  # ponytail: a crowd at the counter doubles up on a spot; the web game has them wait out of sight
	_tony_taken.append(x)
	w.path = [Vector2(PIZZA_DOOR.x, 0.6), Vector2(PIZZA_DOOR.x, 6.0), Vector2(x, TONY_COUNTER_Z - 0.55)]
	w.then = func(w2: Dictionary) -> void:
		w2.c.rotation.y = 0.0
		w2.wait = secs
		w2.after = _order_up.bind(w2, x, home, car)


func _order_up(w: Dictionary, x: float, home: Array, car) -> void:
	_tony_taken.erase(x)
	_box(w, true)
	if tony != null:
		tony.set_mood("happy")
	w.path = [Vector2(PIZZA_DOOR.x, 6.0), Vector2(PIZZA_DOOR.x, 0.6), PIZZA_DOOR] + home
	w.then = func(w2: Dictionary) -> void:
		_gone(w2)
		if car != null:
			$"../Cars".drive_out(car)


func _pizza_parked(car: Dictionary, wait: float) -> void:  # out of the car and over to Tony's
	var d: Vector2 = car.door
	walker([d, Vector2(d.x, -1.2), Vector2(PIZZA_DOOR.x, SIDEWALK_Z), PIZZA_DOOR], _in_tonys.bind(wait, [Vector2(PIZZA_DOOR.x, SIDEWALK_Z), Vector2(d.x, -1.2), d], car))  # (straight off the lot onto the sidewalk, and back the same way)


func pizza_run() -> void:  # someone getting a pizza: by car (parked near it) or on foot
	var wait := Clock.HOUR * (0.12 + randf() * 0.15)
	var cars: Node = $"../Cars"
	if randf() < 0.6:
		var car = cars.drive_in(cars.new_look(), _pizza_parked.bind(wait), PIZZA_DOOR.x)
		if car != null:
			car.idling = randf() < 0.2
			return
	var from := (-1.0 if randf() < 0.5 else 1.0) * 24.0  # on foot, up the sidewalk
	walker([Vector2(from, SIDEWALK_Z - randf() * 0.3), Vector2(PIZZA_DOOR.x, SIDEWALK_Z), PIZZA_DOOR], _in_tonys.bind(wait, [Vector2(PIZZA_DOOR.x, SIDEWALK_Z), Vector2(-24.0 if from > 0.0 else 24.0, SIDEWALK_Z)], null))


func _process(dt: float) -> void:  # walkerTick: somebody going by
	if _glow == null:
		_glow_build()
	var open_k: float = 0.85 * maxf(0.0, 1.0 - $"../Sky".level * 1.4) if fmod(Clock.h, 24.0) >= 11.0 and fmod(Clock.h, 24.0) < 23.0 else 0.0
	_glow.material_override.albedo_color.a = open_k
	_glow.visible = open_k > 0.01
	if tony == null and not _templates.is_empty():
		_tony()
	if tony != null:
		tony.tick(dt, 0.0)
	if _templates.is_empty():
		return
	var h := fmod(Clock.h, 24.0)
	var night := h < 7.0 or h > 21.5
	_next -= dt
	if _next <= 0.0:
		_next = (70.0 + randf() * 120.0 if night else 18.0 + randf() * 40.0) * (1.8 if weather.k > 0.3 else 1.0)
		if walkers.size() < 4 and h > 6.5:
			var dir := 1.0 if randf() < 0.5 else -1.0
			var z := SIDEWALK_Z - randf() * 0.4
			walker([Vector2(-dir * 24.0, z), Vector2(dir * 24.0, z)])
	var busy := (h > 11.5 and h < 13.5) or (h > 17.0 and h < 20.5)
	if h >= 11.0 and h < 23.0:  # Tony's is open
		_pizza_t -= dt
		if _pizza_t <= 0.0:
			_pizza_t = (25.0 if busy else 70.0) + randf() * (40.0 if busy else 110.0)
			if walkers.size() < 5:
				pizza_run()
	for w: Dictionary in walkers.duplicate():
		var c: Node3D = w.c
		var speed := 0.0
		if w.wait >= 0.0:  # (waiting at Tony's counter for the order)
			w.wait -= dt
			if w.wait < 0.0:
				w.after.call()
		elif w.path.is_empty():
			var f: Callable = w.then
			w.then = Callable()
			if f.is_valid():
				f.call(w)
			else:
				_gone(w)
			if not w in walkers:
				continue
		else:
			var to: Vector2 = w.path[0] - Vector2(c.position.x, c.position.z)
			var d := to.length()
			if d < 0.05:
				w.path.pop_front()
			elif not c.busy():
				speed = pace(w, c, w.speed * (1.12 if night else 1.0), to / d, dt)  # (a quicker step after dark)
				var vel := Traffic.walk(c.get_instance_id(), Vector2(c.position.x, c.position.z), to / d, speed, "walker", dt)  # (round whoever's in the way, out of the cars' road)
				speed = vel.length()
				if speed > 0.001:
					c.position += Vector3(vel.x, 0.0, vel.y) / speed * minf(d, speed * dt)
					c.rotation.y = atan2(vel.x, vel.y)
				c.position.y = floor_y(Vector2(c.position.x, c.position.z))
		if speed == 0.0 and c.visible:
			Traffic.person(c.get_instance_id(), Vector2(c.position.x, c.position.z), Vector2.ZERO, "walker")
		var out := c.position.z < 0.25
		var rain: bool = out and weather.kind == "rain" and weather.k > 0.2 and w.umb_own
		if rain != w.umb and not w.box:  # umbrellas up in the rain (down once they're in next door)
			w.umb = rain
			c.hold_prop("umbrella" if rain else null)
		env(w, c, out, dt)
		c.tick(dt, speed)
