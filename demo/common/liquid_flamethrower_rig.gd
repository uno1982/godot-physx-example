extends Camera3D
# Drop-in node script for a node-authored flamethrower demo built on the
# liquid solver: attach to a Camera3D with a muzzle-mounted PhysXParticleFluid3D
# child. Delegates fly/look to FlyCamera like fly_camera_node.gd; adds
# continuous-fire-on-hold-LMB on top, independent of whether RMB-look is
# currently captured -- same pattern as this session's other aim rigs, just
# toggling PhysXParticleFluid3D.emitting instead of a gas emitter's enabled.

const FlyCamera = preload("res://demo/common/fly_camera.gd")

@export var fly_speed := 8.0
@export var fluid_path: NodePath

var _fly: FlyCamera
var _fluid: PhysXParticleFluid3D

func _ready() -> void:
	_fly = FlyCamera.new(self, fly_speed)
	_fluid = get_node(fluid_path)

func _process(delta: float) -> void:
	_fly.process(delta)
	_fluid.emitting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _unhandled_input(event: InputEvent) -> void:
	if _fly.handle_input(event):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
