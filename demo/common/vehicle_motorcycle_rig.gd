extends VehicleBody3D
# Stock-Godot counterpart to physx_motorcycle_rig.gd -- same arcade controls
# as vehicle_rig.gd (W/S throttle-reverse, A/D steer, Space brake) on a
# VehicleBody3D with 2 VehicleWheel3D children, plus the same lean-balance
# controller, built on RigidBody3D's own built-in angular_velocity/
# apply_torque_impulse (VehicleBody3D IS a RigidBody3D, so this needs no
# engine-core changes at all -- unlike the PhysX side, which needed
# PhysXMotorcycle3D to expose those as new methods). This is the module's
# "no C++ needed here" half of the comparison: VehicleBody3D's own raycast
# vehicle model has no balancing mechanism either, so the exact same
# script-side lean controller is required on both sides -- the difference is
# only that RigidBody3D already had the hooks this needs, built in.

@export var max_engine_force := 40.0
@export var max_brake_force := 15.0
@export var max_steer_angle := 0.5 # radians
@export var steer_speed := 2.0 # radians/sec toward the target angle

# Lean controller gains -- same meaning/values as physx_motorcycle_rig.gd's
# own constants (see that script's comment for where this approach came from).
const LEAN_ANGLE_GAIN := 25.0
const LEAN_BLEND := 0.6
const MAX_LEAN_ANGLE := 0.35
const STEER_TO_LEAN := -0.5
# Pitch stabilization -- same PD/velocity-blend pattern as the roll
# correction, but correcting pitch (nose-up wheelies / nose-down endos) back
# toward level. See physx_motorcycle_rig.gd's own comment for why this is
# needed: a steep wheelie isn't caught by the airborne gate (one wheel is
# still down), but it makes flat_forward nearly degenerate and misdirects
# engine force mostly upward instead of forward.
const PITCH_GAIN := 15.0
const PITCH_BLEND := 0.5
# Rear-wheel slide-under-braking, ported from physx_motorcycle_rig.gd's own
# _apply_rear_braking_step_out() -- without it, getting a real rear slide
# needed a hacky forward-shifted center of mass (which made the bike
# unrealistically front-heavy for everything else). A real outward force at
# the rear wheel while braking+turning gets a genuine slide without that
# trade-off.
@export var rear_braking_step_out_strength := 0.25

var active := false

func _physics_process(delta: float) -> void:
	if not active:
		engine_force = 0.0
		brake = 0.0
		steering = move_toward(steering, 0.0, steer_speed * delta)
		_apply_lean_control(0.0)
		return

	# Real bug found via direct headless verification: throttle and brake
	# were computed fully independently, so holding W and then pressing
	# Space WITHOUT first releasing W (a completely normal way to brake)
	# left engine_force at full power at the same time brake was fully
	# engaged -- fighting itself. physx_motorcycle_rig.gd already zeroes
	# throttle when Space is pressed; this never did, which is very likely
	# what actually produced the erratic behavior reported while braking,
	# not the lean/pitch correction (which real testing already ruled out).
	brake = max_brake_force if Input.is_key_pressed(KEY_SPACE) else 0.0

	var throttle := 0.0
	if brake <= 0.0:
		if Input.is_key_pressed(KEY_W):
			throttle += 1.0
		if Input.is_key_pressed(KEY_S):
			throttle -= 1.0
	engine_force = throttle * max_engine_force

	var steer_input := 0.0
	if Input.is_key_pressed(KEY_A):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D):
		steer_input -= 1.0
	var target_steer := steer_input * max_steer_angle
	steering = move_toward(steering, target_steer, steer_speed * delta)

	_apply_rear_braking_step_out(steer_input)
	_apply_lean_control(steer_input)

func _apply_rear_braking_step_out(steer_input: float) -> void:
	if brake <= 0.0 or absf(steer_input) < 0.05 or rear_braking_step_out_strength <= 0.0:
		return
	var speed := absf(linear_velocity.dot(-global_transform.basis.z))
	if speed < 1.0:
		return
	var body_right := global_transform.basis.x
	var outward_direction := -body_right * signf(steer_input)
	var rear_wheel := get_node_or_null("WheelRear")
	if rear_wheel == null:
		return
	var cast_origin: Vector3 = rear_wheel.global_position + Vector3.UP * 0.1
	var cast_length: float = rear_wheel.wheel_radius + rear_wheel.get_suspension_travel() + 0.2
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cast_origin, cast_origin + Vector3.DOWN * cast_length)
	if not get_world_3d().direct_space_state.intersect_ray(query):
		return
	var rear_brake_force := max_brake_force / maxf(rear_wheel.wheel_radius, 0.01)
	var step_out_force := outward_direction * rear_brake_force * rear_braking_step_out_strength * absf(steer_input)
	# RigidBody3D.apply_force()'s position is a WORLD-ALIGNED offset from the
	# body's origin, unlike PhysXMotorcycle3D.apply_force_at_local_position()'s
	# LOCAL (rotated) position -- rear_wheel.position has to be rotated into
	# world-aligned axes first, or this applies the force at the wrong point
	# once the bike isn't level.
	var rear_wheel_local_position: Vector3 = rear_wheel.position
	var world_aligned_offset := global_transform.basis * rear_wheel_local_position
	apply_force(step_out_force, world_aligned_offset)

