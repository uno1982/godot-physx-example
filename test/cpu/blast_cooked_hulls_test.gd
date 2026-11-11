extends SceneTree

# PhysXBlastAsset stores each chunk's collision hull, cooked ahead of time (R23), so a break only loads it:
# - fracture_mesh() cooks them; cook_hulls() adds the same ones to an asset fractured before, and a save keeps them.
# - get_hull_status(): none, cooked, or out of date (another PhysX build's).
# - Pieces from stored hulls land exactly where pieces from hulls cooked at the break do.
# - An asset without hulls, with out-of-date ones, or with damaged bytes still breaks: its hulls are cooked instead.

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[blast_hulls] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _strip(asset: Resource) -> Resource:
	var old: Resource = ClassDB.instantiate("PhysXBlastAsset")
	old.asset_bytes = asset.asset_bytes
	old.chunk_points = asset.chunk_points
	old.chunk_normals = asset.chunk_normals
	old.chunk_uvs = asset.chunk_uvs
	old.chunk_interior_starts = asset.chunk_interior_starts
	old.chunk_surface_starts = asset.chunk_surface_starts
	old.surface_materials = asset.surface_materials
	return old


# Breaks a dynamic destructible over a floor and lets the pieces settle; returns where they are.
func _drop(asset: Resource, label: String) -> PackedVector3Array:
	var root := Node3D.new()
	get_root().add_child(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var node: Node3D = ClassDB.instantiate("PhysXDestructible3D")
	node.blast_asset = asset
	node.position = Vector3(0, 1.5, 0)
	root.add_child(node)
	for i in 3:
		await physics_frame
	node.apply_radial_damage(node.global_position, 1000.0, 5.0, 10.0)
	for i in 120:
		await physics_frame
	var at := PackedVector3Array()
	var lowest := INF
	for i in node.get_piece_count():
		var p: Vector3 = node.get_piece_transform(i).origin
		at.append(p)
		lowest = minf(lowest, p.y)
	_check(node.is_fractured() and node.get_piece_count() > 1 and lowest > -2.0, "%s: breaks, and the pieces stay on the floor (%d pieces, lowest %.3f)" % [label, node.get_piece_count(), lowest])
	root.queue_free()
	await process_frame
	return at


func _run() -> void:
	var authoring: Object = ClassDB.instantiate("PhysXBlastAuthoring")
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var asset: Resource = authoring.fracture_mesh(box, 12, 7)
	if asset == null:
		_check(false, "fractures")
		quit(1)
		return
	var hulls: Array = asset.chunk_hulls
	var cooked := 0
	for h in hulls:
		cooked += 1 if (h as PackedByteArray).size() > 0 else 0
	_check(asset.get_hull_status() == 1 and asset.hull_format.begins_with("PhysX ") and hulls.size() == asset.get_chunk_count() and cooked == hulls.size(),
			"fracture_mesh cooks every chunk's hull (%d of %d, %s)" % [cooked, asset.get_chunk_count(), asset.hull_format])

	var old := _strip(asset)
	_check(old.get_hull_status() == 0, "an asset without hulls: none")
	_check(old.cook_hulls() == OK and old.get_hull_status() == 1 and old.chunk_hulls == asset.chunk_hulls and old.hull_format == asset.hull_format,
			"cook_hulls() adds the same hulls fracturing does")

	var stale := _strip(asset)
	stale.chunk_hulls = asset.chunk_hulls
	stale.hull_format = "PhysX 0.0.0"
	_check(stale.get_hull_status() == 2, "hulls from another PhysX build: out of date")
	var short := _strip(asset)
	short.chunk_hulls = asset.chunk_hulls.slice(0, 2)
	short.hull_format = asset.hull_format
	_check(short.get_hull_status() == 2, "hulls that don't match the chunks: out of date")

	var path := "user://blast_cooked_hulls_test.res"
	_check(ResourceSaver.save(asset, path) == OK, "saves")
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.chunk_hulls == asset.chunk_hulls and loaded.hull_format == asset.hull_format and loaded.get_hull_status() == 1, "and loads with its hulls")
	DirAccess.remove_absolute(path)
	var tres := "user://blast_cooked_hulls_test.tres"
	_check(ResourceSaver.save(asset, tres) == OK, "saves as text")
	var loaded_text: Resource = ResourceLoader.load(tres, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded_text != null and loaded_text.chunk_hulls == asset.chunk_hulls, "and loads its hulls from text")
	DirAccess.remove_absolute(tres)

	var with_hulls := await _drop(asset, "stored hulls")
	var without := await _drop(_strip(asset), "hulls cooked at the break")
	var same := with_hulls.size() == without.size()
	if same:
		for i in with_hulls.size():
			same = same and with_hulls[i].is_equal_approx(without[i])
	_check(same, "the pieces land exactly where the ones with hulls cooked at the break do")
	await _drop(stale, "out-of-date hulls")
	var damaged := _strip(asset)
	var bad := []
	for h in asset.chunk_hulls:
		var b := PackedByteArray(h)
		for i in range(0, b.size(), 3):
			b[i] = 0x5a
		bad.append(b)
	damaged.chunk_hulls = bad
	damaged.hull_format = asset.hull_format
	await _drop(damaged, "damaged hull bytes")

	print("[blast_hulls] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXBlastAuthoring"):
		print("SKIP: no Blast support in this build")
		quit(0)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)
