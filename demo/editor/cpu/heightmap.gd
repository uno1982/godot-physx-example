@tool
extends Node3D

# Node-authored HeightMapShape3D demo on the PhysX backend. The terrain's
# collision (a HeightMapShape3D on the Terrain StaticBody3D) and its visible
# mesh are both generated from the same noise here, so selecting
# Terrain/CollisionShape3D shows the real height-field gizmo in the editor.
# Tweak the exported noise params and it rebuilds live. Press Play to walk it
# and roll balls down the slopes.
#
#   W A S D / arrows  move    SPACE  jump    mouse  look
#   B   drop a row of balls up the hill        R  reset      ESC  quit

# HeightMapShape3D is fixed at 1 unit per sample, so `grid` is also the terrain
# size in metres. (Scaling the body would only stretch the visual mesh, not the
# PhysX height field.)
@export var grid: int = 101 : set = _set_grid
@export var height: float = 11.0 : set = _set_height
@export var feature_scale: float = 0.018 : set = _set_feature
@export var noise_seed: int = 7 : set = _set_seed

const SPEED := 6.0
const JUMP := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.0025

var _char: CharacterBody3D
var _cam: Camera3D
var _hud: Label
var _yaw := 0.0
var _pitch := 0.0
var _balls: Array[RigidBody3D] = []

func _set_grid(v: int) -> void: grid = clampi(v, 4, 257); _rebuild()
func _set_height(v: float) -> void: height = v; _rebuild()
func _set_feature(v: float) -> void: feature_scale = maxf(v, 0.001); _rebuild()
func _set_seed(v: int) -> void: noise_seed = v; _rebuild()

func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	_char = $Player
	_cam = $Player/Camera3D
	_hud = $HUD/Label
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Drop the player onto the surface above the centre.
	_char.global_position = Vector3(0, _sample_height(0.0, 0.0) + 2.0, 0)

func _heights() -> PackedFloat32Array:
	var n := grid * grid
	var h := PackedFloat32Array()
	h.resize(n)
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = feature_scale
	noise.fractal_octaves = 4
	var mid := (grid - 1) * 0.5
	for z in grid:
		for x in grid:
			var e := noise.get_noise_2d(float(x), float(z)) * 0.5 + 0.5 # 0..1
			# taper to 0 at the rim so the walls of the map aren't a cliff
			var edge := minf(minf(x, grid - 1 - x), minf(z, grid - 1 - z)) / mid
			e *= smoothstep(0.0, 0.35, edge)
			h[z * grid + x] = e * height
	return h

func _sample_height(wx: float, wz: float) -> float:
	# nearest-sample lookup in world space (grid centred on the origin).
	var mid := (grid - 1) * 0.5
	var gx := clampi(int(round(wx + mid)), 0, grid - 1)
	var gz := clampi(int(round(wz + mid)), 0, grid - 1)
	var h := ($Terrain/CollisionShape3D.shape as HeightMapShape3D).map_data
	if h.size() == grid * grid:
		return h[gz * grid + gx]
	return 0.0

func _rebuild() -> void:
	if not is_node_ready():
		return
	var h := _heights()

	var shape := HeightMapShape3D.new()
	shape.map_width = grid
	shape.map_depth = grid
	shape.map_data = h
	var cs: CollisionShape3D = $Terrain/CollisionShape3D
	cs.shape = shape

	# Matching visible mesh -- CCW winding so the top surface faces up.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := (grid - 1) * 0.5
	for z in grid - 1:
		for x in grid - 1:
			var p00 := Vector3(x - mid, h[z * grid + x], z - mid)
			var p10 := Vector3(x + 1 - mid, h[z * grid + x + 1], z - mid)
			var p01 := Vector3(x - mid, h[(z + 1) * grid + x], z + 1 - mid)
			var p11 := Vector3(x + 1 - mid, h[(z + 1) * grid + x + 1], z + 1 - mid)
			for tri in [[p00, p10, p01], [p10, p11, p01]]:
				for v in tri:
					st.add_vertex(v)
	st.generate_normals()
	$Terrain/MeshInstance3D.mesh = st.commit()

func _spawn_balls() -> void:
	for b in _balls:
		if is_instance_valid(b):
			b.queue_free()
	_balls.clear()
	var top := Vector3(0, 0, -(grid - 1) * 0.3)
	top.y = _sample_height(top.x, top.z) + 4.0
	for i in 9:
		var rb := RigidBody3D.new()
		rb.mass = 3.0
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.4
		cs.shape = s
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(float(i) / 9.0, 0.6, 0.95)
		mi.material_override = m
		rb.add_child(mi)
		rb.position = top + Vector3((i - 4) * 1.1, 0, 0)
		add_child(rb)
		_balls.append(rb)

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
			KEY_B: _spawn_balls()
			KEY_R: get_tree().reload_current_scene()
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

func _process(_dt: float) -> void:
	if _hud == null:
		return
	_hud.text = "HeightMapShape3D showcase (%d x %d grid)   WASD move   SPACE jump   B balls   R reset   ESC\nchar y: %.1f   FPS: %d" % [
		grid, grid, _char.global_position.y, Engine.get_frames_per_second()]