func _apply_lean_control(steer_input: float) -> void:
	# Airborne-safe gate, ported from physx_motorcycle_rig.gd after real
	# testing showed it meaningfully helps there and this script had no
	# equivalent at all. The trigger moment isn't really "airborne" in the
	# simple sense -- it's the transition where one wheel (e.g. front,
	# leaving a ramp) is off the ground while the other (rear) is still
	# planted and still applying drive/brake torque through the suspension.
	# That asymmetric, one-sided load is exactly what was tossing the bike
	# into a chaotic spin. Full airborne (both wheels off) skips the normal
	# lean correction entirely (there's no real ground-reaction data to
	# correct from) and instead just damps out any non-yaw spin picked up
	# from the impact, so the bike tends to fall roughly upright instead of
	# tumbling further.
	if not _has_wheel_ground_contact(0) and not _has_wheel_ground_contact(1):
		var airborne_up: Vector3 = global_transform.basis.y
		var airborne_spin: Vector3 = airborne_up * angular_velocity.dot(airborne_up)
		angular_velocity = angular_velocity.lerp(airborne_spin, 0.35)
		return

	# Reverted: fading the correction's own effect (not just target_lean) to
	# zero at low speed made a DIFFERENT, worse problem (the bike fell over
	# while braking) -- low speed is when active balance is needed MOST
	# (least gyroscopic self-stability from wheel spin), so removing the
	# correction there was the wrong direction. Keeping only the earlier
	# target_lean fade (below), which fixed "spins in place holding a steer
	# key while stopped" without removing real balance assistance.
	var speed := absf(linear_velocity.dot(-global_transform.basis.z))
	var speed_factor := clampf(speed / 2.0, 0.0, 1.0)

	_apply_pitch_stabilization()

	var basis := global_transform.basis
	var right := basis.x
	var up := basis.y
	var roll := atan2(right.y, up.y)
	# Correct around the HEADING-projected forward (flattened to the
	# horizontal plane), not the raw basis forward -- the raw one tilts
	# whenever the bike pitches (e.g. nose-dip under braking from weight
	# transfer), and rotating around a tilted axis to fix roll has a real
	# side-component that leaks into world-frame yaw. That's not noise -- it
	# stayed in one consistent direction and was a real observed bug (a bike
	# left standing after braking from a turn slowly spun in place). A
	# horizontal, heading-aligned axis corrects roll without touching yaw.
	var flat_forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if flat_forward.length() < 0.001:
		return # pointing straight up/down -- no meaningful heading to correct around
	flat_forward = flat_forward.normalized()
	var roll_rate := -angular_velocity.dot(flat_forward)

	var target_lean := clampf(steer_input, -1.0, 1.0) * MAX_LEAN_ANGLE * STEER_TO_LEAN * speed_factor
	var target_roll_rate := LEAN_ANGLE_GAIN * (target_lean - roll)
	var new_roll_rate := lerpf(roll_rate, target_roll_rate, LEAN_BLEND)
	angular_velocity += flat_forward * (roll_rate - new_roll_rate)

func _apply_pitch_stabilization() -> void:
	var basis := global_transform.basis
	var forward := -basis.z
	var right_now := basis.x

	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	# Deadzone reverted -- real headless testing showed pitch stabilization
	# was NOT the actual cause of the brake jitter (the roll correction was),
	# so this was fixing a problem that wasn't there. Back to targeting
	# level (0) unconditionally, matching physx_motorcycle_rig.gd again.
	var cos_pitch := maxf(0.05, sqrt(max(0.0, 1.0 - forward.y * forward.y)))
	var pitch_rate := angular_velocity.cross(forward).y / cos_pitch

	var target_pitch_rate := PITCH_GAIN * (0.0 - pitch)
	var new_pitch_rate := lerpf(pitch_rate, target_pitch_rate, PITCH_BLEND)
	# See physx_motorcycle_rig.gd's own comment: this axis/coordinate pair's
	# sensitivity sign is the opposite of the roll correction's own, so this
	# is axis*(new-old), not axis*(old-new).
	angular_velocity += right_now * (new_pitch_rate - pitch_rate)

func _has_wheel_ground_contact(wheel_index: int) -> bool:
	var wheel_path := "WheelFront" if wheel_index == 0 else "WheelRear"
	var wheel := get_node_or_null(wheel_path)
	if wheel == null:
		return false
	var cast_origin: Vector3 = wheel.global_position + Vector3.UP * 0.1
	var cast_length: float = wheel.wheel_radius + wheel.get_suspension_travel() + 0.2
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		cast_origin,
		cast_origin + Vector3.DOWN * cast_length
	)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
