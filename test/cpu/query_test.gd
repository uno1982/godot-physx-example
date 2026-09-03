extends SceneTree

# Exercises scene queries against the PhysX backend.

var _state: PhysicsDirectSpaceState3D
var _floor_rid: RID
var _ball_body: RigidBody3D
var _tick := 0
var _pass := true

func _initialize() -> void:
	print("[query] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(10, 1, 10)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	_floor_rid = floor_body.get_rid()

	_ball_body = RigidBody3D.new()
	var bc := CollisionShape3D.new()
	var bs := SphereShape3D.new()
	bs.radius = 1.0
	bc.shape = bs
	_ball_body.add_child(bc)
	_ball_body.position = Vector3(3, 1.0, 0)
	_ball_body.freeze = true
	root.add_child(_ball_body)

	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick < 5:
		return false
	_state = _ball_body.get_world_3d().direct_space_state

	# 1) Ray straight down hits the floor.
	var rp := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -5, 0))
	var r := _state.intersect_ray(rp)
	_check("ray down hits floor", not r.is_empty() and r.rid == _floor_rid)
	if not r.is_empty():
		_check("ray hit near y=0", absf(r.position.y) < 0.05)
		_check("ray normal points up", r.normal.dot(Vector3.UP) > 0.9)

	# 2) Ray that misses everything.
	var rp2 := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 20), Vector3(0, -5, 20))
	_check("ray in empty space misses", _state.intersect_ray(rp2).is_empty())

	# 3) Ray with the floor excluded misses.
	var rp3 := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -5, 0))
	rp3.exclude = [_floor_rid]
	_check("ray with floor excluded misses", _state.intersect_ray(rp3).is_empty())

	# 4) Shape overlap: a box where the ball is should find the ball.
	var sp := PhysicsShapeQueryParameters3D.new()
	var probe := BoxShape3D.new()
	probe.size = Vector3(2, 2, 2)
	sp.shape = probe
	sp.transform = Transform3D(Basis(), Vector3(3, 1.0, 0))
	var hits := _state.intersect_shape(sp, 8)
	var found_ball := false
	for h in hits:
		if h.rid == _ball_body.get_rid():
			found_ball = true
	_check("shape overlap finds the ball", found_ball)

	# 5) Shape overlap away from anything finds nothing.
	sp.transform = Transform3D(Basis(), Vector3(3, 20, 0))
	_check("shape overlap in air finds nothing", _state.intersect_shape(sp, 8).is_empty())

	# 6) Motion cast: box moving toward the floor stops partway.
	var mp := PhysicsShapeQueryParameters3D.new()
	var mbox := BoxShape3D.new()
	mbox.size = Vector3.ONE
	mp.shape = mbox
	mp.transform = Transform3D(Basis(), Vector3(-3, 5, 0))
	mp.motion = Vector3(0, -10, 0)
	var frac := _state.cast_motion(mp)
	_check("cast_motion returns a fraction < 1", frac.size() == 2 and frac[0] < 0.99 and frac[0] > 0.0)

	print("[query] ", "PASS" if _pass else "FAIL")
	quit(0 if _pass else 1)
	return true

func _check(name: String, ok: bool) -> void:
	print("[query]   %s ... %s" % [name, "ok" if ok else "FAIL"])
	if not ok:
		_pass = false
