extends VehicleBody3D
# A light prop plane on stock nodes: a VehicleBody3D whose VehicleWheel3D
# landing gear handles taxiing, take-off and landing, plus a small flight
# model applied as ordinary forces -- nothing engine-specific, so it flies the
# same on PhysX and Jolt.
#
# Flight model: each lifting surface (the two wing halves, the tailplane and
# the fin) is a flat plate at its own spot on the airframe. Every tick it
# takes the air flowing over it there (the body's velocity plus its spin --
# that's what gives the plane its damping and stability), works out its angle
# of attack, and gets lift (a straight lift curve that stalls past ~15
# degrees) and drag, applied with apply_force() at that spot. The ailerons,
# elevator and rudder change their surface's angle of attack, so the plane
# rolls, pitches and yaws because of where those forces land, not because a
# torque is dialed in. The prop's thrust fades with airspeed.
#
#   W / S          throttle up / down (it stays where you leave it)
#   Up / Down      stick forward / back: nose down / nose up
#   Left / Right   roll
#   A / D          rudder, and nose-wheel steering on the ground
#   Space          wheel brakes
#   R              back to the runway

@export var max_thrust := 3000.0 # N, static
@export var prop_top_speed := 75.0 # m/s, where the prop stops pulling
@export var throttle_rate := 0.6 # per second
@export var max_aileron := 0.35 # rad
@export var max_elevator := 0.4 # rad
@export var max_rudder := 0.4 # rad
@export var control_rate := 3.0 # rad/s the surfaces move at
@export var max_brake := 12.0
@export var max_steer := 0.4 # rad, nose wheel
@export var stall_angle_deg := 15.0
@export var control_effectiveness := 0.5 # angle of attack added per radian of deflection
@export var fuselage_drag_area := 0.35 # m^2, drag coefficient * frontal area
@export var air_density := 1.225 # kg/m^3

# For the chase camera (vehicle_chase_camera.gd).
var camera_distance := 16.0
var camera_follow_heading := true

# Only the active vehicle reads input (vehicle_swap.gd).
var active := false

var throttle := 0.0
var _aileron := 0.0
var _elevator := 0.0
var _rudder := 0.0
var _prop_angle := 0.0
var _spawn: Transform3D

# Lifting surfaces, in the plane's own space (nose +Z, up +Y, so the left
# wing is +X). pos: the surface's aerodynamic center; normal: its lift axis;
# area m^2; aspect: aspect ratio; incidence: built-in angle, rad; control:
# which control moves it, and sign: how that control's deflection adds to its
# angle of attack.
var _surfaces := [
	{"name": "wing_left", "pos": Vector3(2.6, 2.0, 1.0), "normal": Vector3(-0.05, 1, 0).normalized(), "area": 8.0, "aspect": 6.25, "incidence": deg_to_rad(2.0), "control": "aileron", "sign": 1.0},
	{"name": "wing_right", "pos": Vector3(-2.6, 2.0, 1.0), "normal": Vector3(0.05, 1, 0).normalized(), "area": 8.0, "aspect": 6.25, "incidence": deg_to_rad(2.0), "control": "aileron", "sign": -1.0},
	{"name": "tail", "pos": Vector3(0, 1.75, -3.4), "normal": Vector3(0, 1, 0), "area": 3.2, "aspect": 3.6, "incidence": deg_to_rad(-4.0), "control": "elevator", "sign": -1.0},
	{"name": "fin", "pos": Vector3(0, 2.5, -3.4), "normal": Vector3(1, 0, 0), "area": 1.3, "aspect": 1.6, "incidence": 0.0, "control": "rudder", "sign": 1.0},
]

@onready var _prop: Node3D = $Prop
@onready var _prop_disc: MeshInstance3D = $Prop/Disc
@onready var _aileron_left: Node3D = $AileronLeft
@onready var _aileron_right: Node3D = $AileronRight
@onready var _elevator_node: Node3D = $Elevator
@onready var _rudder_node: Node3D = $Rudder


func _ready() -> void:
	_spawn = global_transform


func reset_to_runway() -> void:
	throttle = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _spawn


func _axis(neg: Key, pos: Key) -> float:
	return (1.0 if Input.is_key_pressed(pos) else 0.0) - (1.0 if Input.is_key_pressed(neg) else 0.0)


