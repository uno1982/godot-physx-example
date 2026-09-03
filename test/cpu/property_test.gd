extends SceneTree

# Exercises per-body material (friction/bounce), damping, and axis locks.

var _tick := 0
var _pass := true
var _bouncy: RigidBody3D
var _damped: RigidBody3D
var _locked: RigidBody3D
var _bouncy_max_y := -100.0
var _bouncy_landed := false

func _initialize() -> void:
	print("[prop] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(40, 1, 40)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	var fmat := PhysicsMaterial.new()
	fmat.bounce = 1.0
	floor_body.physics_material_override = fmat
	root.add_child(floor_body)

	# Bouncy ball dropped from 5 m should rebound high.
	_bouncy = _make_ball(Vector3(-5, 5, 0))
	var bmat := PhysicsMaterial.new()
	bmat.bounce = 0.9
	_bouncy.physics_material_override = bmat
	root.add_child(_bouncy)

	# Heavily damped ball given a sideways shove should barely travel.
	_damped = _make_ball(Vector3(0, 1.0, 0))
	_damped.linear_damp = 20.0
	root.add_child(_damped)

	# Axis-locked ball: linear X/Z + all angular locked -> only moves on Y.
	_locked = _make_ball(Vector3(5, 3, 0))
	root.add_child(_locked)

	get_root().add_child(root)

	_damped.apply_central_impulse(Vector3(15, 0, 0))
	_locked.axis_lock_linear_x = true
	_locked.axis_lock_linear_z = true
	_locked.axis_lock_angular_x = true
	_locked.axis_lock_angular_y = true
	_locked.axis_lock_angular_z = true
	_locked.apply_central_impulse(Vector3(20, 0, 8))

func _make_ball(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.5
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	return rb

func _physics_process(_delta: float) -> bool:
	_tick += 1

	if _bouncy.global_position.y < 0.7:
		_bouncy_landed = true
	if _bouncy_landed:
		_bouncy_max_y = maxf(_bouncy_max_y, _bouncy.global_position.y)

	if _tick >= 180:
		_check("bouncy ball rebounded above 1.5 m", _bouncy_max_y > 1.5)
		_check("damped ball barely moved in X (<2 m)", absf(_damped.global_position.x) < 2.0)
		_check("axis-locked ball stayed on X=5", absf(_locked.global_position.x - 5.0) < 0.05)
		_check("axis-locked ball stayed on Z=0", absf(_locked.global_position.z) < 0.05)
		_check("axis-locked ball still fell on Y", _locked.global_position.y < 2.9)
		print("[prop] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
	return false

func _check(name: String, ok: bool) -> void:
	print("[prop]   %s ... %s" % [name, "ok" if ok else "FAIL"])
	if not ok:
		_pass = false
