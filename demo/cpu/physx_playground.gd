extends Node3D

# Interactive PhysX playground: a first-person CharacterBody3D, a jointed ragdoll,
# a hinged door, a pin-joint pendulum row, and a box pile. Built for recording.
#
# Controls:
#   W A S D / arrows  move        SPACE  jump        mouse  look
#   left click        launch a ragdoll
#   right click       fire a heavy ball that blasts nearby bodies on impact
#   R                 reset the ragdoll and boxes
#   ESC               release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025

var _char: CharacterBody3D
var _cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _gravity := 18.0
var _spawn_root: Node3D
var _hud: Label
var _phys_ms := 0.0

const PILE_COUNT := 2000
var _pile_mm: MultiMesh
var _pile_bodies: Array[RigidBody3D] = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_world()
	_build_character()
	_spawn_root = Node3D.new()
	add_child(_spawn_root)

	# One MultiMesh draw call for the whole box pile.
	var mmi := MultiMeshInstance3D.new()
	_pile_mm = MultiMesh.new()
	_pile_mm.transform_format = MultiMesh.TRANSFORM_3D
	_pile_mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.6
	bm.material = bmat
	_pile_mm.mesh = bm
	mmi.multimesh = _pile_mm
	add_child(mmi)

	_reset_scene()

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -60, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.32, 0.34)
	mat.roughness = 0.95
	_static_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60), mat)

	# Hinged door.
	var post := _static_box(Vector3(-6, 1.5, -4), Vector3(0.3, 3, 0.3), mat)
	var door := RigidBody3D.new()
	door.name = "Door"
	_visual_box(door, Vector3(2, 2.8, 0.15), Color(0.5, 0.35, 0.2))
	_col_box(door, Vector3(2, 2.8, 0.15))
	door.position = Vector3(-4.9, 1.5, -4)
	door.mass = 20.0
	add_child(door)
	var hinge := HingeJoint3D.new()
	hinge.position = Vector3(-6, 1.5, -4)
	hinge.rotation_degrees = Vector3(-90, 0, 0)
	add_child(hinge)
	hinge.node_a = hinge.get_path_to(post)
	hinge.node_b = hinge.get_path_to(door)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-100))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(100))

	# Pendulum row (pin joints).
	for i in 5:
		var anchor := _static_box(Vector3(-2 + i * 1.0, 5, 6), Vector3(0.1, 0.1, 0.1), mat)
		var bob := RigidBody3D.new()
		_visual_box(bob, Vector3(0.5, 0.5, 0.5), Color.from_hsv(0.55 + i * 0.08, 0.6, 0.95))
		_col_box(bob, Vector3(0.5, 0.5, 0.5))
		bob.position = Vector3(-2 + i * 1.0, 2.5, 6)
		bob.mass = 2.0
		add_child(bob)
		var pin := PinJoint3D.new()
		pin.position = Vector3(-2 + i * 1.0, 5, 6)
		add_child(pin)
		pin.node_a = pin.get_path_to(anchor)
		pin.node_b = pin.get_path_to(bob)
		if i == 0:
			bob.position = Vector3(-4.5, 5, 6) # pull the first one out

	# Dangling chains to shoot ragdolls into.
	for c in 4:
		_build_chain(Vector3(-4.5 + c * 3.0, 6.5, 1.5), 6)

func _build_chain(top: Vector3, links: int) -> void:
	var link_h := 0.5
	var link_w := 0.4
	var anchor := StaticBody3D.new()
	anchor.position = top
	add_child(anchor)
	var prev: Node3D = anchor
	for i in links:
		var seg := RigidBody3D.new()
		_visual_box(seg, Vector3(link_w, link_h, link_w), Color.from_hsv(fmod(0.08 + i * 0.05, 1.0), 0.5, 0.9))
		_col_box(seg, Vector3(link_w, link_h, link_w))
		var pos := top - Vector3(0, (i + 0.5) * link_h, 0)
		seg.position = pos
		seg.mass = 2.0
		add_child(seg)
		var j := PinJoint3D.new()
		j.position = top - Vector3(0, i * link_h, 0)
		add_child(j)
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(seg)
		prev = seg

func _build_character() -> void:
	_char = CharacterBody3D.new()
	_char.name = "Player"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	_char.add_child(cs)
	_char.position = Vector3(0, 2, 10)
	add_child(_char)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 0.7, 0)
	_cam.current = true
	_char.add_child(_cam)

