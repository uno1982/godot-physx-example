extends PhysXTank3D
# Skid-steer controls: W/S drive both tracks forward/reverse, A/D bias the
# two tracks apart (a held A/D with no W/S held pivots in place, since
# left_ratio/right_ratio go to opposite signs) -- same W/S/A/D/Space keys as
# the other vehicles in this demo, but mapped onto PhysXTank3D's independent
# per-track ratio convention instead of a single throttle+steer pair.
#
# Left click fires a scaled-down version of physx_playground.gd's red
# "fireball" projectile (same radial-blast-on-impact mechanic, smaller ball
# and blast radius) from the turret's own current aim point.
#
# Right click (hold) fires a machine gun. It damages destructibles through
# apply_radial_damage() with sub-overkill chip damage in a small radius --
# the graded-damage regime the cannon can never produce: cannon contact
# impacts go through the module's _check_impact_fracture(), whose damage is
# floored at health*1.5 (guaranteed overkill -> the whole asset shatters at
# once), while the gun chips a few bonds per burst, peeling lone chunks off
# and leaving the rest standing until later bursts split it. Two weapons,
# two breaking behaviors, one wall.

@export var ratio_speed := 2.0 # normalized ratio change/sec toward the target

# Only the active vehicle reads keyboard input -- see vehicle_rig.gd's own
# note on why the inactive one must relax to neutral instead of coasting.
var active := false

@onready var _turret: Node3D = get_node("Turret")

const MUZZLE_LOCAL := Vector3(0, 1.262, 2.845) # tip of the Gun mesh (size.z=2.5, centered at local z=1.595)
const BOMB_RADIUS := 0.15 # physx_playground.gd's fireball is 0.35 -- scaled down
const BOMB_SPEED := 45.0
const BLAST_RADIUS := 4.0 # playground's is 8.0 -- scaled down
const BLAST_SPEED := 14.0 # playground's is 22.0 -- scaled down

const MG_COOLDOWN := 0.09 # seconds between machine-gun rounds while held
const MG_RANGE := 300.0
const MG_DAMAGE := 4.0 # bond health ~2-3: clears it with falloff margin (2.0 bounced off)
const MG_RADIUS := 2.6 # wall's bonds are ~2 m apart -- 1.2 reached zero bonds; 2.6 chips a few
const MG_IMPULSE := 0.4 # nudge on whatever the round hits so the gun feels physical

var _mg_firing := false
var _mg_cooldown := 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fire()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_mg_firing = event.pressed

func _fire() -> void:
	var muzzle_pos := _turret.global_transform * MUZZLE_LOCAL
	var fwd := _turret.global_transform.basis.z.normalized() # Gun's own +Z barrel-forward, already includes the camera-driven pitch tank_turret_rig.gd applies

	var bomb := RigidBody3D.new()
	bomb.mass = 1.0
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BOMB_RADIUS
	sm.height = BOMB_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.15, 0.0)
	sm.material = mat
	mi.mesh = sm
	bomb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = BOMB_RADIUS
	cs.shape = sh
	bomb.add_child(cs)
	bomb.contact_monitor = true
	bomb.max_contacts_reported = 4

	get_tree().current_scene.add_child(bomb)
	bomb.global_position = muzzle_pos
	bomb.linear_velocity = fwd * BOMB_SPEED
	bomb.body_entered.connect(_on_bomb_hit.bind(bomb), CONNECT_ONE_SHOT)

