extends PhysXMotorcycle3D
# Same arcade drive controls as physx_vehicle_rig.gd, plus a lean-balance
# controller -- PxVehicle2 has no balancing mechanism for a 2-wheel vehicle
# (unlike Jolt's MotorcycleController), so this script supplies it directly
# via apply_torque_impulse()/set_angular_velocity(), the same API and
# velocity-blend approach proven headlessly in
# GodotPhysXMotorcycleProbe/test/cpu/motorcycle_probe_test.gd (a direct
# torque-impulse PD controller was tried there first and found to diverge --
# see that test's own comments for the numbers that showed it).

@export var steer_speed := 2.0 # normalized steering input/sec toward the target
@export var lean_velocity_correction_enabled := true
@export_range(0.0, 1.0, 0.05) var lean_velocity_correction_strength := 1.0
@export_range(0.0, 1.0, 0.05) var rear_braking_step_out_strength := 0.25

var _held_target_lean := 0.0

# Lean controller gains -- same values/meaning as motorcycle_probe_test.gd's
# own constants, tuned against this node's default ~220kg/wheelbase-1.4m
# config.
const LEAN_ANGLE_GAIN := 25.0
const LEAN_BLEND := 0.6
const MAX_LEAN_ANGLE := 0.35
# Max rad/sec the held lean target is allowed to move back toward the
# freshly-computed banking value once the brake releases -- without this,
# releasing the brake let target_lean jump instantly from whatever it was
# held at (mid-slide) to the fresh banking-formula value, yanking the bike
# upright in one tick instead of settling out of the lean smoothly.
const LEAN_RELEASE_RATE := 1.5
# Pitch stabilization -- same PD/velocity-blend pattern as the roll
# correction, but correcting pitch (nose-up wheelies / nose-down endos)
# back toward level instead of correcting lean. Needed because a steep
# wheelie isn't caught by the airborne gate (one wheel is still down), but
# it makes the roll correction's own flat_forward (horizontal projection of
# forward) nearly degenerate, and misdirects engine force mostly upward
# instead of forward -- both of which were found to compound into the
# chaotic spins during bump testing.
const PITCH_GAIN := 15.0
const PITCH_BLEND := 0.5

# Only the active bike reads keyboard input -- see vehicle_rig.gd's own note
# on why the inactive one must relax to neutral instead of coasting.
var active := false

func _physics_process(delta: float) -> void:
	if not active:
		throttle = 0.0
		brake = 0.0
		steer = move_toward(steer, 0.0, steer_speed * delta)
		_apply_lean_control()
		return

	if Input.is_key_pressed(KEY_W):
		reverse = false
		throttle = 1.0
		brake = 0.0
	elif Input.is_key_pressed(KEY_S):
		if not reverse and get_forward_speed() > 0.5:
			throttle = 0.0
			brake = 1.0
		else:
			reverse = true
			throttle = 1.0
			brake = 0.0
	else:
		throttle = 0.0
		brake = 0.0

	if Input.is_key_pressed(KEY_SPACE):
		brake = 1.0
		throttle = 0.0

	var s := 0.0
	if Input.is_key_pressed(KEY_A):
		s += 1.0
	if Input.is_key_pressed(KEY_D):
		s -= 1.0
	steer = move_toward(steer, s, steer_speed * delta)

	_apply_rear_braking_step_out()
	_apply_lean_control()

func _apply_rear_braking_step_out() -> void:
	if brake <= 0.0 or absf(steer) < 0.05 or rear_braking_step_out_strength <= 0.0:
		return
	var speed := absf(get_forward_speed())
	if speed < 1.0:
		return
	var body_right := global_transform.basis.x
	var outward_direction := -body_right * signf(steer)
	var rear_wheel := get_node_or_null("WheelRear")
	if rear_wheel == null:
		return
	var cast_origin: Vector3 = rear_wheel.global_position + Vector3.UP * 0.1
	var cast_length: float = rear_wheel.radius + rear_wheel.get_suspension_travel() + 0.2
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cast_origin, cast_origin + Vector3.DOWN * cast_length)
	if not get_world_3d().direct_space_state.intersect_ray(query):
		return
	var rear_brake_force := max_brake_torque / maxf(rear_wheel.radius, 0.01)
	var step_out_force := outward_direction * rear_brake_force * rear_braking_step_out_strength * absf(steer)
	apply_force_at_local_position(step_out_force, rear_wheel.position)

