extends VehicleBody3D
# An arcade stunt plane on stock nodes: a VehicleBody3D whose VehicleWheel3D
# landing gear handles the runway, and a game-style flight controller in the
# air -- no aerodynamics, no stall. Past take-off speed the plane flies where
# its nose points at the throttle's speed, and the nose turns at a set rate,
# banking into the turn. Nothing engine-specific: it flies the same on PhysX
# and Jolt.
#
# Two control modes, C to switch:
#   Arcade   the plane flies toward where the camera looks (the camera rests
#            a little above it, looking down, where the plane flies level);
#            Q / E roll in place for as long as they're held (barrel rolls;
#            it levels again on release); A / D rudder (a flat yaw -- the
#            aim swings with the nose).
#   Manual   Up / Down pitch (Down = nose up), Left / Right roll (Q / E too),
#            A / D yaw; the camera is free.
#   Both     W / S throttle (it stays where you leave it), Space wheel
#            brakes, R back to the runway (vehicle_swap.gd). On the ground
#            only A / D steer (rudder and nose wheel); in arcade mode the
#            camera is a free look there -- once airborne, wherever it points
#            is the aim.
#
# Take-off: throttle up, and past take-off speed aim (or pull) the nose up.
# Landing: throttle down and fly it onto the runway; below take-off speed on
# the wheels it's a ground vehicle again.

enum ControlMode { ARCADE, MANUAL }

@export var control_mode := ControlMode.ARCADE:
	set(value):
		control_mode = value
		# Arcade: the camera is the aim -- it mustn't chase the heading, and
		# it can look well up and down.
		camera_follow_heading = value == ControlMode.MANUAL
		camera_free_aim = value == ControlMode.ARCADE
@export var max_speed := 70.0 # m/s at full throttle
@export var takeoff_speed := 24.0 # m/s; in the air it never flies slower
@export var acceleration := 8.0 # m/s^2 toward the throttle's speed
@export var turn_rate := 100.0 # deg/s the nose turns at, at most
@export var roll_rate := 220.0 # deg/s
@export var max_bank := 65.0 # deg the plane banks into a turn
# Weight. 1: climbs bleed speed and dives build it, and below take-off speed
# the wing carries less -- the plane sinks and its nose falls until it has
# speed again (no stall, no spin). 0: floaty, gravity cancelled outright.
@export_range(0.0, 1.0) var gravity_feel := 1.0

# For the chase camera (vehicle_chase_camera.gd).
var camera_distance := 16.0
var camera_follow_heading := false
var camera_free_aim := true
# The camera rests above the plane looking down this much (rad), where the
# aim is level -- so you see the plane, and the runway, from above.
var camera_pitch := deg_to_rad(12.0)
# Arcade A / D: how fast the camera's heading (the aim) swings, rad/s.
var camera_yaw_rate := 0.0

# Only the active vehicle reads input (vehicle_swap.gd).
var active := false
var throttle := 0.0
# Tests aim with this instead of the camera (world direction; zero = camera).
var aim_override := Vector3.ZERO

const RESPONSE := 8.0 # how quickly the rotation follows what's asked, 1/s
const VELOCITY_GRIP := 5.0 # how quickly the velocity swings onto the nose, 1/s
const MAX_DIVE_SPEED := 1.5 # x max_speed
const BRAKE := 12.0
const STEER := 0.5 # rad, nose wheel

var _speed := 0.0
var _asked := Vector3.ZERO # rates asked for, local: x nose down, y nose left, z roll right -- drives the surfaces
var _prop_angle := 0.0
var _spawn: Transform3D

@onready var _prop: Node3D = $Prop
@onready var _prop_disc: MeshInstance3D = $Prop/Disc
@onready var _aileron_left: Node3D = $AileronLeft
@onready var _aileron_right: Node3D = $AileronRight
@onready var _elevator: Node3D = $Elevator
@onready var _rudder: Node3D = $Rudder
@onready var _wheels: Array[VehicleWheel3D] = [$NoseWheel, $MainLeft, $MainRight]


func _ready() -> void:
	_spawn = global_transform
	control_mode = control_mode


func reset_to_runway() -> void:
	throttle = 0.0
	_speed = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _spawn


func airspeed() -> float:
	return linear_velocity.length()


