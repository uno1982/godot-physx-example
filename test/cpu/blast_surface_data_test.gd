extends SceneTree

# PhysXBlastAuthoring keeps what's needed to texture the pieces, for each fracture pattern, on both ways through the
# authoring (a closed mesh, and one that goes through the mesh cleaner for its unwelded vertices).
# - Source faces: UVs and normals come through the cut. The mesh's UVs are a linear function of position here, so any
#   vertex's right UV is known, wherever a cut put it.
# - Cut faces: marked, facing out of their piece, undistorted (a UV distance is the same distance in mesh units), and the
#   two faces of a crack read the same UVs.
# - A mesh without UVs or normals still fractures, an inside-out one gets outward normals, and it all survives a save.
# - PhysXDestructible3D takes interior_material and breaks, with these assets and with one from before they existed.

const HALF := 1.0

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[blast_surface] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _uv_of(p: Vector3) -> Vector2:
	return Vector2(p.x * 0.25 + p.y * 0.1 + 0.5, p.z * 0.25 - p.y * 0.05 + 0.5)


# A 2 m box with the UVs above: 24 vertices (open to Blast: goes through the cleaner), or 8 welded ones (closed).
func _box(welded: bool) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * HALF * 2.0
	var a := box.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	if welded:
		var at := {}
		var new_verts := PackedVector3Array()
		var new_normals := PackedVector3Array()
		var remap := PackedInt32Array()
		for i in verts.size():
			var key := verts[i].snappedf(0.001)
			if not at.has(key):
				at[key] = new_verts.size()
				new_verts.append(verts[i])
				new_normals.append(verts[i].normalized())
			remap.append(at[key])
		for i in indices.size():
			indices[i] = remap[indices[i]]
		verts = new_verts
		normals = new_normals
	var uvs := PackedVector2Array()
	for v in verts:
		uvs.append(_uv_of(v))
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