func _apply_lean_control() -> void:
	if not _has_wheel_ground_contact(0) and not _has_wheel_ground_contact(1):
		var airborne_angular_velocity: Vector3 = get_angular_velocity()
		var airborne_up: Vector3 = global_transform.basis.y
		var airborne_spin: Vector3 = airborne_up * airborne_angular_velocity.dot(airborne_up)
		set_angular_velocity(airborne_angular_velocity.lerp(airborne_spin, 0.35))
		return
	_apply_pitch_stabilization()
	# Everything below is built ONLY from raw physical vectors (position
	# basis vectors, angular_velocity, linear_velocity) combined via the
	# standard rigid-body identity d(v)/dt = angular_velocity.cross(v) --
	# never from a hand-picked axis label like "angular_velocity.y is yaw
	# rate, and positive yaw rate is a left turn". Two earlier versions of
	# this function got exactly that kind of hand-derived axis-convention
	# backward in different ways (confirmed by direct rotation-matrix
	# algebra that contradicted itself between attempts), which is why this
	# is now built entirely out of cross/dot products against get_roll_angle()'s
	# own reference vectors (right, up) instead: whatever "positive" turns
	# out to mean for a given raw component, target_lean and roll are
	# guaranteed to agree, because they're built from the same vectors the
	# same way.
	var roll := get_roll_angle()
	var angular_velocity := get_angular_velocity()
	var velocity := get_linear_velocity()
	var xf := global_transform
	var right_now := xf.basis.x
	var up_now := xf.basis.y

	# Roll rate: exact derivative of roll = atan2(right.y, up.y), using
	# d(right)/dt = angular_velocity x right and d(up)/dt = angular_velocity x up.
	var d_right_y := angular_velocity.cross(right_now).y
	var d_up_y := angular_velocity.cross(up_now).y
	var denom := right_now.y * right_now.y + up_now.y * up_now.y
	var roll_rate := 0.0
	if denom > 0.0001:
		roll_rate = (up_now.y * d_right_y - right_now.y * d_up_y) / denom

	# Target lean: real centripetal acceleration (angular_velocity x velocity,
	# the same standard identity), projected onto the bike's own CURRENT
	# right vector.
	#
	# Ground-truthed via a real raycast test (cast from a point offset above
	# the origin along up_now, landing spot compared to origin along
	# right_now): get_roll_angle() = atan2(right.y, up.y) reports NEGATIVE
	# when the bike is ACTUALLY leaning toward its own right (right_now) --
	# the opposite of its own doc comment ("positive = leaning right"), which
	# is wrong and was trusted uncritically throughout this file's earlier
	# versions. Physically, "lean toward right_now" should happen when
	# lateral_accel (centripetal accel dotted with right_now) is POSITIVE,
	# but that must map to NEGATIVE target_lean to match roll's real (inverted)
	# convention -- hence the negation below.
	var lateral_accel := angular_velocity.cross(velocity).dot(right_now)

	# Under hard braking, forward speed collapses fast, and lateral_accel
	# (which scales with full velocity magnitude, per the standard
	# steady-turn banking formula this is built on) collapses right along
	# with it -- even while the bike is genuinely sliding/turning, i.e. real
	# yaw still happening. That showed up as "slamming straight up instead
	# of leaning into a slide" under braking, unlike the reference Jolt bike.
	# A first fix (a separate lateral-VELOCITY term, not scaled by speed)
	# introduced a real feedback loop instead -- that term depended on
	# right_now, which the controller's own output changes every tick, so
	# it fed back into itself and wobbled the bike even in a straight line.
	# This is the simpler, feedback-free fix the user asked for directly:
	# while braking, don't recompute target_lean at all -- HOLD the last
	# value computed before the brake was applied, so the lean the bike was
	# already committed to (from actually turning) persists through the
	# braking event instead of chasing a decaying banking-formula target.
	#
	# On release, don't snap back to the fresh banking value either -- that
	# produced a real "yanked upright in one tick" jolt, since the held lean
	# and the fresh value can differ a lot right after a slide. Instead
	# move_toward's the held value at a bounded rate, so it settles out of
	# the lean smoothly over LEAN_RELEASE_RATE's own timescale.
	var raw_target_lean := clampf(atan2(-lateral_accel, 9.81), -MAX_LEAN_ANGLE, MAX_LEAN_ANGLE)
	if brake > 0.0:
		pass # frozen -- see comment above.
	else:
		_held_target_lean = move_toward(_held_target_lean, raw_target_lean, LEAN_RELEASE_RATE * get_physics_process_delta_time())
	var target_lean := _held_target_lean

	var target_roll_rate := LEAN_ANGLE_GAIN * (target_lean - roll)
	var new_roll_rate := lerpf(roll_rate, target_roll_rate, LEAN_BLEND)

	# Apply the correction around the HEADING-projected forward (flattened
	# to the horizontal plane), not the raw forward -- rotating around a
	# pitched forward axis (e.g. during braking nose-dip) leaks a real
	# side-component into world-frame yaw. This step's direction (which way
	# "forward" points) doesn't carry the same risk as the terms above: it's
	# only used as the axis to nudge angular velocity along, and roll_rate/
	# new_roll_rate are already correctly signed relative to roll itself.
	var raw_forward := get_forward()
	var flat_forward := Vector3(raw_forward.x, 0.0, raw_forward.z)
	if flat_forward.length() < 0.001:
		return
	flat_forward = flat_forward.normalized()
	var new_angular_velocity := angular_velocity + flat_forward * (roll_rate - new_roll_rate)
	if lean_velocity_correction_enabled:
		var corrected_angular_velocity := angular_velocity.lerp(new_angular_velocity, lean_velocity_correction_strength)
		set_angular_velocity(corrected_angular_velocity)

