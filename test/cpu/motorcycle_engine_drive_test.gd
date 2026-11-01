extends SceneTree

# PhysXMotorcycle3D.drivetrain = DRIVETRAIN_ENGINE (uno1982/godot#4): the car's
# engine drive on the bike, with a sport bike's defaults (110 N m to 12000 RPM,
# six gears, about 115 km/h in first). The vehicle demo's bike, at full throttle
# on a flat floor, held upright by motorcycle2_test.gd's roll controller:
#   the defaults are the bike's, not the car's
#   automatic: shifts up through the gears and keeps accelerating, upright
#   manual, 1st gear: stays in 1st, held at the 12000 RPM limit near 115 km/h
#   direct drive next to them: unchanged (no engine, gear 1)
# Then a teleport brings the manual bike's engine back to idle.
#   godot --headless --path . --script res://test/cpu/motorcycle_engine_drive_test.gd

const RUN := 12 * 60 # ticks of full throttle
const LEAN_ANGLE_GAIN := 25.0
const LEAN_BLEND := 0.6
const MAX_LEAN_ANGLE := 0.35

var _bikes := {}
var _t := 0
var _ok := true
var _max_gear := {}
var _max_roll := {}


func _check(cond: bool, msg: String) -> void:
	print("[bike engine drive] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _wheel(front: bool) -> PhysXVehicleWheel3D:
	var w := PhysXVehicleWheel3D.new()
	w.use_as_steering = front
	w.use_as_traction = not front
	w.transform = Transform3D(Basis(Vector3.RIGHT, -0.349) if front else Basis(), Vector3(0, 0.05, 0.7 if front else -0.7))
	w.radius = 0.3
	w.half_width = 0.08
	w.wheel_mass = 8.0
	w.wheel_moment_of_inertia = 0.4
	w.damping_rate = 0.15
	w.suspension_travel = 0.23
	w.suspension_stiffness = 9800.0
	w.suspension_damping = 2200.0
	w.tire_lateral_stiffness = 12000.0
	w.tire_longitudinal_stiffness = 12000.0
	w.tire_camber_stiffness = 500.0
	return w


func _bike(x: float, setup: Callable) -> PhysXMotorcycle3D:
	var b := PhysXMotorcycle3D.new()
	b.position = Vector3(x, 0.25, 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.36, 0.5, 0.9)
	cs.shape = box
	cs.position = Vector3(0, 0.437, 0)
	b.add_child(cs)
	b.add_child(_wheel(true))
	b.add_child(_wheel(false))
	b.drivetrain = PhysXMotorcycle3D.DRIVETRAIN_ENGINE
	setup.call(b)
	get_root().add_child(b)
	return b


func _initialize() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 4000)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	f.add_child(cs)
	get_root().add_child(f)
	var fresh := PhysXMotorcycle3D.new()
	_check(fresh.engine_peak_torque == 110.0 and fresh.engine_max_rpm == 12000.0 and fresh.gear_ratios.size() == 6,
			"sport bike defaults: %.0f N m to %.0f RPM, %d gears" % [fresh.engine_peak_torque, fresh.engine_max_rpm, fresh.gear_ratios.size()])
	fresh.free()
	_bikes["automatic"] = _bike(-10, func(b): pass)
	_bikes["manual 1st"] = _bike(0, func(b): b.automatic_transmission = false; b.gear = 1)
	_bikes["direct"] = _bike(10, func(b): b.drivetrain = PhysXMotorcycle3D.DRIVETRAIN_DIRECT)
	for k in _bikes:
		_max_gear[k] = -2
		_max_roll[k] = 0.0
	physics_frame.connect(_step)


# motorcycle2_test.gd's roll controller.
func _hold_upright(b: PhysXMotorcycle3D) -> void:
	var roll := b.get_roll_angle()
	var angular_velocity := b.get_angular_velocity()
	var raw_forward := -b.get_forward()
	var flat_forward := Vector3(raw_forward.x, 0.0, raw_forward.z)
	if flat_forward.length() < 0.001:
		return
	flat_forward = flat_forward.normalized()
	var roll_rate := -angular_velocity.dot(flat_forward)
	var target_lean := clampf(atan2(b.get_forward_speed() * angular_velocity.y, 9.81), -MAX_LEAN_ANGLE, MAX_LEAN_ANGLE)
	var new_roll_rate := lerpf(roll_rate, LEAN_ANGLE_GAIN * (target_lean - roll), LEAN_BLEND)
	b.set_angular_velocity(angular_velocity + flat_forward * (roll_rate - new_roll_rate))


func _step() -> void:
	_t += 1
	for k in _bikes:
		_hold_upright(_bikes[k])
	if _t < 30:
		return
	if _t < 30 + RUN:
		for k in _bikes:
			var b: PhysXMotorcycle3D = _bikes[k]
			b.throttle = 1.0
			_max_gear[k] = maxi(_max_gear[k], b.get_current_gear())
			_max_roll[k] = maxf(_max_roll[k], absf(b.get_roll_angle()))
		return
	if _t == 30 + RUN:
		var a: PhysXMotorcycle3D = _bikes["automatic"]
		_check(_max_gear["automatic"] >= 4 and a.get_forward_speed() > 40.0, "automatic: up to gear %d, %.0f km/h, %.0f RPM" % [_max_gear["automatic"], a.get_forward_speed() * 3.6, a.get_engine_rpm()])
		_check(a.get_engine_rpm() <= 12000.5, "automatic: engine within its 12000 RPM")
		var m: PhysXMotorcycle3D = _bikes["manual 1st"]
		_check(_max_gear["manual 1st"] == 1 and m.get_engine_rpm() > 11900.0 and m.get_forward_speed() * 3.6 > 105.0 and m.get_forward_speed() * 3.6 < 125.0,
				"manual 1st: gear %d (max %d), held at %.0f RPM, %.0f km/h" % [m.get_current_gear(), _max_gear["manual 1st"], m.get_engine_rpm(), m.get_forward_speed() * 3.6])
		var d: PhysXMotorcycle3D = _bikes["direct"]
		_check(d.get_engine_rpm() == 0.0 and d.get_current_gear() == 1 and d.get_forward_speed() > 20.0, "direct drive: %.0f km/h, no engine, gear %d" % [d.get_forward_speed() * 3.6, d.get_current_gear()])
		var worst := 0.0
		for k in _bikes:
			worst = maxf(worst, _max_roll[k])
		_check(worst < 0.5, "all upright (largest roll %.2f rad)" % worst)
		m.throttle = 0.0
		m.teleport(Transform3D(Basis(), Vector3(0, 0.25, -200)))
		return
	var m: PhysXMotorcycle3D = _bikes["manual 1st"]
	_check(m.get_engine_rpm() < 1.0, "teleported to a standstill: the engine is back to idle (%.0f RPM)" % m.get_engine_rpm())
	print("[bike engine drive] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