func _pattern_texture() -> ImageTexture:
	# Black fill with white cracks reaching the edges: four panes.
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	for i in 64:
		img.set_pixel(32, i, Color.WHITE)
		img.set_pixel(i, 32, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (c - a).cross(b - a).normalized()


func _check_asset(asset: Resource, label: String, welded: bool) -> void:
	var points: Array = asset.chunk_points
	var normals: Array = asset.chunk_normals
	var uvs: Array = asset.chunk_uvs
	var starts: PackedInt32Array = asset.chunk_interior_starts
	_check(normals.size() == points.size() and uvs.size() == points.size() and starts.size() == points.size(), "%s: per-chunk arrays line up" % label)

	var outer_uv_error := 0.0
	var outer_normal_worst := 1.0
	var outer_area := 0.0
	var interior_tris := 0
	var stretch_worst := 0.0
	var facing_wrong := 0
	var interior_on_surface := 0
	var crack_uvs := {}
	var crack_seen := 0
	var crack_mismatch := 0.0
	var sizes_ok := true
	for c in range(1, points.size()):
		var p: PackedVector3Array = points[c]
		var n: PackedVector3Array = normals[c]
		var uv: PackedVector2Array = uvs[c]
		sizes_ok = sizes_ok and n.size() == p.size() and uv.size() == p.size()
		if not sizes_ok:
			continue
		var center := Vector3.ZERO
		for v in p:
			center += v
		center /= maxf(p.size(), 1)
		for t in range(0, p.size(), 3):
			var flat := _face_normal(p[t], p[t + 1], p[t + 2])
			var area := (p[t + 1] - p[t]).cross(p[t + 2] - p[t]).length() * 0.5
			if t < starts[c]:
				outer_area += area
				for v in range(t, t + 3):
					outer_uv_error = maxf(outer_uv_error, uv[v].distance_to(_uv_of(p[v])))
					if not welded and area > 1e-4:
						outer_normal_worst = minf(outer_normal_worst, n[v].dot(flat))
			else:
				interior_tris += 1
				if area > 1e-4:
					if flat.dot((p[t] + p[t + 1] + p[t + 2]) / 3.0 - center) < -1e-3:
						facing_wrong += 1
					for e in 3:
						var a := t + e
						var b := t + (e + 1) % 3
						var length := p[a].distance_to(p[b])
						if length > 0.02:
							stretch_worst = maxf(stretch_worst, absf(uv[a].distance_to(uv[b]) / length - 1.0))
				var mid := (p[t] + p[t + 1] + p[t + 2]) / 3.0
				if area > 1e-4 and maxf(maxf(absf(mid.x), absf(mid.y)), absf(mid.z)) > HALF - 1e-3:
					interior_on_surface += 1
				# The same point on the same plane, seen from another chunk.
				var plane_key := flat.abs().snappedf(0.01)
				for v in range(t, t + 3):
					var key := [p[v].snappedf(0.001), plane_key]
					if crack_uvs.has(key) and crack_uvs[key][0] != c:
						crack_seen += 1
						crack_mismatch = maxf(crack_mismatch, uv[v].distance_to(crack_uvs[key][1]))
					elif not crack_uvs.has(key):
						crack_uvs[key] = [c, uv[v]]
	_check(sizes_ok, "%s: normals and UVs for every point" % label)
	_check(outer_uv_error < 1e-3, "%s: source UVs come through the cut (worst error %.5f)" % [label, outer_uv_error])
	if not welded:
		_check(outer_normal_worst > 0.99, "%s: source normals come through the cut (worst %.3f)" % [label, outer_normal_worst])
	_check(absf(outer_area - 24.0) < 0.3, "%s: the source faces are still the box's surface (area %.3f of 24)" % [label, outer_area])
	_check(interior_tris > 0, "%s: cut faces are marked (%d triangles)" % [label, interior_tris])
	_check(interior_on_surface == 0, "%s: no source face was marked as cut (%d)" % [label, interior_on_surface])
	_check(facing_wrong == 0, "%s: cut faces face out of their piece (%d wrong)" % [label, facing_wrong])
	_check(stretch_worst < 0.02, "%s: cut face UVs don't stretch (worst %.4f)" % [label, stretch_worst])
	_check(crack_seen > 0 and crack_mismatch < 1e-3, "%s: both faces of a crack read the same UVs (%d shared points, worst %.5f)" % [label, crack_seen, crack_mismatch])
	_check(int(starts[0]) == (points[0] as PackedVector3Array).size(), "%s: chunk 0, the intact mesh, has no cut faces" % label)


func _fracture(authoring: Object, mesh: Mesh, pattern: int) -> Resource:
	if pattern == 2:
		return authoring.fracture_mesh(mesh, 8, 42, pattern, _pattern_texture())
	return authoring.fracture_mesh(mesh, 8, 42, pattern)


func _destructible(asset: Resource, interior: Material) -> Node:
	var node: Node = ClassDB.instantiate("PhysXDestructible3D")
	node.blast_asset = asset
	var outer := StandardMaterial3D.new()
	node.material_override = outer
	node.interior_material = interior
	get_root().add_child(node)
	return node


func _run() -> void:
	var authoring: Object = ClassDB.instantiate("PhysXBlastAuthoring")
	var names := ["voronoi", "slicing", "cutout"]
	for pattern in 3:
		for welded in [false, true]:
			var label := "%s %s" % [names[pattern], "closed" if welded else "cleaned"]
			var asset := _fracture(authoring, _box(welded), pattern)
			_check(asset != null, "%s: fractures" % label)
			if asset:
				_check_asset(asset, label, welded)

	# Without UVs or normals.
	var bare := _box(true).surface_get_arrays(0)
	bare[Mesh.ARRAY_NORMAL] = null
	bare[Mesh.ARRAY_TEX_UV] = null
	var bare_mesh := ArrayMesh.new()
	bare_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bare)
	var bare_asset: Resource = authoring.fracture_mesh(bare_mesh, 8, 42)
	_check(bare_asset != null, "a mesh without UVs or normals fractures")
	if bare_asset:
		var p: PackedVector3Array = bare_asset.chunk_points[1]
		var n: PackedVector3Array = bare_asset.chunk_normals[1]
		_check(n[0].is_equal_approx(_face_normal(p[0], p[1], p[2])), "and gets flat normals")

	# Inside out: flipped triangles, and normals pointing in as a mesh like that has them.
	var flipped := _box(false).surface_get_arrays(0)
	var idx: PackedInt32Array = flipped[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		var swap := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = swap
	flipped[Mesh.ARRAY_INDEX] = idx
	var inward: PackedVector3Array = flipped[Mesh.ARRAY_NORMAL]
	for i in inward.size():
		inward[i] = -inward[i]
	flipped[Mesh.ARRAY_NORMAL] = inward
	var flipped_mesh := ArrayMesh.new()
	flipped_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, flipped)
	var flipped_asset: Resource = authoring.fracture_mesh(flipped_mesh, 8, 42)
	_check(flipped_asset != null, "an inside-out mesh fractures")
	if flipped_asset:
		var worst := 1.0
		var starts: PackedInt32Array = flipped_asset.chunk_interior_starts
		for c in range(1, flipped_asset.chunk_points.size()):
			var p: PackedVector3Array = flipped_asset.chunk_points[c]
			var n: PackedVector3Array = flipped_asset.chunk_normals[c]
			for t in range(0, starts[c], 3):
				if (p[t + 1] - p[t]).cross(p[t + 2] - p[t]).length() > 2e-4:
					worst = minf(worst, n[t].dot(_face_normal(p[t], p[t + 1], p[t + 2])))
		_check(worst > 0.99, "and its normals face out (worst %.3f)" % worst)

	# A save keeps it all.
	var asset: Resource = authoring.fracture_mesh(_box(false), 8, 42)
	var path := "user://blast_surface_data_test.res"
	_check(ResourceSaver.save(asset, path) == OK, "saves")
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.chunk_uvs == asset.chunk_uvs and loaded.chunk_normals == asset.chunk_normals and loaded.chunk_interior_starts == asset.chunk_interior_starts, "and loads the same")
	DirAccess.remove_absolute(path)

	# The node, new asset and old.
	var interior := StandardMaterial3D.new()
	var old_asset: Resource = ClassDB.instantiate("PhysXBlastAsset")
	old_asset.asset_bytes = asset.asset_bytes
	old_asset.chunk_points = asset.chunk_points
	for pair in [[asset, "new asset"], [old_asset, "asset from before"]]:
		var node := _destructible(pair[0], interior)
		for i in 3:
			await physics_frame
		node.apply_radial_damage(Vector3.ZERO, 1000.0, 5.0, 10.0)
		for i in 10:
			await physics_frame
		_check(node.is_fractured() and node.get_piece_count() > 1, "%s: breaks with interior_material set (%d pieces)" % [pair[1], node.get_piece_count()])
		node.interior_material = null
		node.material_override = null
		node.interior_material = interior
		for i in 3:
			await process_frame
		node.queue_free()
		await process_frame

	print("[blast_surface] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXBlastAuthoring"):
		print("SKIP: no Blast support in this build")
		quit(0)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)
