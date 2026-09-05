extends Node3D

# Node-authored debris showcase -- select "Debris" to tune its inspector
# (chunk_count, chunk sizes, impulse, spread, max_active, lifetime) and see the
# viewport update. Press Play and shoot the walls and floor.
#
#   W A S D / arrows  move        SPACE  jump        mouse  look
#   left click        shoot -- raycasts and bursts debris at the hit point
#   right click       fire a singularity -- drifts forward, sucking in every
#                      dynamic body it passes near (including debris chunks,
#                      which have no Node of their own) into a swirling orbit,
#                      then pulses everything back out once it's gathered enough
#   R  reset      ESC  release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025
const GRAVITY := 18.0

@onready var _debris: PhysXChunkEmitter3D = $Debris
@onready var _vortex: PhysXVortex3D = $Vortex
@onready var _char: CharacterBody3D = $Player
@onready var _cam: Camera3D = $Player/Camera3D
@onready var _hud: Label = $HUD/Label

var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_shoot()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_fire_vortex()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()

func _shoot() -> void:
	var from := _cam.global_position
	var to := from + _cam.global_transform.basis.z * -60.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [_char]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit:
		# Nudge off the surface along the normal so chunks don't spawn embedded.
		_debris.spawn_at(hit.position + hit.normal * 0.05, hit.normal)

func _fire_vortex() -> void:
	if _vortex.is_active():
		return
	# The vortex node itself is the traveling projectile now -- no separate
	# grenade body, so no impact/timeout race and nothing to free mid-flight.
	var fwd := (-_cam.global_transform.basis.z).normalized()
	_vortex.launch(_cam.global_position + fwd * 1.0, fwd)

func _physics_process(delta: float) -> void:
	_char.rotation.y = _yaw
	_cam.rotation.x = _pitch

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	var dir := (_char.transform.basis * input).normalized()

	var v := _char.velocity
	v.x = dir.x * SPEED
	v.z = dir.z * SPEED
	if _char.is_on_floor():
		# No downward "stick" -- see the bridge demo's notes on why that jitters
		# the camera and fights depenetration.
		v.y = JUMP if Input.is_key_pressed(KEY_SPACE) else 0.0
	else:
		v.y -= GRAVITY * delta
	_char.velocity = v
	_char.move_and_slide()

func _process(_dt: float) -> void:
	_hud.text = "PhysXChunkEmitter3D showcase (node-based)   L-click shoot   R-click singularity   R reset   ESC\nactive chunks: %d / %d     FPS: %d" % [
		_debris.get_active_chunk_count(), _debris.max_active, Engine.get_frames_per_second()]
