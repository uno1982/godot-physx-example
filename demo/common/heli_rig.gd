extends RigidBody3D
# An arcade helicopter on stock nodes: a RigidBody3D on skids with a
# game-style flight controller -- it holds a hover when you let go. Nothing
# engine-specific: it flies the same on PhysX and Jolt.
#
#   Mouse          the flight assistant: the helicopter turns toward where
#                  the camera looks
#   W / S          forward / back (it tilts to fly that way)
#   Space / Ctrl   collective: climb / descend (let go and it holds its height)
#   A / D          tail rotor: yaw in place (the aim turns with the nose)
#   Q / E          tilt sideways: strafe left / right
#   R              back to the pad (vehicle_swap.gd)

@export var max_speed := 40.0 # m/s forward (backward: 40% of it)
@export var climb_rate := 8.0 # m/s up or down
@export var turn_rate := 90.0 # deg/s the nose turns at, at most
@export var max_tilt := 25.0 # deg the body tilts toward where it's going

# For the chase camera (vehicle_chase_camera.gd) -- the same contract as the
# plane: the camera is the aim, resting above looking down camera_pitch.
var camera_distance := 14.0
var camera_follow_heading := false
var camera_free_aim := true
var camera_pitch := deg_to_rad(15.0)
var camera_yaw_rate := 0.0

# Only the active vehicle reads input (vehicle_swap.gd).
var active := false
# Tests aim with this instead of the camera (world direction; zero = camera).
var aim_override := Vector3.ZERO

const ACCELERATION := 12.0 # m/s^2 toward the speed asked for
const RESPONSE := 5.0 # how quickly the attitude follows, 1/s
const SPINUP := 1.5 # s for the rotor to reach full speed

var _rotor := 0.0 # 0 stopped .. 1 flying speed
var _rotor_angle := 0.0
var _spawn: Transform3D

@onready var _main_rotor: Node3D = $MainRotor
@onready var _rotor_disc: MeshInstance3D = $MainRotor/Disc
@onready var _tail_rotor: Node3D = $TailRotor
@onready var _ground_ray: RayCast3D = $GroundRay


func _ready() -> void:
	_spawn = global_transform


func reset_to_pad() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _spawn


func airspeed() -> float:
	return linear_velocity.length()


func _axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_key_pressed(pos) else 0.0) - (1.0 if Input.is_key_pressed(neg) else 0.0)


# Where the camera looks, lifted by its resting look-down angle.
func _aim() -> Vector3:
	if aim_override != Vector3.ZERO:
		return aim_override.normalized()
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return global_basis.z
	var look := -cam.global_basis.z
	var elevation := asin(clampf(look.y, -1.0, 1.0)) + camera_pitch
	var heading := atan2(look.x, look.z)
	return Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation))


func _physics_process(delta: float) -> void:
	var on_ground := _ground_ray.is_colliding()
	# The rotor runs while it's being flown, or while it's in the air (switch
	# away mid-air and it hovers); on the ground, idle, it spins down.
	_rotor = move_toward(_rotor, 1.0 if active or not on_ground else 0.0, delta / SPINUP)
	camera_yaw_rate = 0.0
	if active and global_position.y < -50.0:
		reset_to_pad()
		return
	if _rotor < 1.0:
		# Spinning up (or down): the skids carry it, gravity holds it.
		return

	var b := global_basis.orthonormalized()
	var forward := b.z
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	flat_forward = flat_forward.normalized() if flat_forward.length() > 0.01 else Vector3.FORWARD
	var flat_right := flat_forward.cross(Vector3.UP).normalized() # +X is left; this is right

	# What's asked for.
	var aim := _aim()
	var heading_error := wrapf(atan2(aim.x, aim.z) - atan2(forward.x, forward.z), -PI, PI)
	var fly := _axis(KEY_S, KEY_W) if active else 0.0
	if fly < 0.0:
		fly *= 0.4 # backing up is slower
	var climb := _axis(KEY_CTRL, KEY_SPACE) if active else 0.0
	var strafe := _axis(KEY_Q, KEY_E) if active else 0.0 # + = right
	var yaw_keys := _axis(KEY_A, KEY_D) if active else 0.0 # + = right
	if on_ground and climb <= 0.0:
		# Sitting on the ground: no sliding about until it lifts off.
		fly = 0.0
		strafe = 0.0

	# Velocity: toward what's asked, and the rotor holds it up.
	var target := flat_forward * fly * max_speed + flat_right * strafe * max_speed * 0.5 + Vector3.UP * climb * climb_rate
	if not (on_ground and climb <= 0.0):
		linear_velocity = linear_velocity.move_toward(target, ACCELERATION * delta)
	apply_central_force(-get_gravity() * mass)

	# Heading: toward the aim; A / D yaw directly and the aim turns with them.
	var max_rate := deg_to_rad(turn_rate)
	var yaw_rate := clampf(heading_error * 3.0, -max_rate, max_rate)
	if yaw_keys != 0.0:
		yaw_rate = -yaw_keys * max_rate
		camera_yaw_rate = yaw_rate
	if on_ground and climb <= 0.0:
		yaw_rate = 0.0

	# Attitude: level, tilted toward where it's going (nose down to go
	# forward, a bank into strafes and turns) -- the look of a helicopter.
	var local_v := Vector3(linear_velocity.dot(flat_right), 0.0, linear_velocity.dot(flat_forward))
	var tilt := deg_to_rad(max_tilt)
	var pitch_down := clampf(local_v.z / max_speed, -0.5, 1.0) * tilt
	var bank := clampf(local_v.x / (max_speed * 0.5), -1.0, 1.0) * tilt * 0.7 + clampf(-yaw_rate / max_rate, -1.0, 1.0) * tilt * 0.3
	var want_basis := Basis(Vector3.UP, atan2(flat_forward.x, flat_forward.z)) * Basis(Vector3.RIGHT, pitch_down) * Basis(Vector3.BACK, bank)
	var err := (want_basis * b.inverse()).get_rotation_quaternion()
	var spin := Vector3.ZERO
	if err.get_angle() > 0.0001:
		var angle := err.get_angle()
		if angle > PI:
			angle -= TAU
		spin = err.get_axis() * angle * RESPONSE
	spin += Vector3.UP * yaw_rate
	angular_velocity = angular_velocity.lerp(spin, clampf(8.0 * delta, 0.0, 1.0))


func _process(delta: float) -> void:
	# Rotors: up to 5 rev/s main, 25 tail; the disc fades in as they blur.
	_rotor_angle = wrapf(_rotor_angle + _rotor * 5.0 * TAU * delta, 0.0, TAU)
	_main_rotor.rotation.y = _rotor_angle
	_tail_rotor.rotation.x = _rotor_angle * 5.0
	var disc_mat := _rotor_disc.get_active_material(0) as StandardMaterial3D
	if disc_mat:
		disc_mat.albedo_color.a = clampf(_rotor * 0.3 - 0.05, 0.0, 0.25)
