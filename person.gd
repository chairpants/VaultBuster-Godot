extends Node3D
## One of the TV-head people: a body from the cast (people/people.glb: the web game's own, built by its customers.js
## and exported joint by joint), posed here every frame the way customers.js poses it.
## From the web game's customers.js: the object build() returns (setMood, setPose, lookAt, holdTape, sigh, talk) and
## its tick: the walk cycle (the planted foot stays put on the floor; the hips ride over it; a run over ~2 m/s),
## the gaits, sitting and crouching, the arms' poses, the head, breathing.
## And what the weather does to them (the wind leaning on them, hunched in the cold and wet, snow settling on the head
## and shoulders, a hand up against the rain or the umbrella held straight up whatever the arm does), the one-off
## moves (shaking it off at the door, a slip, a palm out, a gust's shove), and blinking.
## The body is its one stretched skin (skinLimbs, below), made here
## from the jointed blocks the export has.
##
## The origin's on the floor between the feet; they face +z.

const GAITS := {
	"plain": { "stride": 1.0, "arms": 1.0, "twist": 1.0, "sway": 0.0, "lean": 0.0, "knee": 1.0 },
	"bouncy": { "stride": 1.0, "arms": 1.2, "twist": 1.0, "sway": 0.0, "lean": 0.0, "knee": 1.3 },
	"shuffle": { "stride": 0.62, "arms": 0.4, "twist": 0.6, "sway": 0.0, "lean": 0.07, "knee": 0.35 },
	"swagger": { "stride": 1.1, "arms": 1.5, "twist": 3.0, "sway": 0.045, "lean": -0.03, "knee": 1.0 },
	"brisk": { "stride": 1.15, "arms": 1.4, "twist": 1.0, "sway": 0.0, "lean": 0.05, "knee": 1.1 },
	"stroll": { "stride": 0.85, "arms": 0.0, "twist": 1.5, "sway": 0.015, "lean": -0.02, "knee": 0.9, "behind": true },  # hands clasped behind the back
	"sway": { "stride": 0.95, "arms": 0.9, "twist": 0.5, "sway": 0.07, "lean": 0.0, "knee": 1.0 },
	"stomp": { "stride": 1.05, "arms": 1.1, "twist": 1.0, "sway": 0.02, "lean": 0.03, "knee": 1.5 },
	"skip": { "stride": 1.05, "arms": 1.6, "twist": 1.0, "sway": 0.0, "lean": 0.0, "knee": 1.8, "hop": true },
}
const HEAD_Z := 0.05  # the TV sits a touch forward, over the neck
const LEG := 0.9
const KNEEL := 0.38  # how far the hips come down, kneeling to the floor
const BLINKS := ["neutral", "browse", "meh", "wait", "impatient", "angry", "shifty", "ask", "watch"]  # the faces with eyes to shut

var mood := "off"
var pose := "idle"  # walk idle reach hold wait sit crouch lean read watch
var gait := "plain"
var walk_lean := true  # tip forward into the stride
var height := 1.0
var talking := false
var sit_at := {}  # { hipY, tuck }
var build := 1.0
var wind := Vector2.ZERO  # the wind on them, world m/s (the way the air's going): they lean into it, and it leans on them
var hunch := 0.0  # cold / wet: shoulders up, arms in, head down, shorter steps
var shield := false  # a hand up over the head (caught in the rain, no umbrella)
var snow := 0.0  # 0..1 settled on the head and shoulders (set_snow)
var prop = null  # what's in the other hand: "card" / "cash" / "receipt" / "form" / "umbrella", or null

var _body: Node3D
var _upper: Node3D
var _head: Node3D
var _torso: Node3D
var _legs: Array = []  # [hip, knee]
var _arms: Array = []  # [shoulder, elbow]
var _tapes: Array[Node3D] = []
var _props := {}  # card, cash, receipt, form, umbrella: in the other hand
var _reach := { "target": Vector3.ZERO, "on": false, "w": 0.0, "arm": 1, "lean": true }
var _reach2 := { "target": Vector3.ZERO, "on": false, "w": 0.0, "arm": 0 }  # the other hand, on something too (a mop's handle)
var _sx := 0.255  # the shoulder joints, off center (hers sit in a little)
var _face := StandardMaterial3D.new()
var _moods: Array = []
var _look = null  # the head's yaw someone asked for (relative to the body), or null
var _t := 0.0
var _phase := 0.0
var _since := 0.0
var _sigh := 0.0
var _st := { "y": 0.0, "squat": 0.0, "nod": 0.0, "ry": 0.0, "rz": 0.0, "rx": 0.0, "ax0": 0.0, "ae0": -0.12, "ax1": 0.0, "ae1": -0.12, "h0": 0.0, "h1": 0.0, "k0": 0.0, "k1": 0.0, "lean": 0.0, "crouch": 0.0, "step": 0.0, "hu": 0.0, "hd": 0.0 }
var _fx := { "shake": 0.0, "slip": 0.0, "feel": 0.0, "stagger": 0.0, "flip": 0.0 }  # one-off moves, each counting down
var _sdir := 1.0
var _blink := false
var _blink_next := 0.0
var _item := Node3D.new()  # hold_item's slot, in the other hand
var _canopy: Node3D  # the umbrella's
var _snow_on: Array[MeshInstance3D] = []  # head, shoulder, shoulder
var _head_top := Vector3(0.36, 0.3, 0.3)  # the TV (and a hat): how wide, how high its top, how deep


func setup(who: Dictionary, face: Texture2D, moods: Array, index: int) -> void:
	var pre := "p%d_" % index  # (each of the cast's joints is named for whose it is)
	height = who.height
	build = who.build
	_sx = 0.235 if who.female else 0.255
	gait = who.get("gait", "plain")
	_moods = moods
	_body = find_child(pre + "body", true, false)
	_upper = find_child(pre + "upper", true, false)
	_head = find_child(pre + "head", true, false)
	_torso = find_child(pre + "torso", true, false)
	for i in 2:
		_legs.append([find_child(pre + "hip%d" % i, true, false), find_child(pre + "knee%d" % i, true, false)])
		_arms.append([find_child(pre + "sh%d" % i, true, false), find_child(pre + "el%d" % i, true, false)])
	for j: Node3D in [_body, _upper, _head, _legs[0][0], _legs[0][1], _legs[1][0], _legs[1][1], _arms[0][0], _arms[0][1], _arms[1][0], _arms[1][1]]:
		j.rotation_order = EULER_ORDER_XYZ  # (three's order: the numbers below are its)
	for n: Node3D in find_children(pre + "tape*", "Node3D", true, false):
		_tapes.append(n)
		n.visible = false
	for n: Node3D in find_children(pre + "prop_*", "Node3D", true, false):
		_props[String(n.name).trim_prefix(pre + "prop_")] = n
		n.visible = false
	_face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # the face: one of sixteen on their sheet, picked by the mood
	_face.albedo_texture = face
	_face.uv1_scale = Vector3(0.25, -0.125, 1)  # (four across; four rows of them open-eyed, and the same four mid-blink)
	_blink_next = randf() * 4.0
	_arms[0][1].add_child(_item)
	_item.position = Vector3(0, -0.4, 0.07)
	if _props.has("umbrella"):
		for n: Node3D in _props.umbrella.get_children():
			if absf(n.position.y - 0.92) < 0.01:
				_canopy = n
	_snow_build()
	var screen: MeshInstance3D = find_child(pre + "screen", true, false)
	if screen:
		screen.material_override = _face
	_skin_limbs(pre, index, who.female)
	_ankles_build(pre)
	set_mood("neutral")


func set_mood(m: String) -> void:
	if m == mood:
		return
	mood = m
	_since = _t
	_face_show()


func _face_show() -> void:
	var i := maxi(0, _moods.find(mood))
	_face.uv1_offset = Vector3((i % 4) * 0.25, (i / 4 + 1 + (4 if _blink and mood in BLINKS else 0)) * 0.125, 0)