func _axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_key_pressed(pos) else 0.0) - (1.0 if Input.is_key_pressed(neg) else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if active and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		control_mode = ControlMode.MANUAL if control_mode == ControlMode.ARCADE else ControlMode.ARCADE


func _physics_process(delta: float) -> void:
	var b := global_basis.orthonormalized()
	var forward := b.z
	engine_force = 0.0 # the prop pulls, not the wheels
	brake = 0.0
	steering = 0.0

	if active:
		throttle = clampf(throttle + _axis(KEY_S, KEY_W) * 0.6 * delta, 0.0, 1.0)
		brake = BRAKE if Input.is_key_pressed(KEY_SPACE) else 0.0
		if global_position.y < -50.0:
			reset_to_runway()
			return
	else:
		throttle = move_toward(throttle, 0.0, 0.6 * delta)

	var on_ground := false
	for w in _wheels:
		on_ground = on_ground or w.is_in_contact()
	var forward_speed := linear_velocity.dot(forward)
	# (Off the ground but nearly still is a spawn or reset settling onto its
	# wheels, not flight.)
	var flying := forward_speed >= takeoff_speed or (not on_ground and linear_velocity.length() > 3.0)
	var g := get_gravity()

	# How much the wing carries: all of it from take-off speed up, less below.
	var lift := clampf(forward_speed / takeoff_speed, 0.0, 1.0)
	lift = lerpf(1.0, lift * lift, gravity_feel)
	# Speed: the engine pulls it toward the throttle's, harder the further
	# off it is, and gravity along the nose takes it away climbing and adds it
	# diving (the part of gravity the wing doesn't carry acts on its own).
	var speed := linear_velocity.length() if flying else forward_speed
	var pull := (throttle * max_speed - speed) * acceleration / max_speed * 2.0
	var slope := g.dot(forward) * gravity_feel * lift if flying else 0.0
	_speed = clampf(speed + (pull + slope) * delta, 0.0, max_speed * MAX_DIVE_SPEED)

	# The rotation asked for, in world space. Q / E roll at the full rate,
	# and while they're held the arcade aim doesn't bank (it would fight them).
	var roll_keys := _axis(KEY_Q, KEY_E) if active else 0.0
	var want := _manual_turn(b) if control_mode == ControlMode.MANUAL else _aim_turn(b, roll_keys == 0.0)
	camera_yaw_rate = 0.0
	if active:
		want += forward * roll_keys * deg_to_rad(roll_rate)
		var turn_keys := _axis(KEY_A, KEY_D) # + = right
		if flying:
			# Rudder: yaw the nose. In arcade the aim swings with it, so the
			# aim doesn't pull it back.
			var yaw_rate := turn_keys * deg_to_rad(turn_rate) * 0.6
			want -= b.y * yaw_rate
			if control_mode == ControlMode.ARCADE:
				camera_yaw_rate = -yaw_rate
	_asked = b.inverse() * want
	# Manual: the camera follows the heading. Arcade: on the ground it's a
	# free look, in the air the aim.
	camera_follow_heading = control_mode == ControlMode.MANUAL

	if flying:
		# The velocity swings onto the nose -- less so when slow, so it mushes
		# -- at the new speed, and the wing holds up as much of the weight as
		# it carries.
		var heading := linear_velocity.normalized() if linear_velocity.length() > 0.5 else forward
		heading = heading.slerp(forward, clampf(VELOCITY_GRIP * lift * delta, 0.0, 1.0)).normalized()
		linear_velocity = heading * _speed
		apply_central_force(-g * mass * lift)
		# Slow, the nose falls toward where the plane is actually going.
		var v := linear_velocity
		if v.length() > 1.0 and lift < 1.0:
			want += forward.cross(v.normalized()) * (1.0 - lift) * 3.0
		angular_velocity = angular_velocity.lerp(want, clampf(RESPONSE * delta, 0.0, 1.0))
	else:
		# On the runway the wheels carry it: the prop pulls it along and the
		# yaw steers the nose wheel.
		apply_central_force(forward * (_speed - forward_speed) / delta * mass)
		# Only A / D steer on the ground -- not the camera. The rudder turns
		# with the nose wheel; the ailerons stay still; the elevator still
		# shows a pull for take-off.
		var steer_keys := _axis(KEY_A, KEY_D) if active else 0.0 # + = right
		steering = -steer_keys * STEER
		_asked.y = -steer_keys * deg_to_rad(turn_rate)
		_asked.z = 0.0


# Manual: the arrows ask for pitch and roll rates directly.
func _manual_turn(b: Basis) -> Vector3:
	if not active:
		return Vector3.ZERO
	var nose_up := _axis(KEY_UP, KEY_DOWN) * deg_to_rad(turn_rate)
	var roll := _axis(KEY_LEFT, KEY_RIGHT) * deg_to_rad(roll_rate)
	return -b.x * nose_up + b.z * roll


# Arcade: turn toward the aim's heading (a level turn) and climb or dive
# toward its elevation, each at up to turn_rate, and bank into the turn (as a
# real plane would to make it) -- wings level again once the nose is on the
# aim. (Swinging the nose straight at an aim behind dipped through the turn.)
func _aim_turn(b: Basis, bank_into_turns: bool) -> Vector3:
	if not active:
		return Vector3.ZERO
	var aim := aim_override
	if aim == Vector3.ZERO:
		var cam := get_viewport().get_camera_3d()
		if not cam:
			return Vector3.ZERO
		# Where the camera looks, lifted by its resting look-down angle.
		var look := -cam.global_basis.z
		var elevation := asin(clampf(look.y, -1.0, 1.0)) + camera_pitch
		var heading := atan2(look.x, look.z)
		aim = Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation))
	aim = aim.normalized()
	var forward := b.z
	var max_rate := deg_to_rad(turn_rate)
	var heading_error := wrapf(atan2(aim.x, aim.z) - atan2(forward.x, forward.z), -PI, PI)
	var climb_error := asin(clampf(aim.y, -1.0, 1.0)) - asin(clampf(forward.y, -1.0, 1.0))
	# About the vertical to turn; about the horizontal "right" to climb.
	var right := forward.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.05 else -b.x
	var turn := Vector3.UP * clampf(heading_error * 3.0, -max_rate, max_rate) + right * clampf(climb_error * 3.0, -max_rate, max_rate)
	turn = turn.limit_length(max_rate)

	if not bank_into_turns:
		return turn
	# Bank by the heading still to turn; level when there's none -- the short
	# way round, from any roll (the full angle, so upside down reads as 180).
	var want_bank := clampf(-heading_error * 2.0, -deg_to_rad(max_bank), deg_to_rad(max_bank))
	var bank := atan2(b.x.y, b.y.y) # + = banked right
	var roll := clampf(wrapf(want_bank - bank, -PI, PI) * 4.0, -deg_to_rad(roll_rate), deg_to_rad(roll_rate))
	return turn + forward * roll


