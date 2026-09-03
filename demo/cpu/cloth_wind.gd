extends Node3D

# Cloth + wind demo for the PhysX module (CPU XPBD path -- works on any GPU).
#
# A gusting WindArea drives a row of PhysXCloth3D flags and hanging banners; the
# cloth reads the area's wind directly. A jointed string pendulum doubles as a
# wind gauge, light crates tumble downwind and leaves drift through. Walk into
# the volume and the gust shoves you too.
#
# Controls:
#   W A S D / arrows  move        SPACE  jump        mouse  look
#   F                 toggle wind        [ / ]  weaker / stronger gusts
#   G                 dump more leaves
#   R                 reset               ESC   release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025
const GROUND_LAYER := 16

var _char: CharacterBody3D
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _gravity := 18.0

var _wind: Area3D
var _wind_on := true
var _base_gust := 11.0
var _gust := 0.0
var _t := 0.0
var _root: Node3D
var _gauge: RigidBody3D
var _gauge_anchor := Vector3(-7, 5.5, 4)
var _leaves: Array[RigidBody3D] = []
var _hud: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_root = Node3D.new()
	add_child(_root)
	_build_world()
	_build_character()

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)

	_reset_scene()

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -55, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.30, 0.34, 0.30)
	gmat.roughness = 0.95
	var ground := _static_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), gmat, self)
	ground.collision_layer = 1 | GROUND_LAYER

	# Wind volume: blows along -X, attenuating downwind.
	_wind = Area3D.new()
	_wind.gravity_space_override = Area3D.SPACE_OVERRIDE_DISABLED
	var wc := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(60, 40, 40)
	wc.shape = wbox
	_wind.add_child(wc)
	_wind.position = Vector3(0, 18, 0)
	_wind.wind_attenuation_factor = 0.2
	_wind.priority = 1
	_wind.collision_mask = 0xFFFFFFFF
	add_child(_wind)
	var wsrc := Marker3D.new()
	wsrc.position = Vector3(28, 0, 0)
	wsrc.rotation_degrees = Vector3(0, 90, 0) # -Z points toward -X
	_wind.add_child(wsrc)
	_wind.wind_source_path = _wind.get_path_to(wsrc)
	_wind.wind_force_magnitude = _base_gust

func _build_character() -> void:
	_char = CharacterBody3D.new()
	_char.name = "Player"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	_char.add_child(cs)
	_char.position = Vector3(-15, 2, 7)
	add_child(_char)
	_yaw = -0.9

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0.7, 0)
	_cam.current = true
	_char.add_child(_cam)

func _reset_scene() -> void:
	for c in _root.get_children():
		c.queue_free()

	# Row of flags on poles, flying off their left edge.
	for i in 4:
		_flag(Vector3(-6 + i * 4.0, 0, -6), Color.from_hsv(0.03 + i * 0.11, 0.7, 0.95))

	# Hanging banners off a high wire, pinned along their top edge.
	var wire := _static_box(Vector3(8, 6.0, 0), Vector3(0.05, 0.05, 18), _grey())
	for i in 4:
		_banner(Vector3(8, 6.0, -6.5 + i * 4.3), Color.from_hsv(0.55 + i * 0.06, 0.5, 0.95))

	# Wind gauge: a heavy bob on a short string; its lean reads out force.
	var anchor := _static_box(_gauge_anchor, Vector3(0.12, 0.12, 0.12), _grey())
	_gauge = _rd_sphere(_gauge_anchor - Vector3(0, 2.0, 0), 0.25, 8.0)
	_gauge.linear_damp = 1.0
	var pin := PinJoint3D.new()
	pin.position = _gauge_anchor
	_root.add_child(pin)
	pin.node_a = pin.get_path_to(anchor)
	pin.node_b = pin.get_path_to(_gauge)

	# Light crates that just tumble downwind.
	for i in 10:
		var crate := RigidBody3D.new()
		var s := randf_range(0.4, 0.8)
		_visual_box(crate, Vector3(s, s, s), Color.from_hsv(randf(), 0.3, 0.9))
		_col_box(crate, Vector3(s, s, s))
		crate.mass = s * s * s * 8.0
		crate.position = Vector3(randf_range(12, 22), s * 0.5 + 0.1, randf_range(-10, 10))
		_root.add_child(crate)

	_leaves.clear()
	_spawn_debris(35)

# Thin leaves that drift downwind and get recycled to the upwind edge once they
# blow out of the play area, so there's always something in the air.
func _spawn_debris(n: int) -> void:
	for i in n:
		var leaf := RigidBody3D.new()
		var sz := Vector3(randf_range(0.15, 0.35), 0.03, randf_range(0.15, 0.35))
		_visual_box(leaf, sz, Color.from_hsv(randf_range(0.06, 0.13), 0.75, 0.55))
		_col_box(leaf, sz)
		leaf.collision_layer = 2
		leaf.collision_mask = 3 # ground + other leaves only
		leaf.mass = 0.12
		leaf.position = Vector3(randf_range(16, 24), randf_range(1.5, 7), randf_range(-9, 9))
		leaf.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		_root.add_child(leaf)
		_leaves.append(leaf)

