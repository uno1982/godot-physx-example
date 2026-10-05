extends AnimatableBody3D
class_name MovingPlatform
# A platform that spins and/or travels back and forth on its own -- set it up
# in the Inspector, no AnimationPlayer needed. Characters (CharacterBody3D)
# and loose rigid bodies standing on it ride along, turning with it too.
#
#   spin       degrees per second about each local axis (Y turns a carousel)
#   travel     offset of the far end of the trip, from where it starts
#   period     seconds for a full there-and-back trip
#
# Moved in _physics_process, so the physics engine sees each step's motion
# and passes it on to whatever stands on top.

@export var spin := Vector3.ZERO
@export var travel := Vector3.ZERO
@export_range(0.5, 120.0, 0.1, "suffix:s") var period := 6.0

var _start: Transform3D
var _time := 0.0


func _ready() -> void:
	_start = transform


func _physics_process(delta: float) -> void:
	_time += delta
	var t := transform
	if spin != Vector3.ZERO:
		var turn := spin * delta * (PI / 180.0)
		t.basis = t.basis * Basis.from_euler(turn)
	if travel != Vector3.ZERO:
		# Smooth there-and-back: 0 at the start, 1 at the far end.
		var k := 0.5 - 0.5 * cos(TAU * _time / period)
		t.origin = _start.origin + _start.basis * (travel * k)
	transform = t