func _apply_pitch_stabilization() -> void:
	var forward := get_forward()
	var right_now := global_transform.basis.x
	var angular_velocity := get_angular_velocity()

	# pitch = angle of forward above/below horizontal (asin of its Y
	# component) -- positive = nose up (wheelie), negative = nose down.
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	# d(forward)/dt = angular_velocity x forward (standard rigid-body
	# identity, same one the roll correction above is built from), so
	# d(forward.y)/dt is the raw rate; dividing by cos(pitch) converts that
	# into the actual d(pitch)/dt via the asin derivative.
	var cos_pitch := maxf(0.05, sqrt(max(0.0, 1.0 - forward.y * forward.y)))
	var pitch_rate := angular_velocity.cross(forward).y / cos_pitch

	var target_pitch_rate := PITCH_GAIN * (0.0 - pitch)
	var new_pitch_rate := lerpf(pitch_rate, target_pitch_rate, PITCH_BLEND)
	# Sensitivity here is the OPPOSITE sign from the roll correction's own
	# (a concrete check: adding a small +right_now to angular_velocity
	# INCREASES d(forward.y)/dt near level, whereas the equivalent check for
	# roll's own axis/coordinate pair came out negative) -- so this is
	# axis*(new-old), not axis*(old-new) the way the roll correction reads.
	set_angular_velocity(angular_velocity + right_now * (new_pitch_rate - pitch_rate))

func _has_wheel_ground_contact(wheel_index: int) -> bool:
	var wheel_path := "WheelFront" if wheel_index == 0 else "WheelRear"
	var wheel := get_node_or_null(wheel_path)
	if wheel == null:
		return false
	var cast_origin: Vector3 = wheel.global_position + Vector3.UP * 0.1
	var cast_length: float = wheel.radius + wheel.get_suspension_travel() + 0.2
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		cast_origin,
		cast_origin + Vector3.DOWN * cast_length
	)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
