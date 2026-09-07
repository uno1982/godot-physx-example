extends Node3D

# SoftBody3D cascade -- a wave of squishy blobs tumbles down a staircase and a
# run of angled ramps into a pit, so you can watch them deform on every edge and
# check they never punch through the steps. Runtime-built; one MultiMesh-free
# pile of stock SoftBody3D nodes on the PhysX backend.
#
#   WASD + mouse   free-fly camera   (Space/Ctrl up-down, Shift = faster)
#   F      drop another batch onto the running pile (count keeps climbing)
#   1..4   drop a batch of 12 / 24 / 40 / 64
#   B  roll a heavy ball in    C  clear the blobs    R  reset    Tab  free mouse    ESC  quit
#
# Headless benchmark (no window/rendering):
#   godot --headless --path . demo/cpu/physx_soft_body.tscn --fixed-fps 60 -- bench count=40 frames=600

const COUNTS := [12, 24, 40, 64]
const COLORS := [
	Color(0.87, 0.35, 0.32), Color(0.35, 0.6, 0.87), Color(0.55, 0.8, 0.4),
	Color(0.9, 0.7, 0.3), Color(0.7, 0.45, 0.85), Color(0.4, 0.8, 0.78),
]

var _count := 24
var _batch := 24 # blobs per F / per number-key drop
var _blobs: Array[SoftBody3D] = []
var _stage: Node3D
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _mouse_captured := true
var _spawn_z := 3.0
var _spawn_y := 10.0
var _launch_batches: Array = [] # [{sbs:[SoftBody3D], t:int}] pending downhill shove
var _phys_frame := 0
var _cam: Camera3D
var _hud: Label
var _ball: RigidBody3D
var _phys_ms := 0.0

var _bench := false
var _bench_frames := 600
var _bench_frame := 0
var _bench_ms_sum := 0.0
var _bench_ms_n := 0

