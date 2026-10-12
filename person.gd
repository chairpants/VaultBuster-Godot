extends Node3D
## One of the TV-head people: a body from the cast (people/people.glb: the web game's own, built by its customers.js
## and exported joint by joint), posed here every frame the way customers.js poses it.
## From the web game's customers.js: the object build() returns (setMood, setPose, lookAt, holdTape, sigh, talk) and
## its tick: the walk cycle (the planted foot stays put on the floor; the hips ride over it; a run over ~2 m/s),
## the gaits, sitting and crouching, the arms' poses, the head, breathing.
## Not over yet: reaching for things (the arm IK), props (card, cash, umbrella), what the weather does to them
## (hunching, snow on them, gusts), slipping and shaking off, blinking. And the body is the web game's older jointed
## blocks, not its one stretched skin.
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

var mood := "off"
var pose := "idle"  # walk idle reach hold wait sit crouch lean read watch
var gait := "plain"
var walk_lean := true  # tip forward into the stride
var height := 1.0
var talking := false
var sit_at := {}  # { hipY, tuck }

var _body: Node3D
var _upper: Node3D
var _head: Node3D
var _torso: Node3D
var _legs: Array = []  # [hip, knee]
var _arms: Array = []  # [shoulder, elbow]
var _tapes: Array[Node3D] = []
var _face := StandardMaterial3D.new()
var _moods: Array = []
var _look = null  # the head's yaw someone asked for (relative to the body), or null
var _t := 0.0
var _phase := 0.0
var _since := 0.0
var _sigh := 0.0
var _st := { "y": 0.0, "squat": 0.0, "nod": 0.0, "ry": 0.0, "rz": 0.0, "rx": 0.0, "ax0": 0.0, "ae0": -0.12, "ax1": 0.0, "ae1": -0.12, "h0": 0.0, "h1": 0.0, "k0": 0.0, "k1": 0.0 }


func setup(who: Dictionary, face: Texture2D, moods: Array, index: int) -> void:
	var pre := "p%d_" % index  # (each of the cast's joints is named for whose it is)
	height = who.height
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
	_face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # the face: one of sixteen on their sheet, picked by the mood
	_face.albedo_texture = face
	_face.uv1_scale = Vector3(0.25, -0.25, 1)
	var screen: MeshInstance3D = find_child(pre + "screen", true, false)
	if screen:
		screen.material_override = _face
	set_mood("neutral")


func set_mood(m: String) -> void:
	if m == mood:
		return
	mood = m
	_since = _t
	var i := maxi(0, _moods.find(m))
	_face.uv1_offset = Vector3((i % 4) * 0.25, (i / 4 + 1) * 0.25, 0)


func set_pose(p: String, opts := {}) -> void:
	pose = p
	sit_at = opts


func look_at_yaw(yaw) -> void:  # turn the head (radians, + = their left); null = back to normal
	_look = null if yaw == null else clampf(yaw, -1.45, 1.45)


