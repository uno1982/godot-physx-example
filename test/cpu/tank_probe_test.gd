extends SceneTree

# Phase 1 probe for a PxVehicle2 N-wheel tracked (tank-style) vehicle
# (vehicle/godot_physx_vehicle_track.h): proves the raw composition drives on
# the real PxScene and that skid-steer (independently signed left/right track
# speed) actually turns it -- using nothing but PxVehicle2's own mechanics.
# PxVehicle2 has no track/tank primitive at all (confirmed: zero track/tank
# types anywhere in the SDK's vehicle/ header tree), so unlike the
# motorcycle probe (which at least had a real Jolt mechanism to port and
# reject), there was never a "real" mechanism to compare against here --
# this composition's skid-steer is a from-scratch design: each wheel's own
# throttle response multiplier IS its track's signed [-1, 1] drive command,
# set fresh every tick, with the vehicle's shared forward/reverse gear held
# fixed at eFORWARD so the two tracks can spin in genuinely opposite
# directions at once (a real pivot turn) without fighting a single shared
# gear. See VehicleTrack::setDriverInput()'s own doc comment.
#
# 8 road wheels (4 per side), spread across a 3m wheelbase -- a modest,
# plausible tank layout, well under VehicleTrack::MAX_WHEELS (16).

var _probe: GodotPhysXTankProbe
var _t := 0
var _start_pos: Vector3
var _start_yaw: float

func _initialize() -> void:
	print("[tank-probe] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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

	var wheel_positions := PackedVector3Array()
	const TRACK_HALF_WIDTH := 1.2
	const WHEEL_Y := 0.1
	var wheel_zs := [-1.5, -0.5, 0.5, 1.5]
	for z in wheel_zs:
		wheel_positions.append(Vector3(-TRACK_HALF_WIDTH, WHEEL_Y, z)) # left track
	for z in wheel_zs:
		wheel_positions.append(Vector3(TRACK_HALF_WIDTH, WHEEL_Y, z)) # right track

	_probe = GodotPhysXTankProbe.new()
	_start_pos = Vector3(0, 0.6, 0)
	var ok := _probe.initialize(get_root().world_3d.space, _start_pos, wheel_positions)
	if not ok:
		print("[tank-probe] FAIL: initialize() returned false")
		quit(1)
		return
	print("[tank-probe] ready, start_pos=", _start_pos, " wheels=", wheel_positions.size())
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1

	var pos := _probe.get_position()
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		print("[tank-probe] FAIL: position went NaN at t+%d" % _t)
		_probe = null
		quit(1)
		return

	var left_ratio := 1.0
	var right_ratio := 1.0
	if _t > 150 and _t <= 250:
		# Phase 2: pivot turn -- left track full forward, right track full
		# reverse. If skid-steer genuinely works, this should spin the tank
		# in place (yaw changes fast, forward position barely drifts) rather
		# than just curve like a car's steered wheel would.
		left_ratio = 1.0
		right_ratio = -1.0
	elif _t > 250:
		# Phase 3: release back to straight-forward, confirm it recovers to
		# normal forward driving after a pivot, not stuck or diverging.
		left_ratio = 1.0
		right_ratio = 1.0

	_probe.step(1.0 / 60.0, left_ratio, right_ratio, 0.0)

	if _t == 150:
		_start_yaw = _probe.get_forward().signed_angle_to(Vector3(0, 0, -1), Vector3.UP)

	if _t % 30 == 0:
		var dist := pos.distance_to(_start_pos)
		print("[tank-probe] t+%d pos=%s dist=%.2f fwd_speed=%.2f ang_vel_y=%.3f" % [
			_t, pos, dist, _probe.get_forward_speed(), _probe.get_angular_velocity().y])

	if _t >= 320:
		var final_pos := _probe.get_position()
		var straight_dist := Vector3(_start_pos.x, 0, _start_pos.z).distance_to(Vector3(final_pos.x, 0, final_pos.z))
		var end_yaw := _probe.get_forward().signed_angle_to(Vector3(0, 0, -1), Vector3.UP)
		var yaw_change_during_pivot := absf(angle_difference(_start_yaw, end_yaw))
		print("[tank-probe] done. final_pos=%s straight_dist=%.2f yaw_change_during_pivot=%.2f rad" % [
			final_pos, straight_dist, yaw_change_during_pivot])
		# straight_dist > 3.0 proves phase 1 (both tracks forward) actually
		# drove it forward a real distance. yaw_change > 0.3 rad (~17 deg)
		# proves phase 2's opposite-signed tracks genuinely spun it, not
		# just curved -- the real thing this probe exists to prove.
		var passed := straight_dist > 3.0 and yaw_change_during_pivot > 0.3
		if passed:
			print("[tank-probe] PASS -- raw VehicleTrack drove forward and skid-steer pivoted it")
		else:
			print("[tank-probe] FAIL -- straight_dist=%.2f (want >3.0), yaw_change_during_pivot=%.2f (want >0.3)" % [
				straight_dist, yaw_change_during_pivot])
		_probe = null
		quit(0 if passed else 1)