func _recycle_leaves() -> void:
	for leaf in _leaves:
		if not is_instance_valid(leaf):
			continue
		var p := leaf.global_position
		if p.x < -40.0 or p.y < -3.0 or absf(p.z) > 24.0:
			leaf.global_position = Vector3(randf_range(20, 26), randf_range(2, 8), randf_range(-9, 9))
			leaf.linear_velocity = Vector3.ZERO
			leaf.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))

func _flag(base: Vector3, col: Color) -> void:
	var pole := _static_box(base + Vector3(0, 3, 0), Vector3(0.1, 6, 0.1), _grey())
	pole.collision_layer = 1

	var w := 2.0
	var cloth := PhysXCloth3D.new()
	cloth.grid_columns = 28
	cloth.grid_rows = 18
	cloth.grid_size = Vector2(w, 1.3)
	# Pin the +X edge at the pole so the flag streams downwind (toward -X).
	cloth.position = base + Vector3(-w * 0.5, 5.2, 0)
	cloth.pin_mode = PhysXCloth3D.PIN_RIGHT_EDGE
	cloth.wind_turbulence = 0.7
	cloth.stiffness = 0.9
	cloth.shear_stiffness = 0.6
	cloth.bend_stiffness = 0.12
	cloth.damping = 0.02
	cloth.drag = 1.5
	cloth.collision_mask = GROUND_LAYER # ignore the pole, still land on the ground
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	cloth.material_override = m
	_root.add_child(cloth)
	cloth.wind_area = cloth.get_path_to(_wind)

func _banner(wire_point: Vector3, col: Color) -> void:
	var h := 2.6
	var cloth := PhysXCloth3D.new()
	cloth.grid_columns = 16
	cloth.grid_rows = 24
	cloth.grid_size = Vector2(1.1, h)
	cloth.position = wire_point - Vector3(0, h * 0.5, 0) # top edge on the wire
	cloth.rotation_degrees = Vector3(0, 90, 0) # width runs along the wire (Z), face toward the wind
	cloth.pin_mode = PhysXCloth3D.PIN_TOP_EDGE
	cloth.wind_turbulence = 0.4
	cloth.stiffness = 0.9
	cloth.bend_stiffness = 0.1
	cloth.damping = 0.08
	cloth.density = 0.6 # heavy fabric: hangs and ripples instead of flying up
	cloth.drag = 0.55
	cloth.lift = 0.15
	cloth.collision_mask = GROUND_LAYER
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	cloth.material_override = m
	_root.add_child(cloth)
	cloth.wind_area = cloth.get_path_to(_wind)

# --- helpers ---------------------------------------------------------------

func _grey() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.4, 0.42)
	m.roughness = 0.8
	return m

func _static_box(pos: Vector3, size: Vector3, mat: Material, parent: Node = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	_col_box(sb, size)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	(parent if parent != null else _root).add_child(sb)
	return sb

func _rd_sphere(pos: Vector3, r: float, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	mi.mesh = sm
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	rb.mass = mass
	_root.add_child(rb)
	return rb

func _visual_box(n: Node, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	bm.material = m
	mi.mesh = bm
	n.add_child(mi)

func _col_box(n: Node, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	n.add_child(cs)

# --- input / movement --------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.57, 1.57)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_wind_on = not _wind_on
			KEY_BRACKETLEFT:
				_base_gust = maxf(0.0, _base_gust - 3.0)
			KEY_BRACKETRIGHT:
				_base_gust = minf(28.0, _base_gust + 3.0)
			KEY_G:
				_spawn_debris(40)
			KEY_R:
				_reset_scene()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()

func _physics_process(delta: float) -> void:
	_char.rotation.y = _yaw
	_cam.rotation.x = _pitch

	_t += delta
	if _wind_on:
		var swell := 0.55 + 0.45 * sin(_t * 0.6)
		var chop := 0.15 * sin(_t * 3.7 + 1.3)
		_gust = _base_gust * clampf(swell + chop, 0.0, 1.4)
	else:
		_gust = lerp(_gust, 0.0, 0.1)
	_wind.wind_force_magnitude = _gust
	_recycle_leaves()

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
		v.y -= _gravity * delta
	_char.velocity = v
	_char.move_and_slide()

func _process(_dt: float) -> void:
	var lean := 0.0
	if is_instance_valid(_gauge):
		var down := _gauge.global_position - _gauge_anchor
		lean = rad_to_deg(down.angle_to(Vector3.DOWN))
	_hud.text = "PhysX cloth in wind (CPU XPBD)   F wind %s   [ ] gust %.0f   G leaves   R reset   ESC\ngust: %4.1f   gauge lean: %4.1f°   leaves: %d   FPS: %d" % [
		("ON" if _wind_on else "OFF"), _base_gust, _gust, lean, _leaves.size(), Engine.get_frames_per_second()]
