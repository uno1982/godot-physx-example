extends Node3D
# Free-look third-person chase camera. Tracks the target's POSITION only, not
# its rotation -- a camera rigidly parented to the car (the original attempt)
# rotates with every turn, so the car looks like it's endlessly spinning even
# on an ordinary corner, since there's no independent reference frame to judge
# against. Decoupling position-follow from rotation fixes that, and letting
# the mouse freely orbit (captured by default, like a normal third-person
# driving game) gives a real reference frame the player controls.
#
#   Mouse    orbit look (captured by default)
#   Esc      release mouse
#   Click    recapture

@export var target_path: NodePath
@export var height := 2.0
@export var follow_speed := 6.0 # position lerp speed, higher = snappier
@export var mouse_sensitivity := 0.0025
# Swinging behind a target whose `camera_follow_heading` is true (the plane):
# how fast, and how long after the last mouse look it waits.
@export var heading_follow_speed := 2.0
@export var heading_follow_delay := 1.5 # s

var yaw := 0.0
# NOTE: positive pitch looks DOWN here, negative looks UP -- inverted from the
# usual convention. SpringArm3D is rotated 180 degrees (see the scene) so it
# extends toward the car's rear instead of its front, and that flip inverts
# the composed pitch response too (confirmed empirically: pitch=+0.5 produced
# a downward-pointing forward vector, not upward). Compensated here instead
# of un-composing the rotation math, since this was verified directly against
# the real transform rather than re-derived by hand.
var pitch := 0.25 # slight default downward tilt, looking down at the car
var _target: Node3D
var _default_spring_length := 0.0
var _since_mouse_look := 100.0

@onready var _spring_arm: SpringArm3D = $SpringArm3D

func _ready() -> void:
	_default_spring_length = _spring_arm.spring_length
	_target = get_node(target_path)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _target:
		global_position = _target.global_position + Vector3(0, height, 0)
	rotation = Vector3(pitch, yaw, 0.0)

# For swapping which car the camera follows at runtime (see vehicle_swap.gd)
# -- target_path alone only takes effect in _ready(), so switching targets
# later needs a real setter, not just reassigning the exported path.
# A target can ask for its own camera distance (`camera_distance`) and for the
# camera to swing in behind it (`camera_follow_heading`) -- the plane does both.
func set_target(p_target: Node3D) -> void:
	_target = p_target
	var distance = p_target.get("camera_distance")
	_spring_arm.spring_length = distance if distance != null else _default_spring_length
	# A target that aims with the camera starts aimed straight ahead of it --
	# or it would turn toward wherever the camera last looked -- looking down
	# at it by its camera_pitch.
	if p_target.get("camera_free_aim") == true:
		var fwd := p_target.global_basis.z
		yaw = atan2(fwd.x, fwd.z)
		var look_down = p_target.get("camera_pitch")
		pitch = look_down if look_down != null else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		# + here, not the more usual - (see the pitch-inversion note above).
		# A target that aims with the camera (camera_free_aim: the plane in
		# arcade mode) needs to look well up and down too.
		var free_aim: bool = _target != null and _target.get("camera_free_aim") == true
		pitch = clampf(pitch + event.relative.y * mouse_sensitivity, -1.45 if free_aim else -0.6, 1.45 if free_aim else 1.2)
		_since_mouse_look = 0.0
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if not _target:
		return
	var target_pos := _target.global_position + Vector3(0, height, 0)
	global_position = global_position.lerp(target_pos, clampf(follow_speed * delta, 0.0, 1.0))
	_since_mouse_look += delta
	if _target.get("camera_follow_heading") and _since_mouse_look > heading_follow_delay:
		# yaw 0 sits behind a target facing +Z (the arm extends to its rear).
		var fwd := _target.global_basis.z
		if Vector2(fwd.x, fwd.z).length() > 0.1:
			yaw = lerp_angle(yaw, atan2(fwd.x, fwd.z), clampf(heading_follow_speed * delta, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0.0)
