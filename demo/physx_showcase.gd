extends Node3D

# Visual PhysX stress demo — a tower of dynamic boxes that falls onto obstacles
# and can be blown apart, with a live HUD (body count, physics ms, Hz, FPS,
# backend). Built for screen recording.
#
# Controls:
#   SPACE   re-stack the tower up high and let it fall
#   E       explosion impulse from the center (scatters everything)
#   B       drop a heavy wrecking ball through the pile
#   1..5    presets: 1k / 5k / 10k / 25k / 50k bodies (rebuilds)
#   ] / [   double / halve the count
#   R       reset camera orbit
#   ESC     quit
#
# Rendering is a single MultiMesh draw call, so the physics-ms on the HUD is the
# real solver + sync cost, not graphics.

const COUNTS := [1000, 5000, 10000, 25000, 50000]
const BOX := 0.5 # half-extent
const FLOOR_HALF := Vector3(40, 1, 40)
const SPACING := 1.12

var _count := 10000
var _bodies: Array[RigidBody3D] = []
var _mm: MultiMesh
var _pit: Node3D
var _hud: Label
var _cam: Camera3D
var _cam_angle := 0.0
var _phys_ms_smooth := 0.0
var _phys_ms_peak := 0.0
var _ball: RigidBody3D

# Real (wall-clock) physics tick-rate tracking.
var _pf_prev := 0
var _wall_prev := 0.0
var _real_hz := 60.0
const PHYS_BUDGET_MS := 1000.0 / 60.0

func _ready() -> void:
	_wall_prev = float(Time.get_ticks_msec()) / 1000.0
	_pf_prev = Engine.get_physics_frames()
	_build_world()
	_rebuild(_count)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -50, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 400.0
	add_child(_cam)
	_update_camera()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.26)
	mat.roughness = 0.95

	# Pit: floor + 4 low walls.
	_add_static_box(Vector3(0, -FLOOR_HALF.y, 0), FLOOR_HALF, mat, Basis())
	var wh := 5.0
	var t := FLOOR_HALF.x
	_add_static_box(Vector3(t, wh, 0), Vector3(1, wh, t), mat, Basis())
	_add_static_box(Vector3(-t, wh, 0), Vector3(1, wh, t), mat, Basis())
	_add_static_box(Vector3(0, wh, t), Vector3(t, wh, 1), mat, Basis())
	_add_static_box(Vector3(0, wh, -t), Vector3(t, wh, 1), mat, Basis())

	# Obstacles so the tower doesn't just pancake: a central wedge + 4 ramps.
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.35, 0.30, 0.22)
	omat.roughness = 0.9
	_add_static_box(Vector3(0, 1.5, 0), Vector3(4, 1.5, 4),
		omat, Basis(Vector3(1, 0, 0), deg_to_rad(45)))
	for a in 4:
		var ang := a * TAU / 4.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		_add_static_box(dir * 12.0 + Vector3(0, 2.0, 0), Vector3(7, 0.5, 4),
			omat, Basis(Vector3(-sin(ang), 0, cos(ang)), deg_to_rad(22)))

	# One MultiMesh for every dynamic box.
	var mmi := MultiMeshInstance3D.new()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(BOX, BOX, BOX) * 2.0
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.55
	bm.material = bmat
	_mm.mesh = bm
	mmi.multimesh = _mm
	add_child(mmi)

	# Wrecking ball (parked far below until launched).
	_ball = RigidBody3D.new()
	_ball.mass = 4000.0
	_ball.gravity_scale = 0.0
	var bcs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 3.0
	bcs.shape = sph
	_ball.add_child(bcs)
	var bmi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.0
	sm.height = 6.0
	bmi.mesh = sm
	var ballmat := StandardMaterial3D.new()
	ballmat.albedo_color = Color(0.1, 0.1, 0.12)
	ballmat.metallic = 0.9
	ballmat.roughness = 0.3
	bmi.material_override = ballmat
	_ball.add_child(bmi)
	_ball.position = Vector3(0, -50, 0)
	add_child(_ball)

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)

func _add_static_box(pos: Vector3, half: Vector3, mat: Material, basis: Basis) -> void:
	var sb := StaticBody3D.new()
	sb.transform = Transform3D(basis, pos)
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

# Tall-ish column footprint so bodies cascade rather than land as one slab.
func _grid_dims(n: int) -> Vector2i:
	var side := maxi(2, int(round(pow(float(n) / 24.0, 1.0 / 3.0))))
	return Vector2i(side, side)

