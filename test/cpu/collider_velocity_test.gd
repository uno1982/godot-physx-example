extends SceneTree

# Every API reporting a body's velocity at a point includes its spin, as on Jolt
# and Godot Physics. On a slab spinning in place at 0.5 rad/s these reported 0 on
# PhysX, even where its surface moves 3 m/s:
#   contact: collider velocity, local velocity
#   body_test_motion, move_and_collide, move_and_slide, get_platform_velocity
#   get_rest_info
# Run on any engine:
#   godot --headless --path . --script res://test/cpu/collider_velocity_test.gd

const TOL := 0.01
# The other engines' contact report is from a moment before the state it's checked against.
const LOCAL_TOL := 0.15

var _t := 0
var _ok := true
var _slab: RigidBody3D
var _puck: Puck
var _mover: CharacterBody3D
var _rider: CharacterBody3D


class Puck extends RigidBody3D:
	var collider_velocity := Vector3.ZERO
	var local_velocity := Vector3.ZERO
	var local_want := Vector3.ZERO
	var point := Vector3.ZERO
	var touching := false

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if state.get_contact_count() == 0:
			return
		touching = true
		point = state.get_contact_collider_position(0)
		collider_velocity = state.get_contact_collider_velocity_at_position(0)
		local_velocity = state.get_contact_local_velocity_at_position(0)
		var offset := state.get_contact_local_position(0) - (state.transform.origin + state.center_of_mass)
		local_want = state.linear_velocity + state.angular_velocity.cross(offset)


func _character(pos: Vector3) -> CharacterBody3D:
	var c := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	c.add_child(cs)
	c.position = pos
	get_root().add_child(c)
	return c


func _initialize() -> void:
	print("[collider_velocity] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	_slab = RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	_slab.add_child(cs)
	_slab.mass = 100000.0
	_slab.gravity_scale = 0.0
	_slab.can_sleep = false
	_slab.axis_lock_linear_x = true
	_slab.axis_lock_linear_y = true
	_slab.axis_lock_linear_z = true
	_slab.axis_lock_angular_x = true
	_slab.axis_lock_angular_z = true
	_slab.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_slab.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_slab.position = Vector3(0, -0.5, 0)
	_slab.angular_velocity = Vector3(0, 0.5, 0)
	get_root().add_child(_slab)

	_puck = Puck.new()
	var ps := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	ps.shape = sphere
	_puck.add_child(ps)
	_puck.position = Vector3(6, 0.5, 0)
	_puck.can_sleep = false
	_puck.contact_monitor = true
	_puck.max_contacts_reported = 4
	get_root().add_child(_puck)

	_mover = _character(Vector3(-6, 1.3, 0)) # hovers, only queried
	_rider = _character(Vector3(0, 1.05, 8))
	physics_frame.connect(_step)


func _slab_velocity(point: Vector3) -> Vector3:
	var s := PhysicsServer3D.body_get_direct_state(_slab.get_rid())
	return s.linear_velocity + s.angular_velocity.cross(point - (s.transform.origin + s.center_of_mass))


func _check(label: String, got: Vector3, want: Vector3, tol := TOL) -> void:
	var ok := got.distance_to(want) <= tol and want.length() > 0.2
	print("[collider_velocity] %s %s: got %s, want %s" % ["ok  " if ok else "FAIL", label, got.snappedf(0.001), want.snappedf(0.001)])
	_ok = _ok and ok


func _step() -> void:
	_t += 1
	_rider.velocity = Vector3(0, -0.1, 0)
	_rider.move_and_slide()
	if _t != 60:
		return
	if _puck.touching:
		_check("contact collider velocity", _puck.collider_velocity, _slab_velocity(_puck.point))
		_check("contact local velocity", _puck.local_velocity, _puck.local_want, LOCAL_TOL)
	else:
		print("[collider_velocity] FAIL no contact reported")
		_ok = false

	var params := PhysicsTestMotionParameters3D.new()
	params.from = _mover.global_transform
	params.motion = Vector3(0, -2, 0)
	var result := PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(_mover.get_rid(), params, result):
		_check("body_test_motion", result.get_collider_velocity(), _slab_velocity(result.get_collision_point()))
	else:
		print("[collider_velocity] FAIL body_test_motion: no hit")
		_ok = false

	var collision := _mover.move_and_collide(Vector3(0, -2, 0), true)
	if collision:
		_check("move_and_collide", collision.get_collider_velocity(), _slab_velocity(collision.get_position()))
	else:
		print("[collider_velocity] FAIL move_and_collide: no hit")
		_ok = false

	if _rider.get_slide_collision_count() > 0:
		var slide := _rider.get_slide_collision(0)
		_check("move_and_slide", slide.get_collider_velocity(), _slab_velocity(slide.get_position()))
		_check("get_platform_velocity", _rider.get_platform_velocity(), _slab_velocity(slide.get_position()))
	else:
		print("[collider_velocity] FAIL move_and_slide: no collision")
		_ok = false

	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	query.shape = shape
	query.transform = Transform3D(Basis(), Vector3(5, 0.48, 5))
	query.exclude = [_puck.get_rid(), _mover.get_rid(), _rider.get_rid()]
	var info := get_root().world_3d.direct_space_state.get_rest_info(query)
	if info.is_empty():
		print("[collider_velocity] FAIL get_rest_info: no hit")
		_ok = false
	else:
		_check("get_rest_info", info.linear_velocity, _slab_velocity(info.point))

	print("[collider_velocity] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
