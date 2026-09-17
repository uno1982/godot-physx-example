extends SceneTree

# Phase 2 regression: the real PhysXVehicle3D node (not the headless probe --
# see vehicle_probe_test.gd for that) drives and turns via its own exported
# properties + throttle/brake/steer control inputs, inside a real scene tree.

var _car: PhysXVehicle3D
var _t := 0
var _start_pos: Vector3

func _initialize() -> void:
	print("[vehicle2] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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

	_car = PhysXVehicle3D.new()
	_start_pos = Vector3(0, 0.6, 0)
	_car.position = _start_pos
	root.add_child(_car)

	await process_frame
	print("[vehicle2] ready, start_pos=", _start_pos)
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1

	var pos := _car.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		print("[vehicle2] FAIL: position went NaN at t+%d" % _t)
		quit(1)
		return

	_car.throttle = 1.0
	_car.brake = 0.0
	_car.steer = 0.0
	if _t > 150:
		_car.throttle = 0.6
		_car.steer = 0.6

	if _t % 30 == 0:
		var dist := pos.distance_to(_start_pos)
		print("[vehicle2] t+%d pos=%s dist=%.2f lin_vel=%s fwd_speed=%.2f" % [
			_t, pos, dist, _car.get_linear_velocity(), _car.get_forward_speed()])

	if _t >= 300:
		var final_pos := _car.global_position
		var straight_dist := Vector3(_start_pos.x, 0, _start_pos.z).distance_to(Vector3(final_pos.x, 0, final_pos.z))
		var lateral_shift := absf(final_pos.x - _start_pos.x)
		print("[vehicle2] done. final_pos=%s straight_dist=%.2f lateral_shift=%.2f" % [final_pos, straight_dist, lateral_shift])
		var passed := straight_dist > 5.0 and lateral_shift > 0.5
		if passed:
			print("[vehicle2] PASS -- PhysXVehicle3D drove forward under throttle and turned under steer")
		else:
			print("[vehicle2] FAIL -- straight_dist=%.2f (want >5.0), lateral_shift=%.2f (want >0.5)" % [straight_dist, lateral_shift])
		# Explicitly free the car now, while PhysicsServer3D/PxScene are still
		# guaranteed alive -- same lesson vehicle_probe_test.gd hit: its
		# destructor releases real PhysX actors, and relying on implicit
		# engine-shutdown cleanup ordering risks running that release after
		# the space has already been torn down.
		_car.free()
		quit(0 if passed else 1)
