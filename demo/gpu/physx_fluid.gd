extends Node3D

# GPU fluid demo for the PhysX backend (PhysXParticleFluid3D). A faucet streams
# water into a glass tank. SPACE drops a ball that splashes and bobs on the
# surface (approximate buoyancy via PhysXParticleFluid3D.get_submersion()).
#
#   F  toggle faucet    SPACE  drop a ball    R  drain & reset    ESC

const WATER_DENSITY := 1000.0

var _fluid: PhysXParticleFluid3D
var _balls: Array[RigidBody3D] = []
var _hud: Label
var _t := 0.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -50, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(2.0, 1.5, 2.4), Vector3(0, 0.8, 0))

	# Narrow deep tank: a thick floor slab and four walls that sink into it, so
	# there is no floor/wall seam for particles to squeeze through at depth.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.8, 0.85, 0.13)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var w := 1.0 # inner width
	var t := 0.15 # wall thickness
	var hh := 2.6 # wall height above the floor
	# Floor: top face at y = 0.
	_wall(Vector3(0, -0.25, 0), Vector3(w + 2.0 * t, 0.5, w + 2.0 * t), mat)
	var wy := hh * 0.5 - 0.25 # walls extend 0.5 m below the floor top
	var wh := hh + 0.5
	var off := w * 0.5 + t * 0.5
	_wall(Vector3(-off, wy, 0), Vector3(t, wh, w + 2.0 * t), mat)
	_wall(Vector3(off, wy, 0), Vector3(t, wh, w + 2.0 * t), mat)
	_wall(Vector3(0, wy, -off), Vector3(w + 2.0 * t, wh, t), mat)
	_wall(Vector3(0, wy, off), Vector3(w + 2.0 * t, wh, t), mat)

	_spawn_fluid()

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)

func _wall(pos: Vector3, size: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)

func _spawn_fluid() -> void:
	if _fluid and is_instance_valid(_fluid):
		_fluid.queue_free()
	_fluid = PhysXParticleFluid3D.new()
	_fluid.spawn_on_ready = false
	_fluid.particle_count = 90000
	_fluid.particle_size = 0.035
	_fluid.viscosity = 0.02
	_fluid.cohesion = 0.03
	_fluid.surface_tension = 0.008
	# Faucet: pour down from above one corner of the tank.
	_fluid.position = Vector3(-0.25, 2.3, -0.25)
	_fluid.emission_rate = 9000.0
	_fluid.emission_radius = 0.06
	_fluid.emission_velocity = Vector3(0.4, -2.5, 0.4)
	_fluid.emitting = true
	_fluid.surface_mesh = true # PhysX GPU isosurface -> smooth water mesh
	# Foam/spray where the stream hits the pool and where balls splash.
	_fluid.foam_enabled = true
	_fluid.foam_particle_count = 30000
	_fluid.foam_lifetime = 1.6
	_fluid.foam_threshold = 120.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.4, 0.62, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.15
	m.roughness = 0.05
	m.refraction_enabled = true
	m.refraction_scale = 0.06
	_fluid.material_override = m
	add_child(_fluid)

func _drop_ball() -> void:
	var r := randf_range(0.09, 0.15)
	var rb := RigidBody3D.new()
	rb.mass = 700.0 * (4.0 / 3.0 * PI * pow(r, 3.0)) # a bit lighter than water
	rb.linear_damp = 0.2
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color.from_hsv(randf(), 0.7, 0.95)
	mm.roughness = 0.5
	sm.material = mm
	mi.mesh = sm
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	rb.add_child(cs)
	rb.set_meta("radius", r)
	rb.set_meta("volume", 4.0 / 3.0 * PI * pow(r, 3.0))
	rb.position = Vector3(randf_range(-0.3, 0.3), 3.0, randf_range(-0.3, 0.3))
	add_child(rb)
	_balls.append(rb)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_fluid.emitting = not _fluid.emitting
			KEY_SPACE:
				_drop_ball()
			KEY_R:
				for b in _balls:
					if is_instance_valid(b):
						b.queue_free()
				_balls.clear()
				_spawn_fluid()
			KEY_ESCAPE:
				get_tree().quit()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_fluid):
		return
	# Gentle wobble of the tank's gravity would be nicer, but keep it simple:
	# just apply approximate buoyancy + drag to the balls from the fluid state.
	_t += delta
	for rb in _balls:
		if not is_instance_valid(rb):
			continue
		var r: float = rb.get_meta("radius")
		var vol: float = rb.get_meta("volume")
		var box := AABB(rb.global_position - Vector3(r, r, r), Vector3(r, r, r) * 2.0)
		var submerged := clampf(_fluid.get_submersion(box) / (PI / 6.0), 0.0, 1.0)
		rb.linear_damp = lerpf(0.2, 3.0, submerged)
		if submerged > 0.0:
			var buoy: float = WATER_DENSITY * submerged * vol * 9.8
			rb.apply_central_force(Vector3.UP * minf(buoy, rb.mass * 9.8 * 1.4))

func _process(_dt: float) -> void:
	var live := _fluid.get_live_particle_count() if is_instance_valid(_fluid) else 0
	var faucet := ("ON" if is_instance_valid(_fluid) and _fluid.emitting else "OFF")
	var foam := _fluid.get_live_foam_count() if is_instance_valid(_fluid) else 0
	_hud.text = "PhysX GPU fluid   F faucet %s   SPACE drop a ball   R reset   ESC\nparticles: %d    foam: %d    balls: %d    FPS: %d" % [faucet, live, foam, _balls.size(), Engine.get_frames_per_second()]
