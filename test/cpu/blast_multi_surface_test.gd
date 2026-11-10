extends SceneTree

# PhysXBlastAuthoring fractures every surface of a mesh (R22), not only the first:
# - A 2 m box in three surfaces (top, bottom, sides) fractures with each pattern. Every piece's source faces stay with
#   their surface: each surface's faces lie where that surface was, and add up to its area.
# - The asset keeps each surface's material, and a save keeps it all.
# - A surface that isn't triangles is left out with a warning, and a one-surface mesh fractures as before.
# - PhysXDestructible3D breaks with it, and with an asset from before surfaces were kept.

const HALF := 1.0
const TOP := 0
const SIDES := 1
const BOTTOM := 2

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[blast_multi] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _surface_of_normal(n: Vector3) -> int:
	if n.y > 0.5:
		return TOP
	if n.y < -0.5:
		return BOTTOM
	return SIDES


# The box's faces split by direction into three surfaces, each with its own material.
func _box(materials: Array) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * HALF * 2.0
	var a := box.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	for s in 3:
		var sv := PackedVector3Array()
		var sn := PackedVector3Array()
		var su := PackedVector2Array()
		var si := PackedInt32Array()
		var remap := {}
		for t in range(0, indices.size(), 3):
			if _surface_of_normal(normals[indices[t]]) != s:
				continue
			for v in 3:
				var i := indices[t + v]
				if not remap.has(i):
					remap[i] = sv.size()
					sv.append(verts[i])
					sn.append(normals[i])
					su.append(uvs[i])
				si.append(remap[i])
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = sv
		out[Mesh.ARRAY_NORMAL] = sn
		out[Mesh.ARRAY_TEX_UV] = su
		out[Mesh.ARRAY_INDEX] = si
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		mesh.surface_set_material(s, materials[s])
	return mesh


