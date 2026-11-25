extends SceneTree

# A sleeping body taken out of its space and put back stays asleep (#35): the PhysX actor is rebuilt on the way back,
# and it used to come back awake, so 2,500 resting props re-added at once all woke, gave a 0.5 s frame and then steps of
# ~33 ms while they settled again. Godot Physics and Jolt keep the sleep state across a space change.
#   1. 400 boxes resting asleep on a floor leave the space and come back: all asleep on the next frame, and none has
#      moved 60 frames later.
#   2. A falling (awake) box that leaves and comes back is still awake and still falling.
#   3. A sleeping box woken (body_set_state SLEEPING false) while out of the space comes back awake.
#   godot --headless --path . --script res://test/cpu/body_space_keep_sleep_test.gd

const GRID := 20 # 20 x 20 boxes
var _t := 0
var _ok := true
var _boxes: Array[RigidBody3D] = []
var _faller: RigidBody3D
var _woken: RigidBody3D
var _space: RID
var _rest := {}


func _check(cond: bool, msg: String) -> void:
	print("[keep-sleep] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box(parent: Node, pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 0.8, 0.8)
	cs.shape = shape
	b.add_child(cs)
	b.position = pos
	parent.add_child(b)
	return b


func _sleeping(b: RigidBody3D) -> bool:
	return PhysicsServer3D.body_get_state(b.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(60, 1, 60)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	for x in GRID:
		for z in GRID:
			_boxes.append(_box(world, Vector3((x - GRID / 2) * 1.5, 0.45, (z - GRID / 2) * 1.5)))
	_woken = _box(world, Vector3(25, 0.45, 25))
	_faller = _box(world, Vector3(-25, 200, -25))
	_faller.gravity_scale = 0.2 # still falling when it is moved


func _all_asleep() -> int:
	var n := 0
	for b in _boxes:
		if _sleeping(b):
			n += 1
	return n


func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 240:
		_space = _boxes[0].get_world_3d().space
		_check(_all_asleep() == _boxes.size(), "all %d boxes asleep before the move (%d)" % [_boxes.size(), _all_asleep()])
		_check(_sleeping(_woken), "the box to be woken is asleep before the move")
		_check(not _sleeping(_faller), "the falling box is awake before the move")
		for b in _boxes:
			_rest[b] = b.global_position
		for b in _boxes + [_woken, _faller]:
			PhysicsServer3D.body_set_space(b.get_rid(), RID())
		PhysicsServer3D.body_set_state(_woken.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
		for b in _boxes + [_woken, _faller]:
			PhysicsServer3D.body_set_space(b.get_rid(), _space)
	if _t == 241:
		_check(_all_asleep() == _boxes.size(), "all %d boxes asleep right after coming back (%d)" % [_boxes.size(), _all_asleep()])
		_check(not _sleeping(_faller), "the falling box came back awake")
		_check(not _sleeping(_woken), "the box woken while out of the space came back awake")
	if _t == 300:
		var moved := 0
		for b in _boxes:
			if b.global_position.distance_to(_rest[b]) > 0.001:
				moved += 1
		_check(moved == 0, "no resting box moved in the 60 frames after (%d moved)" % moved)
		_check(_all_asleep() == _boxes.size(), "all boxes still asleep 60 frames later (%d)" % _all_asleep())
		_check(_faller.linear_velocity.y < -1.0, "the falling box is still falling (%.2f m/s)" % _faller.linear_velocity.y)
		quit(0 if _ok else 1)
	return false
