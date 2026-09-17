extends SceneTree

# Sanity check: does stock VehicleBody3D/VehicleWheel3D (backend-agnostic --
# raycasts + apply_impulse only) actually drive on top of the PhysX
# PhysicsServer3D backend, with zero vehicle-specific engine code?

var _car: VehicleBody3D
var _t := 0
var _start_pos: Vector3

func _initialize() -> void:
	print("[vehicle] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var floor_cs := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(200, 1, 200)
	floor_cs.shape = floor_shape
	floor_body.add_child(floor_cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	_car = VehicleBody3D.new()
	# Default mass (40) -- default suspension (stiffness=5.88, max_force=6000)
	# is tuned for this, matching Bullet's/Godot's own well-tested demo scale.
	# A heavier mass needs proportionally stiffer suspension too, or it bottoms
	# out completely and the chassis itself ends up resting on the ground.
	_car.position = Vector3(0, 0.6, 0)
	root.add_child(_car)

	var chassis_cs := CollisionShape3D.new()
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = Vector3(1.8, 0.6, 4.0)
	chassis_cs.shape = chassis_shape
	_car.add_child(chassis_cs)

	var wheel_positions := {
		"fl": Vector3(-0.9, -0.2, 1.4),
		"fr": Vector3(0.9, -0.2, 1.4),
		"bl": Vector3(-0.9, -0.2, -1.4),
		"br": Vector3(0.9, -0.2, -1.4),
	}
	for key in wheel_positions:
		var w := VehicleWheel3D.new()
		w.position = wheel_positions[key]
		w.wheel_radius = 0.4
		w.use_as_traction = true
		w.use_as_steering = key.begins_with("f")
		_car.add_child(w)

	_start_pos = _car.global_position
	print("[vehicle] ready, start_pos=", _start_pos)

func _physics_process(_delta: float) -> bool:
	_t += 1
	_car.engine_force = 800.0

	if _t == 100:
		print("[vehicle] mass=%.1f applying direct central impulse (0,0,1000)" % _car.mass)
		_car.apply_central_impulse(Vector3(0, 0, 1000))
	if _t == 101:
		print("[vehicle] one tick after direct impulse: lin_vel=%s (expected ~0.83 m/s on z)" % [_car.linear_velocity])

	if _t % 30 == 0:
		var pos := _car.global_position
		var dist := pos.distance_to(_start_pos)
		print("[vehicle] t+%d pos=%s dist_travelled=%.2f sleeping=%s lin_vel=%s" % [_t, pos, dist, _car.sleeping, _car.linear_velocity])
		for c in _car.get_children():
			if c is VehicleWheel3D:
				print("  wheel in_contact=%s engine_force=%.2f skid=%.4f rpm=%.2f" % [c.is_in_contact(), c.engine_force, c.get_skidinfo(), c.get_rpm()])

	if _t >= 300:
		var final_pos := _car.global_position
		var dist := final_pos.distance_to(_start_pos)
		print("[vehicle] done. final_pos=%s total_dist=%.2f" % [final_pos, dist])
		if dist > 3.0:
			print("[vehicle] PASS -- car drove forward under engine force")
		else:
			print("[vehicle] FAIL -- car did not move meaningfully (dist=%.2f)" % dist)
		quit(0)
	return false
