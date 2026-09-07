extends Node3D

# A FleX-style ball pit: 2k-10k small rigid spheres (bare PhysicsServer3D RID
# bodies, one shared sphere shape, MultiMesh-rendered) settling into a friction
# pile in a dark pit. Wade a physics character through them and watch them
# scatter -- runs on the GPU rigid-body solver (or the CPU one).
#
#   mouse           orbit camera
#   WASD            run through the pit      SHIFT sprint      SPACE hop
#   F   fling a wrecking ball through the pile
#   G   pour a fresh wave of balls from above
#   R   drop the character back in            1-3 ball count      ESC free mouse

const COUNTS := [2000, 5000, 10000]
const BALL_R := 0.16
const PIT := Vector3(7, 8, 7)   # inner half-extents (x, y, z)
const WALL := 0.8
const CHAR_R := 0.42
const CHAR_H := 1.9               # full capsule height

var _count := 2000
var _bodies: Array[RID] = []
var _shape: RID
var _space: RID
var _mm: MultiMesh
var _hud: Label
var _cam: Camera3D
var _yaw := 0.6
var _pitch := -0.35
var _cam_dist := 6.5
var _wreck: RigidBody3D
var _char: RigidBody3D
var _char_mesh: Node3D
var _face := 0.0
var _phys_ms := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("count="):
			_count = int(arg.substr(6))
	_build_world()
	_build_character()
	_space = get_world_3d().space
	_shape = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(_shape, BALL_R)
	_rebuild(_count)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.32, 0.40)
	e.ambient_light_energy = 0.18
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.ssao_enabled = true
	e.ssao_intensity = 2.5
	e.ssao_radius = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.25
	e.glow_bloom = 0.05
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 33, 0)
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 2.6
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 90.0
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, -145, 0)
	rim.light_color = Color(0.55, 0.65, 0.9)
	rim.light_energy = 0.7
	add_child(rim)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.10, 0.10, 0.115)
	wall_mat.roughness = 0.95
	# floor + 4 short walls, open top -- low enough to see the character over
	var wh := 3.0
	_static_box(Vector3(0, -WALL, 0), Vector3(PIT.x + WALL, WALL, PIT.z + WALL), wall_mat)
	for s in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along_x: bool = absf(s.x) > 0.5
		var half := Vector3(WALL, wh, PIT.z + WALL) if along_x else Vector3(PIT.x + WALL, wh, WALL)
		_static_box(s * Vector3(PIT.x + WALL, 0, PIT.z + WALL) + Vector3(0, wh - WALL, 0), half, wall_mat)
	# a dark floor slab beyond the pit so the camera looking over the rim
	# doesn't see the void
	var apron := StandardMaterial3D.new()
	apron.albedo_color = Color(0.06, 0.06, 0.07)
	apron.roughness = 1.0
	_static_box(Vector3(0, -WALL - 0.05, 0), Vector3(28, WALL, 28), apron)

	var mmi := MultiMeshInstance3D.new()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.82
	bmat.metallic = 0.05
	sm.material = bmat
	_mm.mesh = sm
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)

	_wreck = RigidBody3D.new()
	_wreck.mass = 1400.0
	_wreck.gravity_scale = 0.0
	_wreck.continuous_cd = true
	var wcs := CollisionShape3D.new()
	var wsp := SphereShape3D.new()
	wsp.radius = 2.2
	wcs.shape = wsp
	_wreck.add_child(wcs)
	var wmi := MeshInstance3D.new()
	var wsm := SphereMesh.new()
	wsm.radius = 2.2
	wsm.height = 4.4
	wmi.mesh = wsm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.06, 0.06, 0.07)
	wm.metallic = 1.0
	wm.roughness = 0.28
	wmi.material_override = wm
	_wreck.add_child(wmi)
	_wreck.position = Vector3(0, -80, 0)
	add_child(_wreck)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 300.0
	_cam.fov = 70.0
	add_child(_cam)

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