func _pattern_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	for i in 64:
		img.set_pixel(32, i, Color.WHITE)
		img.set_pixel(i, 32, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _fracture(authoring: Object, mesh: Mesh, pattern: int) -> Resource:
	if pattern == 2:
		return authoring.fracture_mesh(mesh, 8, 42, pattern, _pattern_texture())
	return authoring.fracture_mesh(mesh, 8, 42, pattern)


func _check_asset(asset: Resource, label: String, materials: Array) -> void:
	var points: Array = asset.chunk_points
	var starts: Array = asset.chunk_surface_starts
	var interior: PackedInt32Array = asset.chunk_interior_starts
	_check(starts.size() == points.size(), "%s: surface starts for every chunk" % label)
	var got: Array = asset.surface_materials
	_check(got.size() == 3 and got[0] == materials[0] and got[1] == materials[1] and got[2] == materials[2], "%s: the asset keeps each surface's material" % label)
	if starts.size() != points.size():
		return
	var area := [0.0, 0.0, 0.0]
	var misplaced := 0
	var ordered := true
	for c in range(1, points.size()):
		var p: PackedVector3Array = points[c]
		var s: PackedInt32Array = starts[c]
		ordered = ordered and s.size() == 3 and s[0] == 0 and s[0] <= s[1] and s[1] <= s[2] and s[2] <= interior[c] and interior[c] <= p.size()
		if not ordered:
			continue
		var bounds := [s[0], s[1], s[2], interior[c]]
		for surface in 3:
			for t in range(bounds[surface], bounds[surface + 1], 3):
				var tri_area := (p[t + 1] - p[t]).cross(p[t + 2] - p[t]).length() * 0.5
				area[surface] += tri_area
				if tri_area < 1e-5:
					continue
				var mid := (p[t] + p[t + 1] + p[t + 2]) / 3.0
				var on_top := absf(mid.y - HALF) < 1e-3
				var on_bottom := absf(mid.y + HALF) < 1e-3
				var on_side := absf(absf(mid.x) - HALF) < 1e-3 or absf(absf(mid.z) - HALF) < 1e-3
				var right := (surface == TOP and on_top) or (surface == BOTTOM and on_bottom) or (surface == SIDES and on_side and not on_top and not on_bottom)
				if not right:
					misplaced += 1
	_check(ordered, "%s: each chunk's surfaces come in order, before its cut faces" % label)
	_check(misplaced == 0, "%s: every source face is on its own surface's part of the box (%d misplaced)" % [label, misplaced])
	_check(absf(area[TOP] - 4.0) < 0.05 and absf(area[BOTTOM] - 4.0) < 0.05 and absf(area[SIDES] - 16.0) < 0.2,
			"%s: each surface's faces add up to its area (top %.3f of 4, sides %.3f of 16, bottom %.3f of 4)" % [label, area[TOP], area[SIDES], area[BOTTOM]])
	var chunk0: PackedInt32Array = starts[0]
	_check(chunk0.size() == 3 and interior[0] == (points[0] as PackedVector3Array).size(), "%s: chunk 0, the intact mesh, has every surface and no cut faces" % label)


func _destructible(asset: Resource) -> Node:
	var node: Node = ClassDB.instantiate("PhysXDestructible3D")
	node.blast_asset = asset
	node.interior_material = StandardMaterial3D.new()
	get_root().add_child(node)
	return node


func _run() -> void:
	var authoring: Object = ClassDB.instantiate("PhysXBlastAuthoring")
	var materials := []
	for color in [Color.RED, Color.BLUE, Color.GREEN]:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		materials.append(m)
	var names := ["voronoi", "slicing", "cutout"]
	var asset: Resource = null
	for pattern in 3:
		var result := _fracture(authoring, _box(materials), pattern)
		_check(result != null, "%s: a three-surface box fractures" % names[pattern])
		if result:
			_check_asset(result, names[pattern], materials)
			if pattern == 0:
				asset = result

	# A line surface is left out.
	var with_lines := _box(materials)
	var line := []
	line.resize(Mesh.ARRAY_MAX)
	line[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.UP * 3.0])
	with_lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line)
	var lines_asset: Resource = authoring.fracture_mesh(with_lines, 8, 42)
	_check(lines_asset != null, "a mesh with a line surface fractures")
	if lines_asset:
		var warned := false
		for w in authoring.get_last_warnings():
			warned = warned or "isn't a triangle list" in w
		_check(warned, "and warns the line surface was left out")
		_check(lines_asset.surface_materials.size() == 4 and lines_asset.surface_materials[3] == null, "and keeps a null material for it")

	# One surface, as before.
	var single := BoxMesh.new()
	single.size = Vector3.ONE * 2.0
	var single_asset: Resource = authoring.fracture_mesh(single, 8, 42)
	_check(single_asset != null, "a one-surface mesh fractures")
	if single_asset:
		var all_zero := true
		for s in single_asset.chunk_surface_starts:
			all_zero = all_zero and (s as PackedInt32Array) == PackedInt32Array([0])
		_check(all_zero, "and its one surface starts each chunk")

	# A surface with an index past its own vertices (but not past the whole mesh's).
	var bad := _box(materials)
	var bad_arrays := bad.surface_get_arrays(0)
	var bad_indices: PackedInt32Array = bad_arrays[Mesh.ARRAY_INDEX]
	bad_indices[0] = (bad_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	bad_arrays[Mesh.ARRAY_INDEX] = bad_indices
	var bad_mesh := ArrayMesh.new()
	bad_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bad_arrays)
	for s in range(1, 3):
		bad_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bad.surface_get_arrays(s))
	_check(authoring.fracture_mesh(bad_mesh, 8, 42) == null and "past its" in authoring.get_last_error(), "an index past its own surface's vertices is refused (%s)" % authoring.get_last_error())

	if asset == null:
		print("[blast_multi] FAIL")
		quit(1)
		return

	# A save keeps it all.
	var path := "user://blast_multi_surface_test.res"
	_check(ResourceSaver.save(asset, path) == OK, "saves")
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.chunk_surface_starts == asset.chunk_surface_starts and loaded.surface_materials.size() == 3 and (loaded.surface_materials[0] as StandardMaterial3D).albedo_color == Color.RED, "and loads the same")
	DirAccess.remove_absolute(path)

	# The node, with this asset and one from before surfaces were kept.
	var old_asset: Resource = ClassDB.instantiate("PhysXBlastAsset")
	old_asset.asset_bytes = asset.asset_bytes
	old_asset.chunk_points = asset.chunk_points
	old_asset.chunk_normals = asset.chunk_normals
	old_asset.chunk_uvs = asset.chunk_uvs
	old_asset.chunk_interior_starts = asset.chunk_interior_starts
	for pair in [[asset, "three-surface asset"], [old_asset, "asset from before surfaces"]]:
		var node := _destructible(pair[0])
		for i in 3:
			await physics_frame
		node.apply_radial_damage(Vector3.ZERO, 1000.0, 5.0, 10.0)
		for i in 10:
			await physics_frame
		_check(node.is_fractured() and node.get_piece_count() > 1, "%s: breaks (%d pieces)" % [pair[1], node.get_piece_count()])
		node.material_override = StandardMaterial3D.new()
		node.interior_material = null
		node.material_override = null
		for i in 3:
			await process_frame
		node.queue_free()
		await process_frame

	print("[blast_multi] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXBlastAuthoring"):
		print("SKIP: no Blast support in this build")
		quit(0)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)
