extends SceneTree

# GPU soft bodies on the PhysX backend (PxDeformableVolume, tetrahedral FEM).
# Forces the GPU path; SKIPs (exit 0) when there is no CUDA device. Checks a
# volume falls, collides with the static floor, deforms and settles -- and, on
# the TGS solver, that two volumes stack instead of merging (soft-vs-soft).

var _floor_a: SoftBody3D
var _stack_lo: SoftBody3D
var _stack_hi: SoftBody3D
var _pinned: SoftBody3D
var _t := 0
var _tgs := false
var _punched_x := 0.0

func _blob(pos: Vector3) -> SoftBody3D:
	var sb := SoftBody3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.4, 1.4, 1.4)
	m.subdivide_width = 4
	m.subdivide_height = 4
	m.subdivide_depth = 4
	sb.mesh = m
	sb.total_mass = 3.0
	sb.pressure_coefficient = 80.0
	sb.linear_stiffness = 0.85
	sb.simulation_precision = 20
	sb.ray_pickable = false
	sb.position = pos
	return sb

func _initialize() -> void:
	ProjectSettings.set_setting("physics/physx_3d/soft_body/mode", 2) # force GPU
	_tgs = int(ProjectSettings.get_setting("physics/physx_3d/simulation/solver_type", 0)) == 1
	print("[sbgpu] engine=%s solver=%s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"), "TGS" if _tgs else "PGS"])

	var root := Node3D.new()
	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(30, 1, 30)
	fc.shape = fs
	fb.add_child(fc)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)

	_floor_a = _blob(Vector3(-6, 3.5, 0))
	root.add_child(_floor_a)
	_stack_lo = _blob(Vector3(6, 1.3, 0))
	root.add_child(_stack_lo)
	_stack_hi = _blob(Vector3(6, 4.2, 0))
	root.add_child(_stack_hi)

	_pinned = _blob(Vector3(0, 5, -6))
	root.add_child(_pinned)

	get_root().add_child(root)
	call_deferred("_pin_top", _pinned)

func _pin_top(sb: SoftBody3D) -> void:
	var verts: PackedVector3Array = sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -1e9
	for v in verts:
		top = maxf(top, v.y)
	for i in verts.size():
		if verts[i].y >= top - 0.15:
			sb.set_point_pinned(i, true)

func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 3:
		# No CUDA -> the module could not build a volume; nothing to test here.
		var b := PhysicsServer3D.soft_body_get_bounds(_floor_a.get_physics_rid())
		if b.size == Vector3.ZERO:
			print("[sbgpu] SKIP (no GPU volume; CUDA unavailable)")
			quit(0)
			return true

	if _t == 90:
		# Punch the free body sideways -- central impulse on the GPU volume.
		_punched_x = PhysicsServer3D.soft_body_get_bounds(_floor_a.get_physics_rid()).get_center().x
		PhysicsServer3D.soft_body_apply_central_impulse(_floor_a.get_physics_rid(), Vector3(24, 8, 0))

	if _t < 360:
		return false

	var fa := PhysicsServer3D.soft_body_get_bounds(_floor_a.get_physics_rid())
	var lo := PhysicsServer3D.soft_body_get_bounds(_stack_lo.get_physics_rid())
	var hi := PhysicsServer3D.soft_body_get_bounds(_stack_hi.get_physics_rid())
	var pin := PhysicsServer3D.soft_body_get_bounds(_pinned.get_physics_rid())
	var fc := fa.get_center()
	if not _finite(fc) or fa.size.length() > 20.0:
		print("[sbgpu] FAIL: volume exploded / non-finite (%s size %s)" % [fc, fa.size])
		quit(1)
	elif fc.y > 2.5:
		print("[sbgpu] FAIL: volume never fell to the floor (center y = %.2f)" % fc.y)
		quit(1)
	elif fa.position.y < -0.6:
		print("[sbgpu] FAIL: volume sank through the floor (bottom y = %.2f)" % fa.position.y)
		quit(1)
	elif fa.size.y > 1.55 or fa.size.y < 0.5:
		print("[sbgpu] FAIL: volume did not deform sanely (height %.2f)" % fa.size.y)
		quit(1)
	elif fc.x - _punched_x < 3.0:
		print("[sbgpu] FAIL: central impulse had no effect (moved %.2f m in x)" % (fc.x - _punched_x))
		quit(1)
	elif pin.position.y < 2.5:
		print("[sbgpu] FAIL: pinned volume sagged (bottom y = %.2f)" % pin.position.y)
		quit(1)
	else:
		var gap := hi.get_center().y - lo.get_center().y
		var soft_soft := "n/a (PGS)"
		if _tgs:
			if gap < 0.7:
				print("[sbgpu] FAIL: TGS -- the two volumes merged instead of stacking (gap %.2f)" % gap)
				quit(1)
				return true
			soft_soft = "stacked, gap=%.2f" % gap
		print("[sbgpu] PASS  (fell to y=%.2f, deformed to h=%.2f, punched +%.1f m; pin held at y=%.2f; soft-vs-soft: %s)" % [
			fc.y, fa.size.y, fc.x - _punched_x, pin.position.y, soft_soft])
		quit(0)
	return true