func _ready() -> void:
	seed(20260906) # deterministic cascade run to run
	for arg in OS.get_cmdline_user_args():
		if arg == "bench":
			_bench = true
		elif arg.begins_with("count="):
			_count = int(arg.substr(6))
		elif arg.begins_with("frames="):
			_bench_frames = int(arg.substr(7))
	_build_world()
	_spawn_wave(_count)
	if not _bench:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -48, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
	add_child(sun)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 400.0
	_cam.fov = 70.0
	add_child(_cam)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.35)
	mat.roughness = 0.9
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.42, 0.36, 0.28)
	rmat.roughness = 0.85

	# --- Marble run: chutes and a big stair section descending along -Z, built
	# by walking a cursor down the track. Every segment gets tall side rails.
	var trk := 5.5 # track width
	var rail := 1.6
	var cz := 0.0 # cursor: z of the current segment's top edge
	var cy := 24.0 # cursor: y of the track surface there

	# Hopper: a steep feed ramp at the same pitch as chute 1, its lower end
	# tucked under chute 1's top so the surface is continuous -- no lip for a
	# blob to hang on. Rails on three sides.
	var hop_ang := 40.0 # match chute 1
	var hop_len := 8.0
	var ca := deg_to_rad(hop_ang)
	# low end 1.2 m past the cursor (-Z) and 0.9 m below it, so chute 1 overlaps.
	var lo_z := cz - 1.2
	var lo_y := cy - 0.9
	var hz := lo_z + cos(ca) * hop_len * 0.5
	var hy := lo_y + sin(ca) * hop_len * 0.5
	_add_ramp(Vector3(0, hy, hz), Vector3(trk + 1.0, 0.6, hop_len), -hop_ang, 0.0, rmat)
	_add_ramp(Vector3(trk * 0.5 + 0.6, hy + 1.0, hz), Vector3(0.6, 2.4, hop_len), -hop_ang, 0.0, mat)
	_add_ramp(Vector3(-trk * 0.5 - 0.6, hy + 1.0, hz), Vector3(0.6, 2.4, hop_len), -hop_ang, 0.0, mat)
	# Backstop at the high end.
	var top_z := lo_z + cos(ca) * hop_len
	var top_y := lo_y + sin(ca) * hop_len
	_add_box(Vector3(0, top_y + 1.2, top_z + 0.4), Vector3(trk + 2, 4, 0.6), mat, Basis())
	_spawn_z = lo_z + cos(ca) * hop_len * 0.72
	_spawn_y = lo_y + sin(ca) * hop_len * 0.72 + 3.0

	# Chute 1: long and steep -- the wave builds speed and squashes flat.
	var c := _add_chute(cz, cy, 13.0, 40.0, trk, rail, rmat, mat)
	cz = c.x
	cy = c.y

	# Stair section: shallow steps, each tilted a few degrees forward so a blob
	# that lands on one keeps rolling off the front edge onto the next -- and
	# every tread is only a touch wider than a blob, so nothing parks. Each box
	# runs well past its front lip (+Z) to underlap the step above; no seam.
	var nsteps := 7
	var srise := 1.25
	var srun := 1.15
	var stilt := 7.0 # forward tilt, degrees
	cy -= 0.4 # drop just under the chute lip
	var stair_top_z := cz
	var stair_top_y := cy
	for s in nsteps:
		_add_ramp(Vector3(0, cy - 3.0, cz - srun * 0.5 + 1.4), Vector3(trk, 6.0, srun + 2.8), -stilt, 0.0, mat)
		cy -= srise
		cz -= srun
	# Low rails that follow the stair slope, not full-height walls.
	var s_dz := stair_top_z - cz
	var s_dy := stair_top_y - cy
	var s_len := sqrt(s_dz * s_dz + s_dy * s_dy) + 3.0
	var s_ang := rad_to_deg(atan2(s_dy, s_dz))
	var s_mz := (stair_top_z + cz) * 0.5
	var s_my := (stair_top_y + cy) * 0.5 + 0.6
	_add_ramp(Vector3(trk * 0.5 + 0.4, s_my, s_mz), Vector3(0.6, 2.4, s_len), -s_ang, 0.0, mat)
	_add_ramp(Vector3(-trk * 0.5 - 0.4, s_my, s_mz), Vector3(0.6, 2.4, s_len), -s_ang, 0.0, mat)

	# Chute 2: shallower, carries the pile out toward the camera.
	c = _add_chute(cz, cy, 12.0, 24.0, trk, rail, rmat, mat)
	cz = c.x
	cy = c.y

	# Catch basin.
	var bl := 13.0
	_add_box(Vector3(0, cy - 0.5, cz - bl * 0.5), Vector3(trk + 7, 1, bl), mat, Basis())
	_add_box(Vector3(trk * 0.5 + 3.5, cy + 1.4, cz - bl * 0.5), Vector3(1, 3, bl), mat, Basis())
	_add_box(Vector3(-trk * 0.5 - 3.5, cy + 1.4, cz - bl * 0.5), Vector3(1, 3, bl), mat, Basis())
	_add_box(Vector3(0, cy + 1.4, cz - bl), Vector3(trk + 7, 3, 1), mat, Basis())

	# Free-fly camera; start well back and above the basin looking up the run.
	_cam.position = Vector3(6.0, cy + 16.0, cz - 20.0)
	_cam.look_at(Vector3(0.0, s_my, s_mz))
	_cam_yaw = _cam.rotation.y
	_cam_pitch = _cam.rotation.x

	_ball = RigidBody3D.new()
	_ball.mass = 1200.0
	_ball.gravity_scale = 0.0
	var bcs := CollisionShape3D.new()
	var bsp := SphereShape3D.new()
	bsp.radius = 1.1
	bcs.shape = bsp
	_ball.add_child(bcs)
	var bmi := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 1.1
	bsm.height = 2.2
	bmi.mesh = bsm
	var ballmat := StandardMaterial3D.new()
	ballmat.albedo_color = Color(0.1, 0.1, 0.12)
	ballmat.metallic = 0.9
	ballmat.roughness = 0.3
	bmi.material_override = ballmat
	_ball.add_child(bmi)
	_ball.position = Vector3(0, -50, 0)
	add_child(_ball)

	if not _bench:
		var layer := CanvasLayer.new()
		add_child(layer)
		_hud = Label.new()
		_hud.position = Vector2(16, 12)
		_hud.add_theme_font_size_override("font_size", 19)
		_hud.add_theme_color_override("font_color", Color.WHITE)
		_hud.add_theme_color_override("font_outline_color", Color.BLACK)
		_hud.add_theme_constant_override("outline_size", 4)
		layer.add_child(_hud)