func set_pose(p: String, opts := {}) -> void:
	pose = p
	sit_at = opts


func look_at_yaw(yaw) -> void:  # turn the head (radians, + = their left); null = back to normal
	_look = null if yaw == null else clampf(yaw, -1.45, 1.45)


func hold_tape(n: int) -> void:
	for i in _tapes.size():
		_tapes[i].visible = i < n


func hold_prop(what) -> void:  # "card" / "cash" / "receipt" / "form" / "umbrella" in the other hand, or null
	prop = what if what != null and _props.has(what) else null
	for k: String in _props:
		_props[k].visible = k == what


func hold_item(n: Node3D) -> void:  # a thing of its own in that hand (a snack, a pizza box), at the size it is in the world; null: nothing
	for c in _item.get_children():
		c.queue_free()
	if n == null:
		return
	_item.add_child(n)
	n.scale /= _item.global_basis.get_scale()  # (undo the body's own scaling)


func set_snow(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if absf(k - snow) < 0.004 and (k == 0.0) == (snow == 0.0):
		return
	snow = k
	for m in _snow_on:
		m.visible = k > 0.02
	if _snow_on.is_empty() or k <= 0.02:
		return
	var w := 0.6 + 0.3 * minf(1.0, k * 2.0)
	_snow_on[0].scale = Vector3(_head_top.x * w, 0.01 + 0.07 * k, _head_top.z * (w - 0.05))
	for i in [1, 2]:
		_snow_on[i].scale = Vector3(0.1 + 0.06 * k, 0.008 + 0.035 * k, 0.12 + 0.06 * k)


func _snow_build() -> void:  # lumps on top of the TV (or the hat) and the shoulders, grown by set_snow
	var top := AABB()
	for m: MeshInstance3D in _head.find_children("*", "MeshInstance3D", true, false):
		if m.visible and m.mesh != null:
			var b: AABB = _head.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			top = b if top.size == Vector3.ZERO else top.merge(b)
	if top.size != Vector3.ZERO:
		_head_top = Vector3(top.size.x, top.end.y, top.size.z)
	var lump := SphereMesh.new()  # ponytail: a ball squashed flat, where the web game has a box with its corners rounded off
	lump.radial_segments = 12
	lump.rings = 6
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("#f4f7fb")
	white.emission_enabled = true
	white.emission = Color("#3c4148")  # (a little of its own light: fresh snow reads white even in the overcast)
	lump.material = white
	for at: Array in [[_head, Vector3(0, _head_top.y, -0.02)], [_upper, Vector3(-_sx * 0.62, 0.665, -0.01)], [_upper, Vector3(_sx * 0.62, 0.665, -0.01)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = lump
		mi.position = at[1]
		mi.visible = false
		at[0].add_child(mi)
		_snow_on.append(mi)


func shake() -> void:  # snow and water off, at the door
	_fx.shake = 1.0


func slip() -> void:  # a wet floor
	_fx.slip = 1.1


func feel_rain() -> void:  # a palm out, a look up: is that rain?
	_fx.feel = 1.8


func stagger(dir := 1.0) -> void:  # shoved by a gust: +1 to their left, -1 to their right
	if _fx.stagger <= 0.0:
		_fx.stagger = 0.9
		_sdir = dir


func umbrella_flip() -> void:  # a gust turns it inside out
	if prop == "umbrella" and _fx.flip <= 0.0:
		_fx.flip = 1.6


func busy() -> bool:  # mid-slip, shaking off: whoever's walking them holds them where they are
	return _fx.slip > 0.0 or _fx.shake > 0.3


func reach_to(point, arm := 1, lean := true) -> void:  # put a hand on a point in the world (eased in and out); null lets go. lean: false = the arm only (counter work: no bowing)
	if point == null:
		_reach.on = false
	else:
		_reach.target = point
		_reach.on = true
		_reach.arm = arm
		_reach.lean = lean


func reach_also(point, arm := 0) -> void:  # the other hand to a point as well (the arm only)
	_reach2.on = point != null
	if point != null:
		_reach2.target = point
		_reach2.arm = arm


func _arm_ik(arm: int, target: Vector3, w: float) -> void:  # two-bone IK: the elbow from the law of cosines, the shoulder swung to aim the chain
	var sh: Node3D = _arms[arm][0]
	var el: Node3D = _arms[arm][1]
	var d := _upper.to_local(target) - sh.position
	var D := clampf(d.length(), 0.12, 0.29 + 0.32 - 0.01)  # (shoulder to elbow 0.29, elbow to hand 0.32)
	var inner := acos(clampf((0.29 * 0.29 + 0.32 * 0.32 - D * D) / (2.0 * 0.29 * 0.32), -1.0, 1.0))
	var e := -(PI - inner)  # negative: the forearm folds forward
	var hand0 := Vector3(0.0, -0.29 - 0.32 * cos(e), -0.32 * sin(e)).normalized()
	sh.quaternion = sh.quaternion.slerp(Quaternion(hand0, d.normalized()), w)
	el.rotation.x += (e - el.rotation.x) * w


func sigh() -> void:
	_sigh = 1.3


func _ease(k: String, v: float, rate: float) -> float:  # eased pose channels
	_st[k] += (v - _st[k]) * rate
	return _st[k]


func tick(dt: float, speed := 0.0) -> void:  # animate; speed: m/s along the ground (0: standing)
	_t += dt
	var t := _t
	var G: Dictionary = GAITS[gait]
	var run := clampf((speed - 1.9) / 0.8, 0.0, 1.0)  # over ~2 m/s the walk turns into a run
	# walk cycle: the stride advances with ground speed, so feet don't skate; a faster walker also lengthens their stride
	for k: String in _fx:
		_fx[k] = maxf(0.0, _fx[k] - dt)
	# the wind in their own frame: x to their left, z the way they face
	var wl := wind.x * cos(rotation.y) - wind.y * sin(rotation.y)
	var wf := wind.x * sin(rotation.y) + wind.y * cos(rotation.y)
	var head_w := clampf(-wf / 8.0, 0.0, 1.0)  # into it
	var tail_w := clampf(wf / 8.0, 0.0, 1.0)  # with it behind them
	var slip_k: float = sin(_fx.slip / 1.1 * PI) if _fx.slip > 0.0 else 0.0
	var shake_k: float = sin(_fx.shake * PI) if _fx.shake > 0.0 else 0.0
	var feel_k: float = minf(1.0, minf(_fx.feel * 2.0, (1.8 - _fx.feel) * 3.0)) if _fx.feel > 0.0 else 0.0
	var stag_k: float = sin(_fx.stagger / 0.9 * PI) if _fx.stagger > 0.0 else 0.0
	var stride: float = (0.34 + 0.12 * clampf(speed - 1.0, 0.0, 1.0)) * (G.stride * (1.0 - run) + run) * (1.0 - 0.3 * hunch * (1.0 - run)) * (1.0 - 0.25 * head_w) + 0.36 * run  # radians of hip swing
	var A := stride * 1.2
	var stance_f := 0.6 - 0.22 * run
	var reach_d := LEG * sin(A)
	if speed > 0.01:
		_phase += dt * TAU * stance_f * speed / (2.0 * reach_d)
	var walking := speed > 0.01
	var r := minf(1.0, dt * 10.0)
	var sit := pose == "sit"
	var sw_u := sin(_phase - 0.5) if walking else 0.0  # the upper body: the same rhythm, trailing the legs
	var soft := minf(1.0, dt * 6.0)
	# down to something on the floor (not the web game's deep squat, which with a reach on top folded them into a ball):
	# a half kneel. The foot on the other side from the reaching hand stays flat out front, thigh level and shin upright;
	# the near knee goes down to the floor under the hip. The back tips forward from the waist, no further than a third of the way
	# over, the reaching arm does the rest, the other hangs to the front knee, and the eyes are on the hand
	var squat := _ease("squat", 1.0 if pose == "crouch" else 0.0, minf(1.0, dt * 6.0))
	var lead := 0 if _reach.arm == 1 else 1
	# reaching: where the target sits relative to an unbent shoulder decides how much to bend at the waist, crouch, or step in
	_reach.w += ((1.0 if _reach.on else 0.0) - _reach.w) * minf(1.0, dt * 5.0)
	var w: float = 0.0 if _reach.w < 0.002 else _reach.w
	var flat := 0.0
	var dy := 0.0
	if w > 0.0:
		var d := to_local(_reach.target) - Vector3((_sx if _reach.arm else -_sx) * build, 1.5 * height, 0.0)
		flat = Vector2(d.x, d.z).length()
		dy = d.y + squat * KNEEL * height  # (knelt: the shoulder's already that much nearer the floor)
	var bend: bool = w > 0.0 and _reach.lean  # may the body help? (shelves yes, counter work no)
	var low := maxf(0.0, -dy - 0.35) if bend else 0.0
	var far := maxf(0.0, flat - 0.4) if bend else 0.0
	var lean := _ease("lean", minf(1.0 - 0.4 * squat, far * 1.4 + low * 0.9), minf(1.0, dt * 5.0)) * w  # bend at the waist toward it
	var crouch := _ease("crouch", clampf((low - 0.35) / 0.5, 0.0, 1.0), minf(1.0, dt * 5.0)) * w * (1.0 - squat)  # really low: bend the knees too
	var step_in := _ease("step", clampf(maxf(0.0, flat - 0.4) - (0.35 if bend else 0.2), 0.0, 0.2) if w > 0.0 else 0.0, minf(1.0, dt * 5.0)) * w  # really far: a half step in
	# the gait cycle, per leg (p: 0..1 from its heel strike): a stance of ~60% (less running), then the swing
	var cyc := _phase / TAU - 0.25
	var knee_k: float = (G.knee * (1.0 - run) + 1.6 * run) * (1.0 - 0.4 * hunch) * minf(1.0, 0.55 + 0.35 * speed)
	var kn_end := 0.55 * knee_k
	var th_end := asin(maxf(-1.0, -reach_d / (LEG * cos(kn_end / 2.0)))) + kn_end / 2.0  # the thigh at toe off, where the swing picks up
	var gl := [_leg_at(fposmod(cyc, 1.0), stance_f, reach_d, knee_k, th_end, A), _leg_at(fposmod(cyc + 0.5, 1.0), stance_f, reach_d, knee_k, th_end, A)]
	# the hips ride on the planted leg: as high as it reaches (vaulting over it), dropping as the legs spread
	var plant := -1.0
	for g: Array in gl:
		if g[2] > 0.0:
			plant = maxf(plant, cos(g[0] - g[1] / 2.0) * cos(g[1] / 2.0) - 1.0)
	var leg_bob := plant * LEG * height if walking and plant > -1.0 else 0.0
	for i in 2:
		var hx: float = -PI / 2.0 if sit else -gl[i][0] if walking else 0.0  # (thigh forward is -x)
		var kx: float = PI / 2.0 + sit_at.get("tuck", 0.0) if sit else gl[i][1] if walking else 0.0
		var lr := 1.0 if walking and not sit else r  # walking: exactly where the cycle puts them (easing lags, and the feet skate)
		_legs[i][0].rotation.x = _ease("h%d" % i, hx - (0.0 if i else slip_k * 0.6), lr) - crouch * 1.05 + squat * (-1.414 if i == lead else 0.425)
		_legs[i][1].rotation.x = _ease("k%d" % i, kx, lr) + crouch * 1.9 + squat * (1.414 if i == lead else 1.325)  # (the knee down: its shin folded up behind, toes clear of the floor)
	var seat_y: float = sit_at.get("hipY", 0.5) - 0.9 * height if sit else 0.0  # hips down to the seat
	var jolt := sin((t - _since) / 0.35 * PI) * 0.06 if mood == "shock" and t - _since < 0.35 else 0.0  # a little jump
	var bob := 0.0
	if walking:
		bob = leg_bob + run * 0.03 * absf(sin(_phase)) + (pow(maxf(0.0, sin(_phase)), 2.0) * 0.06 if G.get("hop", false) and run == 0.0 else 0.0)
	var body_y := seat_y + jolt + bob - slip_k * 0.08
	_st.y += (body_y - _st.y) * (r if absf(body_y - _st.y) > 0.05 else 1.0)  # eased sitting down / getting up, the bob tracked directly
	_body.position.y = _st.y - crouch * 0.4 - squat * KNEEL * height
	_body.position.z = step_in - squat * 0.12  # (the hips sit back between the front foot and the knee that's down)
	_body.position.x = stag_k * 0.12 * _sdir  # a gust shoves them a step sideways
	var sg := 0.0  # a sigh: up, then a long sag
	if _sigh > 0.0:
		_sigh -= dt
		sg = sin((1.0 - _sigh / 1.3) * PI)
	_upper.rotation.x = lean + (0.28 if pose == "lean" else 0.0) + maxf(0.0, sg) * 0.08 + _ease("hu", hunch * 0.16 + head_w * 0.12, minf(1.0, dt * 3.0)) + (G.lean if walking else 0.0)  # hunched against it
	if _torso:  # breathing
		_torso.scale.y = 0.56 * (1.0 + sin(t * 1.7) * 0.012)
		_torso.scale.z = 0.245 * (1.0 + sin(t * 1.7) * 0.02)
	var pelvis := _ease("ry", (gl[0][0] - gl[1][0]) / (2.0 * A) * 0.08 * G.twist * (1.0 - 0.6 * run) if walking else 0.0, soft)  # the pelvis turns with the leg going forward
	_body.rotation.y = pelvis + shake_k * sin(t * 38.0) * 0.16  # (a shake: twisting it off)
	_upper.rotation.y = -pelvis * 1.7  # the shoulders counter it, with the arms
	var wind_z := clampf(wl * 0.022, -0.16, 0.16)  # leaning into a crosswind (wind to their left: they lean right, into it)
	_body.rotation.z = _ease("rz", (0.0 if walking or sit else sin(t * 0.45) * 0.018) + (G.sway * (1.0 - run) * sin(_phase) if walking else 0.0) + (0.0 if sit else wind_z), r * 0.3) \
		- stag_k * 0.2 * _sdir + slip_k * sin(t * 17.0) * 0.12  # idle weight shift, hip to hip; a hip sway; the wind
	_body.rotation.x = _ease("rx", (minf(0.08, speed * 0.05) + 0.17 * run if walking and walk_lean else 0.0) + (0.0 if sit else head_w * 0.2 - tail_w * 0.05), r * 0.5) - slip_k * 0.3  # lean into the walk (and the run, and a headwind); back on their heels in a slip
	var a_sw: float = 0.3 * (G.arms * (1.0 - run) + 2.3 * run) * (1.0 - 0.6 * hunch)
	var lx := sw_u * a_sw if walking else 0.0  # arms: smaller than the legs, trailing them
	var rx := -sw_u * a_sw if walking else 0.0
	var le := -0.22 - maxf(0.0, -sw_u) * 0.22 if walking else -0.12  # elbows bend on the forward swing
	var re := -0.22 - maxf(0.0, sw_u) * 0.22 if walking else -0.12
	if run > 0.0:  # running: elbows at right angles, pumping
		le += (-1.45 - maxf(0.0, -sw_u) * 0.25 - le) * run
		re += (-1.45 - maxf(0.0, sw_u) * 0.25 - re) * run
	var holding := _tapes.size() > 0 and _tapes[0].visible
	var free := not pose in ["hold", "reach", "wait", "lean", "read", "watch", "sit"] and not holding and prop == null
	if free and walking and G.get("behind", false) and run == 0.0:  # a stroll: hands clasped behind
		lx = 0.42
		rx = 0.42
		le = -0.55
		re = -0.55
	if free and hunch > 0.05:  # hugging themselves
		var k := minf(1.0, hunch * 1.3) * (1.0 - run)
		lx += (-0.4 - lx) * k
		rx += (-0.4 - rx) * k
		le += (-1.6 - le) * k
		re += (-1.6 - re) * k
	if pose == "reach":
		rx = -1.45 - sin(t * 3.0) * 0.05
		re = -0.2
	if pose == "hold":
		rx = -0.35 if walking else -0.45
		re = -1.0
	if sit:  # hands in the lap (up when startled)
		lx = -1.1 if mood == "shock" else -0.45
		rx = lx
		le = -0.9 if mood == "shock" else -0.8
		re = le
	if pose == "wait":  # hands up on the counter
		lx = -0.25
		le = -1.2
		if not holding:
			rx = -0.25
			re = -1.25
	if pose == "lean":  # forearms down on the counter, weight on them
		lx = -0.55
		rx = -0.55
		le = -1.05
		re = -1.05
	if pose == "read":  # the tape up in front, turned to read the back
		rx = -1.05
		re = -1.45
	if pose == "watch":  # wrist up across the chest
		lx = -0.45
		le = -1.55
	if prop == "umbrella":  # held up, the hand at the chest (wrestling it, inside out)
		lx = -0.35
		le = -1.25
		if _fx.flip > 0.0:
			lx -= sin(t * 22.0) * 0.3
			le -= 0.3
	elif shield:  # a hand up over the head against the rain
		lx = -2.75
		le = -0.95
	if feel_k > 0.0:  # palm out: is that rain?
		rx += (-1.15 - rx) * feel_k
		re += (-0.3 - re) * feel_k
	if shake_k > 0.0:  # brushing it off the shoulders
		lx += (-1.0 - lx) * shake_k
		le += (-1.75 + sin(t * 24.0) * 0.25 - le) * shake_k
	var ar := soft if walking else r  # arms carry some momentum while walking; poses still settle promptly
	var p2 := [[_ease("ax0", lx, ar), _ease("ae0", le, ar)], [_ease("ax1", rx, ar), _ease("ae1", re, ar)]]
	var flail := maxf(slip_k, stag_k * 0.6)  # arms out for balance
	for i in 2:
		_arms[i][0].rotation = Vector3(p2[i][0] - flail * 0.4, 0.0, (-0.06 if i else 0.06) + flail * (-1.2 if i else 1.2) * (1.0 + sin(t * 15.0 + i) * 0.15))
		_arms[i][1].rotation.x = p2[i][1]
	_arms[lead][0].rotation.x -= lean * squat * 0.9  # (knelt: the other arm hangs straight down, to the front knee)
	_ankles_tick([not walking or gl[0][2] > 0.0, not walking or gl[1][2] > 0.0])
	_mocap_tick(dt, speed, walking and run < 0.3 and not sit and squat < 0.1 and crouch < 0.1 and w < 0.1 and pose in ["idle", "walk", "hold"], free and pose != "hold")
	_move_tick(dt, false)  # ponytail: the arms stay procedural, the kneel's capture has them out comforting someone
	if w > 0.0:
		_arm_ik(_reach.arm, _reach.target, w)
	_reach2.w += ((1.0 if _reach2.on else 0.0) - _reach2.w) * minf(1.0, dt * 5.0)
	if _reach2.w > 0.002 and not (w > 0.0 and _reach.arm == _reach2.arm):
		_arm_ik(_reach2.arm, _reach2.target, _reach2.w)
	# head: browsing scans, impatience tilts, otherwise a slow idle drift
	var yaw: float = _look if _look != null else sin(t * 1.3) * 0.25 if mood == "browse" else sin(t * 2.3) * 0.55 if mood == "shifty" else sin(t * 0.4) * 0.05  # shifty: checking over both shoulders
	_head.rotation.y += (yaw + (sin(t * 0.9) * 0.06 if talking else 0.0) - _head.rotation.y) * r * 0.6
	_head.rotation.z += ((0.12 if mood == "impatient" else sin(t * 1.3) * 0.05 if talking else 0.0) - _head.rotation.z) * r * 0.5
	_head.rotation.x = _ease("nod", cos(_phase * 2.0 - 0.8) * 0.008 if walking else -0.06 if mood == "watch" else maxf(0.0, sin(t * 2.4)) * 0.05 if talking else 0.0, soft) \
		+ lean * 0.85 + (0.3 if pose == "read" else 0.35 if pose == "watch" else 0.0) + maxf(0.0, sg) * 0.2 + squat * w * 0.25 \
		+ _ease("hd", hunch * 0.14 + head_w * 0.16 - feel_k * 0.4 + (0.08 if walking and G.lean > 0.06 else 0.0), minf(1.0, dt * 3.0)) - slip_k * 0.25  # (bowing with the upper body; knelt, eyes on what the hand's at; down into the weather, up at the sky, thrown back in a slip)
	_head.rotation.z += shake_k * sin(t * 31.0) * 0.1
	_head.position = to_local(_upper.to_global(Vector3(0.0, 0.73, HEAD_Z / height)))  # the head rides the top of the neck, wherever the waist has put it
	if prop == "umbrella":  # straight up in the world, over the head: angled into the wind, shaking in it
		var wob := sin(t * 7.3) * 0.04 * minf(1.0, wind.length() / 6.0)
		_props.umbrella.global_basis = Basis.from_euler(Vector3(clampf(-wind.y * 0.045, -0.5, 0.5) + wob, 0.0, clampf(wind.x * 0.045, -0.5, 0.5) - wob), EULER_ORDER_XYZ)
		if _canopy != null:
			_canopy.scale.y = -0.7 if _fx.flip > 0.0 else 1.0  # blown inside out
	if t > _blink_next:  # a blink now and then
		_blink = not _blink
		_blink_next = t + (0.12 if _blink else 2.0 + randf() * 3.0)
		_face_show()
	for i in _bones.size():  # the skin follows the joints
		_skel.set_bone_pose_position(i, _bones[i].position)
		_skel.set_bone_pose_rotation(i, _bones[i].quaternion)
		_skel.set_bone_pose_scale(i, _bones[i].scale)


# ---- ankles: not the web game's (its legs end at the knee, the shoe hung off the shin). A joint where the shin meets
# the shoe: planted, the foot stays flat on the floor (walking, crouched, knelt, sat), and in the air it hangs a little

var _ankles: Array[Node3D] = []


func _ankles_build(pre: String) -> void:
	for i in 2:
		var knee: Node3D = _legs[i][1]
		var a := Node3D.new()
		a.name = pre + "ankle%d" % i
		a.position = Vector3(0, -0.37, 0)  # (the shin's foot: the shoe's top)
		a.rotation_order = EULER_ORDER_XYZ
		knee.add_child(a)
		for c in knee.get_children():
			if c is MeshInstance3D and (c.transform * c.get_aabb().get_center()).y < -0.25:
				c.reparent(a, true)  # the shoe and everything on it
		_ankles.append(a)


func _ankles_tick(stance: Array) -> void:  # stance: is each foot planted (or on the floor anyway: sat, crouched)
	for i in _ankles.size():
		var shin: float = _body.rotation.x + _legs[i][0].rotation.x + _legs[i][1].rotation.x  # the shin's pitch in the world
		_ankles[i].rotation.x = -shin if stance[i] else -shin * 0.6 + 0.25  # flat on the floor; in the air, toes a little down


# ---- mocap: a walk out of the 100STYLE motion capture (Mason, Starke, Komura et al., CC BY 4.0: people/gaits/, made by
# tools/bvh2gait.py, from its BVH files), played over the procedural walk for the gaits that
# have one. Every joint the rig has (the pelvis, the waist, the hips, knees, ankles, shoulders, elbows, the head's
# nod) follows the capture, cycled at the speed the person's going (its stride scaled to their legs). Reaching,
# sitting, crouching, running and the counter's poses stay procedural; it eases in and out with the walk

const MOCAP := { "plain": "neutral", "brisk": "rushed", "shuffle": "old", "swagger": "strutting", "stroll": "armsbehindback", "bouncy": "elated", "sway": "wigglehips", "stomp": "heavyset", "skip": "skip" }

static var _clips := {}  # gait -> its cycle (or null: none)

var mocap := false  # ponytail: off, the captures looked goofy on this cast (true: play people/gaits/ over the walk)
var _mw := 0.0
var _mphase := 0.0


static func clip(g: String):
	if not _clips.has(g):
		var path := "res://people/gaits/%s.json" % MOCAP.get(g, "-")
		_clips[g] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return _clips[g]


func _mocap_tick(dt: float, speed: float, want: bool, arms_free: bool) -> void:
	var c = clip(gait) if mocap else null
	_mw += ((1.0 if want and c != null else 0.0) - _mw) * minf(1.0, dt * 6.0)
	if c == null or _mw < 0.002:
		return
	var per: float = c.period
	var rate := clampf(speed / maxf(0.2, float(c.stride) * LEG * height), 0.6 / per, 1.5 / per)  # a cycle per stride, at their speed (kept near the style's own pace: a shuffle at a brisk walk would whirl)
	_mphase = fposmod(_mphase + dt * rate, 1.0)
	var n: int = c.n
	var f := _mphase * n
	var i0 := int(f) % n
	var i1 := (i0 + 1) % n
	var k := f - floorf(f)
	var cv: Dictionary = c.curves
	var at := func(key: String) -> float: return lerpf(cv[key][i0], cv[key][i1], k) if cv.has(key) else 0.0
	_body.position.y += at.call("y") * LEG * height * _mw
	_apply_capture(at, _mw, arms_free, false)
	_head.rotation.x += (at.call("head_rx") - 0.39) * 0.5 * _mw  # (the capture's neck rides ~22 degrees forward walking: level, that's looking ahead)


func _apply_capture(at: Callable, w: float, arms_free: bool, mirror: bool) -> void:  # a capture's joint angles onto the joints, by w (mirror: its left is their right)
	var m := -1.0 if mirror else 1.0
	var lean: float = at.call("body_rx")
	_body.rotation.y = lerpf(_body.rotation.y, at.call("body_ry") * m, w)
	_body.rotation.x = lerpf(_body.rotation.x, 0.0, w)  # (the lean's the waist's: the legs are measured from upright)
	_upper.rotation.x = lerpf(_upper.rotation.x, lean, w)
	_upper.rotation.y = lerpf(_upper.rotation.y, at.call("upper_ry") * m, w)
	_upper.rotation.z = lerpf(_upper.rotation.z, at.call("body_rz") * m, w)
	for i in 2:  # (0 is on their right, -x; 1 their left)
		var s := "R" if (i == 0) != mirror else "L"
		var out := -1.0 if i == 0 else 1.0
		_legs[i][0].rotation.x = lerpf(_legs[i][0].rotation.x, -at.call("hip%s_x" % s), w)  # (thigh forward is -x)
		_legs[i][0].rotation.z = lerpf(_legs[i][0].rotation.z, at.call("hip%s_z" % s) * out, w)
		_legs[i][1].rotation.x = lerpf(_legs[i][1].rotation.x, at.call("knee%s" % s), w)
		if i < _ankles.size():
			_ankles[i].rotation.x = lerpf(_ankles[i].rotation.x, at.call("ankle%s" % s), w)
		if arms_free:
			_arms[i][0].rotation.x = lerpf(_arms[i][0].rotation.x, -(at.call("sh%s_x" % s) - lean), w)  # (forward is -x; under the waist's lean)
			_arms[i][0].rotation.z = lerpf(_arms[i][0].rotation.z, (0.06 if i == 0 else -0.06) + at.call("sh%s_z" % s) * out, w)
			_arms[i][1].rotation.x = lerpf(_arms[i][1].rotation.x, -at.call("el%s" % s), w)


# ---- moves: one-off captures from the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu: people/moves/, made by
# tools/bvh2move.py) over the procedural pose. Going down to the floor ("crouch"), the capture plays to its lowest
# point and holds there while the reaching hand finds the thing (its IK goes on top); letting go of the pose plays the
# rest of it, back up. Mirrored so the front foot is the one away from the reaching hand

const MOVES := { "crouch": "kneel" }  # pose -> people/moves/<name>.json
const MOVE_DOWN := 0.7  # seconds to the bottom, whatever the capture took (it took 1.6: too slow for someone's errand, or your crouch key)

static var _moves := {}

var moves := true  # (false: the procedural poses only)
var _mv := { "clip": null, "t": 0.0, "up": false, "mirror": false }


static func move_clip(n: String):
	if not _moves.has(n):
		var path := "res://people/moves/%s.json" % n
		var c = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if c != null:
			var ys: Array = c.curves.y
			c.low = float(ys.find(ys.min())) / float(c.n - 1)  # (0..1: the bottom)
		_moves[n] = c
	return _moves[n]


func _move_tick(dt: float, arms_free: bool) -> void:
	var want: String = MOVES.get(pose, "") if moves else ""
	if want != "" and (_mv.clip == null or _mv.up):
		_mv.clip = move_clip(want)
		_mv.t = 0.0 if not _mv.up else _mv.clip.low * (1.0 - (_mv.t - _mv.clip.low) / (1.0 - _mv.clip.low))  # (back down from as far up as they'd got)
		_mv.up = false
		_mv.mirror = _reach.arm == 1
	var c = _mv.clip
	if c == null:
		return
	var rate: float = c.low / MOVE_DOWN
	if want == "" and not _mv.up:
		_mv.up = true
		_mv.t = c.low + (c.low - _mv.t) / c.low * (1.0 - c.low)  # (up from as far down as they'd got)
	_mv.t = _mv.t + dt * rate if _mv.up else minf(c.low, _mv.t + dt * rate)
	if _mv.t >= 1.0:
		_mv.clip = null
		return
	var w := minf(1.0, minf(_mv.t, 1.0 - _mv.t) / 0.08)  # (in and out of it from whatever they were doing)
	var f: float = _mv.t * (c.n - 1)
	var i0 := int(f)
	var i1 := mini(i0 + 1, c.n - 1)
	var k := f - i0
	var cv: Dictionary = c.curves
	var at := func(key: String) -> float: return lerpf(cv[key][i0], cv[key][i1], k) if cv.has(key) else 0.0
	_body.position.y = lerpf(_body.position.y, _st.y + at.call("y") * LEG * height, w)
	_body.position.z = lerpf(_body.position.z, at.call("z") * LEG * height, w)
	_apply_capture(at, w, arms_free, _mv.mirror)


func _leg_at(p: float, stance_f: float, reach_d: float, knee_k: float, th_end: float, A: float) -> Array:  # -> [thigh angle forward, knee bend, planted]
	if p < stance_f:  # planted: the foot slides back under the hip at a steady rate (so it's still on the floor), the thigh solved for it
		var k := p / stance_f
		var kn := (0.32 * exp(-pow((k - 0.2) / 0.13, 2.0)) + 0.55 * pow(maxf(0.0, (k - 0.65) / 0.35), 2.0)) * knee_k  # the knee giving to take the weight, then heel off into toe off
		return [asin(clampf(reach_d * (1.0 - 2.0 * k) / (LEG * cos(kn / 2.0)), -1.0, 1.0)) + kn / 2.0, kn, 1.0]
	var k := (p - stance_f) / (1.0 - stance_f)  # the swing: fold just enough to clear the floor, swing through, straighten
	return [th_end + (A - th_end) * (1.0 - cos(PI * minf(1.0, k / 0.8))) / 2.0, (0.55 + 0.07 * k / 0.2 if k < 0.2 else 0.62 * cos(PI / 2.0 * minf(1.0, (k - 0.2) / 0.6))) * knee_k, 0.0]


# ---- the limbs as one skin (customers.js: skinLimbs). The legs, hips, torso and arms as one skinned surface over the
# same joints, so a knee or an elbow bends as one surface instead of two blocks meeting: each vertex follows its
# nearest joints, blended across the joint, and the cloth stops where the colour changes, not at a gap. The cut of the
# pants, the sleeve and the shirt's faces are read back off the blocks the export has (their sizes and materials),
# which are then hidden. Hands, shoes and the head stay as they are

const SEG := 16

static var _skins := {}  # the cast's skins, by their number: { mesh, mat } (mat: the leg's material it was made with)

var _skel: Skeleton3D
var _bones: Array[Node3D] = []


func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _blocks(joint: Node3D) -> Array:  # the meshes hung straight off a joint
	return joint.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D)


func _skin_limbs(pre: String, index: int, female: bool) -> void:
	var thighs: Array = _blocks(_legs[0][0])
	if thighs.is_empty():
		return
	var soft_n: int = thighs[0].mesh.get_faces().size()  # (the soft block every limb is made of)
	var soft := func(c: MeshInstance3D) -> bool: return c.mesh.get_faces().size() == soft_n and not String(c.name).begins_with(pre)
	_bones = [_body, _upper, _legs[0][0], _legs[0][1], _legs[1][0], _legs[1][1], _arms[0][0], _arms[0][1], _arms[1][0], _arms[1][1]]
	var parents := [-1, 0, 0, 2, 0, 4, 1, 6, 1, 8]
	_skel = Skeleton3D.new()
	for i in _bones.size():
		_skel.add_bone(String(_bones[i].name))
		if parents[i] >= 0:
			_skel.set_bone_parent(i, parents[i])
		_skel.set_bone_rest(i, Transform3D(Basis.from_scale(_bones[i].scale), Vector3.ZERO if i == 0 else _bones[i].position))
	_skel.reset_bone_poses()
	add_child(_skel)
	var at := func(i: int) -> Vector3: return _skel.get_bone_global_rest(i).origin
	var H := _body.scale.y
	var W := _body.scale.x
	var A := { "pos": PackedVector3Array(), "uv": PackedVector2Array(), "bones": PackedInt32Array(), "weights": PackedFloat32Array(), "by_mat": {} }
	var hide: Array = []
	var leg_m: Material = thighs[0].get_active_material(0)
	var make: bool = not _skins.has(index) or _skins[index].mat != leg_m
	for li in 2:  # the legs: from inside the hips down into the shoes
		var hip_blocks: Array = _blocks(_legs[li][0])
		var knee_blocks: Array = _blocks(_legs[li][1]).filter(soft)
		hide.append_array(hip_blocks)
		hide.append_array(knee_blocks)
		if not make or hip_blocks.is_empty() or knee_blocks.is_empty():
			continue
		var thigh: MeshInstance3D = hip_blocks[0]
		var shin: MeshInstance3D = knee_blocks[0]
		var skin: Material = shin.get_active_material(0)
		var kind := "bike" if skin != thigh.get_active_material(0) else ""
		for b: MeshInstance3D in knee_blocks:  # (the hem just past the knee: shorts; a long loose one to mid-shin: cargo)
			if absf(b.position.y + 0.02) < 0.005 and absf(b.scale.y - 0.1) < 0.005:
				kind = "shorts"
			elif absf(b.position.y + 0.07) < 0.005 and absf(b.scale.y - 0.2) < 0.005:
				kind = "cargo"
		var stripe: bool = thigh.mesh.get_surface_count() > 1  # (track pants: the face with the stripe, wrapped round so it runs down the outside seam)
		var hp: Vector3 = at.call(2 + li * 2)
		var hY := hp.y
		var kY: float = at.call(3 + li * 2).y
		var aY := kY - 0.37 * H
		var t0 := thigh.scale.x / 2.0
		var t1 := shin.scale.x / 2.0
		var B := 2 + li * 2
		var cut: float = kY - 0.02 if kind == "shorts" else kY - 0.2 if kind == "cargo" else kY + 0.02 if kind == "bike" else -9.0  # where bare leg starts
		var pants: Material = thigh.get_active_material(0)
		_tube(A, hp.x, 0.005, [[hY + 0.04, t0 * W * 1.02, t0 + 0.012], [hY - 0.2, t0 * W * 0.98, t0 + 0.01], [kY + 0.08, t0 * W * 0.86, t0 * 0.9 + 0.008], [kY, t1 * W * 1.02, t1 + 0.01], [kY - 0.12, t1 * W * 1.05, t1 + 0.012], [aY, t1 * W * 0.72, t1 * 0.75]],
			func(y: float) -> Array:
				var top := 0.5 * (1.0 - _ss(hY + 0.04, hY - 0.14, y))
				var kn := _ss(kY + 0.06, kY - 0.06, y)
				return [[0, top], [B, (1.0 - top) * (1.0 - kn)], [B + 1, (1.0 - top) * kn]],
			func(y: float) -> Material: return pants if y > cut else skin,
			(0.46 if hp.x > 0.0 else -0.04) if stripe else 0.0)
	for ai in 2:  # the arms: from the shoulder (inside the torso) to the wrist (inside the hand)
		var sh_blocks: Array = _blocks(_arms[ai][0])
		var el_blocks: Array = _blocks(_arms[ai][1]).filter(soft)
		hide.append_array(sh_blocks)
		hide.append_array(el_blocks)
		var hand: MeshInstance3D = _arms[ai][1].get_node_or_null(pre + "hand%d" % ai)
		if not make or sh_blocks.is_empty() or el_blocks.is_empty() or hand == null:
			continue
		var cuffs: Array = el_blocks.filter(func(b: MeshInstance3D) -> bool: return absf(b.scale.y - 0.04) < 0.005)
		var sl := "cap" if sh_blocks.size() >= 3 else "baggy" if absf(sh_blocks[0].scale.x - 0.145) < 0.005 else "long" if cuffs.size() else "short"
		var skin: Material = hand.get_active_material(0)
		var sleeve_m: Material = sh_blocks[1 if sl == "cap" else 0].get_active_material(0)
		var collar_m: Material = sh_blocks[2].get_active_material(0) if sl == "cap" else cuffs[0].get_active_material(0) if sl == "long" else sh_blocks[1].get_active_material(0) if sh_blocks.size() > 1 else skin
		var sp: Vector3 = at.call(6 + ai * 2)
		var sY := sp.y
		var eY: float = at.call(7 + ai * 2).y
		var wY := eY - 0.27 * H
		var B := 6 + ai * 2
		var end: float = sY - 0.1 if sl == "cap" else -9.0 if sl == "long" else sY - 0.3  # where the sleeve stops
		var loose: float = 0.012 if sl == "baggy" else 0.0 if sl == "long" else 0.006
		var r := func(y: float) -> float: return loose if y > end else 0.0
		var rings: Array = [[sY - 0.02, 0.06, 0.064], [sY - 0.07, 0.064, 0.068], [eY + 0.03, 0.055, 0.058], [eY - 0.03, 0.053, 0.056], [wY, 0.043, 0.045]].map(func(q: Array) -> Array: return [q[0], (q[1] + r.call(q[0])) * W, q[2] + r.call(q[0])])
		if end > wY:
			for y: float in [end + 0.012, end - 0.012]:
				var rx := 0.055 + (0.064 - 0.055) * clampf((y - eY) / (sY - eY), 0.0, 1.0)
				rings.append([y, (rx + r.call(y)) * W, rx + 0.004 + r.call(y)])
		rings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		_tube(A, sp.x, 0.0, rings,
			func(y: float) -> Array:
				var top := 0.5 * (1.0 - _ss(sY + 0.04, sY - 0.12, y))
				var e := _ss(eY + 0.06, eY - 0.06, y)
				return [[1, top], [B, (1.0 - top) * (1.0 - e)], [B + 1, (1.0 - top) * e]],
			func(y: float) -> Material: return collar_m if sl == "long" and y < wY + 0.04 else sleeve_m if y > end else collar_m if sl == "short" and y > end - 0.04 else skin)  # (a cuff at the wrist; a short sleeve's hem band)
	var trunk := {}
	if _torso is MeshInstance3D:
		var seats: Array = _blocks(_body).filter(func(b: MeshInstance3D) -> bool: return b.scale.is_equal_approx(Vector3(0.35, 0.16, 0.22)))
		var belts: Array = _blocks(_upper).filter(func(b: MeshInstance3D) -> bool: return b.scale.is_equal_approx(Vector3(0.37, 0.035, 0.23)))
		if seats.size():
			hide.append_array(seats)
			hide.append_array(belts)  # (the buckle stays, on the band)
			hide.append(_torso)
			if make:
				trunk = _trunk(at.call(2).y, H, W, female, seats[0].get_active_material(0), belts[0].get_active_material(0) if belts.size() else null)
	# a skirt (not the web game's, where it's a stiff block hung off the hips and stays pointing down whatever the legs
	# do): its own shape, in the skin. The waistband stays with the hips; below, each side goes with its own thigh, so
	# it swings with a stride, lies along the lap sat down, and opens over a knee
	for sk: MeshInstance3D in _blocks(_body).filter(func(b: MeshInstance3D) -> bool: return absf(b.scale.x - 0.37) < 0.005 and absf(b.scale.z - 0.25) < 0.005):
		hide.append(sk)
		if not make:
			continue
		var xf := Transform3D(Basis.from_scale(_body.scale)) * sk.transform
		var nb := xf.basis.inverse().transposed()
		var hY: float = at.call(2).y
		for si in sk.mesh.get_surface_count():
			var arr: Array = sk.mesh.surface_get_arrays(si)
			var mat: Material = sk.get_active_material(si)
			if not trunk.has(mat):
				trunk[mat] = { "pos": PackedVector3Array(), "normal": PackedVector3Array(), "uv": PackedVector2Array(), "bones": PackedInt32Array(), "weights": PackedFloat32Array() }
			var o: Dictionary = trunk[mat]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(arr[Mesh.ARRAY_VERTEX].size()))
			for vi: int in ix:
				var v: Vector3 = xf * arr[Mesh.ARRAY_VERTEX][vi]
				var leg := 0.9 * _ss(hY + 0.03, hY - 0.14, v.y)  # (the hem keeps a little of the hips: cloth, not a trouser leg)
				var right := _ss(-0.1 * W, 0.1 * W, v.x)
				o.pos.append(v)
				o.normal.append((nb * arr[Mesh.ARRAY_NORMAL][vi]).normalized())
				o.uv.append(arr[Mesh.ARRAY_TEX_UV][vi] if arr[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO)
				o.bones.append_array([0, 2, 4, 0])
				o.weights.append_array([1.0 - leg, leg * (1.0 - right), leg * right, 0.0])
	if make and A.pos.size():
		_skins[index] = { "mesh": _skin_mesh(A, trunk), "mat": leg_m }
	if not _skins.has(index):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _skins[index].mesh
	mi.skin = _skel.create_skin_from_rest_transforms()
	_skel.add_child(mi)
	mi.skeleton = NodePath("..")
	for b: MeshInstance3D in hide:  # the blocks it stands in for
		b.visible = false


# one tube down a joint chain (vertical in the rest pose): rings [y, rx, rz] top to bottom, rounded shut at both ends;
# w(y) -> [[bone, weight], ...], m(y) -> its material there
func _tube(A: Dictionary, cx: float, cz: float, rings: Array, w: Callable, m: Callable, u_off := 0.0) -> void:
	var cap := func(r: Array, dir: float) -> Array: return [0.92, 0.7, 0.38, 0.02].map(func(k: float) -> Array: return [r[0] + dir * sqrt(1.0 - k * k) * minf(r[1], r[2]) * 0.9, r[1] * k, r[2] * k])
	var R: Array = cap.call(rings[0], 1.0)
	R.reverse()
	R.append_array(rings)
	R.append_array(cap.call(rings[-1], -1.0))
	var y0: float = R[0][0]
	var y1: float = R[-1][0]
	var base: int = A.pos.size()
	for q: Array in R:
		var ws: Array = w.call(q[0])
		ws.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		ws = ws.slice(0, 4)
		while ws.size() < 4:
			ws.append([0, 0.0])
		var tot: float = ws[0][1] + ws[1][1] + ws[2][1] + ws[3][1]
		for j in SEG + 1:
			var a := float(j) / SEG * TAU
			A.pos.append(Vector3(cx + q[1] * cos(a), q[0], cz + q[2] * sin(a)))
			A.uv.append(Vector2(float(j) / SEG + u_off, (q[0] - y1) / (y0 - y1)))
			for bw: Array in ws:
				A.bones.append(bw[0])
				A.weights.append(bw[1] / tot)
	for i in R.size() - 1:
		var mat: Material = m.call((R[i][0] + R[i + 1][0]) / 2.0)
		if not A.by_mat.has(mat):
			A.by_mat[mat] = PackedInt32Array()
		var a := base + i * (SEG + 1)
		var b := a + SEG + 1
		for j in SEG:
			A.by_mat[mat].append_array([a + j, a + j + 1, b + j, a + j + 1, b + j + 1, b + j])  # (wound to face out, as three has it)


# the torso and hips: one surface from the collar down to between the legs. Down to the waist it's the torso's own
# shape (so the bust, tags and hood still sit right), then it eases into the hips and closes between the legs; it
# bends at the waist. The shirt's front, back and side keep their own designs (each face of it projected flat, as on
# the box), the belt's a band painted round it, and the pants take over below. -> { material: { pos, normal, uv, bones, weights } }
func _trunk(hY: float, H: float, W: float, female: bool, seat_m: Material, belt_m: Material) -> Dictionary:
	var torso: MeshInstance3D = _torso
	var ts := Vector3(torso.scale.x, 0.56, 0.245)  # (as it's built: the export caught it mid-breath)
	var tq := torso.position
	var torso_m: Array = range(torso.mesh.get_surface_count()).map(func(i: int) -> Material: return torso.get_active_material(i))  # box faces: +x -x +y -y, front, back
	var wrap: Material = torso_m[0] if torso_m.size() < 6 else null  # (a design all the way round: the one material)
	var wrap_a := 0.5 * ts.x * W
	var wrap_b := 0.5 * ts.z
	var TAPER := 0.1 if female else 0.22
	var TC := 0.2
	var TR := 0.3
	var u_y := func(yu: float) -> float: return (0.9 + tq.y + ts.y * yu) * H  # torso unit height -> the rest pose's
	var waist := (0.9 + 0.105) * H
	var belt_h := 0.0175 * H if belt_m != null else 0.0
	var rings: Array = []  # [y, unit core, unit radius, x scale, z scale, dy (rounding)]
	for ph: float in [0.15, 0.4, 0.65, 0.85, 1.0]:
		var dy := 0.3 * cos(ph * PI / 2.0)
		var yu := TC + dy
		rings.append([u_y.call(yu), TC, sqrt(maxf(0.0, TR * TR - dy * dy)), ts.x * W * (1.0 - TAPER * (0.5 - yu)), ts.z, dy])
	for yu: float in [0.05, -0.1, -0.25]:
		rings.append([u_y.call(yu), TC, TR, ts.x * W * (1.0 - TAPER * (0.5 - yu)), ts.z, 0.0])
	var tb: Array = rings[-1]
	var pel := [0.356 * W, 0.236]  # the hips' size (as the seat of the pants was)
	var down: Array = [[waist + 0.04, 0.3], [waist, 0.55], [hY + 0.04, 0.85], [hY - 0.02, 1.0]]
	if belt_h > 0.0:  # (not the web game's: a ring at each edge of the belt, so the band's edges run straight instead of in teeth)
		down.insert(1, [waist + belt_h, 0.55 - 0.25 * belt_h / 0.04])
		down.insert(3, [waist - belt_h, 0.55 + 0.3 * belt_h / (waist - hY - 0.04)])
	for q: Array in down:
		rings.append([q[0], TC, TR, tb[3] + (pel[0] - tb[3]) * q[1], tb[4] + (pel[1] - tb[4]) * q[1], 0.0])
	for q: Array in [[0.04, 0.8], [0.065, 0.5], [0.075, 0.2]]:  # closing between the legs
		rings.append([hY - 0.02 - q[0], TC * q[1], TR * q[1], pel[0], pel[1], -q[0] / 0.075 * 0.3])
	var AN := 4
	var verts: Array = []  # a ring of { p, n, u, w } each
	for ring: Array in rings:
		var y: float = ring[0]
		var c: float = ring[1]
		var r: float = ring[2]
		var w1 := _ss(waist - 0.05, waist + 0.06, y)  # the waist: hips with the body, chest with the upper half
		var row: Array = []
		for q in 4:
			var sx := 1.0 if q == 0 or q == 3 else -1.0
			var sz := 1.0 if q < 2 else -1.0
			for t in AN + 1:
				var a := (q + float(t) / AN) * PI / 2.0
				var ux := sx * c + r * cos(a)
				var uz := sz * c + r * sin(a)
				var ru := maxf(r, 1e-4)
				var n := Vector3(cos(a) * ru, ring[5], sin(a) * ru).normalized()
				n = Vector3(n.x / ring[3], n.y / H, n.z / ring[4]).normalized()
				row.append({ "p": Vector3(ux * ring[3], y, uz * ring[4]), "n": n, "u": Vector3(ux, (y / H - 0.9 - tq.y) / ts.y, uz), "w": [0, 1.0 - w1, 1, w1] })
		verts.append(row)
	var top_c := { "p": Vector3(0, u_y.call(0.5), 0), "n": Vector3.UP, "u": Vector3(0, 0.5, 0), "w": [1, 1.0, 0, 0.0] }
	var bot_c := { "p": Vector3(0, hY - 0.1, 0), "n": Vector3.DOWN, "u": Vector3.ZERO, "w": [0, 1.0, 0, 0.0] }
	var tris: Array = []
	var M: int = verts[0].size()
	for i in M:
		tris.append([top_c, verts[0][(i + 1) % M], verts[0][i]])
	for r in verts.size() - 1:
		for i in M:
			var a: Dictionary = verts[r][i]
			var a2: Dictionary = verts[r][(i + 1) % M]
			var b2: Dictionary = verts[r + 1][(i + 1) % M]
			var bb: Dictionary = verts[r + 1][i]
			tris.append([a, a2, bb])
			tris.append([a2, b2, bb])
	for i in M:
		tris.append([bot_c, verts[-1][i], verts[-1][(i + 1) % M]])
	var out := {}
	for t: Array in tris:  # which of the shirt's faces (and its flat mapping), or the belt, or the pants
		var y: float = (t[0].p.y + t[1].p.y + t[2].p.y) / 3.0
		var n: Vector3 = t[0].n + t[1].n + t[2].n
		var mat: Material
		var uvs: Array
		if belt_m != null and absf(y - waist) < belt_h:
			mat = belt_m
			uvs = t.map(func(v: Dictionary) -> Vector2: return Vector2(v.u.x + 0.5, v.u.y + 0.5))
		elif y < waist:
			mat = seat_m
			uvs = t.map(func(v: Dictionary) -> Vector2: return Vector2(v.u.x + 0.5, v.u.y + 0.5))
		elif wrap != null:  # (a design all the way round)
			mat = wrap
			uvs = t.map(func(v: Dictionary) -> Vector2: return Vector2(_wrap_u(v.u.x, v.u.z, wrap_a, wrap_b), v.u.y + 0.5))
		elif absf(n.y) > maxf(absf(n.x), absf(n.z)):
			mat = torso_m[2]
			uvs = t.map(func(v: Dictionary) -> Vector2: return Vector2(v.u.x + 0.5, -v.u.z + 0.5))
		elif absf(n.x) > absf(n.z):
			mat = torso_m[0 if n.x > 0.0 else 1]
			var k := -1.0 if n.x > 0.0 else 1.0
			uvs = t.map(func(v: Dictionary) -> Vector2: return Vector2(k * v.u.z + 0.5, v.u.y + 0.5))
		else:
			mat = torso_m[4 if n.z > 0.0 else 5]
			var k := 1.0 if n.z > 0.0 else -1.0
			uvs = t.map(func(v: Dictionary) -> Vector2: return Vector2(k * v.u.x + 0.5, v.u.y + 0.5))
		var us: Array = uvs.map(func(q: Vector2) -> float: return q.x)
		if us.max() - us.min() > 0.5:  # (straddling where a wrapped design meets itself)
			uvs = uvs.map(func(q: Vector2) -> Vector2: return Vector2(q.x + 1.0, q.y) if q.x < 0.5 else q)
		if not out.has(mat):
			out[mat] = { "pos": PackedVector3Array(), "normal": PackedVector3Array(), "uv": PackedVector2Array(), "bones": PackedInt32Array(), "weights": PackedFloat32Array() }
		var o: Dictionary = out[mat]
		for vi: int in [0, 2, 1]:  # (Godot's front faces wind the other way)
			o.pos.append(t[vi].p)
			o.normal.append(t[vi].n)
			o.uv.append(uvs[vi])
			o.bones.append_array([t[vi].w[0], t[vi].w[2], 0, 0])
			o.weights.append_array([t[vi].w[1], t[vi].w[3], 0.0, 0.0])
	return out


# u all the way round a torso (a top whose design wraps): distance round the box's outline from the front's left edge,
# over its whole girth (A, B: half its width and depth); x, z in its unit box
func _wrap_u(x: float, z: float, A: float, B: float) -> float:
	var X := x * 2.0 * A
	var Z := z * 2.0 * B
	var s: float = (2.0 * A + (B - Z) if X > 0.0 else 4.0 * A + 2.0 * B + (Z + B)) if absf(X) / A >= absf(Z) / B else (X + A if Z > 0.0 else 2.0 * A + 2.0 * B + (A - X))
	return s / (4.0 * A + 4.0 * B)


func _skin_mesh(A: Dictionary, trunk: Dictionary) -> ArrayMesh:
	var pos: PackedVector3Array = A.pos
	var normals := PackedVector3Array()
	normals.resize(pos.size())
	for ix: PackedInt32Array in A.by_mat.values():
		for i in range(0, ix.size(), 3):
			var n := (pos[ix[i + 1]] - pos[ix[i]]).cross(pos[ix[i + 2]] - pos[ix[i]])
			for k in 3:
				normals[ix[i + k]] += n
	for i in range(0, pos.size(), SEG + 1):  # the u seam down each tube: both copies the same normal, so no crease there
		var n := normals[i] + normals[i + SEG]
		normals[i] = n
		normals[i + SEG] = n
	for i in normals.size():
		normals[i] = normals[i].normalized()
	var mesh := ArrayMesh.new()
	for mat: Material in A.by_mat:
		var ix: PackedInt32Array = A.by_mat[mat]
		for i in range(0, ix.size(), 3):  # (Godot's front faces wind the other way)
			var t := ix[i + 1]
			ix[i + 1] = ix[i + 2]
			ix[i + 2] = t
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = A.uv
		arrays[Mesh.ARRAY_BONES] = A.bones
		arrays[Mesh.ARRAY_WEIGHTS] = A.weights
		arrays[Mesh.ARRAY_INDEX] = ix
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	for mat: Material in trunk:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = trunk[mat].pos
		arrays[Mesh.ARRAY_NORMAL] = trunk[mat].normal
		arrays[Mesh.ARRAY_TEX_UV] = trunk[mat].uv
		arrays[Mesh.ARRAY_BONES] = trunk[mat].bones
		arrays[Mesh.ARRAY_WEIGHTS] = trunk[mat].weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh
