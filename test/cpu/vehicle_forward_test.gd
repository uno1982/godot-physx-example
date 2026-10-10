extends SceneTree

# U25: the PhysX vehicles' forward is +Z, the same as VehicleBody3D (its doc:
# "The local forward for this node is Vector3.MODEL_FRONT" = (0, 0, 1)), and a
# left turn bends the path toward +X (as VehicleBody3D's +steering does).
# Pins what must hold for all three vehicle nodes:
#   car:   throttle drives +Z; get_forward_speed() > 0 going
#          forward; +steer turns left (+X) with the inner (+X) front wheel sharper
#   moto:  throttle drives +Z; get_forward() ~ +Z; get_forward_speed() > 0
#   tank:  both tracks forward drive +Z; get_forward() ~ +Z; get_forward_speed() > 0;
#          left_ratio alone turns it RIGHT (the left track is on the driver's left)

var _car: PhysXVehicle3D
var _moto: PhysXMotorcycle3D
var _tank: PhysXTank3D
var _tank_turn: PhysXTank3D
var _car_fx: PhysXVehicleWheel3D
var _car_fnx: PhysXVehicleWheel3D
var _start := {}
var _t := 0
var _ok := true

func _check(cond: bool, msg: String) -> void:
	print("[forward] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond

func _floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(600, 1, 600)
	cs.shape = b
	f.add_child(cs)
	f.position = Vector3(0, -0.5, 0)
	get_root().add_child(f)

func _box(size: Vector3, y: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = Vector3(0, y, 0)
	return cs

func _make_tank(x: float) -> PhysXTank3D:
	var tank := PhysXTank3D.new()
	tank.position = Vector3(x, 0.6, 0)
	tank.add_child(_box(Vector3(2.4, 1.2, 6.0), 0.9))
	for wx in [-1.2, 1.2]:
		for z in [-1.5, -0.5, 0.5, 1.5]:
			var w := PhysXVehicleWheel3D.new()
			w.position = Vector3(wx, 0.1, z)
			w.radius = 0.35
			w.half_width = 0.12
			w.wheel_mass = 15.0
			w.wheel_moment_of_inertia = 1.2
			w.damping_rate = 0.15
			w.suspension_travel = 0.15
			w.suspension_stiffness = 60000.0
			w.suspension_damping = 5000.0
			w.tire_lateral_stiffness = 30000.0
			w.tire_longitudinal_stiffness = 40000.0
			w.tire_friction = 1.4
			tank.add_child(w)
	get_root().add_child(tank)
	return tank

func _initialize() -> void:
	_floor()
	_car = PhysXVehicle3D.new()
	_car.position = Vector3(-60, 0.6, 0)
	_car.add_child(_box(Vector3(1.9, 0.8, 3.7), 0.4))
	for p in [Vector3(-0.75, 0.05, 1.35), Vector3(0.75, 0.05, 1.35), Vector3(-0.75, 0.05, -1.35), Vector3(0.75, 0.05, -1.35)]:
		var w := PhysXVehicleWheel3D.new()
		w.position = p
		w.use_as_steering = p.z > 0.0
		_car.add_child(w)
		if p.z > 0.0:
			if p.x > 0.0:
				_car_fx = w
			else:
				_car_fnx = w
	get_root().add_child(_car)

	_moto = PhysXMotorcycle3D.new()
	_moto.position = Vector3(-20, 0.6, 0)
	_moto.add_child(_box(Vector3(0.4, 0.6, 1.8), 0.5))
	for z in [0.75, -0.75]:
		var w := PhysXVehicleWheel3D.new()
		w.position = Vector3(0, 0.05, z)
		w.use_as_steering = z > 0.0
		_moto.add_child(w)
	get_root().add_child(_moto)

	_tank = _make_tank(20)
	_tank_turn = _make_tank(60)
	for n in [_car, _moto, _tank, _tank_turn]:
		_start[n] = n.position
	physics_frame.connect(_tick)

# Steer angle from the axle line in the car's XZ plane (spin and a mirrored
# wheel don't change the line), folded into (-90, 90].
func _steer_deg(w: PhysXVehicleWheel3D) -> float:
	var axle := w.transform.basis.x
	var a := rad_to_deg(atan2(-axle.z, axle.x))
	while a > 90.0:
		a -= 180.0
	while a <= -90.0:
		a += 180.0
	return a

func _tick() -> void:
	_t += 1
	_car.throttle = 0.6
	_car.steer = 0.0 if _t <= 120 else 0.5
	_moto.throttle = 0.4
	_moto.apply_torque_impulse(_moto.get_forward() * _moto.get_roll_angle() * 40.0) # keep it upright
	_tank.left_ratio = 1.0
	_tank.right_ratio = 1.0
	_tank_turn.left_ratio = 1.0
	_tank_turn.right_ratio = 0.0
	if _t == 120:
		var d: Vector3 = _car.global_position - _start[_car]
		_check(d.z > 5.0 and abs(d.x) < 1.0, "car: throttle drives +Z (moved %s)" % d)
		_check(_car.get_forward_speed() > 1.0, "car: get_forward_speed() > 0 going forward (%.2f)" % _car.get_forward_speed())
		_start[_car] = _car.global_position
		var dm: Vector3 = _moto.global_position - _start[_moto]
		_check(dm.z > 1.5, "moto: throttle drives +Z (moved %s)" % dm)
		_check(_moto.get_forward_speed() > 0.5, "moto: get_forward_speed() > 0 going forward (%.2f)" % _moto.get_forward_speed())
		_check(_moto.get_forward().z > 0.9, "moto: get_forward() ~ +Z (%s)" % _moto.get_forward())
		var dt: Vector3 = _tank.global_position - _start[_tank]
		_check(dt.z > 3.0, "tank: both tracks forward drive +Z (moved %s)" % dt)
		_check(_tank.get_forward_speed() > 0.5, "tank: get_forward_speed() > 0 going forward (%.2f)" % _tank.get_forward_speed())
		_check(_tank.get_forward().z > 0.9, "tank: get_forward() ~ +Z (%s)" % _tank.get_forward())
	if _t == 150:
		var inner := _steer_deg(_car_fx)
		var outer := _steer_deg(_car_fnx)
		_check(inner > 0.0 and outer > 0.0 and inner > outer, "car: +steer = left turn, inner (+X) wheel sharper (inner %.1f, outer %.1f deg)" % [inner, outer])
	if _t == 240:
		var dc: Vector3 = _car.global_position - _start[_car]
		_check(dc.x > 1.0, "car: +steer bends the path toward +X, a left turn (moved %s)" % dc)
		var dtt: Vector3 = _tank_turn.global_position - _start[_tank_turn]
		_check(dtt.x < -1.0, "tank: left track alone turns it RIGHT, toward -X (moved %s)" % dtt)
		print("[forward] %s" % ("PASS -- vehicles drive +Z, report it, steer left on +steer, tracks are on the named sides" if _ok else "FAIL"))
		quit(0 if _ok else 1)
