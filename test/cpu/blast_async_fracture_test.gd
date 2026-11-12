extends SceneTree

# PhysXBlastAuthoring.fracture_mesh_async() (R25): the same fracture on a worker thread.
# - It produces exactly what fracture_mesh() does, and reports each stage in order, the hulls one by one.
# - Failures come through finished, with the same error fracture_mesh() gives.
# - cancel() stops it: finished comes with no asset.
# - A task nobody keeps a reference to still finishes, and the main thread keeps running frames meanwhile.

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[blast_async] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _hash(asset: Resource) -> String:
	if asset == null:
		return "null"
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p in [asset.asset_bytes, var_to_bytes(asset.chunk_points), var_to_bytes(asset.chunk_normals), var_to_bytes(asset.chunk_uvs),
			var_to_bytes(asset.chunk_interior_starts), var_to_bytes(asset.chunk_surface_starts), var_to_bytes(asset.chunk_hulls), asset.hull_format.to_utf8_buffer()]:
		ctx.update(p)
	return ctx.finish().hex_encode()


# Runs a task to the end, recording its stages and how many frames went by. Returns [asset, stages, descriptions, frames, finished_count].
func _await_task(task: Object) -> Array:
	var stages := []
	var descriptions := []
	var result := [null, stages, descriptions, 0, 0]
	task.stage_changed.connect(func(stage: int, count: int, description: String) -> void:
		stages.append(stage)
		descriptions.append(description)
		_check(count == 6, "stage_count is 6") if count != 6 else null)
	task.finished.connect(func(asset: Resource) -> void:
		result[0] = asset
		result[4] += 1)
	var frames := 0
	while result[4] == 0 and frames < 100000:
		await process_frame
		frames += 1
	result[3] = frames
	await process_frame # a second finished would show here
	return result


func _run() -> void:
	var authoring: Object = ClassDB.instantiate("PhysXBlastAuthoring")
	var box := BoxMesh.new()
	var pattern: Texture2D = load("res://demo/common/blast/test_cutout_pattern.png")

	# The same asset as fracture_mesh(), Voronoi and cutout.
	for c in [["Voronoi", 24, 0, null], ["cutout", 0, 2, pattern]]:
		var sync: Resource = authoring.fracture_mesh(box, c[1], 5, c[2], c[3])
		var task: Object = authoring.fracture_mesh_async(box, c[1], 5, c[2], c[3])
		_check(task.is_running(), "%s: running once started" % c[0])
		var r := await _await_task(task)
		var asset: Resource = r[0]
		_check(asset != null and _hash(asset) == _hash(sync), "%s: the same asset as fracture_mesh() (%d chunks)" % [c[0], asset.get_chunk_count() if asset else 0])
		_check(r[4] == 1 and not task.is_running() and task.get_asset() == asset and not task.is_cancelled() and task.get_last_error() == "", "%s: finished once, with the asset" % c[0])
		var stages: Array = r[1]
		var firsts := []
		for s in stages:
			if firsts.is_empty() or firsts[-1] != s:
				firsts.append(s)
		_check(firsts == [1, 2, 3, 4, 5, 6], "%s: stages 1 to 6 in order (%s)" % [c[0], str(firsts)])
		var hulls := stages.count(6)
		var last: String = r[2][-1] if not r[2].is_empty() else ""
		_check(hulls == sync.get_chunk_count() and last == "Cooking collision hulls (%d of %d)" % [hulls, hulls], "%s: one report per hull, the last '%s'" % [c[0], last])
		_check(task.get_stage() == 6 and task.get_stage_description() == last, "%s: get_stage() and get_stage_description() hold the last stage" % c[0])

	# Failures: the same errors as fracture_mesh(), through finished.
	for c in [["no mesh", ArrayMesh.new(), 0, null], ["cutout without a pattern", box, 2, null]]:
		authoring.fracture_mesh(c[1], 8, 1, c[2], c[3])
		var expected: String = authoring.get_last_error()
		var task: Object = authoring.fracture_mesh_async(c[1], 8, 1, c[2], c[3])
		var r := await _await_task(task)
		_check(r[0] == null and r[4] == 1 and task.get_last_error() == expected and expected != "", "%s: finished with no asset and the same error ('%s')" % [c[0], task.get_last_error()])

	# Cancelled: a slow mesh (its cleanup takes seconds), stopped right away.
	var sphere := SphereMesh.new()
	var slow: Object = authoring.fracture_mesh_async(sphere, 16, 1)
	slow.cancel()
	var cancelled := await _await_task(slow)
	_check(cancelled[0] == null and cancelled[4] == 1 and slow.is_cancelled() and slow.get_last_error() == "Cancelled." and not slow.is_running(), "cancel(): finished with no asset, is_cancelled()")

	# Nobody keeps the task: it still finishes, and frames keep coming while the slow mesh fractures.
	var done := [null, 0]
	authoring.fracture_mesh_async(sphere, 16, 1).finished.connect(func(asset: Resource) -> void:
		done[0] = asset
		done[1] += 1)
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while done[1] == 0 and frames < 1000000:
		await process_frame
		frames += 1
	var ms := Time.get_ticks_msec() - t0
	_check(done[0] != null and done[1] == 1, "a task with no reference kept still finishes, with its asset")
	_check(frames > 20, "the main thread kept running: %d frames in %d ms" % [frames, ms])

	print("[blast_async] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXBlastAuthoring"):
		print("SKIP: no Blast support in this build")
		quit(0)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)
