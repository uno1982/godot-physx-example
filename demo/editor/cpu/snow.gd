extends Node3D

# Editor + runtime showcase: the blue capsule wading through fresh snow.
#
# Four layers, each the right tool for its job:
#
#   1. TERRAIN       -- one FastNoiseLite field builds a HeightMapShape3D (the
#      character and every chunk collide with it) and a matching visual mesh.
#
#   2. TRAMPLE TRAIL -- a plain shader trick, no physics. snow.gd keeps a small
#      top-down depth texture; the ground shader sinks the surface and packs the
#      snow darker wherever anything has walked. Persistent, slowly refills.
#
#   3. PLOUGHED SNOW -- a PhysXChunkEmitter3D at the character's feet, emitting
#      light sphere "snow clumps" as they wade. Real GPU rigid bodies: the plough
#      collider shoves them out of the path, they tumble down the slopes, collide
#      and pile. A heavier burst on each footfall.
#
#   4. FALLING SNOW  -- GPUParticles3D. Ambient only.
#
#   mouse  orbit    WASD wade    SHIFT sprint    SPACE hop
#   F  lob a snowball      H  clear the trail      R  respawn
#   ESC  free mouse / quit

const WORLD_LAYER := 1 << 5
const MAP_RES := 220
const FIELD_SIZE := 46.0
const TRAIL_REFILL := 0.005

const TERRAIN_N := 65
const TERRAIN_SPAN := 46.0
const TERRAIN_AMP := 1.4
const MESH_N := 200

@onready var _snow: PhysXChunkEmitter3D = $Player/Snow
@onready var _char: RigidBody3D = $Player
@onready var _char_mesh: Node3D = $Player/Skin
@onready var _ball: RigidBody3D = $Snowball
@onready var _cam: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _ground_mat: ShaderMaterial = $Ground/MeshInstance3D.material_override

var _yaw := 0.5
var _pitch := -0.30
var _cam_dist := 7.0
var _face := 0.0
var _char_home := Vector3.ZERO
var _step_accum := 0.0

var _heights: PackedFloat32Array
var _tn_lo: FastNoiseLite
var _tn_hi: FastNoiseLite

var _map: Image
var _map_tex: ImageTexture
var _map_dirty := false
var _refill_accum := 0.0


func _ready() -> void:
	_char_home = _char.position
	_build_terrain()

	_map = Image.create(MAP_RES, MAP_RES, false, Image.FORMAT_RF)
	_map.fill(Color(0, 0, 0))
	_map_tex = ImageTexture.create_from_image(_map)
	_ground_mat.set_shader_parameter("disp_tex", _map_tex)
	_ground_mat.set_shader_parameter("field_center", Vector2.ZERO)
	_ground_mat.set_shader_parameter("field_size", FIELD_SIZE)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _cam_basis() -> Basis:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


# --- terrain --------------------------------------------------------------

func _terrain_sample(wx: float, wz: float) -> float:
	var lo := _tn_lo.get_noise_2d(wx, wz)
	var hi := _tn_hi.get_noise_2d(wx, wz)
	var r := (wx * wx + wz * wz) / (TERRAIN_SPAN * TERRAIN_SPAN * 0.25)
	var rim: float = 0.5 * maxf(0.0, r - 0.4)
	return (lo * 0.7 + hi * 0.3 + rim) * TERRAIN_AMP


