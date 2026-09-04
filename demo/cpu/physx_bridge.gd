extends Node3D

# Rope-bridge showcase for the PhysX backend's joints.
#
# The deck is a single chain of plank RigidBody3D bodies, pin-jointed end to end
# and anchored to a stone abutment at each side. It sags into a catenary under
# its own weight and sags further under the crates or the character, then rides
# back up -- a plain PGS pin chain, kept to one clean load path so the solver
# stays happy. Two rope meshes are drawn along the deck edges purely for looks.
#
# Controls:
#   W A S D / arrows  move        SPACE  jump        mouse  look
#   C                 drop a crate pile mid-span
#   R                 reset       ESC   release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025
const GRAVITY := 18.0

const PLANKS := 11
const PLANK_LEN := 1.3
const DECK_W := 3.4
const DECK_Y := 4.0
const SAG_MAX := 1.0

var _span := PLANKS * PLANK_LEN
var _char: CharacterBody3D
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _root: Node3D
var _hud: Label
var _planks: Array[RigidBody3D] = []
var _rope_l: MeshInstance3D
var _rope_r: MeshInstance3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_root = Node3D.new()
	add_child(_root)

	_build_environment()
	_build_bridge()
	_build_character()

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(_hud)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.5, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment = e
	add_child(env)

# --- helpers ---------------------------------------------------------------

func _mat(col: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

func _static_box(pos: Vector3, size: Vector3, col: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	sb.add_child(mi)
	_root.add_child(sb)
	return sb

func _pin(a: Node3D, b: Node3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	j.position = at
	j.set_param(PinJoint3D.PARAM_BIAS, 0.3)
	j.set_param(PinJoint3D.PARAM_DAMPING, 0.7)
	_root.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)

# Pre-sagged rest shape so the deck starts near equilibrium.
func _sag_at(x: float) -> float:
	var t := x / (_span * 0.5)
	return SAG_MAX * (1.0 - t * t)

# --- environment ---------------------------------------------------------------

func _build_environment() -> void:
	var half := _span * 0.5
	_static_box(Vector3(-half - 6, DECK_Y - 3.0, 0), Vector3(12, 6, 26), Color(0.46, 0.41, 0.36))
	_static_box(Vector3(half + 6, DECK_Y - 3.0, 0), Vector3(12, 6, 26), Color(0.46, 0.41, 0.36))
	_static_box(Vector3(0, DECK_Y - 18.0, 0), Vector3(_span + 44, 2, 44), Color(0.19, 0.24, 0.29))
	for x in [-half - 0.9, half + 0.9]:
		for z in [-DECK_W * 0.5 - 0.2, DECK_W * 0.5 + 0.2]:
			_static_box(Vector3(x, DECK_Y + 1.4, z), Vector3(0.6, 4.0, 0.6), Color(0.34, 0.34, 0.37))

# --- bridge -----------------------------------------------------------------

func _plank(idx: int) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 1.2
	rb.can_sleep = false
	rb.linear_damp = 0.6
	rb.angular_damp = 1.5
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(PLANK_LEN * 0.94, 0.14, DECK_W)
	cs.shape = b
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = b.size
	mi.mesh = bm
	mi.material_override = _mat(Color(0.55, 0.38, 0.22) if idx % 2 else Color(0.47, 0.31, 0.17))
	rb.add_child(mi)
	var px := -_span * 0.5 + (idx + 0.5) * PLANK_LEN
	# Offset by half the plank thickness so the top face sits at the deck line
	# (flush with the cliff shelves at the ends).
	rb.position = Vector3(px, DECK_Y - _sag_at(px) - 0.07, 0)
	_root.add_child(rb)
	return rb

func _build_bridge() -> void:
	var half := _span * 0.5
	# Abutments: sunk so their tops are below the deck -- they exist to anchor the
	# end pins, not to be walked on (that lip is what you'd trip over).
	var abut_l := _static_box(Vector3(-half - 0.45, DECK_Y - 0.6, 0), Vector3(0.5, 1.0, DECK_W + 0.6), Color(0.34, 0.34, 0.37))
	var abut_r := _static_box(Vector3(half + 0.45, DECK_Y - 0.6, 0), Vector3(0.5, 1.0, DECK_W + 0.6), Color(0.34, 0.34, 0.37))

	var prev: Node3D = abut_l
	for i in PLANKS:
		var p := _plank(i)
		_planks.append(p)
		var jx := -half + i * PLANK_LEN
		for dz in [-DECK_W * 0.5 + 0.15, DECK_W * 0.5 - 0.15]:
			_pin(prev, p, Vector3(jx, DECK_Y - _sag_at(jx) - 0.07, dz))
		prev = p
	for dz in [-DECK_W * 0.5 + 0.15, DECK_W * 0.5 - 0.15]:
		_pin(prev, abut_r, Vector3(half, DECK_Y - _sag_at(half) - 0.07, dz))

	_rope_l = _make_rope_mesh()
	_rope_r = _make_rope_mesh()
	_root.add_child(_rope_l)
	_root.add_child(_rope_r)

func _make_rope_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var m := _mat(Color(0.14, 0.11, 0.08), 0.7)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	return mi

func _redraw_rope(mi: MeshInstance3D, z: float) -> void:
	var im: ImmediateMesh = mi.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var half := _span * 0.5
	im.surface_add_vertex(Vector3(-half - 0.45, DECK_Y - _sag_at(half), z))
	for p in _planks:
		if is_instance_valid(p):
			im.surface_add_vertex(p.global_position + Vector3(0, 0.12, z))
	im.surface_add_vertex(Vector3(half + 0.45, DECK_Y - _sag_at(half), z))
	im.surface_end()

func _crate_pile(center: Vector3, n: int) -> void:
	for i in n:
		var rb := RigidBody3D.new()
		var s := randf_range(0.3, 0.5)
		rb.mass = s * s * s * 10.0
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(s, s, s)
		cs.shape = b
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		mi.mesh = bm
		mi.material_override = _mat(Color.from_hsv(randf(), 0.4, 0.9))
		rb.add_child(mi)
		rb.position = center + Vector3(randf_range(-0.7, 0.7), 1.2 + i * 0.55, randf_range(-0.7, 0.7))
		_root.add_child(rb)

# --- character --------------------------------------------------------------

func _build_character() -> void:
	_char = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	_char.add_child(cs)
	_char.position = Vector3(-_span * 0.5 - 4, DECK_Y + 1.2, 0)
	_char.floor_snap_length = 0.5
	add_child(_char)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0.7, 0)
	_cam.current = true
	_char.add_child(_cam)

func _reset() -> void:
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_crate_pile(Vector3(0, DECK_Y, 0), 8)
			KEY_R:
				_reset()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()

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
		v.y = JUMP if Input.is_key_pressed(KEY_SPACE) else -2.0
	else:
		v.y -= GRAVITY * delta
	_char.velocity = v
	_char.move_and_slide()

func _process(_dt: float) -> void:
	_redraw_rope(_rope_l, -DECK_W * 0.5 + 0.15)
	_redraw_rope(_rope_r, DECK_W * 0.5 - 0.15)
	var mid := _planks[PLANKS / 2]
	var sag := (DECK_Y - mid.global_position.y) if is_instance_valid(mid) else 0.0
	_hud.text = "%s   |   WASD move  SPACE jump  C crates  R reset  ESC\nmid-span sag: %.2f m     FPS: %d" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		sag, Engine.get_frames_per_second()]
