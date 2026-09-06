extends SceneTree

# Stock SoftBody3D on the PhysX backend (module soft_body_* server API + CPU
# XPBD solver). Two bodies from the same sphere mesh:
#   A - free, with pressure: must fall, stay finite, land on the floor, keep
#       some volume (not pancake to a disc), and settle.
#   B - its top cap pinned in the air: must NOT fall to the floor.
#
# Bounds are read from PhysicsServer3D.soft_body_get_bounds() -- the node only
# refreshes its visual mesh AABB on frame_pre_draw, which does not run headless.

var _free: SoftBody3D
var _pinned: SoftBody3D
var _tick := 0
var _free_y_min := 1e9
var _free_y_at_150 := 0.0
var _rest_height := 0.0

func _make_sphere_soft(pos: Vector3) -> SoftBody3D:
	var sb := SoftBody3D.new()
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 24
	m.rings = 12
	sb.mesh = m
	sb.total_mass = 2.0
	sb.simulation_precision = 8
	sb.linear_stiffness = 0.6
	sb.pressure_coefficient = 40.0
	sb.ray_pickable = false
	sb.position = pos
	return sb

func _bounds(sb: SoftBody3D) -> AABB:
	return PhysicsServer3D.soft_body_get_bounds(sb.get_physics_rid())

func _initialize() -> void:
	# These test the CPU XPBD path specifically; pin GPU auto off.
	ProjectSettings.set_setting("physics/physx_3d/soft_body/mode", 1)
	print("[soft] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(40, 1, 40)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	_free = _make_sphere_soft(Vector3(0, 4, 0))
	root.add_child(_free)

	_pinned = _make_sphere_soft(Vector3(4, 4, 0))
	root.add_child(_pinned)

	get_root().add_child(root)
	_rest_height = _free.mesh.get_aabb().size.y

	call_deferred("_pin_top", _pinned)

func _pin_top(sb: SoftBody3D) -> void:
	var verts: PackedVector3Array = sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -1e9
	for v in verts:
		top = maxf(top, v.y)
	var n := 0
	for i in verts.size():
		if verts[i].y >= top - 0.08:
			sb.set_point_pinned(i, true)
			n += 1
	print("[soft] pinned %d top vertices on body B" % n)

func _finite_aabb(a: AABB) -> bool:
	return is_finite(a.position.x) and is_finite(a.position.y) and is_finite(a.position.z) \
		and is_finite(a.size.x) and is_finite(a.size.y) and is_finite(a.size.z)

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _free == null:
		return true

	var fa := _bounds(_free)
	var pa := _bounds(_pinned)
	if not _finite_aabb(fa) or not _finite_aabb(pa) or fa.size.length() > 50.0:
		print("[soft] FAIL: soft body exploded / non-finite (free size=%s)" % fa.size)
		quit(1)
		return true

	var free_center_y := fa.get_center().y
	_free_y_min = minf(_free_y_min, free_center_y)
	if _tick == 150:
		_free_y_at_150 = free_center_y

	if _tick >= 300:
		var free_bottom_y := fa.position.y
		var pinned_bottom_y := pa.position.y
		var drift := absf(free_center_y - _free_y_at_150)
		var vol_ratio := fa.size.y / maxf(_rest_height, 0.001)

		if _free_y_min > 2.5:
			print("[soft] FAIL: free body never fell (min center y = %.2f)" % _free_y_min)
			quit(1)
		elif free_bottom_y < -0.6:
			print("[soft] FAIL: free body fell through the floor (bottom y = %.2f)" % free_bottom_y)
			quit(1)
		elif vol_ratio < 0.35:
			print("[soft] FAIL: pressure body pancaked (height %.2f of rest %.2f)" % [fa.size.y, _rest_height])
			quit(1)
		elif drift > 0.25:
			print("[soft] FAIL: free body still moving at t=5s (|dy| = %.2f over last 2.5s)" % drift)
			quit(1)
		elif pinned_bottom_y < 1.5:
			print("[soft] FAIL: pinned body sagged to the floor (bottom y = %.2f)" % pinned_bottom_y)
			quit(1)
		else:
			print("[soft] PASS  (free: fell to y=%.2f rest y=%.2f |dy|=%.3f height=%.0f%%; pinned held, bottom y=%.2f)" % [
				_free_y_min, free_center_y, drift, vol_ratio * 100.0, pinned_bottom_y])
			quit(0)
		return true
	return false
