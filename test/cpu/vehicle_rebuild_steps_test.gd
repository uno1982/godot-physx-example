extends SceneTree

# A vehicle rebuilt while playing (a property edited in the Inspector) must drive
# like a fresh one. Each rebuild used to add the vehicle's components to the old
# sequence again, so they all ran once more per step for every rebuild: a car
# rebuilt twice reached three times the speed under the same throttle. For the
# car, the motorcycle and the tank: one fresh, one rebuilt twice (same settings),
# then 2 s of the same throttle -- the speeds must match.
#   godot --headless --path . --script res://test/cpu/vehicle_rebuild_steps_test.gd

var _pairs := [] # [label, fresh, rebuilt]
var _t := 0
var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[rebuild steps] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box(size: Vector3, y: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = Vector3(0, y, 0)
	return cs


func _car(x: float) -> Node3D:
	var car := PhysXVehicle3D.new()
	car.position = Vector3(x, 0.6, 0)
	car.add_child(_box(Vector3(1.9, 0.8, 3.7), 0.4))
	for p in [Vector3(-0.75, 0.05, 1.35), Vector3(0.75, 0.05, 1.35), Vector3(-0.75, 0.05, -1.35), Vector3(0.75, 0.05, -1.35)]:
		var w := PhysXVehicleWheel3D.new()
		w.position = p
		w.use_as_steering = p.z > 0.0
		car.add_child(w)
	return car


func _moto(x: float) -> Node3D:
	var moto := PhysXMotorcycle3D.new()
	moto.position = Vector3(x, 0.6, 0)
	moto.add_child(_box(Vector3(0.4, 0.6, 1.8), 0.5))
	for z in [0.75, -0.75]:
		var w := PhysXVehicleWheel3D.new()
		w.position = Vector3(0, 0.05, z)
		w.use_as_steering = z > 0.0
		moto.add_child(w)
	return moto


func _tank(x: float) -> Node3D:
	var tank := PhysXTank3D.new()
	tank.position = Vector3(x, 0.6, 0)
	tank.add_child(_box(Vector3(2.4, 1.2, 6.0), 0.9))
	for wx in [-1.2, 1.2]:
		for z in [-1.5, -0.5, 0.5, 1.5]:
			var w := PhysXVehicleWheel3D.new()
			w.position = Vector3(wx, 0.1, z)
			w.suspension_stiffness = 60000.0
			w.suspension_damping = 5000.0
			tank.add_child(w)
	return tank


func _initialize() -> void:
	var f := StaticBody3D.new()
	f.add_child(_box(Vector3(1000, 1, 1000), -0.5))
	get_root().add_child(f)
	var x := -60.0
	for kind in ["car", "motorcycle", "tank"]:
		var pair := [kind]
		for i in 2:
			var v: Node3D = _car(x) if kind == "car" else (_moto(x) if kind == "motorcycle" else _tank(x))
			get_root().add_child(v)
			pair.append(v)
			x += 20.0
		_pairs.append(pair)
	physics_frame.connect(_step)


func _step() -> void:
	_t += 1
	if _t == 5:
		for pair in _pairs:
			pair[2].mass = pair[2].mass # a live rebuild, settings unchanged
			pair[2].mass = pair[2].mass
	if _t < 60:
		return
	for pair in _pairs:
		for i in [1, 2]:
			var v: Node3D = pair[i]
			if pair[0] == "tank":
				v.left_ratio = 1.0
				v.right_ratio = 1.0
			else:
				v.throttle = 1.0 if pair[0] == "car" else 0.4
			if pair[0] == "motorcycle":
				v.apply_torque_impulse(v.get_forward() * v.get_roll_angle() * 40.0) # keep it upright
	if _t == 60 + 120:
		for pair in _pairs:
			var fresh: float = pair[1].get_forward_speed()
			var rebuilt: float = pair[2].get_forward_speed()
			_check(fresh > 1.0 and absf(rebuilt - fresh) < fresh * 0.05, "%s: fresh %.2f m/s, rebuilt twice %.2f m/s" % [pair[0], fresh, rebuilt])
		print("[rebuild steps] %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
