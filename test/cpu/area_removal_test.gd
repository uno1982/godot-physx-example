extends SceneTree

# Removing an area from a space (#39): the areas that saw it overlapping drop it, and removing many areas is not
# O(n^2). Every area used to be told about every removal, so taking 9,300 areas out of a space took ~165 ms; now only
# the areas holding area-overlap records are told.
#   1. A monitoring area A overlaps B and C (monitorable, among 300 passive areas): A sees both enter.
#   2. B leaves the space and comes back: A sees it enter again (its record was dropped); C gives no new event.
#   3. A stops monitoring while it still overlaps C, C leaves and comes back, A monitors again: A sees C enter
#      (the record of C was dropped although A was not monitoring).
#   4. B is freed while overlapping: no crash, no event for it after.
#   5. 9,300 passive areas leave the space in one frame in under 60 ms (~165 ms before).
#   godot --headless --path . --script res://test/cpu/area_removal_test.gd

const MANY := 9300
var _t := 0
var _ok := true
var _space: RID
var _shape: RID
var _a: RID
var _b: RID
var _c: RID
var _passive: Array[RID] = []
var _many: Array[RID] = []
var _added := {} # other area RID -> enter count
var _removed := {} # other area RID -> exit count


func _check(cond: bool, msg: String) -> void:
	print("[area-removal] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _area(pos: Vector3, monitorable: bool) -> RID:
	var r := PhysicsServer3D.area_create()
	PhysicsServer3D.area_add_shape(r, _shape)
	PhysicsServer3D.area_set_transform(r, Transform3D(Basis(), pos))
	PhysicsServer3D.area_set_monitorable(r, monitorable)
	PhysicsServer3D.area_set_space(r, _space)
	return r


func _on_area(status: int, rid: RID, _id: int, _other_shape: int, _self_shape: int) -> void:
	var d := _added if status == PhysicsServer3D.AREA_BODY_ADDED else _removed
	d[rid] = int(d.get(rid, 0)) + 1


func _monitor(on: bool) -> void:
	PhysicsServer3D.area_set_area_monitor_callback(_a, _on_area if on else Callable())


func _n(d: Dictionary, r: RID) -> int:
	return int(d.get(r, 0))


func _initialize() -> void:
	_space = root.get_world_3d().space
	_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(_shape, Vector3(0.5, 0.5, 0.5))
	_a = _area(Vector3.ZERO, false)
	_b = _area(Vector3(0.5, 0, 0), true)
	_c = _area(Vector3(-0.5, 0, 0), true)
	for i in 300:
		_passive.append(_area(Vector3(10 + (i % 20) * 3, 0, (i / 20) * 3), true))
	_monitor(true)


func _physics_process(_d: float) -> bool:
	_t += 1
	match _t:
		10:
			_check(_n(_added, _b) == 1 and _n(_added, _c) == 1, "A saw B and C enter (%d, %d)" % [_n(_added, _b), _n(_added, _c)])
			_check(_removed.is_empty(), "no exits yet")
			PhysicsServer3D.area_set_space(_b, RID())
		12:
			PhysicsServer3D.area_set_space(_b, _space)
		20:
			_check(_n(_added, _b) == 2, "B left and came back: A saw it enter again (%d)" % _n(_added, _b))
			_check(_n(_added, _c) == 1 and _n(_removed, _c) == 0, "no new event for C (%d in, %d out)" % [_n(_added, _c), _n(_removed, _c)])
			_monitor(false)
		22:
			PhysicsServer3D.area_set_space(_c, RID())
		24:
			PhysicsServer3D.area_set_space(_c, _space)
			_monitor(true)
		30:
			_check(_n(_added, _c) == 2, "C left while A was not monitoring: A sees it enter again (%d)" % _n(_added, _c))
			PhysicsServer3D.free_rid(_b)
		40:
			_check(_n(_added, _b) == 2, "B freed: no new event for it (%d in, %d out)" % [_n(_added, _b), _n(_removed, _b)])
			var side := int(ceil(sqrt(MANY)))
			for i in MANY:
				_many.append(_area(Vector3((i % side) * 2.0, 50, (i / side) * 2.0), true))
		50:
			var t0 := Time.get_ticks_usec()
			for r in _many:
				PhysicsServer3D.area_set_space(r, RID())
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			_check(ms < 60.0, "%d areas left the space in %.1f ms (under 60; ~165 before)" % [MANY, ms])
			for r in _many + _passive + [_a, _c]:
				PhysicsServer3D.free_rid(r)
			PhysicsServer3D.free_rid(_shape)
			quit(0 if _ok else 1)
	return false