func _process(delta: float) -> void:
	# Prop: idles at 10 rev/s, up to 40 at full throttle; the disc fades in as
	# the blades blur.
	var rev_per_s := 10.0 + 30.0 * throttle if active or throttle > 0.0 else 0.0
	_prop_angle = wrapf(_prop_angle + rev_per_s * TAU * delta, 0.0, TAU)
	_prop.rotation.z = _prop_angle
	var disc_mat := _prop_disc.get_active_material(0) as StandardMaterial3D
	if disc_mat:
		disc_mat.albedo_color.a = clampf((rev_per_s - 8.0) / 60.0, 0.0, 0.35)
	# The control surfaces show what's being asked of them.
	var roll := clampf(_asked.z / deg_to_rad(roll_rate), -1.0, 1.0) * 0.4
	var nose_up := clampf(-_asked.x / deg_to_rad(turn_rate), -1.0, 1.0) * 0.4
	var yaw_right := clampf(-_asked.y / deg_to_rad(turn_rate), -1.0, 1.0) * 0.4
	var k := clampf(12.0 * delta, 0.0, 1.0)
	_aileron_left.rotation.x = lerpf(_aileron_left.rotation.x, -roll, k)
	_aileron_right.rotation.x = lerpf(_aileron_right.rotation.x, roll, k)
	_elevator.rotation.x = lerpf(_elevator.rotation.x, nose_up, k)
	_rudder.rotation.y = lerpf(_rudder.rotation.y, yaw_right, k)
