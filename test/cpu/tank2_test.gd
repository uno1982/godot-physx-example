extends SceneTree

# Phase 2 regression: the real PhysXTank3D node (not the headless probe --
# see tank_probe_test.gd for that) drives and skid-steer pivots via its own
# exported properties, inside a real scene tree. Mirrors motorcycle2_test.gd's
# structure for direct comparison against the other vehicle types.

var _tank: PhysXTank3D
var _t := 0
var _start_pos: Vector3
var _start_yaw: float

func _initialize() -> void:
	print("[tank2] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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

	_tank = PhysXTank3D.new()
	_start_pos = Vector3(0, 0.6, 0)
	_tank.position = _start_pos

	var chassis_cs := CollisionShape3D.new()
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = Vector3(2.4, 1.2, 6.0)
	chassis_cs.shape = chassis_shape
	chassis_cs.position = Vector3(0, 0.9, 0)
	_tank.add_child(chassis_cs)

	# 8 road wheels (4 per side), same layout as tank_probe_test.gd's own
	# probe-level test. Built BEFORE the tank enters the tree (unlike the
	# motorcycle/car tests' own pattern) to isolate whether PhysXTank3D
	# rebuilding once per wheel addition (2, 3, 4... 8 -- unlike the car/
	# motorcycle, whose exact wheel-count requirement means they only ever
	# build once) is itself the cause of a real bug found via direct
	# comparison against tank_probe_test.gd's clean result.
	const TRACK_HALF_WIDTH := 1.2
	const WHEEL_Y := 0.1
	for wx in [-TRACK_HALF_WIDTH, TRACK_HALF_WIDTH]:
		for z in [-1.5, -0.5, 0.5, 1.5]:
			var w := PhysXVehicleWheel3D.new()
			w.position = Vector3(wx, WHEEL_Y, z)
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
			_tank.add_child(w)

	root.add_child(_tank)

	await process_frame
	print("[tank2] ready, start_pos=", _start_pos)
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1

	var pos := _tank.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		print("[tank2] FAIL: position went NaN at t+%d" % _t)
		quit(1)
		return

	_tank.left_ratio = 1.0
	_tank.right_ratio = 1.0
	if _t > 150 and _t <= 250:
		# Pivot turn -- same phase 2 as tank_probe_test.gd.
		_tank.left_ratio = 1.0
		_tank.right_ratio = -1.0
	elif _t > 250:
		_tank.left_ratio = 1.0
		_tank.right_ratio = 1.0
	_tank.brake = 0.0

	if _t == 150:
		_start_yaw = _tank.get_forward().signed_angle_to(Vector3(0, 0, -1), Vector3.UP)

	if _t % 30 == 0:
		var dist := pos.distance_to(_start_pos)
		print("[tank2] t+%d pos=%s dist=%.2f fwd_speed=%.2f ang_vel_y=%.3f" % [
			_t, pos, dist, _tank.get_forward_speed(), _tank.get_angular_velocity().y])

	if _t >= 320:
		var final_pos := _tank.global_position
		var straight_dist := Vector3(_start_pos.x, 0, _start_pos.z).distance_to(Vector3(final_pos.x, 0, final_pos.z))
		var end_yaw := _tank.get_forward().signed_angle_to(Vector3(0, 0, -1), Vector3.UP)
		var yaw_change_during_pivot := absf(angle_difference(_start_yaw, end_yaw))
		print("[tank2] done. final_pos=%s straight_dist=%.2f yaw_change_during_pivot=%.2f rad" % [
			final_pos, straight_dist, yaw_change_during_pivot])
		var passed := straight_dist > 3.0 and yaw_change_during_pivot > 0.3
		if passed:
			print("[tank2] PASS -- PhysXTank3D drove forward and skid-steer pivoted it")
		else:
			print("[tank2] FAIL -- straight_dist=%.2f (want >3.0), yaw_change_during_pivot=%.2f (want >0.3)" % [
				straight_dist, yaw_change_during_pivot])
		_tank.free()
		quit(0 if passed else 1)