func _ragdoll(origin: Vector3, xf: Basis = Basis(), velocity: Vector3 = Vector3.ZERO) -> Array:
	# pelvis - torso - head, two legs, two arms. Cone-twist at spine/neck/hips/
	# shoulders, hinge at knees/elbows. `xf` orients the body, `velocity`
	# launches every part.
	var at := func(local: Vector3) -> Vector3: return origin + xf * local
	var parts := {}
	parts.pelvis = _rd_box(at.call(Vector3(0, 1.1, 0)), Vector3(0.5, 0.3, 0.28), 3.0)
	parts.torso = _rd_box(at.call(Vector3(0, 1.6, 0)), Vector3(0.5, 0.6, 0.28), 5.0)
	parts.head = _rd_sphere(at.call(Vector3(0, 2.15, 0)), 0.18, 1.5)
	parts.l_thigh = _rd_capsule(at.call(Vector3(-0.16, 0.7, 0)), 0.12, 0.45, 2.0)
	parts.r_thigh = _rd_capsule(at.call(Vector3(0.16, 0.7, 0)), 0.12, 0.45, 2.0)
	parts.l_shin = _rd_capsule(at.call(Vector3(-0.16, 0.2, 0)), 0.1, 0.45, 1.5)
	parts.r_shin = _rd_capsule(at.call(Vector3(0.16, 0.2, 0)), 0.1, 0.45, 1.5)
	parts.l_uarm = _rd_capsule(at.call(Vector3(-0.34, 1.62, 0)), 0.09, 0.36, 1.3)
	parts.r_uarm = _rd_capsule(at.call(Vector3(0.34, 1.62, 0)), 0.09, 0.36, 1.3)
	parts.l_farm = _rd_capsule(at.call(Vector3(-0.34, 1.18, 0)), 0.08, 0.36, 1.0)
	parts.r_farm = _rd_capsule(at.call(Vector3(0.34, 1.18, 0)), 0.08, 0.36, 1.0)

	for p in parts.values():
		p.basis = xf
		p.linear_velocity = velocity

	_cone(parts.pelvis, parts.torso, at.call(Vector3(0, 1.35, 0)), 30, 20)
	_cone(parts.torso, parts.head, at.call(Vector3(0, 1.95, 0)), 40, 30)
	_cone(parts.pelvis, parts.l_thigh, at.call(Vector3(-0.16, 0.95, 0)), 50, 20)
	_cone(parts.pelvis, parts.r_thigh, at.call(Vector3(0.16, 0.95, 0)), 50, 20)
	_knee(parts.l_thigh, parts.l_shin, at.call(Vector3(-0.16, 0.45, 0)))
	_knee(parts.r_thigh, parts.r_shin, at.call(Vector3(0.16, 0.45, 0)))
	_cone(parts.torso, parts.l_uarm, at.call(Vector3(-0.30, 1.84, 0)), 80, 40)
	_cone(parts.torso, parts.r_uarm, at.call(Vector3(0.30, 1.84, 0)), 80, 40)
	_knee(parts.l_uarm, parts.l_farm, at.call(Vector3(-0.34, 1.40, 0)))
	_knee(parts.r_uarm, parts.r_farm, at.call(Vector3(0.34, 1.40, 0)))
	return parts.values()

func _reset_scene() -> void:
	for c in _spawn_root.get_children():
		c.queue_free()
	_pile_bodies.clear()

	# A wall of PILE_COUNT collision-only boxes, drawn by the MultiMesh.
	var w := 20
	var d := 5
	var spacing := 1.04
	_pile_mm.instance_count = 0
	_pile_mm.instance_count = PILE_COUNT
	for i in PILE_COUNT:
		var x := i % w
		var z := (i / w) % d
		var y := i / (w * d)
		var b := RigidBody3D.new()
		_col_box(b, Vector3.ONE)
		b.position = Vector3(
			8.0 + (x - w * 0.5) * spacing,
			0.55 + y * spacing,
			-16.0 + (z - d * 0.5) * spacing)
		_spawn_root.add_child(b)
		_pile_bodies.append(b)
		_pile_mm.set_instance_color(i, Color.from_hsv(fmod(0.05 + i * 0.0007, 1.0), 0.5, 0.95))

	call_deferred("_ragdoll", Vector3(0, 0, 2))