func _physics_process(delta: float) -> void:
	var stick := Vector3.ZERO # x: roll right, y: nose up, z: yaw right
	brake = 0.0
	if active:
		throttle = clampf(throttle + _axis(KEY_S, KEY_W) * throttle_rate * delta, 0.0, 1.0)
		stick = Vector3(_axis(KEY_LEFT, KEY_RIGHT), _axis(KEY_UP, KEY_DOWN), _axis(KEY_A, KEY_D))
		brake = max_brake if Input.is_key_pressed(KEY_SPACE) else 0.0
		if global_position.y < -50.0:
			reset_to_runway()
	else:
		throttle = move_toward(throttle, 0.0, throttle_rate * delta)
	_aileron = move_toward(_aileron, stick.x * max_aileron, control_rate * delta)
	_elevator = move_toward(_elevator, stick.y * max_elevator, control_rate * delta)
	_rudder = move_toward(_rudder, stick.z * max_rudder, control_rate * delta)
	steering = -_rudder / max_rudder * max_steer
	engine_force = 0.0 # the prop pulls, not the wheels

	_apply_aero()
	_apply_thrust()


func _control(name: String) -> float:
	match name:
		"aileron":
			return _aileron
		"elevator":
			return _elevator
		"rudder":
			return _rudder
	return 0.0


func _apply_aero() -> void:
	var basis := global_basis
	var forward := basis.z.normalized()
	var stall := deg_to_rad(stall_angle_deg)
	for s in _surfaces:
		var r: Vector3 = basis * s.pos # offset from the body origin, world axes
		var v := linear_velocity + angular_velocity.cross(r - basis * center_of_mass)
		var n: Vector3 = (basis * s.normal).normalized()
		var f := (forward - n * forward.dot(n)).normalized() # chord, toward the nose
		var vf := v.dot(f)
		var vn := v.dot(n)
		var speed := Vector2(vf, vn).length()
		if speed < 0.5:
			continue
		# Air meets the surface from below when it moves down through it.
		var alpha: float = atan2(-vn, vf) + s.incidence
		# A deflected control surface adds lift as if the surface met the air
		# at a steeper angle -- but the surface still stalls by its own angle
		# (a deflection counted toward the stall made a down-going aileron
		# stall its wing and spin the plane).
		var deflection: float = _control(s.control) * s.sign * control_effectiveness
		var lift_slope: float = TAU * s.aspect / (s.aspect + 2.0)
		var cl_max: float = lift_slope * stall
		var cl_linear := clampf(lift_slope * (alpha + deflection), -cl_max * 1.3, cl_max * 1.3)
		var stalled := smoothstep(stall, stall + deg_to_rad(10.0), absf(alpha))
		var cl := lerpf(cl_linear, 0.9 * sin(2.0 * alpha), stalled)
		var cd: float = 0.02 + cl_linear * cl_linear / (PI * 0.8 * s.aspect) + 1.1 * sin(alpha) * sin(alpha) * stalled
		var q: float = 0.5 * air_density * speed * speed * s.area
		var u := (f * vf + n * vn) / speed # the surface's motion through the air
		var lift_dir := (n * vf - f * vn) / speed # square to it, on the lift side
		apply_force(lift_dir * (q * cl) - u * (q * cd), r)
	# The fuselage and gear: plain drag at the center of mass.
	var speed_total := linear_velocity.length()
	if speed_total > 0.5:
		apply_central_force(-linear_velocity * (0.5 * air_density * speed_total * fuselage_drag_area))


func _apply_thrust() -> void:
	var forward := global_basis.z.normalized()
	var airspeed := maxf(linear_velocity.dot(forward), 0.0)
	var thrust := throttle * max_thrust * clampf(1.0 - airspeed / prop_top_speed, 0.0, 1.0)
	apply_force(forward * thrust, global_basis * _prop.position)


func _process(delta: float) -> void:
	# Prop: idles at 10 rev/s, up to 40 at full throttle; the disc fades in as
	# the blades blur.
	var rev_per_s := 10.0 + 30.0 * throttle if active or throttle > 0.0 else 0.0
	_prop_angle = wrapf(_prop_angle + rev_per_s * TAU * delta, 0.0, TAU)
	_prop.rotation.z = _prop_angle
	var disc_mat := _prop_disc.get_active_material(0) as StandardMaterial3D
	if disc_mat:
		disc_mat.albedo_color.a = clampf((rev_per_s - 8.0) / 60.0, 0.0, 0.35)
	_aileron_left.rotation.x = -_aileron
	_aileron_right.rotation.x = _aileron
	_elevator_node.rotation.x = _elevator
	_rudder_node.rotation.y = _rudder


func airspeed() -> float:
	return linear_velocity.length()


func is_stalling() -> bool:
	var forward := global_basis.z.normalized()
	var up := global_basis.y.normalized()
	var v := linear_velocity
	if v.length() < 5.0 or not active:
		return false
	var alpha := atan2(-v.dot(up), v.dot(forward)) + deg_to_rad(2.0)
	return absf(alpha) > deg_to_rad(stall_angle_deg)
