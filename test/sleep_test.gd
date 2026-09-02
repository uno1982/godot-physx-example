extends SceneTree

# Diagnostic: a body sleeps when settled, and wakes when hit.

var _box: RigidBody3D
var _ball: RigidBody3D
var _tick := 0

func _initialize() -> void:
	print("[sleep] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(20, 1, 20)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	_box = RigidBody3D.new()
	var bc := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE
	bc.shape = bs
	_box.add_child(bc)
	_box.position = Vector3(0, 3, 0)
	root.add_child(_box)

	_ball = RigidBody3D.new()
	var lc := CollisionShape3D.new()
	var ls := SphereShape3D.new()
	ls.radius = 0.5
	lc.shape = ls
	_ball.add_child(lc)
	_ball.position = Vector3(0, 40, 0)
	_ball.gravity_scale = 0.0
	_ball.freeze = true
	root.add_child(_ball)

	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1

	# Once the box is asleep, drop a ball on it.
	if _tick == 150:
		print("[sleep] t150 box sleeping=%s -> dropping ball" % _box.sleeping)
		_ball.freeze = false
		_ball.gravity_scale = 1.0
		_ball.linear_velocity = Vector3(0, -30, 0)

	if _tick % 30 == 0:
		print("[sleep] tick %4d  box.y=%.3f  box.sleeping=%s  active=%d" % [
			_tick, _box.global_position.y, _box.sleeping,
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])

	if _tick >= 360:
		var slept := true # box should have slept early
		var woke := _box.global_position.y > 0.55 or not _box.sleeping # ball impact moved/woke it near t150
		print("[sleep] RESULT slept_then_woke: check log above")
		quit(0)
	return false
