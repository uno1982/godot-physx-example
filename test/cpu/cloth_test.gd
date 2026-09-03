extends SceneTree

# A free PhysXCloth3D sheet is dropped onto a floor. Checks the CPU XPBD solver
# actually runs: the sheet falls, then settles on the floor (mean height drops
# and stabilizes just above it) with nothing going non-finite. Works on any GPU.

var _cloth: PhysXCloth3D
var _tick := 0
var _y_at_120 := 0.0
var _y_min := 1e9

func _initialize() -> void:
	print("[cloth] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXCloth3D"):
		print("[cloth] PhysXCloth3D not registered -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(10, 1, 10)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	_cloth = PhysXCloth3D.new()
	_cloth.grid_columns = 18
	_cloth.grid_rows = 18
	_cloth.grid_size = Vector2(1.4, 1.4)
	_cloth.pin_mode = PhysXCloth3D.PIN_NONE
	_cloth.wind_enabled = false
	_cloth.rotation_degrees = Vector3(-90, 0, 0) # lay flat, fall onto the floor
	_cloth.position = Vector3(0, 2.5, 0)
	root.add_child(_cloth)

func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _cloth == null:
		return true

	if _cloth.get_vertex_count() != 324:
		print("[cloth] FAIL: vertex_count = %d (expected 324)" % _cloth.get_vertex_count())
		quit(1)
		return true

	var box := _cloth.get_aabb()
	var world_center := _cloth.global_transform * box.get_center()
	if not _finite(world_center) or box.size.length() > 100.0:
		print("[cloth] FAIL: cloth exploded / non-finite: center=%s size=%s" % [world_center, box.size])
		quit(1)
		return true

	_y_min = minf(_y_min, world_center.y)
	if _tick == 120:
		_y_at_120 = world_center.y
	if _tick >= 240:
		var drift := absf(world_center.y - _y_at_120)
		if _y_min > 2.0:
			print("[cloth] FAIL: cloth never fell (min center y = %.2f)" % _y_min)
			quit(1)
			return true
		if world_center.y < -0.5:
			print("[cloth] FAIL: cloth fell through the floor (center y = %.2f)" % world_center.y)
			quit(1)
			return true
		if drift > 0.2:
			print("[cloth] FAIL: still moving at t=4s (|dy| = %.2f over last 2s)" % drift)
			quit(1)
			return true
		print("[cloth] PASS  (fell to y=%.2f, resting near %.2f, |dy|=%.3f)" % [_y_min, world_center.y, drift])
		quit(0)
		return true
	return false
