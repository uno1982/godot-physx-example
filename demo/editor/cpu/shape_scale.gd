extends Node3D

# Walk scaled collision shapes with a capsule character to see how traversal
# feels once node scale is baked into the geometry -- box, convex, trimesh and
# height field take full non-uniform scale like Jolt; sphere/capsule are
# uniform-only.
#
# The platforms, ramp and sphere dome are authored nodes -- select one and
# stretch its transform in the inspector, then press Play. The convex wedge,
# trimesh hump and height-field mound are generated here (they need geometry
# data) and take their scale from the exports below.
#
#   W A S D / arrows  move    SPACE  jump    mouse  look    R  reset    ESC  quit

const SPEED := 6.0
const JUMP := 6.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.0025

@export var convex_scale := Vector3(5, 1.0, 4) : set = _set_cvx
@export var trimesh_scale := Vector3(7, 1.6, 4) : set = _set_tri
@export var heightfield_scale := Vector3(1.1, 2.5, 1.1) : set = _set_hf

var _char: CharacterBody3D
var _cam: Camera3D
var _hud: Label
var _yaw := 0.0
var _pitch := 0.0


func _set_cvx(v: Vector3) -> void:
	convex_scale = v
	_rebuild()


func _set_tri(v: Vector3) -> void:
	trimesh_scale = v
	_rebuild()


func _set_hf(v: Vector3) -> void:
	heightfield_scale = v
	_rebuild()


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	_char = $Player
	_cam = $Player/Camera3D
	_hud = $HUD/Label
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_char.global_position = Vector3(0, 3, 10)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_build_convex_ramp()
	_build_trimesh_strip()
	_build_heightfield_mound()


# Physics nodes want scale on their own transform, not on a parent -- so each
# generated piece is a StaticBody3D scaled directly, with its mesh a child of
# the body so they stretch together.
func _scaled_piece(holder: Node3D, sc: Vector3, shape: Shape3D, mesh: Mesh, col: Color) -> void:
	for c in holder.get_children():
		c.queue_free()
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis.IDENTITY.scaled(sc), Vector3.ZERO)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	body.add_child(mi)
	holder.add_child(body)


# A chamfered-box convex ramp -- non-uniform scale stretches the hull long and
# low. (A hull needs a few non-coplanar points to cook cleanly.)
func _build_convex_ramp() -> void:
	var pts := PackedVector3Array()
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				# clip the corners so the hull has 24 distinct vertices
				pts.append(Vector3(sx * 0.8, sy, sz))
				pts.append(Vector3(sx, sy * 0.8, sz))
				pts.append(Vector3(sx, sy, sz * 0.8))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts

	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_scaled_piece($ConvexRamp, convex_scale, shape, bm, Color(0.45, 0.5, 0.6))


# A smooth trimesh hump -- non-uniform scale stretches it long and low.
func _build_trimesh_strip() -> void:
	var cols := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[float] = []
	for i in cols + 1:
		var f := float(i) / cols
		pts.append(sin(f * PI) * 0.7 + 0.05 * sin(f * 22.0))
	# Godot front faces wind clockwise seen from the front, and the backend's
	# trimesh collision is one-sided -- so a top surface is CW from above.
	for i in cols:
		var x0 := float(i) / cols - 0.5
		var x1 := float(i + 1) / cols - 0.5
		var y0 := pts[i]
		var y1 := pts[i + 1]
		for tri in [
			[Vector3(x0, y0, -0.5), Vector3(x1, y1, 0.5), Vector3(x0, y0, 0.5)],
			[Vector3(x0, y0, -0.5), Vector3(x1, y1, -0.5), Vector3(x1, y1, 0.5)]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	_scaled_piece($TrimeshHump, trimesh_scale, shape, mesh, Color(0.6, 0.55, 0.4))


# A noise mound as a HeightMapShape3D, non-uniformly scaled.
func _build_heightfield_mound() -> void:
	var holder: Node3D = $HeightfieldMound
	for c in holder.get_children():
		c.queue_free()

	var grid := 15
	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.12
	var mid := (grid - 1) * 0.5
	for z in grid:
		for x in grid:
			var e := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var edge: float = minf(minf(x, grid - 1 - x), minf(z, grid - 1 - z)) / mid
			heights[z * grid + x] = e * smoothstep(0.0, 0.4, edge)

	var shape := HeightMapShape3D.new()
	shape.map_width = grid
	shape.map_depth = grid
	shape.map_data = heights

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in grid - 1:
		for x in grid - 1:
			var p := func(ix: int, iz: int) -> Vector3:
				return Vector3(ix - mid, heights[iz * grid + ix], iz - mid)
			for tri in [[p.call(x, z), p.call(x, z + 1), p.call(x + 1, z)],
					[p.call(x + 1, z), p.call(x, z + 1), p.call(x + 1, z + 1)]]:
				for v in tri:
					st.add_vertex(v)
	st.generate_normals()
	_scaled_piece(holder, heightfield_scale, shape, st.commit(), Color(0.4, 0.5, 0.35))


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _char == null:
		return
	_char.rotation.y = _yaw
	_cam.rotation.x = _pitch

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input.x += 1.0
	var dir := (_char.transform.basis * input).normalized()

	var v := _char.velocity
	v.x = dir.x * SPEED
	v.z = dir.z * SPEED
	if _char.is_on_floor():
		v.y = JUMP if Input.is_key_pressed(KEY_SPACE) else 0.0
	else:
		v.y -= GRAVITY * delta
	_char.velocity = v
	_char.move_and_slide()

	if _char.global_position.y < -20.0:
		_char.global_position = Vector3(0, 3, 10)
		_char.velocity = Vector3.ZERO


func _process(_dt: float) -> void:
	if _hud == null:
		return
	_hud.text = "Scaled-shape traversal   WASD move   SPACE jump   R reset   ESC\npos %.1v   on_floor %s   floor_angle %.0f°   FPS %d" % [
		_char.global_position, _char.is_on_floor(),
		rad_to_deg(_char.get_floor_angle()) if _char.is_on_floor() else 0.0,
		Engine.get_frames_per_second()]
