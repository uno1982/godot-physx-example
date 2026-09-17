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

@onready var _spring_arm: SpringArm3D = $SpringArm3D

func _ready() -> void:
	_target = get_node(target_path)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _target:
		global_position = _target.global_position + Vector3(0, height, 0)
	rotation = Vector3(pitch, yaw, 0.0)

# For swapping which car the camera follows at runtime (see vehicle_swap.gd)
# -- target_path alone only takes effect in _ready(), so switching targets
# later needs a real setter, not just reassigning the exported path.
func set_target(p_target: Node3D) -> void:
	_target = p_target

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		# + here, not the more usual - (see the pitch-inversion note above).
		pitch = clampf(pitch + event.relative.y * mouse_sensitivity, -0.6, 1.2)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if not _target:
		return
	var target_pos := _target.global_position + Vector3(0, height, 0)
	global_position = global_position.lerp(target_pos, clampf(follow_speed * delta, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0.0)
