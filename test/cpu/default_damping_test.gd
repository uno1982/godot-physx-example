extends SceneTree

# Project default damping (physics/3d/default_linear_damp / default_angular_damp,
# 0.1 each) applies to every rigid body, combined with the body's own damping
# per its damp mode, and an Area3D can override it -- the same as Godot
# Physics and Jolt. Bodies coast with no gravity for 1 s; what's left of their
# speed or spin is compared with e^(-total damping).
#   godot --headless --path . --script res://test/cpu/default_damping_test.gd

var _tick := 0
var _pass := true
var _bodies := {}


func _initialize() -> void:
	print("[damp] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)
	# name: [position, damp mode linear/angular, own damp]
	_add(root, "default", Vector3(0, 0, 0), RigidBody3D.DAMP_MODE_COMBINE, 0.0)
	_add(root, "replace_zero", Vector3(10, 0, 0), RigidBody3D.DAMP_MODE_REPLACE, 0.0)
	_add(root, "combine_half", Vector3(20, 0, 0), RigidBody3D.DAMP_MODE_COMBINE, 0.5)
	_add(root, "in_area", Vector3(40, 0, 0), RigidBody3D.DAMP_MODE_COMBINE, 0.0)

	# An area replacing the area-level damping with 2.0 around "in_area".
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 60) # around "in_area" only, along its path
	cs.shape = box
	area.add_child(cs)
	area.position = Vector3(40, 0, 0)
	area.linear_damp_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.linear_damp = 2.0
	area.angular_damp_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.angular_damp = 2.0
	area.monitorable = true
	root.add_child(area)


func _add(root: Node, n: String, pos: Vector3, mode: int, damp: float) -> void:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.5
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	rb.gravity_scale = 0.0
	rb.can_sleep = false
	rb.linear_damp_mode = mode
	rb.angular_damp_mode = mode
	rb.linear_damp = damp
	rb.angular_damp = damp
	root.add_child(rb)
	_bodies[n] = rb


func _check(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	print("  [%s] %-52s got %.3f want %.3f" % ["ok" if ok else "FAIL", label, got, want])
	if not ok:
		_pass = false


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 5:
		for rb in _bodies.values():
			rb.linear_velocity = Vector3(0, 0, 10)
			rb.angular_velocity = Vector3(0, 10, 0)
	if _tick == 65:
		# 1 s of coasting: speed fraction left = e^(-damp).
		_check("default: speed left after 1 s (damp 0.1)", _bodies.default.linear_velocity.z / 10.0, exp(-0.1), 0.01)
		_check("default: spin left after 1 s (damp 0.1)", _bodies.default.angular_velocity.y / 10.0, exp(-0.1), 0.01)
		_check("replace, own 0: no damping", _bodies.replace_zero.linear_velocity.z / 10.0, 1.0, 0.005)
		_check("combine, own 0.5: default + own = 0.6", _bodies.combine_half.linear_velocity.z / 10.0, exp(-0.6), 0.01)
		_check("in an area replacing it with 2.0", _bodies.in_area.linear_velocity.z / 10.0, exp(-2.0), 0.02)
		_check("in an area replacing it with 2.0 (spin)", _bodies.in_area.angular_velocity.y / 10.0, exp(-2.0), 0.02)
		var state := PhysicsServer3D.body_get_direct_state(_bodies.combine_half.get_rid())
		_check("direct state total_linear_damp (combine 0.5)", state.total_linear_damp, 0.6, 0.001)
		print("[damp] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false
