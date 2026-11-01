extends SceneTree

# Rays on a flat trimesh grid of n x n quads (front faces up), cast from above
# and below, with backface_collision and hit_back_faces each on and off
# (uno1982/godot#17). The normal must face the ray on every hit, face_index
# must be a source face, and a back face nearer the ray must not hide a front
# face behind it in a one-sided mesh. The expectations are Godot Physics'
# results; run on any engine:
#   godot --headless --path . --script res://test/cpu/trimesh_ray_sides_test.gd

const RAYS := 441

var _pass := true


func _grid(n: int, y: float) -> PackedVector3Array:
	var f := PackedVector3Array()
	var s := 22.0 / n
	for iz in n:
		for ix in n:
			var a := Vector3(-11 + ix * s, y, -11 + iz * s)
			f.append_array([a, a + Vector3(s, 0, 0), a + Vector3(s, 0, s), a, a + Vector3(s, 0, s), a + Vector3(0, 0, s)])
	return f


func _body(faces: PackedVector3Array, backface: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = backface
	sh.set_faces(faces)
	cs.shape = sh
	body.add_child(cs)
	root.add_child(body)
	return body


# 21 x 21 vertical rays through the y = 4 plane from from_y. Returns [hits, normals facing the ray, source face indices].
func _cast(sp: PhysicsDirectSpaceState3D, from_y: float, back_faces: bool, face_count: int) -> Array:
	var hits := 0
	var facing := 0
	var source := 0
	for zi in range(-10, 11):
		for xi in range(-10, 11):
			var p := Vector3(xi + 0.3, from_y, zi + 0.2)
			var q := PhysicsRayQueryParameters3D.create(p, Vector3(p.x, 8.0 - from_y, p.z))
			q.hit_back_faces = back_faces
			var r := sp.intersect_ray(q)
			if r.is_empty():
				continue
			hits += 1
			if (r.normal as Vector3).y * (4.0 - from_y) < 0.0:
				facing += 1
			if r.face_index >= 0 and r.face_index < face_count:
				source += 1
	return [hits, facing, source]


func _check(label: String, got: Array, hits: int) -> void:
	var ok: bool = got[0] == hits and got[1] == hits and got[2] == hits
	print("[ray sides] %s: %d/%d hits (expected %d), normals facing the ray %d, source face_index %d %s" % [label, got[0], RAYS, hits, got[1], got[2], "OK" if ok else "FAIL"])
	_pass = _pass and ok


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	for backface in [true, false]:
		for n in [1, 4, 16]:
			var faces := _grid(n, 4.0)
			var body := _body(faces, backface)
			for i in 3:
				await physics_frame
			var sp := body.get_world_3d().direct_space_state
			for back_faces in [true, false]:
				var label := "backface_collision %s, n = %d, hit_back_faces %s" % [backface, n, back_faces]
				_check(label + ", from above", _cast(sp, 10.0, back_faces, faces.size() / 3), RAYS)
				# From behind, only a back-face mesh queried for back faces is hit.
				_check(label + ", from below", _cast(sp, -2.0, back_faces, faces.size() / 3), RAYS if backface and back_faces else 0)
			body.free()

	# One-sided: a down-facing sheet 2 m above an up-facing one, in the same shape. A ray from above passes the
	# upper sheet's back faces and meets the lower sheet.
	var faces := _grid(1, 4.0)
	var top := _grid(1, 6.0)
	for i in range(0, top.size(), 3):
		faces.append_array([top[i], top[i + 2], top[i + 1]])
	var body := _body(faces, false)
	for i in 3:
		await physics_frame
	_check("one-sided, back faces above a front face", _cast(body.get_world_3d().direct_space_state, 10.0, true, faces.size() / 3), RAYS)

	print("[ray sides] %s" % ("PASS" if _pass else "FAIL"))
	quit(0 if _pass else 1)
