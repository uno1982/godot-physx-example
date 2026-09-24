extends PhysXTank3D
# Skid-steer controls: W/S drive both tracks forward/reverse, A/D bias the
# two tracks apart (a held A/D with no W/S held pivots in place, since
# left_ratio/right_ratio go to opposite signs) -- same W/S/A/D/Space keys as
# the other vehicles in this demo, but mapped onto PhysXTank3D's independent
# per-track ratio convention instead of a single throttle+steer pair.
# Left click fires a scaled-down version of physx_playground.gd's red
# "fireball" projectile (same radial-blast-on-impact mechanic, smaller ball
# and blast radius) from the turret's own current aim point.

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

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fire()

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
		if col is RigidBody3D and not seen.has(col):
			seen[col] = true
			var body := col as RigidBody3D
			var off := body.global_position - center
			var dist := off.length()
			var dir := (off / dist) if dist > 0.001 else Vector3.UP
			var falloff := clampf(1.0 - dist / BLAST_RADIUS, 0.0, 1.0)
			var dv := (dir + Vector3.UP * 0.3).normalized() * BLAST_SPEED * falloff
			body.sleeping = false
			body.linear_velocity += dv

func _physics_process(delta: float) -> void:
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