func hold_tape(n: int) -> void:
	for i in _tapes.size():
		_tapes[i].visible = i < n


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
	var stride: float = (0.34 + 0.12 * clampf(speed - 1.0, 0.0, 1.0)) * (G.stride * (1.0 - run) + run) + 0.36 * run  # radians of hip swing
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
	var squat := _ease("squat", 1.0 if pose == "crouch" else 0.0, minf(1.0, dt * 10.0))  # a deep knees-bent crouch
	# the gait cycle, per leg (p: 0..1 from its heel strike): a stance of ~60% (less running), then the swing
	var cyc := _phase / TAU - 0.25
	var knee_k: float = (G.knee * (1.0 - run) + 1.6 * run) * minf(1.0, 0.55 + 0.35 * speed)
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
		_legs[i][0].rotation.x = _ease("h%d" % i, hx, lr) - squat * 1.6
		_legs[i][1].rotation.x = _ease("k%d" % i, kx, lr) + squat * 2.4
	var seat_y: float = sit_at.get("hipY", 0.5) - 0.9 * height if sit else 0.0  # hips down to the seat
	var jolt := sin((t - _since) / 0.35 * PI) * 0.06 if mood == "shock" and t - _since < 0.35 else 0.0  # a little jump
	var bob := 0.0
	if walking:
		bob = leg_bob + run * 0.03 * absf(sin(_phase)) + (pow(maxf(0.0, sin(_phase)), 2.0) * 0.06 if G.get("hop", false) and run == 0.0 else 0.0)
	var body_y := seat_y + jolt + bob
	_st.y += (body_y - _st.y) * (r if absf(body_y - _st.y) > 0.05 else 1.0)  # eased sitting down / getting up, the bob tracked directly
	_body.position.y = _st.y - squat * 0.6
	var sg := 0.0  # a sigh: up, then a long sag
	if _sigh > 0.0:
		_sigh -= dt
		sg = sin((1.0 - _sigh / 1.3) * PI)
	_upper.rotation.x = (0.28 if pose == "lean" else 0.0) + maxf(0.0, sg) * 0.08 + (G.lean if walking else 0.0)
	if _torso:  # breathing
		_torso.scale.y = 0.56 * (1.0 + sin(t * 1.7) * 0.012)
		_torso.scale.z = 0.245 * (1.0 + sin(t * 1.7) * 0.02)
	var pelvis := _ease("ry", (gl[0][0] - gl[1][0]) / (2.0 * A) * 0.08 * G.twist * (1.0 - 0.6 * run) if walking else 0.0, soft)  # the pelvis turns with the leg going forward
	_body.rotation.y = pelvis
	_upper.rotation.y = -pelvis * 1.7  # the shoulders counter it, with the arms
	_body.rotation.z = _ease("rz", (0.0 if walking or sit else sin(t * 0.45) * 0.018) + (G.sway * (1.0 - run) * sin(_phase) if walking else 0.0), r * 0.3)  # idle weight shift, hip to hip; a hip sway
	_body.rotation.x = _ease("rx", minf(0.08, speed * 0.05) + 0.17 * run if walking and walk_lean else 0.0, r * 0.5)  # lean into the walk (and the run)
	var a_sw: float = 0.3 * (G.arms * (1.0 - run) + 2.3 * run)
	var lx := sw_u * a_sw if walking else 0.0  # arms: smaller than the legs, trailing them
	var rx := -sw_u * a_sw if walking else 0.0
	var le := -0.22 - maxf(0.0, -sw_u) * 0.22 if walking else -0.12  # elbows bend on the forward swing
	var re := -0.22 - maxf(0.0, sw_u) * 0.22 if walking else -0.12
	if run > 0.0:  # running: elbows at right angles, pumping
		le += (-1.45 - maxf(0.0, -sw_u) * 0.25 - le) * run
		re += (-1.45 - maxf(0.0, sw_u) * 0.25 - re) * run
	var holding := _tapes.size() > 0 and _tapes[0].visible
	var free := not pose in ["hold", "reach", "wait", "lean", "read", "watch", "sit"] and not holding
	if free and walking and G.get("behind", false) and run == 0.0:  # a stroll: hands clasped behind
		lx = 0.42
		rx = 0.42
		le = -0.55
		re = -0.55
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
	var ar := soft if walking else r  # arms carry some momentum while walking; poses still settle promptly
	var p2 := [[_ease("ax0", lx, ar), _ease("ae0", le, ar)], [_ease("ax1", rx, ar), _ease("ae1", re, ar)]]
	for i in 2:
		_arms[i][0].rotation = Vector3(p2[i][0], 0.0, -0.06 if i else 0.06)
		_arms[i][1].rotation.x = p2[i][1]
	# head: browsing scans, impatience tilts, otherwise a slow idle drift
	var yaw: float = _look if _look != null else sin(t * 1.3) * 0.25 if mood == "browse" else sin(t * 2.3) * 0.55 if mood == "shifty" else sin(t * 0.4) * 0.05  # shifty: checking over both shoulders
	_head.rotation.y += (yaw + (sin(t * 0.9) * 0.06 if talking else 0.0) - _head.rotation.y) * r * 0.6
	_head.rotation.z += ((0.12 if mood == "impatient" else sin(t * 1.3) * 0.05 if talking else 0.0) - _head.rotation.z) * r * 0.5
	_head.rotation.x = _ease("nod", cos(_phase * 2.0 - 0.8) * 0.008 if walking else -0.06 if mood == "watch" else maxf(0.0, sin(t * 2.4)) * 0.05 if talking else 0.0, soft) \
		+ (0.3 if pose == "read" else 0.35 if pose == "watch" else 0.0) + maxf(0.0, sg) * 0.2
	_head.position = to_local(_upper.to_global(Vector3(0.0, 0.73, HEAD_Z / height)))  # the head rides the top of the neck, wherever the waist has put it


func _leg_at(p: float, stance_f: float, reach_d: float, knee_k: float, th_end: float, A: float) -> Array:  # -> [thigh angle forward, knee bend, planted]
	if p < stance_f:  # planted: the foot slides back under the hip at a steady rate (so it's still on the floor), the thigh solved for it
		var k := p / stance_f
		var kn := (0.32 * exp(-pow((k - 0.2) / 0.13, 2.0)) + 0.55 * pow(maxf(0.0, (k - 0.65) / 0.35), 2.0)) * knee_k  # the knee giving to take the weight, then heel off into toe off
		return [asin(clampf(reach_d * (1.0 - 2.0 * k) / (LEG * cos(kn / 2.0)), -1.0, 1.0)) + kn / 2.0, kn, 1.0]
	var k := (p - stance_f) / (1.0 - stance_f)  # the swing: fold just enough to clear the floor, swing through, straighten
	return [th_end + (A - th_end) * (1.0 - cos(PI * minf(1.0, k / 0.8))) / 2.0, (0.55 + 0.07 * k / 0.2 if k < 0.2 else 0.62 * cos(PI / 2.0 * minf(1.0, (k - 0.2) / 0.6))) * knee_k, 0.0]
