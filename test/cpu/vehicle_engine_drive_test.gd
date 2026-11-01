extends SceneTree

# PhysXVehicle3D.drivetrain = DRIVETRAIN_ENGINE (uno1982/godot#4): PhysX's engine
# drive -- engine, clutch, gearbox, autobox, differential. Cars side by side at
# full throttle on a flat floor, with the default engine (500 N m, 6000 RPM,
# gears 4 / 2 / 1.5 / 1.1 / 1.0, final drive 4):
#   automatic: shifts up through the gears and keeps accelerating
#   manual, 1st gear: stays in 1st, held at the 6000 RPM limit
#   clutch pressed / neutral: the engine revs, the car stays put
#   reverse: drives backwards in the reverse gear
#   limited slip, rear-wheel drive: drives
#   split grip (rear-wheel drive in 1st, the left rear tyre on almost no grip):
#     the open differential spins that wheel and crawls, limited slip pulls away
#     (measured after 3 s; then both lift off -- the uneven drive yaws the car)
#   no clutch assist, manual: asked for 2nd without the clutch it stays in
#     1st; with the clutch pressed it shifts, and stays there once released
#   direct drive next to them: unchanged (no engine, gear 1)
#   bad gear ratios (ascending): an error, and the car never builds
# Then: a teleport brings the engine back to idle, the automatic car switched to
# DRIVETRAIN_DIRECT while playing drives on with no engine, and an engine car
# left alone at rest goes to sleep.
#   godot --headless --path . --script res://test/cpu/vehicle_engine_drive_test.gd

const RUN := 12 * 60 # ticks of full throttle

var _cars := {}
var _t := 0
var _ok := true
var _max_gear := {}
var _speed_before_switch := 0.0
var _split := {}


