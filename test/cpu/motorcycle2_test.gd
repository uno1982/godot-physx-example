extends SceneTree

# Phase 2 regression: the real PhysXMotorcycle3D node (not the headless probe
# -- see motorcycle_probe_test.gd for that) drives, turns, and stays upright
# via its own exported properties + the same velocity-blend lean controller
# proven against the probe, inside a real scene tree. Mirrors vehicle2_test.gd's
# structure for direct comparison against the 4-wheel car.

var _bike: PhysXMotorcycle3D
var _t := 0
var _start_pos: Vector3
var _max_abs_roll := 0.0

const LEAN_ANGLE_GAIN := 25.0
const LEAN_BLEND := 0.6
const MAX_LEAN_ANGLE := 0.35

func _initialize() -> void:
	print("[motorcycle2] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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

	_bike = PhysXMotorcycle3D.new()
	_start_pos = Vector3(0, 0.6, 0)
	_bike.position = _start_pos
	root.add_child(_bike)

	var chassis_cs := CollisionShape3D.new()
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = Vector3(0.36, 0.5, 0.9)
	chassis_cs.shape = chassis_shape
	chassis_cs.position = Vector3(0, 0.55, 0)
	_bike.add_child(chassis_cs)

	# PhysXVehicleWheel3D's own field defaults are car-scale (radius 0.35,
	# wheel_mass 20, ...) -- override to motorcycle scale explicitly, same as
	# every wheel instance in vehicle_demo.tscn does.
	for is_front in [true, false]:
		var w := PhysXVehicleWheel3D.new()
		w.use_as_steering = is_front
		w.use_as_traction = not is_front
		w.position = Vector3(0, 0.05, 0.7 if is_front else -0.7)
		w.radius = 0.3
		w.half_width = 0.08
		w.wheel_mass = 8.0
		w.wheel_moment_of_inertia = 0.4
		w.damping_rate = 0.15
		w.suspension_travel = 0.12
		w.suspension_stiffness = 25000.0
		w.suspension_damping = 2200.0
		w.tire_lateral_stiffness = 12000.0
		w.tire_longitudinal_stiffness = 12000.0
		_bike.add_child(w)

	await process_frame
	print("[motorcycle2] ready, start_pos=", _start_pos)
	physics_frame.connect(_tick)

func _apply_lean_control(_steer: float) -> void:
	var roll := _bike.get_roll_angle()
	var angular_velocity := _bike.get_angular_velocity()
	# Correct around the HEADING-projected forward (flattened to the
	# horizontal plane) -- see motorcycle_probe_test.gd's identical fix for
	# why (rotating around a pitched forward axis leaks into world-frame yaw).
	var raw_forward := _bike.get_forward()
	var flat_forward := Vector3(raw_forward.x, 0.0, raw_forward.z)
	if flat_forward.length() < 0.001:
		return
	flat_forward = flat_forward.normalized()
	var roll_rate := -angular_velocity.dot(flat_forward)

	# Target lean from real banking-angle physics -- see motorcycle_probe_test.gd
	# and physx_motorcycle_rig.gd's identical fix for why.
	var yaw_rate := angular_velocity.y
	var forward_speed := _bike.get_forward_speed()
	var target_lean := clampf(atan2(forward_speed * yaw_rate, 9.81), -MAX_LEAN_ANGLE, MAX_LEAN_ANGLE)
	var target_roll_rate := LEAN_ANGLE_GAIN * (target_lean - roll)
	var new_roll_rate := lerpf(roll_rate, target_roll_rate, LEAN_BLEND)
	var new_angular_velocity := angular_velocity + flat_forward * (roll_rate - new_roll_rate)
	_bike.set_angular_velocity(new_angular_velocity)

func _tick() -> void:
	_t += 1

	var pos := _bike.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		print("[motorcycle2] FAIL: position went NaN at t+%d" % _t)
		quit(1)
		return

	_bike.throttle = 1.0
	_bike.brake = 0.0
	_bike.steer = 0.0
	if _t > 150:
		_bike.throttle = 0.6
		_bike.steer = clampf(float(_t - 150) / 60.0, 0.0, 1.0) * 0.6

	_apply_lean_control(_bike.steer)

	var roll := _bike.get_roll_angle()
	_max_abs_roll = maxf(_max_abs_roll, absf(roll))
	if absf(roll) > PI * 0.5:
		print("[motorcycle2] FAIL: fell over at t+%d, roll=%.2f rad" % [_t, roll])
		_bike.free()
		quit(1)
		return

	if _t % 30 == 0:
		var dist := pos.distance_to(_start_pos)
		print("[motorcycle2] t+%d pos=%s dist=%.2f roll=%.2f fwd_speed=%.2f" % [
			_t, pos, dist, roll, _bike.get_forward_speed()])

	if _t >= 300:
		var final_pos := _bike.global_position
		var straight_dist := Vector3(_start_pos.x, 0, _start_pos.z).distance_to(Vector3(final_pos.x, 0, final_pos.z))
		var lateral_shift := absf(final_pos.x - _start_pos.x)
		print("[motorcycle2] done. final_pos=%s straight_dist=%.2f lateral_shift=%.2f max_abs_roll=%.2f" % [
			final_pos, straight_dist, lateral_shift, _max_abs_roll])
		var passed := straight_dist > 5.0 and lateral_shift > 0.3 and _max_abs_roll < (PI * 0.5)
		if passed:
			print("[motorcycle2] PASS -- PhysXMotorcycle3D drove forward, turned, and stayed upright")
		else:
			print("[motorcycle2] FAIL -- straight_dist=%.2f (want >5.0), lateral_shift=%.2f (want >0.3), max_abs_roll=%.2f (want <%.2f)" % [
				straight_dist, lateral_shift, _max_abs_roll, PI * 0.5])
		_bike.free()
		quit(0 if passed else 1)
