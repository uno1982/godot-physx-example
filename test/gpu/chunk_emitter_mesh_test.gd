extends SceneTree

# uno1982/godot#37: PhysXChunkEmitter3D no longer asks the RenderingServer whether its multimesh has a mesh on every
# burst (that getter waited for the render thread); it keeps a flag instead. What must still hold: the multimesh draws
# the default box when no chunk_mesh is set, the default sphere for chunk_shape = SHAPE_SPHERE, a custom chunk_mesh
# when one is set, and the default again when it's cleared. Windowed: the headless dummy renderer's
# multimesh_get_mesh always returns null. (The timing itself: excluded/chunk_spawn_probe.gd, thread_model = Separate.)

var _ok := true
var _t := 0
var _emitter: PhysXChunkEmitter3D


func _check(cond: bool, msg: String) -> void:
	print("[chunk_mesh] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _mesh() -> RID:
	return RenderingServer.multimesh_get_mesh(_emitter.get_base())


func _initialize() -> void:
	if ProjectSettings.get_setting("physics/3d/physics_engine", "?") != "PhysX":
		print("SKIP: not running on PhysX")
		quit(0)
		return
	_emitter = PhysXChunkEmitter3D.new()
	_emitter.max_active = 20
	get_root().add_child(_emitter)
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t == 2:
		_emitter.spawn_at(Vector3(0, 2, 0), Vector3.UP, 4)
		_check(_mesh().is_valid(), "a burst with no chunk_mesh draws the default mesh")
		_check(_emitter.get_active_chunk_count() == 4, "4 chunks spawned (%d)" % _emitter.get_active_chunk_count())
	if _t == 4:
		var box := _mesh()
		_emitter.chunk_shape = PhysXChunkEmitter3D.SHAPE_SPHERE
		_emitter.spawn_at(Vector3(0, 2, 0), Vector3.UP, 4)
		_check(_mesh().is_valid() and _mesh() != box, "chunk_shape = sphere switches the default mesh")
		var custom := PrismMesh.new()
		_emitter.chunk_mesh = custom
		_emitter.spawn_at(Vector3(0, 2, 0), Vector3.UP, 4)
		_check(_mesh() == custom.get_rid(), "a custom chunk_mesh is drawn")
		_emitter.chunk_mesh = null
		_emitter.spawn_at(Vector3(0, 2, 0), Vector3.UP, 4)
		_check(_mesh().is_valid() and _mesh() != custom.get_rid(), "clearing chunk_mesh goes back to the default")
		_emitter.emission_rate = 30.0
		_emitter.emitting = true
	if _t == 40:
		_check(_emitter.get_active_chunk_count() == 20, "continuous emission fills max_active (%d)" % _emitter.get_active_chunk_count())
		_check(_mesh().is_valid() and _mesh() != _emitter.get_base(), "still drawing a mesh")
		quit(0 if _ok else 1)