func _check(cond: bool, msg: String) -> void:
	print("[engine drive] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box(size: Vector3, y: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = Vector3(0, y, 0)
	return cs


func _car(x: float, setup: Callable) -> PhysXVehicle3D:
	var car := PhysXVehicle3D.new()
	car.position = Vector3(x, 0.6, 0)
	car.add_child(_box(Vector3(1.9, 0.8, 3.7), 0.4))
	for p in [Vector3(-0.75, 0.05, 1.35), Vector3(0.75, 0.05, 1.35), Vector3(-0.75, 0.05, -1.35), Vector3(0.75, 0.05, -1.35)]:
		var w := PhysXVehicleWheel3D.new()
		w.position = p
		w.use_as_steering = p.z > 0.0
		car.add_child(w)
	car.drivetrain = PhysXVehicle3D.DRIVETRAIN_ENGINE
	setup.call(car)
	get_root().add_child(car)
	return car


func _initialize() -> void:
	var f := StaticBody3D.new()
	f.add_child(_box(Vector3(4000, 1, 4000), -0.5))
	get_root().add_child(f)
	_cars["automatic"] = _car(-60, func(c): pass)
	_cars["manual 1st"] = _car(-40, func(c): c.automatic_transmission = false; c.gear = 1)
	_cars["clutch pressed"] = _car(-20, func(c): c.clutch = 1.0)
	_cars["neutral"] = _car(0, func(c): c.automatic_transmission = false; c.gear = 0)
	_cars["reverse"] = _car(20, func(c): c.reverse = true)
	_cars["limited slip RWD"] = _car(40, func(c):
		c.differential = PhysXVehicle3D.DIFFERENTIAL_LIMITED_SLIP
		for w in c.get_children():
			if w is PhysXVehicleWheel3D and w.use_as_steering:
				w.use_as_traction = false)
	for diff in [PhysXVehicle3D.DIFFERENTIAL_OPEN, PhysXVehicle3D.DIFFERENTIAL_LIMITED_SLIP]:
		var key := "split open" if diff == PhysXVehicle3D.DIFFERENTIAL_OPEN else "split limited slip"
		_cars[key] = _car(120 + diff * 20, func(c):
			c.differential = diff
			c.automatic_transmission = false
			c.gear = 1
			for w in c.get_children():
				if w is PhysXVehicleWheel3D:
					w.use_as_traction = not w.use_as_steering
					if not w.use_as_steering and w.position.x < 0.0:
						w.tire_friction = 0.1)
	_cars["no clutch assist"] = _car(160, func(c): c.automatic_transmission = false; c.gear = 1; c.clutch_assist = false)
	_cars["direct"] = _car(60, func(c): c.drivetrain = PhysXVehicle3D.DRIVETRAIN_DIRECT)
	print("[engine drive] (an error about gear ratios is expected next)")
	_cars["bad ratios"] = _car(80, func(c): c.gear_ratios = PackedFloat32Array([1.0, 2.0]))
	_cars["at rest"] = _car(100, func(c): pass)
	for k in _cars:
		_max_gear[k] = -2
	physics_frame.connect(_step)


func _step() -> void:
	_t += 1
	if _t < 60:
		return
	if _t == 60 + 180:
		for k in ["split open", "split limited slip"]:
			_split[k] = _cars[k].get_forward_speed()
	var na: PhysXVehicle3D = _cars["no clutch assist"]
	if _t == 60 + 60:
		na.gear = 2 # no clutch
	if _t == 60 + 120:
		_check(na.get_current_gear() == 1 and na.get_target_gear() == 1, "no clutch assist: asked for 2nd without the clutch, still in gear %d (target %d)" % [na.get_current_gear(), na.get_target_gear()])
		na.clutch = 1.0
	if _t == 60 + 180:
		_check(na.get_target_gear() == 2, "no clutch assist: clutch pressed, shifting to gear %d" % na.get_target_gear())
		na.clutch = 0.0
	if _t < 60 + RUN:
		for k in _cars:
			if k != "at rest" and not (k.begins_with("split") and _t >= 60 + 180):
				_cars[k].throttle = 1.0
			elif k.begins_with("split"):
				_cars[k].throttle = 0.0
			_max_gear[k] = maxi(_max_gear[k], _cars[k].get_current_gear())
		return
	if _t == 60 + RUN:
		var a: PhysXVehicle3D = _cars["automatic"]
		_check(_max_gear["automatic"] >= 4 and a.get_forward_speed() > 30.0, "automatic: up to gear %d, %.1f m/s, %.0f RPM" % [_max_gear["automatic"], a.get_forward_speed(), a.get_engine_rpm()])
		_check(a.get_engine_rpm() <= 6000.5, "automatic: engine within its 6000 RPM")
		var m: PhysXVehicle3D = _cars["manual 1st"]
		_check(_max_gear["manual 1st"] == 1 and m.get_current_gear() == 1 and m.get_engine_rpm() > 5900.0 and m.get_forward_speed() > 10.0 and m.get_forward_speed() < 16.0,
				"manual 1st: gear %d (max %d), held at %.0f RPM, %.1f m/s" % [m.get_current_gear(), _max_gear["manual 1st"], m.get_engine_rpm(), m.get_forward_speed()])
		var cl: PhysXVehicle3D = _cars["clutch pressed"]
		_check(absf(cl.get_forward_speed()) < 0.2 and cl.get_engine_rpm() > 3000.0, "clutch pressed: %.2f m/s at %.0f RPM" % [cl.get_forward_speed(), cl.get_engine_rpm()])
		var n: PhysXVehicle3D = _cars["neutral"]
		_check(absf(n.get_forward_speed()) < 0.2 and n.get_current_gear() == 0 and n.get_engine_rpm() > 3000.0, "neutral: %.2f m/s, gear %d, %.0f RPM" % [n.get_forward_speed(), n.get_current_gear(), n.get_engine_rpm()])
		var r: PhysXVehicle3D = _cars["reverse"]
		_check(r.get_forward_speed() < -10.0 and r.get_current_gear() == -1, "reverse: %.1f m/s in gear %d" % [r.get_forward_speed(), r.get_current_gear()])
		var l: PhysXVehicle3D = _cars["limited slip RWD"]
		_check(l.get_forward_speed() > 25.0, "limited slip, rear-wheel drive: %.1f m/s, gear %d" % [l.get_forward_speed(), l.get_current_gear()])
		var so: float = _split["split open"]
		var sl: float = _split["split limited slip"]
		_check(sl > 2.0 and sl > so * 3.0, "split grip: limited slip %.2f m/s, open %.2f m/s" % [sl, so])
		_check(na.get_current_gear() == 2 and na.get_forward_speed() > 15.0, "no clutch assist: clutch released, drives on in gear %d at %.1f m/s" % [na.get_current_gear(), na.get_forward_speed()])
		var d: PhysXVehicle3D = _cars["direct"]
		_check(d.get_forward_speed() > 50.0 and d.get_engine_rpm() == 0.0 and d.get_current_gear() == 1, "direct drive: %.1f m/s, no engine, gear %d" % [d.get_forward_speed(), d.get_current_gear()])
		var b: PhysXVehicle3D = _cars["bad ratios"]
		_check(absf(b.get_forward_speed()) < 0.01 and b.get_engine_rpm() == 0.0, "ascending gear ratios: not built (%.2f m/s)" % b.get_forward_speed())
		var s: PhysXVehicle3D = _cars["at rest"]
		_check(s.is_sleeping(), "an engine car left at rest sleeps")

		# Teleport the manual car (engine at its limit) to a standstill, throttle off: the engine idles, no lurch.
		m.throttle = 0.0
		m.teleport(Transform3D(Basis(), Vector3(-40, 0.6, -200)))
		# The automatic car changes to direct drive while playing.
		_speed_before_switch = a.get_forward_speed()
		a.drivetrain = PhysXVehicle3D.DRIVETRAIN_DIRECT
		a.throttle = 1.0
		return
	if _t == 60 + RUN + 1:
		var m: PhysXVehicle3D = _cars["manual 1st"]
		_check(m.get_engine_rpm() < 1.0, "teleported to a standstill: the engine is back to idle (%.0f RPM)" % m.get_engine_rpm())
		return
	if _t < 60 + RUN + 120:
		_cars["automatic"].throttle = 1.0
		return
	var m: PhysXVehicle3D = _cars["manual 1st"]
	_check(absf(m.get_forward_speed()) < 0.5, "teleported, throttle off: stays put (%.2f m/s two seconds later)" % m.get_forward_speed())
	var a: PhysXVehicle3D = _cars["automatic"]
	_check(a.get_engine_rpm() == 0.0 and a.get_current_gear() == 1 and a.get_forward_speed() > 5.0,
			"switched to direct drive while playing: %.1f m/s, no engine" % a.get_forward_speed())
	print("[engine drive] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
