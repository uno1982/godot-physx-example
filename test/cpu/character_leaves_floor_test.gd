extends SceneTree

# A motion moving away from a floor the body starts inside doesn't hit that floor, as on Jolt. Reported as characters
# that had sunk into the floor staying is_on_floor() after a jump's first move up: they skipped a tick of gravity, went
# higher and landed late. (Godot Physics does report the floor from inside a box, so it isn't the referee here.)
# - From inside a box or a mesh floor: an upward test reports nothing, and move_and_slide up leaves the floor.
# - No motion, or motion into the floor, from inside it still reports it.
# - A character standing normally still has its floor, walking on it too, and still leaves it when it jumps.

var _t := 0
var _ok := true
var _box_sunk: CharacterBody3D
var _mesh_sunk: CharacterBody3D
var _walker: CharacterBody3D
var _jumper: CharacterBody3D
var _walk_floor := true


func _check(cond: bool, msg: String) -> void:
	print("[leaves_floor] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box_floor(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(5, 1, 5)
	cs.shape = b
	body.add_child(cs)
	body.position = pos + Vector3(0, -0.5, 0)
	get_root().add_child(body)


func _mesh_floor(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var m := ConcavePolygonShape3D.new()
	m.set_faces(PackedVector3Array([Vector3(-2.5, 0, -2.5), Vector3(2.5, 0, -2.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, -2.5), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5)]))
	cs.shape = m
	body.add_child(cs)
	body.position = pos
	get_root().add_child(body)


func _character(pos: Vector3) -> CharacterBody3D:
	var c := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	c.add_child(cs)
	c.position = pos
	get_root().add_child(c)
	return c


func _hits(c: CharacterBody3D, motion: Vector3) -> bool:
	var p := PhysicsTestMotionParameters3D.new()
	p.from = c.global_transform
	p.motion = motion
	p.recovery_as_collision = true
	return PhysicsServer3D.body_test_motion(c.get_rid(), p, PhysicsTestMotionResult3D.new())


func _initialize() -> void:
	print("[leaves_floor] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	_box_floor(Vector3(0, 0, 0))
	_box_sunk = _character(Vector3(0, 0.85, 0))
	_mesh_floor(Vector3(0, 0, 8))
	_mesh_sunk = _character(Vector3(0, 0.85, 8))
	_box_floor(Vector3(0, 0, 16))
	_walker = _character(Vector3(-1, 0.92, 16))
	_box_floor(Vector3(0, 0, 24))
	_jumper = _character(Vector3(0, 0.92, 24))
	physics_frame.connect(_tick)


func _rise(c: CharacterBody3D, label: String) -> void:
	var before := c.position.y
	c.velocity = Vector3(0, 12, 0)
	c.move_and_slide()
	_check(c.position.y - before > 0.19, "%s: move_and_slide rises: %.3f m" % [label, c.position.y - before])
	_check(not c.is_on_floor(), "%s: and is off the floor" % label)


func _press(c: CharacterBody3D, walk: float) -> void:
	c.velocity = Vector3(walk, -0.1 if c.is_on_floor() else c.velocity.y - 18.0 / 60.0, 0)
	c.move_and_slide()


func _tick() -> void:
	_t += 1
	if _t == 2:
		for pair in [[_box_sunk, "box"], [_mesh_sunk, "mesh"]]:
			var c: CharacterBody3D = pair[0]
			var label: String = pair[1]
			_check(not _hits(c, Vector3(0, 0.1, 0)), "%s, 5 cm in: moving up doesn't hit it" % label)
			_check(_hits(c, Vector3(0, -0.1, 0)), "%s, 5 cm in: moving down does" % label)
		_check(_hits(_box_sunk, Vector3.ZERO), "box, 5 cm in: not moving at all reports it")
		_rise(_box_sunk, "box, 5 cm in")
		_rise(_mesh_sunk, "mesh, 5 cm in")
	if _t > 2 and _t < 60:
		_press(_walker, 0.0)
		_press(_jumper, 0.0)
	if _t >= 60 and _t < 120:
		_press(_walker, 1.0)
		_walk_floor = _walk_floor and _walker.is_on_floor()
		_press(_jumper, 0.0)
	if _t == 120:
		_check(_walk_floor, "walking on a floor it keeps it, every tick")
		_check(_jumper.is_on_floor(), "standing on a floor it has it")
		_check(not _hits(_jumper, Vector3(0, 0.2, 0)), "standing: moving up doesn't hit it")
		_rise(_jumper, "standing")
		print("[leaves_floor] %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
