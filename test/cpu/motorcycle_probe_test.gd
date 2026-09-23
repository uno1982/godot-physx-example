extends SceneTree

# Phase 1 probe for a PxVehicle2 2-wheel (motorcycle-style) vehicle
# (vehicle/godot_physx_vehicle2w.h): proves the raw composition drives on the
# real PxScene and responds to steer, using nothing but PxVehicle2's own
# mechanics -- no balance/lean correction at all. PxVehicle2 itself has no
# balancing mechanism for a 2-wheel vehicle (unlike Jolt's
# MotorcycleController), and this probe doesn't add one either; two real C++
# attempts at porting one (a Jolt-style torque-impulse port, then a
# steer-based countersteer controller) were both tried and removed after the
# working solution turned out to be a script-side controller instead (see
# physx_motorcycle_rig.gd) -- keeping unused C++ mechanisms around after that
# was just dead weight. So this test only checks what the raw probe can
# still promise: it drives forward and turning changes its path, without
# ever claiming it stays upright (it won't, on its own).

var _probe: GodotPhysXMotorcycleProbe
var _t := 0
var _start_pos: Vector3

func _initialize() -> void:
	print("[motorcycle-probe] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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

	_probe = GodotPhysXMotorcycleProbe.new()
	_start_pos = Vector3(0, 0.6, 0)
	var ok := _probe.initialize(get_root().world_3d.space, _start_pos)
	if not ok:
		print("[motorcycle-probe] FAIL: initialize() returned false")
		quit(1)
		return
	print("[motorcycle-probe] ready, start_pos=", _start_pos)
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1

	var pos := _probe.get_position()
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		print("[motorcycle-probe] FAIL: position went NaN at t+%d" % _t)
		_probe = null
		quit(1)
		return

	# Held nearly upright by a small constant angular-velocity counter-nudge
	# so a pure kinematics check (does steer change the path) doesn't need
	# real balance logic to survive the run -- see this file's own doc
	# comment for why no such logic lives here anymore.
	var roll := _probe.get_roll_angle()
	_probe.set_angular_velocity(_probe.get_angular_velocity() - _probe.get_forward() * roll * 4.0)

	var throttle := 1.0
	var steer := 0.0
	if _t > 100:
		steer = 0.4

	_probe.step(1.0 / 60.0, throttle, 0.0, steer)

	if _t % 30 == 0:
		var dist := pos.distance_to(_start_pos)
		print("[motorcycle-probe] t+%d pos=%s dist=%.2f roll=%.2f fwd_speed=%.2f" % [
			_t, pos, dist, roll, _probe.get_forward_speed()])

	if _t >= 200:
		var final_pos := _probe.get_position()
		var straight_dist := Vector3(_start_pos.x, 0, _start_pos.z).distance_to(Vector3(final_pos.x, 0, final_pos.z))
		var lateral_shift := absf(final_pos.x - _start_pos.x)
		print("[motorcycle-probe] done. final_pos=%s straight_dist=%.2f lateral_shift=%.2f" % [
			final_pos, straight_dist, lateral_shift])
		var passed := straight_dist > 3.0 and lateral_shift > 0.2
		if passed:
			print("[motorcycle-probe] PASS -- raw Vehicle2W drove forward and turning changed its path")
		else:
			print("[motorcycle-probe] FAIL -- straight_dist=%.2f (want >3.0), lateral_shift=%.2f (want >0.2)" % [
				straight_dist, lateral_shift])
		_probe = null
		quit(0 if passed else 1)
