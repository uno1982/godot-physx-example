extends Node3D
# Free-fly camera for watching the gas tornado from any angle, matching the
# WASD + hold-RMB-to-look pattern from demo/cpu/physx_soft_body.gd.
#
#   WASD          fly
#   Space/Ctrl    up/down
#   Shift         faster
#   Hold RMB      mouse-look

@onready var _cam: Camera3D = $Camera3D
@onready var _gas: Node3D = $PhysXGas3D
@onready var _diag_label: Label = $HUD/Label

var _cam_yaw := 0.0
var _cam_pitch := 0.0

const FLY_SPEED := 6.0
const MOUSE_SENS := 0.0025

func _ready() -> void:
	_cam_yaw = _cam.rotation.y
	_cam_pitch = _cam.rotation.x

func _process(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z -= 1
	if Input.is_key_pressed(KEY_S): mv.z += 1
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_SPACE): mv.y += 1
	if Input.is_key_pressed(KEY_CTRL): mv.y -= 1
	var spd := FLY_SPEED * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_cam.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	if mv != Vector3.ZERO:
		_cam.position += (_cam.transform.basis * mv).normalized() * spd * delta
	_update_diag()

# Live diagnostics for the "drag stops emitting" investigation -- shows
# whether the domain has actually configured/settled and where the emitters
# think they are, without needing to copy console output.
func _update_diag() -> void:
	if _gas == null or _diag_label == null:
		return
	var configured: bool = _gas.call("is_domain_configured")
	var anchor: Vector3 = _gas.call("get_configured_domain_anchor")
	var max_density: float = _gas.call("get_last_max_density")
	var lines := ["configured=%s  anchor=%s  max_density=%.4f" % [configured, anchor, max_density]]
	for child in _gas.get_children():
		if child.get_class() == "PhysXGasEmitter3D" or (child.get("enabled") != null and child.get("density") != null):
			lines.append("%s enabled=%s pos=%s" % [child.name, child.get("enabled"), child.global_position])
	# The FogVolume is an INTERNAL child (created lazily by PhysXGas3D) --
	# get_children(true) is needed to see it at all. Shows whether it's even
	# been created, and if so, where/how big it thinks it is.
	var found_fog := false
	for child in _gas.get_children(true):
		if child.get_class() == "FogVolume":
			found_fog = true
			lines.append("FogVolume pos=%s size=%s visible=%s" % [child.global_position, child.get("size"), child.visible])
	if not found_fog:
		lines.append("FogVolume: NOT FOUND (never created?)")
	_diag_label.text = "PhysXGas3D -- fire tornado\nWASD fly - Space/Ctrl up-down - Shift fast - hold RMB to look\n" + "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * MOUSE_SENS
		_cam_pitch = clampf(_cam_pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