func _build_terrain() -> void:
	_tn_lo = FastNoiseLite.new()
	_tn_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tn_lo.frequency = 0.045
	_tn_hi = FastNoiseLite.new()
	_tn_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tn_hi.frequency = 0.16

	var cstep := TERRAIN_SPAN / float(TERRAIN_N - 1)
	var chalf := (TERRAIN_N - 1) * 0.5
	_heights = PackedFloat32Array()
	_heights.resize(TERRAIN_N * TERRAIN_N)
	for iz in range(TERRAIN_N):
		for ix in range(TERRAIN_N):
			_heights[iz * TERRAIN_N + ix] = _terrain_sample((ix - chalf) * cstep, (iz - chalf) * cstep)
	var shape := HeightMapShape3D.new()
	shape.map_width = TERRAIN_N
	shape.map_depth = TERRAIN_N
	shape.map_data = _heights
	var cs: CollisionShape3D = $Ground/CollisionShape3D
	cs.shape = shape
	cs.scale = Vector3(cstep, 1.0, cstep)
	cs.position = Vector3.ZERO

	var mstep := TERRAIN_SPAN / float(MESH_N - 1)
	var mhalf := (MESH_N - 1) * 0.5
	var verts := PackedVector3Array()
	verts.resize(MESH_N * MESH_N)
	for iz in range(MESH_N):
		for ix in range(MESH_N):
			var wx := (ix - mhalf) * mstep
			var wz := (iz - mhalf) * mstep
			verts[iz * MESH_N + ix] = Vector3(wx, _terrain_sample(wx, wz), wz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(MESH_N - 1):
		for x in range(MESH_N - 1):
			var i0 := z * MESH_N + x
			for k in [i0, i0 + 1, i0 + MESH_N, i0 + 1, i0 + MESH_N + 1, i0 + MESH_N]:
				st.add_vertex(verts[k])
	st.generate_normals()
	$Ground/MeshInstance3D.mesh = st.commit()


func _ground_y(wx: float, wz: float) -> float:
	return _terrain_sample(wx, wz)


# --- trample map ---------------------------------------------------------

func _stamp(world_pos: Vector3, radius_m: float, strength: float) -> void:
	var uv := Vector2(world_pos.x, world_pos.z) / FIELD_SIZE + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return
	var c := uv * float(MAP_RES)
	var r := maxf(1.0, radius_m / FIELD_SIZE * float(MAP_RES))
	for y in range(maxi(0, int(c.y - r)), mini(MAP_RES - 1, int(c.y + r)) + 1):
		for x in range(maxi(0, int(c.x - r)), mini(MAP_RES - 1, int(c.x + r)) + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if d >= 1.0:
				continue
			var w: float = (1.0 - d * d) * strength
			if w > _map.get_pixel(x, y).r:
				_map.set_pixel(x, y, Color(w, 0, 0))
	_map_dirty = true


func _refill(delta: float) -> void:
	_refill_accum += delta
	if _refill_accum < 0.1:
		return
	var step := TRAIL_REFILL * _refill_accum
	_refill_accum = 0.0
	var y0 := randi() % MAP_RES
	for i in range(24):
		var y := (y0 + i) % MAP_RES
		for x in range(MAP_RES):
			var v := _map.get_pixel(x, y).r
			if v > 0.0:
				_map.set_pixel(x, y, Color(maxf(0.0, v - step), 0, 0))
	_map_dirty = true


func _clear_trail() -> void:
	_map.fill(Color(0, 0, 0))
	_map_dirty = true


# --- interactions ------------------------------------------------------

func _respawn_char() -> void:
	_char.linear_velocity = Vector3.ZERO
	_char.global_position = to_global(_char_home) + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))


func _lob_snowball() -> void:
	_ball.gravity_scale = 1.5
	_ball.angular_velocity = Vector3.ZERO
	var flat := _cam_basis()
	var fwd := -Vector3(flat.z.x, 0, flat.z.z).normalized()
	_ball.global_position = _char.global_position + fwd * 1.2 + Vector3.UP * 1.6
	_ball.linear_velocity = fwd * 9.5 + Vector3.UP * 3.2


func _footfall() -> void:
	var v := _char.linear_velocity
	var travel := Vector3(v.x, 0, v.z).normalized()
	var foot := _char.global_position + Vector3.DOWN * 0.85
	_snow.spawn_at(foot, (Vector3.UP * 0.5 - travel * 0.6).normalized(), 16)
	_stamp(foot, 0.5, 0.9)


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
			KEY_F: _lob_snowball()
			KEY_R: _respawn_char()
			KEY_H: _clear_trail()
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

	var run: float = 5.0 if Input.is_key_pressed(KEY_SHIFT) else 3.0
	var v := _char.linear_velocity
	v.x = move_toward(v.x, wish.x * run, 18.0 * delta)
	v.z = move_toward(v.z, wish.z * run, 18.0 * delta)
	_char.linear_velocity = v

	var gy := _ground_y(_char.global_position.x, _char.global_position.z)
	var grounded := _char.global_position.y - gy < 1.15
	if Input.is_key_pressed(KEY_SPACE) and _char.linear_velocity.y < 2.0 and grounded:
		var jv := _char.linear_velocity
		jv.y = 6.0
		_char.linear_velocity = jv

	var speed := Vector2(_char.linear_velocity.x, _char.linear_velocity.z).length()

	# ploughed-snow emitter: only while wading -- emission_rate stays whatever
	# the node/inspector has it set to, we just gate it on/off with stepping
	_snow.emitting = grounded and speed > 0.4

	if grounded:
		_stamp(_char.global_position + Vector3.DOWN * 0.9, 0.36, 0.55)
	if speed > 0.6 and grounded:
		_step_accum += speed * delta
		if _step_accum > 1.4:
			_step_accum = 0.0
			_footfall()
	else:
		_step_accum = 1.4

	if _ball.gravity_scale > 0.0 and _ball.position.y < gy + 0.3:
		_stamp(_ball.global_position, 0.5, 0.7)

	if wish.length() > 0.1:
		_face = lerp_angle(_face, atan2(wish.x, wish.z), 12.0 * delta)

	_refill(delta)


func _process(delta: float) -> void:
	if _map_dirty:
		_map_tex.update(_map)
		_map_dirty = false

	$Snowfall.global_position = Vector3(_char.global_position.x, _char.global_position.y + 8.0, _char.global_position.z)

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

	if _ball.position.y < -20.0 and _ball.gravity_scale > 0.0:
		_ball.gravity_scale = 0.0
		_ball.linear_velocity = Vector3.ZERO
		_ball.position = Vector3(0, -40, 0)
	if _char.position.y < -8.0:
		_respawn_char()

	_hud.text = "PhysXChunkEmitter3D snow clumps + heightmap trail   %d clumps · FPS %d\nWASD wade · SHIFT sprint · SPACE hop · F snowball · H clear trail" % [
		_snow.get_active_chunk_count(), Engine.get_frames_per_second()]
