extends RefCounted
class_name FirstPersonCharacter
# Shared first-person controller: WASD + jump movement on a real
# CharacterBody3D, mouse-look, manual RigidBody3D/PhysicsServer3D-body
# pushing (CharacterBody3D doesn't do this on its own), and ragdoll firing.
# Extracted from physx_playground.gd, which had all of this duplicated
# in-place -- same composition pattern as FlyCamera (see its own header):
# a RefCounted helper wrapping real nodes the owning scene creates/places,
# not a Node subclass/script of its own, so a scene can still add its own
# scene-specific input (a bomb, a different fire button, ...) alongside
# this rather than being locked into one fixed control scheme.
#
# Usage:
#   var fp := FirstPersonCharacter.new(_char, _cam, _spawn_root)
#   func _physics_process(delta): fp.physics_process(delta)
#   func _unhandled_input(event): fp.handle_input(event)   # mouse-look only
#   fp.fire_ragdoll()   # e.g. on left click

const SPEED := 5.0
const JUMP_VELOCITY := 6.0
const GRAVITY := 18.0
const MOUSE_SENS := 0.0025

var body: CharacterBody3D
var cam: Camera3D
var spawn_parent: Node3D
var yaw: float
var pitch: float
var speed: float
var jump_velocity: float
var gravity: float
var mouse_sensitivity: float

func _init(p_body: CharacterBody3D, p_cam: Camera3D, p_spawn_parent: Node3D,
		p_speed: float = SPEED, p_jump_velocity: float = JUMP_VELOCITY,
		p_gravity: float = GRAVITY, p_mouse_sensitivity: float = MOUSE_SENS) -> void:
	body = p_body
	cam = p_cam
	spawn_parent = p_spawn_parent
	yaw = body.rotation.y
	pitch = cam.rotation.x
	speed = p_speed
	jump_velocity = p_jump_velocity
	gravity = p_gravity
	mouse_sensitivity = p_mouse_sensitivity

# Mouse-look only -- unlike FlyCamera's own handle_input(), this doesn't
# manage Input.mouse_mode itself (the owning scene typically wants that tied
# to its own click-to-shoot handling, e.g. "first click captures the mouse
# AND fires", not a separate held-button-to-look gesture). Returns true if
# this event was consumed, same convention as FlyCamera.handle_input().
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.57, 1.57)
		return true
	return false

func physics_process(delta: float) -> void:
	body.rotation.y = yaw
	cam.rotation.x = pitch

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	var dir := (body.transform.basis * input).normalized()

	var v := body.velocity
	v.x = dir.x * speed
	v.z = dir.z * speed
	if body.is_on_floor():
		if Input.is_key_pressed(KEY_SPACE):
			v.y = jump_velocity
		else:
			v.y = -0.1
	else:
		v.y -= gravity * delta
	body.velocity = v
	body.move_and_slide()

	_push_slide_collisions()

# CharacterBody3D doesn't push RigidBodies on its own -- do it manually.
# RID-based (PhysicsServer3D.body_apply_impulse), not `col is RigidBody3D`
# -- a PhysXDestructible3D's pieces are raw PhysicsServer3D bodies with no
# owning RigidBody3D node, so that check silently skipped every one of
# them: the player could shove a plain box around but debris just sat
# there taking only the raw depenetration response, which read as
# "harder to push". get_collider_rid() resolves to the actual piece body
# regardless of what node (if any real Node at all) owns it.
func _push_slide_collisions() -> void:
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		var rid := c.get_collider_rid()
		if rid.is_valid() and PhysicsServer3D.body_get_mode(rid) == PhysicsServer3D.BODY_MODE_RIGID:
			var body_mass: float = PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_MASS)
			var body_origin: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM).origin
			var push := -c.get_normal() * 4.0
			push.y = maxf(push.y, 0.0)
			PhysicsServer3D.body_apply_impulse(rid, push * body_mass * 0.15, c.get_position() - body_origin)

# --- ragdoll -----------------------------------------------------------

# Launches a ragdoll from just in front of the camera, tumbling forward.
# Returns the spawned RigidBody3D parts (same as spawn_ragdoll()) in case
# the caller wants to do something extra with them.
func fire_ragdoll() -> Array:
	var fwd := (-cam.global_transform.basis.z).normalized()
	var spawn := cam.global_position + fwd * 2.5 + Vector3(0, -1.0, 0)
	var parts := spawn_ragdoll(spawn, Basis(Vector3.UP, yaw), fwd * 20.0 + Vector3(0, 4.5, 0))
	for p in parts:
		p.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
	return parts

# pelvis - torso - head, two legs, two arms. Cone-twist at spine/neck/hips/
# shoulders, hinge at knees/elbows. `xf` orients the body, `velocity`
# launches every part. Added under spawn_parent, same as fire_ragdoll().
func spawn_ragdoll(origin: Vector3, xf: Basis = Basis(), velocity: Vector3 = Vector3.ZERO) -> Array:
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
	_hinge(parts.l_thigh, parts.l_shin, at.call(Vector3(-0.16, 0.45, 0)), xf, false)
	_hinge(parts.r_thigh, parts.r_shin, at.call(Vector3(0.16, 0.45, 0)), xf, false)
	_cone(parts.torso, parts.l_uarm, at.call(Vector3(-0.30, 1.84, 0)), 80, 40)
	_cone(parts.torso, parts.r_uarm, at.call(Vector3(0.30, 1.84, 0)), 80, 40)
	_hinge(parts.l_uarm, parts.l_farm, at.call(Vector3(-0.34, 1.40, 0)), xf, true)
	_hinge(parts.r_uarm, parts.r_farm, at.call(Vector3(0.34, 1.40, 0)), xf, true)
	return parts.values()

func _rd_box(pos: Vector3, size: Vector3, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.75, 0.6)
	m.roughness = 0.6
	bm.material = m
	mi.mesh = bm
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	rb.add_child(cs)
	rb.position = pos
	rb.mass = mass
	spawn_parent.add_child(rb)
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
	spawn_parent.add_child(rb)
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
	spawn_parent.add_child(rb)
	return rb

func _cone(a: RigidBody3D, b: RigidBody3D, at: Vector3, swing_deg: float, twist_deg: float) -> void:
	var j := ConeTwistJoint3D.new()
	j.position = at
	spawn_parent.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing_deg))
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist_deg))

# A knee or an elbow: a hinge across the body (a HingeJoint3D turns about its
# local Z, so it's turned to lie along the body's X), bending one way only --
# a knee takes the foot back, an elbow the hand forward (the body faces -Z).
# Godot's hinge angle runs clockwise about the axis, so back is positive.
func _hinge(a: RigidBody3D, b: RigidBody3D, at: Vector3, xf: Basis, bend_forward: bool) -> void:
	var j := HingeJoint3D.new()
	j.position = at
	j.basis = xf * Basis(Vector3.UP, PI / 2.0)
	spawn_parent.add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-120.0 if bend_forward else 0.0))
	j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(0.0 if bend_forward else 120.0))