func _add_ramp(center: Vector3, size: Vector3, x_deg: float, z_deg: float, mat: Material) -> void:
	var b := Basis(Vector3(1, 0, 0), deg_to_rad(x_deg)) * Basis(Vector3(0, 0, 1), deg_to_rad(z_deg))
	_add_box(center, size, mat, b)

# A downhill chute of `length` at `deg` (its -Z end lower), its top edge at the
# surface point (top_z, top_y). Adds the ramp floor + two side rails. Returns the
# new cursor as Vector2(z, y).
func _add_chute(top_z: float, top_y: float, length: float, deg: float,
		trk: float, rail_h: float, floor_mat: Material, rail_mat: Material) -> Vector2:
	var a := deg_to_rad(deg)
	var dz := cos(a) * length
	var dy := sin(a) * length
	var mz := top_z - dz * 0.5
	var my := top_y - dy * 0.5
	# The floor and rails run 1.5 m past each end so they underlap the adjoining
	# segments -- no seam for a fast blob to fall through.
	_add_ramp(Vector3(0, my, mz), Vector3(trk, 0.6, length + 3.0), -deg, 0.0, floor_mat)
	_add_ramp(Vector3(trk * 0.5 + 0.3, my + rail_h * 0.4, mz), Vector3(0.5, rail_h, length + 3.0), -deg, 0.0, rail_mat)
	_add_ramp(Vector3(-trk * 0.5 - 0.3, my + rail_h * 0.4, mz), Vector3(0.5, rail_h, length + 3.0), -deg, 0.0, rail_mat)
	return Vector2(top_z - dz, top_y - dy)

func _add_box(pos: Vector3, size: Vector3, mat: Material, basis: Basis) -> void:
	var sb := StaticBody3D.new()
	sb.transform = Transform3D(basis, pos)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)

const MAX_BLOBS := 260

# Drop another batch of `n` blobs into the hopper. `reset` clears the course
# first; otherwise they pile on top of whatever is already running, so the
# count -- and the physics cost -- keeps climbing.
func _spawn_wave(n: int, reset: bool = true) -> void:
	if reset:
		if _stage != null:
			_stage.queue_free()
		_stage = Node3D.new()
		_stage.name = "Stage"
		add_child(_stage)
		_blobs.clear()
		_launch_batches.clear()
	elif _stage == null:
		return
	n = mini(n, MAX_BLOBS - _blobs.size())
	if n <= 0:
		return

	var batch: Array[SoftBody3D] = []
	var side := int(ceil(sqrt(float(n))))
	for i in n:
		var sb := SoftBody3D.new()
		var is_box := (i % 4) == 0
		if is_box:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.8
			bm.subdivide_width = 3
			bm.subdivide_height = 3
			bm.subdivide_depth = 3
			sb.mesh = bm
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.42
			sm.height = 0.84
			sm.radial_segments = 14
			sm.rings = 9
			sb.mesh = sm
		sb.total_mass = 1.4
		sb.simulation_precision = 10
		sb.pressure_coefficient = 50.0
		sb.linear_stiffness = 0.8
		sb.ray_pickable = false
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLORS[i % COLORS.size()]
		mat.roughness = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sb.material_override = mat
		# Compact 3D block in the hopper so the batch tumbles down as a mass.
		var per_layer := side
		var layer := i / (per_layer * per_layer)
		var rem := i % (per_layer * per_layer)
		sb.position = Vector3(
			(rem % per_layer - per_layer * 0.5) * 1.0 + randf_range(-0.06, 0.06),
			_spawn_y + layer * 1.0,
			_spawn_z - (rem / per_layer) * 1.0 + randf_range(-0.15, 0.15))
		_stage.add_child(sb)
		_blobs.append(sb)
		batch.append(sb)
	_launch_batches.append({"sbs": batch, "t": 4}) # shove this batch downhill soon