# A physics character: an upright capsule RigidBody3D. It has real mass, so
# it sinks into the pile and shoves balls as it wades -- rotation is locked so
# it stays on its feet.
func _build_character() -> void:
	_char = RigidBody3D.new()
	_char.mass = 24.0
	_char.lock_rotation = true
	_char.continuous_cd = true
	_char.linear_damp = 0.4
	_char.can_sleep = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CHAR_R
	cap.height = CHAR_H
	cs.shape = cap
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4
	_char.physics_material_override = pm
	_char.add_child(cs)

	_char_mesh = Node3D.new()
	_char.add_child(_char_mesh)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.05, 0.75, 0.9)
	skin.roughness = 0.5
	var body := MeshInstance3D.new()
	var bcap := CapsuleMesh.new()
	bcap.radius = CHAR_R
	bcap.height = CHAR_H
	body.mesh = bcap
	body.material_override = skin
	_char_mesh.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.28
	hs.height = 0.56
	head.mesh = hs
	head.position = Vector3(0, CHAR_H * 0.5 + 0.15, 0)
	head.material_override = skin
	_char_mesh.add_child(head)

	_char.position = Vector3(0, PIT.y + 4.0, PIT.z * 0.45)
	add_child(_char)


func _respawn_char() -> void:
	_char.linear_velocity = Vector3.ZERO
	_char.global_position = Vector3(randf_range(-4, 4), PIT.y + 4.0, randf_range(-4, 4))


const WORLD_LAYER := 1 << 5   # the pit shell -- what the camera arm collides with

func _static_box(pos: Vector3, half: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.collision_layer = 1 | WORLD_LAYER   # 1 so balls/character still hit it
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = half * 2.0
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = half * 2.0
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)


func _fill_positions(n: int, top: float) -> void:
	# loose cubic cloud above the pit; physics settles it into a heap
	var per_row := int(floor((PIT.x * 2.0 - 1.0) / (BALL_R * 2.3)))
	var i := 0
	var y := top
	while i < n:
		for zx in per_row * per_row:
			if i >= n:
				break
			var gx := zx % per_row
			var gz := zx / per_row
			var p := Vector3(
				(gx - per_row * 0.5) * BALL_R * 2.3 + randf_range(-0.08, 0.08),
				y + randf_range(-0.05, 0.05),
				(gz - per_row * 0.5) * BALL_R * 2.3 + randf_range(-0.08, 0.08))
			PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), p))
			PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
			PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
			i += 1
		y += BALL_R * 2.3


func _rebuild(n: int) -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_mm.instance_count = 0
	_mm.instance_count = n
	for i in n:
		var b := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_space(b, _space)
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(b, _shape)
		PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_MASS, 0.3)
		PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_FRICTION, 0.75)
		PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.02)
		_bodies.append(b)
		var h := 0.055 + randf() * 0.05          # warm amber band
		var sat := 0.5 + randf() * 0.18
		var val := 0.45 + randf() * 0.35
		_mm.set_instance_color(i, Color.from_hsv(h, sat, val))
	_count = n
	_fill_positions(n, PIT.y + 3.0)


func _pour(n: int) -> void:
	# recycle the lowest-energy balls to a fresh cloud above
	_fill_positions(mini(n, _bodies.size()), PIT.y + 8.0)


func _fling() -> void:
	_wreck.gravity_scale = 1.0
	_wreck.angular_velocity = Vector3.ZERO
	var from := _cam.global_position
	var dir := (_char.global_position + Vector3.UP - from).normalized()
	_wreck.global_position = from + dir * 3.0
	_wreck.linear_velocity = dir * 40.0


