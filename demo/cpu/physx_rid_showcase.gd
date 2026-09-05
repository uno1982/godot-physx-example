extends Node3D

# Same stress demo as physx_showcase.gd, but every dynamic box is a bare
# PhysicsServer3D RID body -- no RigidBody3D/CollisionShape3D Node pair, no
# scene tree, no per-node transform-notification overhead. One shared box
# shape RID is reused by every body. This isolates "solver + render sync"
# from "Godot Node overhead" so the two showcases can be compared directly
# at the same body count.
#
# Controls: identical to physx_showcase.gd (see that file's header).

const COUNTS := [1000, 5000, 10000, 25000, 50000]
const BOX := 0.5 # half-extent
const FLOOR_HALF := Vector3(40, 1, 40)
const SPACING := 1.12
const MASS := 1.0

var _count := 10000
var _bodies: Array[RID] = []
var _shape: RID
var _space: RID
var _mm: MultiMesh
var _hud: Label
var _cam: Camera3D
var _cam_angle := 0.0
var _phys_ms_smooth := 0.0
var _phys_ms_peak := 0.0
var _ball: RigidBody3D

var _pf_prev := 0
var _wall_prev := 0.0
var _real_hz := 60.0
const PHYS_BUDGET_MS := 1000.0 / 60.0

# Headless benchmark mode -- see physx_showcase.gd for the invocation shape:
#   ... demo/cpu/physx_rid_showcase.tscn --fixed-fps 60 -- bench count=25000 frames=600
var _bench := false
var _bench_frames := 1200
var _bench_frame := 0
var _bench_hz_sum := 0.0
var _bench_hz_n := 0
var _bench_hz_min := 1e9

func _ready() -> void:
	_wall_prev = float(Time.get_ticks_msec()) / 1000.0
	_pf_prev = Engine.get_physics_frames()
	for arg in OS.get_cmdline_user_args():
		if arg == "bench":
			_bench = true
		elif arg.begins_with("count="):
			_count = int(arg.substr(6))
		elif arg.begins_with("frames="):
			_bench_frames = int(arg.substr(7))
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

	_add_static_box(Vector3(0, -FLOOR_HALF.y, 0), FLOOR_HALF, mat, Basis())
	var wh := 5.0
	var t := FLOOR_HALF.x
	_add_static_box(Vector3(t, wh, 0), Vector3(1, wh, t), mat, Basis())
	_add_static_box(Vector3(-t, wh, 0), Vector3(1, wh, t), mat, Basis())
	_add_static_box(Vector3(0, wh, t), Vector3(t, wh, 1), mat, Basis())
	_add_static_box(Vector3(0, wh, -t), Vector3(t, wh, 1), mat, Basis())

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

	_space = get_world_3d().space

	# One shared box shape RID for every dynamic body -- no per-body shape
	# allocation at all.
	_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(_shape, Vector3(BOX, BOX, BOX))

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
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()

	_mm.instance_count = 0
	_mm.instance_count = n
	var dims := _grid_dims(n)
	for i in n:
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_space(body, _space)
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, _shape)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, MASS)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), _slot_position(i, dims, 8.0)))
		_bodies.append(body)
		_mm.set_instance_color(i, Color.from_hsv(fmod(0.58 + i * 0.00011, 1.0), 0.6, 0.98))
	_count = n

func _restack() -> void:
	var dims := _grid_dims(_bodies.size())
	for i in _bodies.size():
		var rid := _bodies[i]
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), _slot_position(i, dims, 14.0)))

func _explode(strength: float) -> void:
	var c := Vector3(0, 3, 0)
	for rid in _bodies:
		var state := PhysicsServer3D.body_get_direct_state(rid)
		if not state:
			continue
		var d := state.transform.origin - c
		var dist := maxf(d.length(), 0.5)
		var dir := d / dist
		var falloff := clampf(14.0 / dist, 0.2, 1.0)
		PhysicsServer3D.body_apply_central_impulse(rid, (dir + Vector3.UP * 0.6).normalized() * strength * falloff)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
			state.angular_velocity + Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))

func _drop_ball() -> void:
	_ball.gravity_scale = 1.0
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = Vector3(randf_range(-3, 3), 34, randf_range(-3, 3))
	_ball.linear_velocity = Vector3(0, -40, 0)

func _process(delta: float) -> void:
	_cam_angle += delta * 0.1
	_update_camera()

	if not _bench:
		for idx in _bodies.size():
			var state := PhysicsServer3D.body_get_direct_state(_bodies[idx])
			if state:
				_mm.set_instance_transform(idx, state.transform)

	var pm := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_phys_ms_smooth = lerp(_phys_ms_smooth, pm, 0.1)
	_phys_ms_peak = maxf(_phys_ms_peak * 0.995, pm)

	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _wall_prev >= 0.4:
		var pf := Engine.get_physics_frames()
		_real_hz = (pf - _pf_prev) / (now - _wall_prev)
		_pf_prev = pf
		_wall_prev = now
		if _bench and _bench_frame > 60:
			_bench_hz_sum += _real_hz
			_bench_hz_n += 1
			_bench_hz_min = minf(_bench_hz_min, _real_hz)
			print("[bench] frame=%d bodies=%d active=%d phys_ms=%5.2f (peak %5.2f) hz=%.1f" % [
				_bench_frame, _bodies.size(),
				int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
				_phys_ms_smooth, _phys_ms_peak, _real_hz])

	if _bench:
		_bench_frame += 1
		if _bench_frame >= _bench_frames:
			var engine_name := str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
			print("[bench] DONE engine=%s bodies=%d avg_hz=%.1f min_hz=%.1f avg_phys_ms=%.2f peak_phys_ms=%.2f" % [
				engine_name, _bodies.size(),
				_bench_hz_sum / maxf(_bench_hz_n, 1), _bench_hz_min,
				_phys_ms_smooth, _phys_ms_peak])
			get_tree().quit(0)
		return

	var engine_name := str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var over := _phys_ms_smooth > PHYS_BUDGET_MS
	var rt_ratio := clampf(_real_hz / 60.0, 0.0, 1.0)
	var status := "REAL-TIME" if rt_ratio > 0.95 else "SLOWED %.2fx" % rt_ratio
	_hud.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if over else Color.WHITE)
	_hud.text = "%s (RID bodies, no Nodes)\nbodies: %d      active: %d\nphysics step: %5.1f ms  (peak %5.1f)  / %.1f ms budget\nsim clock: %s      render FPS: %d\n[1-5 count   SPACE restack   E blast   B ball]" % [
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

func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	if _shape.is_valid():
		PhysicsServer3D.free_rid(_shape)