func _on_bomb_hit(_other: Node, bomb: RigidBody3D) -> void:
	_blast(bomb.global_position)
	var t := get_tree().create_timer(0.05)
	t.timeout.connect(func() -> void: if is_instance_valid(bomb): bomb.queue_free())

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
		if seen.has(col):
			continue
		seen[col] = true
		if col is PhysXDestructible3D and not (col as PhysXDestructible3D).dynamic:
			# Static destructible: damage it directly (static bodies report
			# no contacts, so the engine's impact path can never see them).
			# Same contract as destructible_demo_rig.gd's bomb ("only STATIC
			# destructibles get scripted explosion damage"): dynamic walls
			# already break from the ball's own collision via
			# _check_impact_fracture(), and scripting damage on top would
			# double-dip. Damage POSITION is the blast center and the radius
			# does the spatial grading in asset space, so a direct hit
			# craters locally regardless of where the asset origin sits.
			# 8.0 makes the cannon the big tool: a wide, deep crater per
			# shot (the MG at 4.0/2.6 sprinkles small chips).
			(col as PhysXDestructible3D).apply_radial_damage(center, 8.0, 0.05, BLAST_RADIUS)
		if col is RigidBody3D:
			var body := col as RigidBody3D
			var off := body.global_position - center
			var dist := off.length()
			var dir := (off / dist) if dist > 0.001 else Vector3.UP
			var falloff := clampf(1.0 - dist / BLAST_RADIUS, 0.0, 1.0)
			var dv := (dir + Vector3.UP * 0.3).normalized() * BLAST_SPEED * falloff
			body.sleeping = false
			body.linear_velocity += dv

func _physics_process(delta: float) -> void:
	_tick_machine_gun(delta)
	if not active:
		left_ratio = move_toward(left_ratio, 0.0, ratio_speed * delta)
		right_ratio = move_toward(right_ratio, 0.0, ratio_speed * delta)
		brake = 0.0
		return

	var base := 0.0
	if Input.is_key_pressed(KEY_W):
		base = 1.0
	elif Input.is_key_pressed(KEY_S):
		base = -1.0

	var turn := 0.0
	if Input.is_key_pressed(KEY_A):
		turn += 1.0
	if Input.is_key_pressed(KEY_D):
		turn -= 1.0

	var target_left := clampf(base + turn, -1.0, 1.0)
	var target_right := clampf(base - turn, -1.0, 1.0)
	left_ratio = move_toward(left_ratio, target_left, ratio_speed * delta)
	right_ratio = move_toward(right_ratio, target_right, ratio_speed * delta)
	brake = 1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0

func _tick_machine_gun(delta: float) -> void:
	_mg_cooldown = maxf(_mg_cooldown - delta, 0.0)
	if _mg_firing and active and _mg_cooldown <= 0.0:
		_mg_cooldown = MG_COOLDOWN
		_fire_mg_round()

func _fire_mg_round() -> void:
	var muzzle_pos := _turret.global_transform * MUZZLE_LOCAL
	var fwd := _turret.global_transform.basis.z.normalized()
	# Hitscan -- one ray per shot, no per-round physics bodies (an 11 rps
	# tracer stream is busy enough already).
	var from := muzzle_pos
	var to := muzzle_pos + fwd * MG_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# PhysXTank3D is a plain Node3D (no body of its own); the ray is cast
	# from the muzzle outward, so nothing of the tank can be hit anyway --
	# no exclusion needed.
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end := to
	if hit:
		end = hit.position
		var col: Object = hit.get("collider")
		# Shove the hit body BEFORE any damage/split: apply_radial_damage()
		# can free the hit piece's body (chunk dedup on split), and
		# body_get_direct_state() on the freed RID errors out and returns
		# null ("Parameter body is null" spam).
		var state := PhysicsServer3D.body_get_direct_state(hit.rid)
		if state:
			state.apply_central_impulse(fwd * MG_IMPULSE)
		# apply_radial_damage() is the only graded-damage entry point: the
		# node's own contact-impact path floors its damage at health*1.5
		# (guaranteed whole-asset shatter), so script-level chip damage is
		# what partial breaking has to come through.
		if col is PhysXDestructible3D:
			(col as PhysXDestructible3D).apply_radial_damage(end, MG_DAMAGE, 0.05, MG_RADIUS)
	_spawn_tracer(from, end)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	tracer.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	tracer.material_override = mat
	tracer.top_level = true
	get_tree().current_scene.add_child(tracer)
	var t := get_tree().create_timer(0.04)
	t.timeout.connect(func() -> void: if is_instance_valid(tracer): tracer.queue_free())
