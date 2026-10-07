extends SceneTree

# Emitters feed the PhysXFlow3D their `flow` path names: two flows, an emitter
# for each 10 m apart -- each flow's gas must sit at its own emitter only. A
# third emitter with no `flow` while there are two flows feeds neither (and
# warns in the editor). Reads the gas back (cpu_readback); needs a window:
#   godot --path . --script res://test/flow/flow_targets_test.gd

var _a: Node3D
var _b: Node3D
var _stray: Node3D
var _tick := 0
var _pass := true


func _initialize() -> void:
	# A broken test must fail and close its window, not hang.
	create_timer(30.0).timeout.connect(func() -> void:
		print("[flow] FAIL: timed out")
		quit(1))
	if not ClassDB.class_exists("PhysXFlow3D"):
		print("[flow-targets] SKIP: no Flow support in this build")
		quit(0)
		return
	var root := Node3D.new()
	get_root().add_child(root)
	_a = _flow(root, "A", Vector3(-5, 0, 0))
	_b = _flow(root, "B", Vector3(5, 0, 0))
	_emitter(root, Vector3(-5, 0.5, 0), NodePath("../A"))
	_emitter(root, Vector3(5, 0.5, 0), NodePath("../B"))
	_stray = _emitter(root, Vector3(0, 0.5, 8), NodePath())


func _flow(root: Node, n: String, pos: Vector3) -> Node3D:
	var f: Node3D = ClassDB.instantiate("PhysXFlow3D")
	f.name = n
	f.cpu_readback = true
	f.position = pos
	root.add_child(f)
	return f


func _emitter(root: Node, pos: Vector3, path: NodePath) -> Node3D:
	var e: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
	e.position = pos
	e.velocity = Vector3(0, 1, 0)
	e.flow = path
	root.add_child(e)
	return e


func _check(label: String, ok: bool, detail: String) -> void:
	print("  [%s] %-50s %s" % ["ok" if ok else "FAIL", label, detail])
	if not ok:
		_pass = false


func _physics_process(_delta: float) -> bool:
	if _a == null:
		return true # skipped: no Flow in this build
	_tick += 1
	if _tick == 150:
		var ba: AABB = _a.get_stats().bounds
		var bb: AABB = _b.get_stats().bounds
		_check("flow A's gas is at its emitter (x -5)", ba.has_volume() and absf(ba.get_center().x + 5.0) < 1.5, str(ba.get_center()))
		_check("flow B's gas is at its emitter (x +5)", bb.has_volume() and absf(bb.get_center().x - 5.0) < 1.5, str(bb.get_center()))
		_check("neither picked up the stray emitter (z +8)", ba.end.z < 6.0 and bb.end.z < 6.0, "A z<=%.1f B z<=%.1f" % [ba.end.z, bb.end.z])
		_check("the stray emitter feeds no flow", _stray.get_flow() == null, str(_stray.get_flow()))
		print("[flow-targets] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false
