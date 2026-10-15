extends SceneTree
## traffic.gd's manners, checked: godot --headless --path . --script tools/traffic_check.gd

const Traffic := preload("res://traffic.gd")


func _sim(a: Vector2, a_to: Vector2, b: Vector2, b_to: Vector2, kb := "customer") -> float:  # two walking at each other -> how close they ever got
	var closest := 99.0
	for i in 400:
		var va := Traffic.walk(1, a, (a_to - a).normalized(), 1.3, "customer", 1.0 / 60.0)
		var vb := Traffic.walk(2, b, (b_to - b).normalized(), 1.3, kb, 1.0 / 60.0)
		a += va / 60.0
		b += vb / 60.0
		closest = minf(closest, a.distance_to(b))
	Traffic.gone(1)
	Traffic.gone(2)
	return closest


func _initialize() -> void:
	# head-on: they slide past each other (not through: shoulders 0.5 apart)
	var near := _sim(Vector2(0, 0), Vector2(0, 8), Vector2(0, 6), Vector2(0, -2))
	assert(near > 0.45, "head-on: they walked through each other (%.2f)" % near)
	# crossing paths
	near = _sim(Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3))
	assert(near > 0.45, "crossing: they walked through each other (%.2f)" % near)
	# somebody stood still: walked round
	Traffic.person(3, Vector2(0, 3), Vector2.ZERO, "customer")
	var p := Vector2(0, 0)
	var closest := 99.0
	for i in 300:
		p += Traffic.walk(1, p, (Vector2(0, 6) - p).normalized(), 1.3, "customer", 1.0 / 60.0) / 60.0
		closest = minf(closest, p.distance_to(Vector2(0, 3)))
	assert(closest > 0.45, "walked through somebody stood still (%.2f)" % closest)
	Traffic.gone(1)
	Traffic.gone(3)
	# boxed in (a narrow aisle, somebody stood in it): no dithering side to side, and they do get by
	Traffic.person(3, Vector2(0.15, 3), Vector2.ZERO, "customer")
	var aisle := func(x: float, _z: float) -> bool: return absf(x) < 0.45
	p = Vector2(0, 0)
	var flips := 0
	var was := 0.0
	for i in 900:
		if p.distance_to(Vector2(0, 6)) < 0.05:
			break  # (there)
		var v := Traffic.walk(1, p, (Vector2(0, 6) - p).normalized(), 1.3, "staff", 1.0 / 60.0, aisle)
		if absf(v.x) > 0.15:  # (a swing you'd see: ~6 degrees)
			if was != 0.0 and signf(v.x) != was:
				flips += 1
			was = signf(v.x)
		p += v / 60.0
	assert(flips <= 2, "dithered side to side in a narrow aisle (%d flips)" % flips)
	assert(p.y > 5.0, "never got by in a narrow aisle (at %s)" % p)
	Traffic.gone(1)
	Traffic.gone(3)
	# a car coming: nobody steps out in front of it
	Traffic.car(10, Vector2(-10, -3.3), 0.0, Vector2(4.1, 1.75), 5.0)  # along the lane, nose +x
	var v := Traffic.walk(1, Vector2(0, -0.9), Vector2(0, -1), 1.3, "customer", 1.0 / 60.0)
	assert(v.length() < 0.01, "stepped out in front of a moving car")
	# ...and the car stops for somebody in its road
	Traffic.person(4, Vector2(-5, -3.3), Vector2.ZERO, "customer")
	assert(Traffic.blocked(10, false, 5.0), "the car didn't see somebody in its road")
	Traffic.gone(4)
	assert(not Traffic.blocked(10, false, 5.0), "the car stopped for nobody")
	# a car backing out claims its space: the car coming stops short of it
	Traffic.claim(11, Vector2(-2, -6), Vector2.RIGHT, Vector2(3.0, 3.0))
	assert(Traffic.blocked(10, false, 5.0), "drove into a backing car's space")
	Traffic.claim(11)
	print("traffic: ok")
	quit()
