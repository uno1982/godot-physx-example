extends SceneTree

# Covers the generalized parts of PhysXChunkEmitter3D: sphere chunk_shape and
# continuous emitting/emission_rate, on top of the existing spawn_at coverage
# in debris_test.gd.

var _emitter: PhysXChunkEmitter3D
var _t := 0

func _initialize() -> void:
	print("[chunk] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(20, 1, 20)
	cs.shape = b
	floor_body.add_child(cs)
	root.add_child(floor_body)

	_emitter = PhysXChunkEmitter3D.new()
	_emitter.chunk_shape = PhysXChunkEmitter3D.SHAPE_SPHERE
	_emitter.max_active = 50
	_emitter.lifetime = 30.0
	_emitter.emission_rate = 20.0
	_emitter.emission_direction = Vector3(0, 1, 0)
	_emitter.position = Vector3(0, 3, 0)
	root.add_child(_emitter)

func _physics_process(_delta: float) -> bool:
	_t += 1
	if _t == 2:
		_emitter.emitting = true
	if _t == 90:
		# ~1.5s at 20/s -> roughly 30 chunks, definitely > 0.
		var count := _emitter.get_active_chunk_count()
		print("[chunk] t=90 emitting active=%d (want > 0)" % count)
		_emitter.emitting = false
	if _t == 200:
		var count := _emitter.get_active_chunk_count()
		print("[chunk] t=200 after stop, active=%d (want stayed roughly steady, not still climbing)" % count)
		var ok := count > 0 and count <= _emitter.max_active
		print("[chunk] %s" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false
