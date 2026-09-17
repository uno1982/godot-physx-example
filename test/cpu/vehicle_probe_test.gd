extends SceneTree

# Phase 1 probe for PxVehicle2 (PhysX 5's component-based vehicle SDK):
# proves a hand-built 4-wheel direct-drive vehicle actually drives on the real
# PxScene, end to end, before any real PhysXVehicle3D node exists. Mirrors
# vehicle_body_test.gd's structure/thresholds so the two are easy to compare.

var _probe: GodotPhysXVehicleProbe
var _t := 0
var _start_pos: Vector3

func _initialize() -> void:
	print("[vehicle-probe] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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

	_probe = GodotPhysXVehicleProbe.new()
	_start_pos = Vector3(0, 0.6, 0)
	var ok := _probe.initialize(get_root().world_3d.space, _start_pos)
	if not ok:
		print("[vehicle-probe] FAIL: initialize() returned false")
		quit(1)
		return
	print("[vehicle-probe] ready, start_pos=", _start_pos)
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1

	var pos := _probe.get_position()
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		print("[vehicle-probe] FAIL: position went NaN at t+%d" % _t)
		_probe = null
		quit(1)
		return

	var throttle := 1.0
	var steer := 0.0
	if _t > 150:
		# Second phase: ease off throttle and turn, to prove steering actually
		# changes the path, not just "does it move forward at all".
		throttle = 0.6
		steer = 0.6

	_probe.step(1.0 / 60.0, throttle, 0.0, steer)

	if _t % 30 == 0:
		var dist := pos.distance_to(_start_pos)
		print("[vehicle-probe] t+%d pos=%s dist=%.2f lin_vel=%s fwd_speed=%.2f" % [
			_t, pos, dist, _probe.get_linear_velocity(), _probe.get_forward_speed()])

	if _t >= 300:
		var final_pos := _probe.get_position()
		var straight_dist := Vector3(_start_pos.x, 0, _start_pos.z).distance_to(Vector3(final_pos.x, 0, final_pos.z))
		var lateral_shift := absf(final_pos.x - _start_pos.x)
		print("[vehicle-probe] done. final_pos=%s straight_dist=%.2f lateral_shift=%.2f" % [final_pos, straight_dist, lateral_shift])
		var passed := straight_dist > 5.0 and lateral_shift > 0.5
		if passed:
			print("[vehicle-probe] PASS -- vehicle drove forward under throttle and turned under steer")
		else:
			print("[vehicle-probe] FAIL -- straight_dist=%.2f (want >5.0), lateral_shift=%.2f (want >0.5)" % [straight_dist, lateral_shift])
		# Explicitly drop the probe now, while PhysicsServer3D/PxScene are still
		# guaranteed alive -- its destructor releases real PhysX actors, and
		# relying on implicit RefCounted cleanup during engine shutdown risks
		# running that release after GodotPhysXServer3D::finish() has already
		# torn PxPhysics/PxScene down (segfaulted on exit before this fix).
		_probe = null
		quit(0 if passed else 1)
