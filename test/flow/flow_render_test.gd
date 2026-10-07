extends SceneTree

# PhysXFlow3D's GPU render: a hot emitter for 3 s in front of a camera. Every
# Flow pipeline it runs must compile through RenderingDevice.
# Flow's own ray marcher draws it into Godot's frame every frame, straight
# from the GPU (nothing read back). Needs a window (headless has no
# RenderingDevice):
#   godot --path . --script res://test/flow/flow_render_test.gd

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
	root.add_child(_flow)
	var e: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
	e.radius = 0.4
	e.velocity = Vector3(0, 1, 0)
	e.temperature = 1.0
	e.smoke = 1.0
	root.add_child(e)
	var cam := Camera3D.new() # the effect only runs when a 3D view renders
	cam.position = Vector3(0, 2, 8)
	root.add_child(cam)
	cam.make_current()


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
		# Pipelines are built on first use: the ~30 a smoke grid runs, not all
		# ~120 Flow registers.
		_check("every Flow pipeline it ran compiled", s.get("pipelines", 0) >= 20 and s.get("pipeline_failures", -1) == 0, "%s ok, %s failed, start %.0f ms" % [s.get("pipelines"), s.get("pipeline_failures"), s.start_ms])
		_check("compute passes ran last frame", s.get("passes", 0) > 0, "%s passes, frame %s done %s" % [s.get("passes"), s.get("frame"), s.get("frame_completed")])
		_check("drawn by Flow's ray marcher every frame", s.render_calls > 0 and s.render_outputs == s.render_calls, "%d frames" % s.render_calls)
		_check("nothing read back to the CPU", s.readback_bytes == 0, "%d bytes" % s.readback_bytes)
		if not _step.is_empty():
			print("[flow] cost per frame (avg ms): step %.2f" % _avg(_step))
		print("[flow] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false


func _avg(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()
