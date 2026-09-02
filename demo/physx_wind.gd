extends Node3D

# Wind playground for the PhysX backend's Area3D space overrides.
#
# A gusting WindArea drives everything downwind: jointed cloth banners, hanging
# streamers, tumbling debris, and a string pendulum that doubles as a wind gauge.
# Walk into the volume and you get shoved too.
#
# Controls:
#   W A S D / arrows  move        SPACE  jump        mouse  look
#   F                 toggle wind on/off
#   [ / ]             weaker / stronger gusts
#   G                 dump a fresh batch of debris
#   R                 reset
#   ESC               release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025

var _char: CharacterBody3D
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _gravity := 18.0

var _wind: Area3D
var _wind_on := true
var _base_gust := 9.0
var _gust := 0.0
var _t := 0.0
var _spawn_root: Node3D
var _gauge: RigidBody3D
var _gauge_anchor := Vector3(-6, 5.5, 3)
var _leaves: Array[RigidBody3D] = []
var _hud: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_root = Node3D.new()
	add_child(_spawn_root)

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
	sun.rotation_degrees = Vector3(-50, -60, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.34, 0.30)
	mat.roughness = 0.95
	# Ground is also on layer 16 so the cloth (which ignores the poles/wire on
	# layer 1) can still rest on it.
	var ground := _static_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), mat, self)
	ground.collision_layer = 1 | 16

	# The wind volume: a big box centred over the play area. Wind blows along -X
	# (the source marker's -Z), attenuating with downwind distance.
	_wind = Area3D.new()
	_wind.gravity_space_override = Area3D.SPACE_OVERRIDE_DISABLED
	var wc := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(60, 40, 40)
	wc.shape = wbox
	_wind.add_child(wc)
	_wind.position = Vector3(0, 18, 0)
	_wind.wind_attenuation_factor = 0.25
	_wind.priority = 1
	_wind.collision_mask = 0xFFFFFFFF # affect every body layer
	add_child(_wind)
	var wsrc := Marker3D.new()
	wsrc.position = Vector3(28, 0, 0) # upwind edge
	wsrc.rotation_degrees = Vector3(0, 90, 0) # -Z now points toward -X
	_wind.add_child(wsrc)
	_wind.wind_source_path = _wind.get_path_to(wsrc)
	_wind.wind_force_magnitude = _base_gust

	# A faint volumetric hint of the wind direction.
	var band := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 0.05, 40)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.6, 0.8, 1.0, 0.05)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = bmat
	band.mesh = bm
	band.position = Vector3(0, 3, 0)
	add_child(band)

func _build_character() -> void:
	_char = CharacterBody3D.new()
	_char.name = "Player"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	_char.add_child(cs)
	_char.position = Vector3(-16, 2, 6)
	add_child(_char)
	_yaw = -0.9 # face the flags / downwind lane

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0.7, 0)
	_cam.current = true
	_char.add_child(_cam)

func _reset_scene() -> void:
	for c in _spawn_root.get_children():
		c.queue_free()

	# Short pennants off vertical poles.
	for i in 3:
		_banner(Vector3(-4 + i * 4.0, 0, -6), Color.from_hsv(0.02 + i * 0.12, 0.6, 0.95))

	# Streamers on a wire.
	var wire := _static_box(Vector3(9, 7.4, 0), Vector3(0.06, 0.06, 20), _grey())
	for i in 6:
		_streamer(wire, Vector3(9, 7.3, -7.5 + i * 3.0), 0.33 + i * 0.07)

	# Free-body wind toys: light crates and beach balls that just get rolled and
	# tumbled downwind (rock-solid -- no joints involved).
	for i in 10:
		var crate := RigidBody3D.new()
		var s := randf_range(0.4, 0.8)
		_visual_box(crate, Vector3(s, s, s), Color.from_hsv(randf(), 0.3, 0.9))
		_col_box(crate, Vector3(s, s, s))
		crate.mass = s * s * s * 8.0
		crate.position = Vector3(randf_range(12, 22), s * 0.5 + 0.1, randf_range(-10, 10))
		_spawn_root.add_child(crate)
	for i in 4:
		var ball := RigidBody3D.new()
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		mi.mesh = sm
		ball.add_child(mi)
		var csb := CollisionShape3D.new()
		var sb := SphereShape3D.new()
		sb.radius = 0.45
		csb.shape = sb
		ball.add_child(csb)
		ball.mass = 0.6
		ball.position = Vector3(randf_range(14, 20), 0.55, randf_range(-8, 8))
		_spawn_root.add_child(ball)

	# Wind gauge: a heavy bob on a short string. Its lean angle reads out force.
	var anchor := _static_box(_gauge_anchor, Vector3(0.12, 0.12, 0.12), _grey())
	_gauge = _rd_sphere(_gauge_anchor - Vector3(0, 2.0, 0), 0.25, 8.0)
	_gauge.linear_damp = 1.0
	var pin := PinJoint3D.new()
	pin.position = _gauge_anchor
	_spawn_root.add_child(pin)
	pin.node_a = pin.get_path_to(anchor)
	pin.node_b = pin.get_path_to(_gauge)

	_leaves.clear()
	_spawn_debris(35)