func _rd_box(pos: Vector3, size: Vector3, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	_visual_box(rb, size, Color(0.85, 0.75, 0.6))
	_col_box(rb, size)
	rb.position = pos
	rb.mass = mass
	_spawn_root.add_child(rb)
	return rb

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

func _rd_capsule(pos: Vector3, r: float, h: float, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h + r * 2
	mi.mesh = cm
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h + r * 2
	cs.shape = cap
	rb.add_child(cs)
	rb.position = pos
	rb.mass = mass
	_spawn_root.add_child(rb)
	return rb

func _cone(a: RigidBody3D, b: RigidBody3D, at: Vector3, swing_deg: float, twist_deg: float) -> void:
	var j := ConeTwistJoint3D.new()
	j.position = at
	_spawn_root.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_deg))
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_deg))

func _knee(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var j := HingeJoint3D.new()
	j.position = at
	_spawn_root.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-120))
	j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(0))

# --- helpers ---------------------------------------------------------------

func _static_box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	_col_box(sb, size)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	return sb

func _visual_box(n: Node, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
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
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_reset_scene()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_fire_ragdoll()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_fire_ball()

const BLAST_RADIUS := 8.0
const BLAST_SPEED := 22.0 # peak added speed (m/s) at the blast centre

func _fire_ball() -> void:
	var fwd := (-_cam.global_transform.basis.z).normalized()
	var ball := RigidBody3D.new()
	ball.mass = 6.0
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.3, 0.1)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.15, 0.0)
	sm.material = m
	mi.mesh = sm
	ball.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.35
	cs.shape = sh
	ball.add_child(cs)
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	_spawn_root.add_child(ball)
	ball.global_position = _cam.global_position + fwd * 1.5
	ball.linear_velocity = fwd * 45.0
	ball.body_entered.connect(_on_ball_hit.bind(ball), CONNECT_ONE_SHOT)

func _on_ball_hit(_other: Node, ball: RigidBody3D) -> void:
	var center := ball.global_position
	_blast(center)
	# brief flash then remove the ball
	var t := get_tree().create_timer(0.05)
	t.timeout.connect(func() -> void: if is_instance_valid(ball): ball.queue_free())

func _blast(center: Vector3) -> void:
	var params := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = BLAST_RADIUS
	params.shape = s
	params.transform = Transform3D(Basis(), center)
	params.collide_with_bodies = true
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 512)
	var seen := {}
	for h in hits:
		var col: Object = h.get("collider")
		if col is RigidBody3D and not seen.has(col):
			seen[col] = true
			var body := col as RigidBody3D
			var off := body.global_position - center
			var dist := off.length()
			var dir := (off / dist) if dist > 0.001 else Vector3.UP
			var falloff := clampf(1.0 - dist / BLAST_RADIUS, 0.0, 1.0)
			# Add a bounded change in velocity (independent of mass) so a light
			# jointed link and a heavy crate get the same shove instead of the
			# solver whipping the constrained islands apart.
			var dv := (dir + Vector3.UP * 0.3).normalized() * BLAST_SPEED * falloff
			body.sleeping = false
			body.linear_velocity += dv

func _fire_ragdoll() -> void:
	var fwd := (-_cam.global_transform.basis.z).normalized()
	# Upright body a couple metres ahead at foot level, hurled forward + up
	# with random spin so it tumbles.
	var spawn := _cam.global_position + fwd * 2.5 + Vector3(0, -1.0, 0)
	var parts := _ragdoll(spawn, Basis(Vector3.UP, _yaw), fwd * 20.0 + Vector3(0, 4.5, 0))
	for p in parts:
		p.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))

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
		if Input.is_key_pressed(KEY_SPACE):
			v.y = JUMP
		else:
			v.y = -0.1
	else:
		v.y -= _gravity * delta
	_char.velocity = v
	_char.move_and_slide()

	# CharacterBody3D doesn't push RigidBodies on its own -- do it manually.
	for i in _char.get_slide_collision_count():
		var c := _char.get_slide_collision(i)
		var col := c.get_collider()
		if col is RigidBody3D:
			var push := -c.get_normal() * 4.0
			push.y = maxf(push.y, 0.0)
			col.apply_impulse(push * col.mass * 0.15, c.get_position() - col.global_position)

	for i in _pile_bodies.size():
		_pile_mm.set_instance_transform(i, _pile_bodies[i].global_transform)

	_phys_ms = lerp(_phys_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1)

func _process(_dt: float) -> void:
	_hud.text = "%s   |   WASD move  SPACE jump  L-click ragdoll  R reset  ESC\n%d dynamic boxes    physics: %.1f ms    FPS: %d    on_floor: %s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		_pile_bodies.size(), _phys_ms, Engine.get_frames_per_second(), _char.is_on_floor()]
