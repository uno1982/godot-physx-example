extends Camera3D
# Drop-in node script for a node-authored editor scene: attach directly to a
# Camera3D and it free-flies (WASD, Space/Ctrl up-down, Shift fast, hold RMB
# to look). Delegates to FlyCamera (demo/common/fly_camera.gd) -- this file
# stays a thin adapter, not a second copy of the movement/look logic.

const FlyCamera = preload("res://demo/common/fly_camera.gd")

@export var fly_speed := 8.0

var _fly: FlyCamera

func _ready() -> void:
	_fly = FlyCamera.new(self, fly_speed)

func _process(delta: float) -> void:
	_fly.process(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _fly.handle_input(event):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
