extends SceneTree

# PhysXChunkEmitter3D: spawn a burst at a floor impact, chunks must fall,
# collide with the floor, and respect the max_active budget + lifetime cull.

var _emitter: PhysXChunkEmitter3D
var _t := 0

func _initialize() -> void:
	print("[debris] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
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
	_emitter.chunk_count = 12
	_emitter.max_active = 30
	_emitter.lifetime = 1.0
	root.add_child(_emitter)

func _physics_process(_delta: float) -> bool:
	_t += 1
	if _t == 2:
		_emitter.spawn_at(Vector3(0, 3, 0), Vector3(0, 1, 0))
		print("[debris] after 1 burst: active=%d (want 12)" % _emitter.get_active_chunk_count())
		_emitter.spawn_at(Vector3(1, 3, 0), Vector3(0, 1, 0))
		_emitter.spawn_at(Vector3(2, 3, 0), Vector3(0, 1, 0))
		_emitter.spawn_at(Vector3(3, 3, 0), Vector3(0, 1, 0))
		print("[debris] after 4 bursts: active=%d (want <= 30)" % _emitter.get_active_chunk_count())
	if _t == 90:
		var over_budget := _emitter.get_active_chunk_count() > _emitter.max_active
		print("[debris] t=90 active=%d over_budget=%s" % [_emitter.get_active_chunk_count(), over_budget])
	if _t == 260:
		# lifetime=1.0s -> by 260 ticks (>4s since the last burst at t=2) everything
		# should have been culled.
		var count := _emitter.get_active_chunk_count()
		print("[debris] t=260 active=%d (want 0, lifetime cull)" % count)
		var ok := count == 0
		print("[debris] %s" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false
