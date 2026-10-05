extends VehicleBody3D
# An arcade stunt plane on stock nodes: a VehicleBody3D whose VehicleWheel3D
# landing gear handles the runway, and a game-style flight controller in the
# air -- no aerodynamics, no stall. Past take-off speed the plane flies where
# its nose points at the throttle's speed, and the nose turns at a set rate,
# banking into the turn. Nothing engine-specific: it flies the same on PhysX
# and Jolt.
#
# Two control modes, C to switch:
#   Arcade   the plane flies toward wherever the camera points (mouse aim;
#            pull the mouse back to aim up); Q / E roll; A / D yaw.
#   Manual   Up / Down pitch (Down = nose up), Left / Right roll (Q / E too),
#            A / D yaw; the camera is free.
#   Both     W / S throttle (it stays where you leave it), Space wheel
#            brakes, R back to the runway (vehicle_swap.gd).
#
# Take-off: throttle up, and past take-off speed aim (or pull) the nose up.
# Landing: throttle down and fly it onto the runway; below take-off speed on
# the wheels it's a ground vehicle again.

enum ControlMode { ARCADE, MANUAL }

@export var control_mode := ControlMode.ARCADE:
	set(value):
		control_mode = value
		# Arcade: the camera is the aim -- it mustn't chase the heading, and
		# the mouse aims like a flight stick over a wide range.
		camera_follow_heading = value == ControlMode.MANUAL
		camera_free_aim = value == ControlMode.ARCADE
@export var max_speed := 70.0 # m/s at full throttle
@export var takeoff_speed := 24.0 # m/s; in the air it never flies slower
@export var acceleration := 8.0 # m/s^2 toward the throttle's speed
@export var turn_rate := 100.0 # deg/s the nose turns at, at most
@export var roll_rate := 220.0 # deg/s
@export var max_bank := 65.0 # deg the plane banks into a turn

# For the chase camera (vehicle_chase_camera.gd).
var camera_distance := 16.0
var camera_follow_heading := false
var camera_free_aim := true

# Only the active vehicle reads input (vehicle_swap.gd).
var active := false
var throttle := 0.0
# Tests aim with this instead of the camera (world direction; zero = camera).
var aim_override := Vector3.ZERO

const RESPONSE := 8.0 # how quickly the rotation follows what's asked, 1/s
const VELOCITY_GRIP := 5.0 # how quickly the velocity swings onto the nose, 1/s
const CLIMB_COST := 15.0 # m/s slower pointing straight up (faster straight down)
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
	# (Off the ground but slow is a spawn or reset settling onto its wheels,
	# not flight.)
	var flying := forward_speed >= takeoff_speed or (not on_ground and forward_speed > takeoff_speed * 0.5)

	# Speed along the nose: toward the throttle's, a bit slower climbing and
	# faster diving -- and in the air, never below take-off speed.
	_speed = move_toward(forward_speed, throttle * max_speed - forward.y * CLIMB_COST, acceleration * delta)
	if flying and not on_ground:
		_speed = maxf(_speed, takeoff_speed)

	# The rotation asked for, in world space.
	var want := _manual_turn(b) if control_mode == ControlMode.MANUAL else _aim_turn(b)
	if active:
		want += forward * _axis(KEY_Q, KEY_E) * deg_to_rad(roll_rate)
		want -= b.y * _axis(KEY_A, KEY_D) * deg_to_rad(turn_rate) * 0.5
	_asked = b.inverse() * want

	if flying:
		# The velocity follows the nose, and the wing holds the plane up.
		linear_velocity = linear_velocity.lerp(forward * _speed, clampf(VELOCITY_GRIP * delta, 0.0, 1.0))
		apply_central_force(-get_gravity() * mass)
		angular_velocity = angular_velocity.lerp(want, clampf(RESPONSE * delta, 0.0, 1.0))
	else:
		# On the runway the wheels carry it: the prop pulls it along and the
		# yaw steers the nose wheel.
		apply_central_force(forward * (_speed - forward_speed) / delta * mass * 0.5)
		steering = clampf(_asked.y / deg_to_rad(turn_rate), -1.0, 1.0) * STEER


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
func _aim_turn(b: Basis) -> Vector3:
	if not active:
		return Vector3.ZERO
	var aim := aim_override
	if aim == Vector3.ZERO:
		var cam := get_viewport().get_camera_3d()
		if not cam:
			return Vector3.ZERO
		aim = -cam.global_basis.z
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

	# Bank by the heading still to turn; level when there's none.
	var want_bank := clampf(-heading_error * 2.0, -deg_to_rad(max_bank), deg_to_rad(max_bank))
	var bank := asin(clampf(b.x.y, -1.0, 1.0)) # + = banked right
	var roll := clampf((want_bank - bank) * 4.0, -deg_to_rad(roll_rate), deg_to_rad(roll_rate))
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
