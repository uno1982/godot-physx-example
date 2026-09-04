extends Node3D

# Suspension-bridge showcase for the PhysX backend's joint solver.
#
# The deck is a run of plank RigidBody3D segments chained end-to-end with
# Generic6DOFJoint3D. Each joint locks the three linear axes (rigid pin) and adds
# angular springs that pull the plank back toward straight -- so the span holds a
# catenary under load and springs back when you take the load off, instead of
# drifting apart the way a bare PGS pin chain does under sustained weight.
#
# Two suspension cables (thin segment chains, pinned at the tower tops) carry
# vertical hangers down to the deck edges for the real support and the look.
#
# Controls:
#   W A S D / arrows  move        SPACE  jump / (hold) also drops crates
#   mouse             look        C     dump a crate pile mid-span
#   R                 reset       ESC   release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025
const GRAVITY := 18.0

const PLANKS := 20
const PLANK_LEN := 1.1
const PLANK_W := 3.0
const DECK_Y := 4.0
const TOWER_H := 5.5

var _span := PLANKS * PLANK_LEN
var _char: CharacterBody3D
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _root: Node3D
var _hud: Label
var _planks: Array[RigidBody3D] = []

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

# --- environment -------------------------------------------------------------

func _mat(col: Color, rough := 0.8) -> StandardMaterial3D:
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

func _build_environment() -> void:
	var half := _span * 0.5
	# Two cliff shelves with a gorge between them.
	_static_box(Vector3(-half - 6, DECK_Y - 3.0, 0), Vector3(12, 6, 20), Color(0.45, 0.4, 0.35))
	_static_box(Vector3(half + 6, DECK_Y - 3.0, 0), Vector3(12, 6, 20), Color(0.45, 0.4, 0.35))
	# Gorge floor, well below the deck -- a dropped crate that misses is gone.
	_static_box(Vector3(0, DECK_Y - 14.0, 0), Vector3(_span + 40, 2, 40), Color(0.2, 0.25, 0.3))

func _tower(x: float) -> void:
	for z in [-PLANK_W * 0.5 - 0.2, PLANK_W * 0.5 + 0.2]:
		_static_box(Vector3(x, DECK_Y + TOWER_H * 0.5 - 0.4, z), Vector3(0.5, TOWER_H, 0.5), Color(0.3, 0.3, 0.33))

# --- bridge -----------------------------------------------------------------

func _plank(idx: int) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 3.0
	rb.can_sleep = false
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(PLANK_LEN * 0.96, 0.14, PLANK_W)
	cs.shape = b
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = b.size
	mi.mesh = bm
	mi.material_override = _mat(Color(0.55, 0.38, 0.22) if idx % 2 else Color(0.5, 0.34, 0.2))
	rb.add_child(mi)
	rb.position = Vector3(-_span * 0.5 + (idx + 0.5) * PLANK_LEN, DECK_Y, 0)
	_root.add_child(rb)
	return rb

func _deck_joint(a: Node3D, b: Node3D, at: Vector3) -> void:
	var j := Generic6DOFJoint3D.new()
	j.position = at
	_root.add_child(j)
	# Rigid in translation.
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
	# Angular springs: let the deck hinge a little but pull back to flat.
	for ax in ["x", "y", "z"]:
		j.set("angular_spring_%s/enabled" % ax, true)
		j.set("angular_spring_%s/stiffness" % ax, 40.0)
		j.set("angular_spring_%s/damping" % ax, 8.0)
		j.set("angular_spring_%s/equilibrium_point" % ax, 0.0)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)

func _cable_segment(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 0.5
	rb.can_sleep = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.05
	cap.height = PLANK_LEN
	cs.shape = cap
	cs.rotation = Vector3(0, 0, PI * 0.5)
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.05
	cm.height = PLANK_LEN
	mi.mesh = cm
	mi.rotation = Vector3(0, 0, PI * 0.5)
	mi.material_override = _mat(Color(0.15, 0.15, 0.16), 0.4)
	rb.add_child(mi)
	rb.position = pos
	rb.collision_layer = 0
	rb.collision_mask = 0
	_root.add_child(rb)
	return rb

func _pin(a: Node3D, b: Node3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	j.position = at
	j.set_param(PinJoint3D.PARAM_BIAS, 0.9)
	j.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
	_root.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)

func _cable(z: float) -> void:
	var half := _span * 0.5
	var tower_top := DECK_Y + TOWER_H - 0.4
	var anchor_l := _static_box(Vector3(-half, tower_top, z), Vector3(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.33))
	var anchor_r := _static_box(Vector3(half, tower_top, z), Vector3(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.33))
	var prev: Node3D = anchor_l
	var segs: Array[RigidBody3D] = []
	for i in PLANKS:
		var t := (i + 0.5) / float(PLANKS)
		# A shallow parabolic sag between the tower tops.
		var sag := 2.6 * (1.0 - pow(2.0 * t - 1.0, 2.0))
		var seg := _cable_segment(Vector3(-half + (i + 0.5) * PLANK_LEN, tower_top - sag, z))
		_pin(prev, seg, Vector3(-half + i * PLANK_LEN, seg.position.y, z))
		prev = seg
		segs.append(seg)
	_pin(prev, anchor_r, Vector3(half, tower_top, z))
	# Vertical hangers: each cable segment holds up the matching plank edge.
	for i in PLANKS:
		_pin(segs[i], _planks[i], Vector3(_planks[i].position.x, DECK_Y + 0.07, z))

func _build_bridge() -> void:
	var half := _span * 0.5
	_tower(-half)
	_tower(half)
	var abut_l := _static_box(Vector3(-half - 0.5, DECK_Y, 0), Vector3(0.4, 0.4, PLANK_W), Color(0.3, 0.3, 0.33))
	var abut_r := _static_box(Vector3(half + 0.5, DECK_Y, 0), Vector3(0.4, 0.4, PLANK_W), Color(0.3, 0.3, 0.33))

	var prev: Node3D = abut_l
	for i in PLANKS:
		var p := _plank(i)
		_deck_joint(prev, p, Vector3(-half + i * PLANK_LEN, DECK_Y, 0))
		prev = p
		_planks.append(p)
	_deck_joint(prev, abut_r, Vector3(half, DECK_Y, 0))

	_cable(-PLANK_W * 0.5 - 0.1)
	_cable(PLANK_W * 0.5 + 0.1)

func _crate_pile(center: Vector3, n: int) -> void:
	for i in n:
		var rb := RigidBody3D.new()
		var s := randf_range(0.35, 0.6)
		rb.mass = s * s * s * 20.0
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(s, s, s)
		cs.shape = b
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		mi.mesh = bm
		mi.material_override = _mat(Color.from_hsv(randf(), 0.35, 0.9))
		rb.add_child(mi)
		rb.position = center + Vector3(randf_range(-0.8, 0.8), 1.5 + i * 0.7, randf_range(-0.8, 0.8))
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
	_char.position = Vector3(-_span * 0.5 - 4, DECK_Y + 4.0, 0)
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
		v.y = JUMP if Input.is_key_pressed(KEY_SPACE) else -0.1
	else:
		v.y -= GRAVITY * delta
	_char.velocity = v
	_char.move_and_slide()

func _process(_dt: float) -> void:
	var mid_sag := DECK_Y - _planks[PLANKS / 2].global_position.y
	_hud.text = "%s   |   WASD move  SPACE jump  C crates  R reset  ESC\nmid-span sag: %.2f m     FPS: %d" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		mid_sag, Engine.get_frames_per_second()]