func _cam_basis() -> Basis:
	return Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.2, 0.4)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(3.5, _cam_dist - 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(16.0, _cam_dist + 0.6)
		elif event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F: _fling()
			KEY_G: _pour(_bodies.size() / 4)
			KEY_R: _respawn_char()
			KEY_1: _rebuild(COUNTS[0])
			KEY_2: _rebuild(COUNTS[1])
			KEY_3: _rebuild(COUNTS[2])
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()


func _physics_process(delta: float) -> void:
	if _char == null:
		return
	var flat := _cam_basis()
	var fwd := -Vector3(flat.z.x, 0, flat.z.z).normalized()
	var right := Vector3(flat.x.x, 0, flat.x.z).normalized()
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): wish += fwd
	if Input.is_key_pressed(KEY_S): wish -= fwd
	if Input.is_key_pressed(KEY_D): wish += right
	if Input.is_key_pressed(KEY_A): wish -= right
	wish = wish.limit_length(1.0)

	var run: float = 8.5 if Input.is_key_pressed(KEY_SHIFT) else 5.0
	var v := _char.linear_velocity
	var target := wish * run
	var accel := 26.0
	v.x = move_toward(v.x, target.x, accel * delta)
	v.z = move_toward(v.z, target.z, accel * delta)
	_char.linear_velocity = v

	# hop -- a short downward ray finds the balls (or the pit floor) under the feet
	if Input.is_key_pressed(KEY_SPACE) and _char.linear_velocity.y < 2.0:
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				_char.global_position, _char.global_position + Vector3.DOWN * (CHAR_H * 0.5 + 0.5),
				1, [_char.get_rid()]))
		if hit:
			var jv := _char.linear_velocity
			jv.y = 6.5
			_char.linear_velocity = jv

	if wish.length() > 0.1:
		_face = lerp_angle(_face, atan2(wish.x, wish.z), 12.0 * delta)


func _process(delta: float) -> void:
	if _char == null:
		return
	var pivot := _char.global_position + Vector3.UP * (CHAR_H * 0.45)
	var back := (_cam_basis().z + Vector3.UP * 0.18).normalized()
	# spring arm: cast toward the wanted camera spot against the pit shell only
	# (WORLD_LAYER -- never the thousands of balls) and clamp the arm to the hit
	var reach := _cam_dist
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(pivot, pivot + back * _cam_dist, WORLD_LAYER))
	if hit:
		reach = maxf(1.4, pivot.distance_to(hit.position) - 0.4)
	# snap in fast when the wall shortens the arm, ease back out when it clears
	var cur := (_cam.global_position - pivot).length()
	var lerp_pow: float = 0.0005 if reach < cur else 0.05
	var arm := lerpf(cur, reach, 1.0 - pow(lerp_pow, delta))
	_cam.global_position = pivot + back * arm
	_cam.look_at(pivot)

	# face + lean the mesh toward travel (rotation on the body is locked)
	var speed := Vector2(_char.linear_velocity.x, _char.linear_velocity.z).length()
	_char_mesh.rotation.y = _face
	_char_mesh.rotation.x = lerp(_char_mesh.rotation.x, clampf(speed * 0.03, 0.0, 0.35), 8.0 * delta)

	for i in _bodies.size():
		var st := PhysicsServer3D.body_get_direct_state(_bodies[i])
		if st:
			_mm.set_instance_transform(i, st.transform)

	if _wreck.position.y < -40.0 and _wreck.gravity_scale > 0.0:
		_wreck.gravity_scale = 0.0
		_wreck.linear_velocity = Vector3.ZERO
		_wreck.position = Vector3(0, -80, 0)
	if _char.position.y < -8.0:
		_respawn_char()

	_phys_ms = lerp(_phys_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1)
	var active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	_hud.text = "%s   %d balls   %d awake\nphysics %.1f ms   FPS %d\nmouse look · WASD run · SHIFT sprint · SPACE hop · F ball · G pour · R respawn · 1-3 count" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		_bodies.size(), active, _phys_ms, Engine.get_frames_per_second()]


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	if _shape.is_valid():
		PhysicsServer3D.free_rid(_shape)
