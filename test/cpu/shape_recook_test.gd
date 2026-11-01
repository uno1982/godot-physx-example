extends SceneTree

# Debug builds send a shape's data to the physics server twice: once when it's set on the resource, again when the
# shape is put on a CollisionShape3D (set_shape gives it the node's debug colour, which resends the data). The second
# send carries the same data, so it must not cook the mesh again (uno1982/godot#21). For a trimesh, a height map and a
# convex hull: assigning the shape (and resending an equal copy of the data) must cost a small fraction of the first
# cook, and a real change must still be cooked and reach the body (a ray down meets the moved surface).
var _t := 0
var _pass := true
var _trimesh: ConcavePolygonShape3D
var _faces: PackedVector3Array


func _ms(start: int) -> float:
	return (Time.get_ticks_usec() - start) / 1000.0


func _check(label: String, cook: float, again: float) -> void:
	# The first cook has to be big enough to tell apart from bookkeeping.
	var ok := cook > 2.0 and again < cook * 0.25
	print("[recook] %s: cook %.2f ms, same data again %.2f ms %s" % [label, cook, again, "OK" if ok else "FAIL"])
	_pass = _pass and ok


func _body_with(shape: Shape3D, label: String) -> void:
	var cs := CollisionShape3D.new()
	var start := Time.get_ticks_usec()
	cs.shape = shape
	var assign := _ms(start)
	print("[recook] %s: assigning to a CollisionShape3D %.2f ms" % [label, assign])
	var body := StaticBody3D.new()
	body.add_child(cs)
	get_root().add_child(body)


func _initialize() -> void:
	# A trimesh: a dense sphere's faces flattened onto a slab whose top is y = 0.
	var sphere := SphereMesh.new()
	sphere.radial_segments = 256
	sphere.rings = 128
	_faces = sphere.get_faces()
	for i in _faces.size():
		_faces[i] = Vector3(_faces[i].x * 20.0, minf(_faces[i].y, 0.0), _faces[i].z * 20.0)
	_trimesh = ConcavePolygonShape3D.new()
	var start := Time.get_ticks_usec()
	_trimesh.set_faces(_faces)
	var cook := _ms(start)
	start = Time.get_ticks_usec()
	_body_with(_trimesh, "trimesh %d tris" % (_faces.size() / 3))
	var assign := _ms(start)
	_check("trimesh assign", cook, assign)
	start = Time.get_ticks_usec()
	_trimesh.set_faces(_faces.duplicate())
	_check("trimesh equal copy", cook, _ms(start))

	var hm := HeightMapShape3D.new()
	var heights := PackedFloat32Array()
	heights.resize(1024 * 1024)
	for i in heights.size():
		heights[i] = sin(i * 0.01) * 0.5
	hm.map_width = 1024
	hm.map_depth = 1024
	start = Time.get_ticks_usec()
	hm.map_data = heights
	cook = _ms(start)
	start = Time.get_ticks_usec()
	var cs := CollisionShape3D.new()
	cs.shape = hm
	_check("height map 1024x1024 assign", cook, _ms(start))
	cs.free()

	var hull := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for i in 20000:
		points.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized())
	start = Time.get_ticks_usec()
	hull.points = points
	cook = _ms(start)
	start = Time.get_ticks_usec()
	cs = CollisionShape3D.new()
	cs.shape = hull
	_check("convex hull 20000 points assign", cook, _ms(start))
	cs.free()

	physics_frame.connect(_step)


func _ray_y() -> float:
	var space := get_root().get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.3, 10, 0.2), Vector3(0.3, -10, 0.2)))
	return hit.position.y if hit else NAN


func _step() -> void:
	_t += 1
	if _t == 3:
		var y := _ray_y()
		var ok := absf(y) < 0.01
		print("[recook] ray meets the trimesh at y = %.3f (expected 0) %s" % [y, "OK" if ok else "FAIL"])
		_pass = _pass and ok
		# A real change: the slab lifted 2 m.
		var moved := _faces.duplicate()
		for i in moved.size():
			moved[i].y += 2.0
		_trimesh.set_faces(moved)
	if _t == 6:
		var y := _ray_y()
		var ok := absf(y - 2.0) < 0.01
		print("[recook] after lifting the faces 2 m, the ray meets y = %.3f (expected 2) %s" % [y, "OK" if ok else "FAIL"])
		_pass = _pass and ok
		print("[recook] %s" % ("PASS" if _pass else "FAIL"))
		quit(0 if _pass else 1)
