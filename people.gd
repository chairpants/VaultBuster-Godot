extends Node3D
## The people: the cast (people/people.glb, people.json and a face sheet each: the web game's tests/export-glb.mjs
## --people writes them), and for now the ones going by out front.
## From the web game's store/shoppers.js (walkerMake, walkerTick): folks walk past on the sidewalk without coming in,
## one every 18 to 58 seconds by day (rarer after dark and in the rain), four at most, at their own pace, a quicker step
## after dark. They're not customers: just people on a path.
## Not over yet: customers and the staff (shoppers.js, staff.js), the pizza place's own comings and goings, cars,
## umbrellas.

const Person := preload("res://person.gd")
const SIDEWALK_Z := -0.95

var cast := {}  # { moods, who: [{ height, build, female, gait }] }
var walkers: Array[Dictionary] = []  # { c, path: [[x, z], ...], speed }

var _templates: Array[Node3D] = []
var _faces: Array[Texture2D] = []
var _holder: Node3D
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
		_templates.append(_holder.get_node("p%d" % i))
		_faces.append(load("res://people/face_%d.png" % i))


func _exit_tree() -> void:
	if _holder:
		_holder.free()


func spawn(i := -1) -> Node3D:  # one of the cast (a random one), standing at the origin
	if _templates.is_empty():
		return null
	if i < 0:
		i = randi() % _templates.size()
	var c: Node3D = _templates[i].duplicate()
	c.set_script(Person)
	add_child(c)
	c.setup(cast.who[i], _faces[i], cast.moods, i)
	return c


func _process(dt: float) -> void:  # walkerTick: somebody going by
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
			var c := spawn()
			c.position = Vector3(-dir * 24.0, 0.0, z)
			walkers.append({ "c": c, "path": [[dir * 24.0, z]], "speed": 1.1 + randf() * 0.5 })
	for w: Dictionary in walkers.duplicate():
		var c: Node3D = w.c
		var speed := 0.0
		if w.path.is_empty():
			c.queue_free()
			walkers.erase(w)
			continue
		var to := Vector2(w.path[0][0] - c.position.x, w.path[0][1] - c.position.z)
		var d := to.length()
		if d < 0.05:
			w.path.pop_front()
		else:
			speed = w.speed * (1.12 if night else 1.0)  # (a quicker step after dark)
			if weather.kind == "rain" and weather.k > 0.25:
				speed = maxf(speed * 1.9, 2.9)  # caught out: run for it
			elif weather.cover > 0.3:
				speed *= 0.85  # short careful steps on the snow
			var step := minf(d, speed * dt)
			c.position += Vector3(to.x, 0.0, to.y) / d * step
			c.rotation.y = atan2(to.x, to.y)
		c.tick(dt, speed)