func _drop(n: int) -> void:
	_batch = n
	_spawn_wave(n, false)

func _clear_blobs() -> void:
	if _stage != null:
		_stage.queue_free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)
	_blobs.clear()
	_launch_batches.clear()

func _roll_ball() -> void:
	_ball.gravity_scale = 1.0
	_ball.linear_velocity = Vector3(0, 0, -6)
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = Vector3(randf_range(-2, 2), 8.5, 1.0)

func _physics_process(_delta: float) -> void:
	_phys_frame += 1
	# Once each batch has been placed, shove it down the course -- toward -Z,
	# a touch of down, and a small per-blob spread so it fans out.
	var still: Array = []
	for b in _launch_batches:
		b.t -= 1
		if b.t > 0:
			still.append(b)
			continue
		for sb in b.sbs:
			if is_instance_valid(sb):
				var m: float = sb.total_mass
				PhysicsServer3D.soft_body_apply_central_impulse(sb.get_physics_rid(),
					Vector3(randf_range(-0.6, 0.6), -1.0, -5.5) * m)
	_launch_batches = still

func _process(delta: float) -> void:
	if not _bench:
		_fly_camera(delta)
	_phys_ms = lerp(_phys_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1)

	if _bench:
		_bench_frame += 1
		if _bench_frame > 60:
			_bench_ms_sum += _phys_ms
			_bench_ms_n += 1
			if _bench_frame % 30 == 0:
				print("[bench] frame=%d bodies=%d phys_ms=%.2f fps=%d" % [
					_bench_frame, _blobs.size(), _phys_ms, Engine.get_frames_per_second()])
		if _bench_frame >= _bench_frames:
			print("[bench] DONE bodies=%d avg_phys_ms=%.2f" % [_blobs.size(), _bench_ms_sum / maxf(_bench_ms_n, 1)])
			get_tree().quit(0)
		return

	var settled := 0
	for sb in _blobs:
		if PhysicsServer3D.soft_body_get_bounds(sb.get_physics_rid()).get_center().y < 2.0:
			settled += 1
	var cap := "  (max)" if _blobs.size() >= MAX_BLOBS else ""
	_hud.text = "SoftBody3D marble run (PhysX)   WASD + mouse fly · Space/Ctrl up-down · Shift fast\nF drop %d more · 1-4 drop 12/24/40/64 · B ball · C clear · R reset · Tab mouse · ESC\nblobs: %d%s   in the basin: %d   physics: %.1f ms   FPS: %d" % [
		_batch, _blobs.size(), cap, settled, _phys_ms, Engine.get_frames_per_second()]

const FLY_SPEED := 14.0
const MOUSE_SENS := 0.0025

func _fly_camera(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z -= 1
	if Input.is_key_pressed(KEY_S): mv.z += 1
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if Input.is_key_pressed(KEY_SPACE): mv.y += 1
	if Input.is_key_pressed(KEY_CTRL): mv.y -= 1
	var spd := FLY_SPEED * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_cam.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	_cam.position += (_cam.transform.basis * mv).normalized() * spd * delta if mv != Vector3.ZERO else Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * MOUSE_SENS
		_cam_pitch = clampf(_cam_pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F: _spawn_wave(_batch, false)
			KEY_B: _roll_ball()
			KEY_C: _clear_blobs()
			KEY_R: get_tree().reload_current_scene()
			KEY_1: _drop(COUNTS[0])
			KEY_2: _drop(COUNTS[1])
			KEY_3: _drop(COUNTS[2])
			KEY_4: _drop(COUNTS[3])
			KEY_TAB:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_ESCAPE: get_tree().quit()
