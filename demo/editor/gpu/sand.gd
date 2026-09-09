extends Node3D

# Editor + runtime showcase for PhysXGranular3D. The pit, the sand volume and
# the character are all real scene nodes: select the "Sand" node to see its
# inspector, drag the domain / spawn-region gizmo handles to match the pit, and
# flip "solver" between Auto/MPM and PBD (CUDA) to compare. Press Play and it
# fills the pit; wade the character through it.
#
#   mouse           orbit camera            WASD  wade    SHIFT sprint   SPACE hop
#   F   drop the boulder in front of you    G  re-level    R  respawn
#   1-3 sand amount (40k / 70k / 100k)       ESC free mouse / quit

const COUNTS := [40000, 70000, 100000]
const WORLD_LAYER := 1 << 5

@onready var _sand: PhysXGranular3D = $Sand
@onready var _char: RigidBody3D = $Player
@onready var _char_mesh: Node3D = $Player/Skin
@onready var _boulder: RigidBody3D = $Boulder
@onready var _cam: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Label

var _yaw := 0.6
var _pitch := -0.35
var _cam_dist := 7.5
var _face := 0.0
var _char_home := Vector3.ZERO


func _ready() -> void:
	_char_home = _char.position
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("count="):
			_sand.particle_count = int(arg.substr(6))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _solver_name() -> String:
	match _sand.solver:
		PhysXGranular3D.SOLVER_PBD:
			return "PBD (CUDA)"
		PhysXGranular3D.SOLVER_MPM:
			return "MPM"
		_:
			return "MPM" if _sand.get_live_particle_count() > 0 else "Auto"


func _cam_basis() -> Basis:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


func _respawn_char() -> void:
	_char.linear_velocity = Vector3.ZERO
	_char.global_position = to_global(_char_home) + Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))


func _relevel() -> void:
	_sand.clear()
	_sand.spawn()


func _set_count(n: int) -> void:
	_sand.particle_count = n
	_relevel()


func _drop_boulder() -> void:
	_boulder.gravity_scale = 1.0
	_boulder.linear_velocity = Vector3.ZERO
	_boulder.angular_velocity = Vector3.ZERO
	var flat := _cam_basis()
	var fwd := -Vector3(flat.z.x, 0, flat.z.z).normalized()
	_boulder.global_position = _char.global_position + fwd * 1.4 + Vector3.UP * 2.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.2, 0.3)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(3.0, _cam_dist - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(14.0, _cam_dist + 0.5)
		elif event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F: _drop_boulder()
			KEY_G: _relevel()
			KEY_R: _respawn_char()
			KEY_1: _set_count(COUNTS[0])
			KEY_2: _set_count(COUNTS[1])
			KEY_3: _set_count(COUNTS[2])
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()


func _physics_process(delta: float) -> void:
	var flat := _cam_basis()
	var fwd := -Vector3(flat.z.x, 0, flat.z.z).normalized()
	var right := Vector3(flat.x.x, 0, flat.x.z).normalized()
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): wish += fwd
	if Input.is_key_pressed(KEY_S): wish -= fwd
	if Input.is_key_pressed(KEY_D): wish += right
	if Input.is_key_pressed(KEY_A): wish -= right
	wish = wish.limit_length(1.0)

	var run: float = 6.0 if Input.is_key_pressed(KEY_SHIFT) else 3.4
	var v := _char.linear_velocity
	v.x = move_toward(v.x, wish.x * run, 22.0 * delta)
	v.z = move_toward(v.z, wish.z * run, 22.0 * delta)
	_char.linear_velocity = v

	if Input.is_key_pressed(KEY_SPACE) and _char.linear_velocity.y < 2.0:
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				_char.global_position, _char.global_position + Vector3.DOWN * 1.3,
				1, [_char.get_rid()]))
		# grounded on the floor, or wading in the sand bed
		if hit or _char.position.y < 1.4:
			var jv := _char.linear_velocity
			jv.y = 6.5
			_char.linear_velocity = jv

	if wish.length() > 0.1:
		_face = lerp_angle(_face, atan2(wish.x, wish.z), 12.0 * delta)


func _process(delta: float) -> void:
	var pivot := _char.global_position + Vector3.UP * 0.7
	var back := (_cam_basis().z + Vector3.UP * 0.15).normalized()
	var reach := _cam_dist
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(pivot, pivot + back * _cam_dist, WORLD_LAYER))
	if hit:
		reach = maxf(1.4, pivot.distance_to(hit.position) - 0.35)
	var cur := (_cam.global_position - pivot).length()
	var lp: float = 0.0005 if reach < cur else 0.05
	_cam.global_position = pivot + back * lerpf(cur, reach, 1.0 - pow(lp, delta))
	_cam.look_at(pivot)

	var speed := Vector2(_char.linear_velocity.x, _char.linear_velocity.z).length()
	_char_mesh.rotation.y = _face
	_char_mesh.rotation.x = lerp(_char_mesh.rotation.x, clampf(speed * 0.04, 0.0, 0.3), 8.0 * delta)

	if _boulder.position.y < -30.0 and _boulder.gravity_scale > 0.0:
		_boulder.gravity_scale = 0.0
		_boulder.linear_velocity = Vector3.ZERO
		_boulder.position = Vector3(0, -60, 0)
	if _char.position.y < -6.0:
		_respawn_char()

	_hud.text = "PhysXGranular3D · %s   %d grains   FPS %d\nWASD wade · SHIFT sprint · SPACE hop · F boulder · G re-level · 1-3 amount" % [
		_solver_name(), _sand.get_live_particle_count(), Engine.get_frames_per_second()]
