extends Node3D
# Rotates the turret to face wherever the active camera is looking, locked
# to the hull's own local X/Z plane for yaw (no roll as the hull tilts),
# with the barrel's own elevation following the camera's up/down look
# angle, clamped to a real tank gun's elevation range -- like a real tank
# turret sitting flush on the deck with a gunner tracking the sight.
#
# Works entirely in the hull's LOCAL space -- never reads or writes this
# node's own global_transform. An earlier version computed the target in
# world space and wrote straight to global_transform.basis; the hull
# (PhysXTank3D) moves its transform on the physics tick, and recomputing
# the turret's orientation from a global-space snapshot once per rendered
# frame could momentarily disagree with the hull's physics-interpolated
# render transform during fast pivots, so the gun visually detached from
# the body. Building the target basis in the parent's local frame and
# assigning it to this node's own local `transform` instead avoids that
# global-space round trip altogether.

@export var turn_speed := 4.0 # radians/sec, like a turret traverse motor
@export var max_pitch_up_deg := 20.0
@export var max_pitch_down_deg := 5.0 # much smaller than up -- the Gun mesh clips into the hull past this

func _physics_process(delta: float) -> void:
	var hull := get_parent() as Node3D
	if not hull:
		return
	var t := clampf(turn_speed * delta, 0.0, 1.0)

	# Only track the camera while this tank is the one actually being
	# driven/followed (physx_tank_rig.gd's own `active` flag, set by
	# vehicle_swap.gd on Tab-cycle) -- otherwise the turret would keep
	# aiming at whatever the camera is looking at while a different
	# vehicle is active, which has nothing to do with this tank. Relax to
	# dead ahead instead, same as every other rig's inactive-vehicle
	# convention in this demo.
	if not hull.get("active"):
		var q_from_idle := transform.basis.get_rotation_quaternion()
		var q_to_idle := Basis.IDENTITY.get_rotation_quaternion()
		transform.basis = Basis(q_from_idle.slerp(q_to_idle, t))
		return

	var cam := get_viewport().get_camera_3d()
	if not cam:
		return

	var cam_fwd_world := -cam.global_transform.basis.z
	var local_dir := (hull.global_transform.basis.inverse() * cam_fwd_world).normalized()

	var horiz := Vector3(local_dir.x, 0.0, local_dir.z)
	if horiz.length() < 0.001:
		return
	horiz = horiz.normalized()

	# Positive pitch = up, negative = down (confirmed empirically: aiming
	# the camera up/down 40deg produced barrel angles of +/-~19.7deg with a
	# +/-20deg clamp, matching sign for sign).
	var pitch := clampf(asin(clampf(local_dir.y, -1.0, 1.0)), -deg_to_rad(max_pitch_down_deg), deg_to_rad(max_pitch_up_deg))
	var right := horiz.cross(Vector3.UP)
	var barrel_dir := horiz.rotated(right, pitch)

	# Basis.looking_at(target, up) aims -Z at target; the Gun mesh's own
	# barrel extends along local +Z (see physx_tank_rig.gd's MUZZLE_LOCAL),
	# so aim -Z at the opposite of the direction we actually want the
	# barrel pointing.
	var target_basis := Basis.looking_at(-barrel_dir, Vector3.UP)

	var q_from := transform.basis.get_rotation_quaternion()
	var q_to := target_basis.get_rotation_quaternion()
	transform.basis = Basis(q_from.slerp(q_to, t))
