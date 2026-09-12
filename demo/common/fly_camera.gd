extends RefCounted
class_name FlyCamera
# Shared free-fly camera behavior (WASD + hold-RMB-to-look), previously
# duplicated near-verbatim across ~9 demo scenes (physx_soft_body.gd,
# physx_playground.gd, cloth_wind.gd, physx_bridge.gd, physx_wind.gd,
# debris.gd, heightmap.gd, shape_scale.gd, gas_showcase.gd). A RefCounted
# helper (not a Camera3D subclass/script) because several of those scenes
# also need the mouse-capture state and yaw/pitch for their OWN input
# handling (e.g. a mouse-look-aimed blast) -- composition lets a scene keep
# its own _unhandled_input for scene-specific keys while delegating exactly
# the fly/look mechanics here, instead of every scene re-implementing it.
#
#   WASD          fly
#   Space/Ctrl    up/down
#   Shift         faster
#   Hold RMB      mouse-look
#
# Usage:
#   var fly := FlyCamera.new(_cam)          # after _cam.position/look_at is set
#   func _process(delta): fly.process(delta)
#   func _unhandled_input(event): fly.handle_input(event)

var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var speed := 8.0
var fast_multiplier := 3.0
var mouse_sensitivity := 0.0025

func _init(p_cam: Camera3D, p_speed: float = 8.0) -> void:
	cam = p_cam
	speed = p_speed
	yaw = cam.rotation.y
	pitch = cam.rotation.x

func process(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z -= 1
	if Input.is_key_pressed(KEY_S): mv.z += 1
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_SPACE): mv.y += 1
	if Input.is_key_pressed(KEY_CTRL): mv.y -= 1
	var spd := speed * (fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	cam.rotation = Vector3(pitch, yaw, 0.0)
	if mv != Vector3.ZERO:
		cam.position += (cam.transform.basis * mv).normalized() * spd * delta

# Returns true if this event was the RMB-look mechanic (caller can early-out);
# false for anything else (including mouse motion while RMB isn't held), so
# the caller's own _unhandled_input can still see/handle LMB, number keys, etc.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		return true
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.5, 1.5)
		return true
	return false
