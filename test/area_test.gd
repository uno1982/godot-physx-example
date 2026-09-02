extends SceneTree

# Verifies Area3D body_entered / body_exited via PhysX trigger shapes.

var _area: Area3D
var _ball: RigidBody3D
var _tick := 0
var _entered := 0
var _exited := 0

func _initialize() -> void:
	print("[area] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(20, 1, 20)
	fc.shape = fs
	fb.add_child(fc)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)

	# A trigger box sitting just above the floor.
	_area = Area3D.new()
	var ac := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(4, 3, 4)
	ac.shape = abox
	_area.add_child(ac)
	_area.position = Vector3(0, 1.5, 0)
	_area.body_entered.connect(func(b): _entered += 1; print("[area]   body_entered: ", b.name))
	_area.body_exited.connect(func(b): _exited += 1; print("[area]   body_exited: ", b.name))
	root.add_child(_area)

	# Ball starts outside, falls through the trigger, lands, then is flung out.
	_ball = RigidBody3D.new()
	_ball.name = "Ball"
	var bc := CollisionShape3D.new()
	var bs := SphereShape3D.new()
	bs.radius = 0.5
	bc.shape = bs
	_ball.add_child(bc)
	_ball.position = Vector3(0, 8, 0)
	root.add_child(_ball)

	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 120:
		print("[area]   flinging ball sideways out of the area")
		_ball.linear_velocity = Vector3(40, 5, 0)
	if _tick >= 220:
		var ok := _entered >= 1 and _exited >= 1
		print("[area] entered=%d exited=%d -> %s" % [_entered, _exited, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