func _slot_position(idx: int, dims: Vector2i, base_y: float) -> Vector3:
	var x := idx % dims.x
	var z := (idx / dims.x) % dims.y
	var y := idx / (dims.x * dims.y)
	var jx := randf_range(-0.15, 0.15)
	var jz := randf_range(-0.15, 0.15)
	return Vector3(
		(x - dims.x * 0.5) * SPACING + jx,
		base_y + y * SPACING,
		(z - dims.y * 0.5) * SPACING + jz)

func _rebuild(n: int) -> void:
	if _pit:
		_pit.queue_free()
	_bodies.clear()
	_pit = Node3D.new()
	add_child(_pit)

	_mm.instance_count = 0
	_mm.instance_count = n
	var dims := _grid_dims(n)
	for i in n:
		var rb := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(BOX, BOX, BOX) * 2.0
		cs.shape = bs
		rb.add_child(cs)
		rb.position = _slot_position(i, dims, 8.0)
		_pit.add_child(rb)
		_bodies.append(rb)
		_mm.set_instance_color(i, Color.from_hsv(fmod(0.58 + i * 0.00011, 1.0), 0.6, 0.98))
	_count = n

func _restack() -> void:
	var dims := _grid_dims(_bodies.size())
	for i in _bodies.size():
		var rb := _bodies[i]
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.global_position = _slot_position(i, dims, 14.0)

func _explode(strength: float) -> void:
	var c := Vector3(0, 3, 0)
	for rb in _bodies:
		var d := rb.global_position - c
		var dist := maxf(d.length(), 0.5)
		var dir := d / dist
		var falloff := clampf(14.0 / dist, 0.2, 1.0)
		rb.apply_impulse((dir + Vector3.UP * 0.6).normalized() * strength * falloff)
		rb.angular_velocity += Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))

func _drop_ball() -> void:
	_ball.gravity_scale = 1.0
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = Vector3(randf_range(-3, 3), 34, randf_range(-3, 3))
	_ball.linear_velocity = Vector3(0, -40, 0)

func _process(delta: float) -> void:
	_cam_angle += delta * 0.1
	_update_camera()

	for idx in _bodies.size():
		_mm.set_instance_transform(idx, _bodies[idx].global_transform)

	var pm := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_phys_ms_smooth = lerp(_phys_ms_smooth, pm, 0.1)
	_phys_ms_peak = maxf(_phys_ms_peak * 0.995, pm)

	# Real physics Hz over a ~0.4 s window: how fast sim time actually advances.
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _wall_prev >= 0.4:
		var pf := Engine.get_physics_frames()
		_real_hz = (pf - _pf_prev) / (now - _wall_prev)
		_pf_prev = pf
		_wall_prev = now

	var engine_name := str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var over := _phys_ms_smooth > PHYS_BUDGET_MS
	var rt_ratio := clampf(_real_hz / 60.0, 0.0, 1.0)
	var status := "REAL-TIME" if rt_ratio > 0.95 else "SLOWED %.2fx" % rt_ratio
	_hud.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if over else Color.WHITE)
	_hud.text = "%s\nbodies: %d      active: %d\nphysics step: %5.1f ms  (peak %5.1f)  / %.1f ms budget\nsim clock: %s      render FPS: %d\n[1-5 count   SPACE restack   E blast   B ball]" % [
		engine_name,
		_bodies.size(), active, _phys_ms_smooth, _phys_ms_peak, PHYS_BUDGET_MS,
		status, Engine.get_frames_per_second()]

func _update_camera() -> void:
	var r := 50.0
	_cam.position = Vector3(cos(_cam_angle) * r, 28, sin(_cam_angle) * r)
	_cam.look_at(Vector3(0, 4, 0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _restack()
			KEY_E: _explode(28.0)
			KEY_B: _drop_ball()
			KEY_BRACKETRIGHT: _rebuild(mini(_count * 2, 80000))
			KEY_BRACKETLEFT: _rebuild(maxi(_count / 2, 250))
			KEY_R: _cam_angle = 0.0
			KEY_1: _rebuild(COUNTS[0])
			KEY_2: _rebuild(COUNTS[1])
			KEY_3: _rebuild(COUNTS[2])
			KEY_4: _rebuild(COUNTS[3])
			KEY_5: _rebuild(COUNTS[4])
			KEY_ESCAPE: get_tree().quit()
