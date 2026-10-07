extends SceneTree

# PhysXFlow3D (NVIDIA Flow on Godot's RenderingDevice) end to end: a hot
# emitter on the ground for 3 s, read back with cpu_readback -- the gas must
# rise (hot gas goes up), stay near the emitter sideways, and sample_smoke
# must find it there. Needs a window (headless has no RenderingDevice):
#   godot --path . --script res://test/flow/flow_smoke_test.gd

var _flow: Node3D
var _tick := 0
var _pass := true
var _step := []


func _initialize() -> void:
	# A broken test must fail and close its window, not hang.
	create_timer(30.0).timeout.connect(func() -> void:
		print("[flow] FAIL: timed out")
		quit(1))
	if not ClassDB.class_exists("PhysXFlow3D"):
		print("[flow] SKIP: this build has no Flow support (flow_sdk=)")
		quit(0)
		return
	var root := Node3D.new()
	get_root().add_child(root)
	_flow = ClassDB.instantiate("PhysXFlow3D")
	_flow.cpu_readback = true
	root.add_child(_flow)
	var e: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
	e.radius = 0.4
	e.velocity = Vector3(0, 1, 0)
	e.temperature = 1.0
	e.smoke = 1.0
	root.add_child(e)


func _check(label: String, ok: bool, detail: String) -> void:
	print("  [%s] %-46s %s" % ["ok" if ok else "FAIL", label, detail])
	if not ok:
		_pass = false


func _physics_process(_delta: float) -> bool:
	if _flow == null:
		return true # skipped: no Flow in this build
	_tick += 1
	var s: Dictionary = _flow.get_stats()
	if _tick > 60:
		_step.append(s.step_ms)
	if _tick == 180:
		_check("Flow running", s.running, str(s.error))
		_check("fields read back from the GPU", s.readback_bytes > 0, "%d bytes" % s.readback_bytes)
		var b: AABB = s.bounds
		_check("hot gas rose above the emitter", b.end.y > 1.0, "top %.2f m" % b.end.y)
		_check("and stayed near it sideways", absf(b.get_center().x) < 2.0 and absf(b.get_center().z) < 2.0, "center %s" % b.get_center())
		var at: float = _flow.sample_smoke(Vector3(0, 1.0, 0))
		var away: float = _flow.sample_smoke(Vector3(6, 1.0, 6))
		_check("sample_smoke finds smoke over the emitter", at > 0.01 and away < 0.001, "%.3f there, %.3f 8 m away" % [at, away])
		print("[flow] step %.2f ms avg" % _avg(_step))
		print("[flow] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false


func _avg(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()