func _spawn_debris(n: int) -> void:
	for i in n:
		var leaf := RigidBody3D.new()
		var sz := Vector3(randf_range(0.15, 0.35), 0.03, randf_range(0.15, 0.35))
		_visual_box(leaf, sz, Color.from_hsv(randf_range(0.06, 0.13), 0.75, 0.55))
		_col_box(leaf, sz)
		# Leaves collide with the ground and each other, nothing else.
		leaf.collision_layer = 2
		leaf.collision_mask = 3
		leaf.mass = 0.12
		leaf.position = Vector3(randf_range(16, 24), randf_range(1.5, 7), randf_range(-9, 9))
		leaf.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		_spawn_root.add_child(leaf)
		_leaves.append(leaf)

# Recycle leaves that have blown out of the play area back to the upwind edge so
# there's always something drifting through the gust.
func _recycle_leaves() -> void:
	for leaf in _leaves:
		if not is_instance_valid(leaf):
			continue
		var p := leaf.global_position
		if p.x < -40.0 or p.y < -3.0 or absf(p.z) > 24.0:
			leaf.global_position = Vector3(randf_range(20, 26), randf_range(2, 8), randf_range(-9, 9))
			leaf.linear_velocity = Vector3.ZERO
			leaf.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))

func _banner(base: Vector3, col: Color) -> void:
	# A pennant: a horizontal chain of tall panels streaming off the pole top.
	# A 1-D chain holds together far better under gust than a stitched grid.
	var pole := _static_box(base + Vector3(0, 3, 0), Vector3(0.12, 6, 0.12), _grey())
	# Few, heavy panels: PGS (the default solver) drifts on long light joint
	# chains under sustained wind, so keep the flag short and dense.
	var panels := 3
	var pw := 0.9 # panel width along the flag
	var ph := 1.3 # panel height
	var top := base + Vector3(0, 5.4, 0)
	var prev: Node3D = pole
	for i in panels:
		var seg := RigidBody3D.new()
		_visual_box(seg, Vector3(pw, ph, 0.04), col.lerp(Color.WHITE, i * 0.06))
		_col_box(seg, Vector3(pw * 0.9, ph * 0.9, 0.04))
		# Cloth ignores the poles/wire (layer 1) it hangs next to -- brushing its
		# own anchor destabilises the chain. It still lands on the ground
		# (layer 16) and never touches the debris.
		seg.collision_layer = 4
		seg.collision_mask = 16
		seg.mass = 2.0
		seg.linear_damp = 0.6
		seg.angular_damp = 1.0
		seg.position = top + Vector3(-(0.2 + (i + 0.5) * pw), 0, 0)
		_spawn_root.add_child(seg)
		var j := PinJoint3D.new()
		j.position = top + Vector3(-(0.2 + i * pw), 0, 0)
		j.set_param(PinJoint3D.PARAM_BIAS, 0.9)
		j.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
		_spawn_root.add_child(j)
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(seg)
		prev = seg

func _streamer(wire: Node3D, top: Vector3, hue: float) -> void:
	var prev: Node3D = wire
	var links := 3
	var lh := 0.8
	for i in links:
		var seg := RigidBody3D.new()
		var col := Color.from_hsv(fmod(hue, 1.0), 0.85, 1.0).lerp(Color.WHITE, i * 0.08)
		_visual_box(seg, Vector3(1.1, lh, 0.04), col)
		_col_box(seg, Vector3(1.0, lh * 0.9, 0.04))
		# Same as the flags: ignore the wire/poles on layer 1, land on layer 16.
		seg.collision_layer = 8
		seg.collision_mask = 16
		seg.mass = 2.0
		seg.linear_damp = 1.0
		seg.angular_damp = 1.4
		seg.position = top - Vector3(0, (i + 0.5) * lh, 0)
		_spawn_root.add_child(seg)
		var j := PinJoint3D.new()
		j.position = top - Vector3(0, i * lh, 0)
		j.set_param(PinJoint3D.PARAM_BIAS, 0.9)
		j.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
		_spawn_root.add_child(j)
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(seg)
		prev = seg

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
	(parent if parent != null else _spawn_root).add_child(sb)
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
	_spawn_root.add_child(rb)
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

# --- input / movement ----------------------------------------------------------

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
				_base_gust = minf(24.0, _base_gust + 3.0)
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

	# Gusting: base + slow swell + a little chop, gated by the on/off toggle.
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
	_hud.text = "%s   |   F wind %s   [ ] gust %.0f   G debris   R reset   ESC\ngust force: %.1f N     gauge lean: %.0f deg     FPS: %d" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		"ON" if _wind_on else "OFF", _base_gust,
		_gust, lean, Engine.get_frames_per_second()]
