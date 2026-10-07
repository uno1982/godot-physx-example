extends SceneTree

# PhysXFlow3D and compositors: Flow must draw without side effects on the
# user's own Compositor resources, and leave nothing behind when the last
# flow goes. Needs a window:
#   godot --path . --script res://test/flow/flow_compositor_test.gd

const USER_EFFECT_SRC := """
extends CompositorEffect
var calls := 0
func _render_callback(_type: int, _data: RenderData) -> void:
	calls += 1
"""

var _pass := true
var _root: Node3D
var _user_script: GDScript


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("[flow-compositor] FAIL: timed out")
		quit(1))
	if not ClassDB.class_exists("PhysXFlow3D"):
		print("[flow-compositor] SKIP: no Flow support in this build")
		quit(0)
		return
	_user_script = GDScript.new()
	_user_script.source_code = USER_EFFECT_SRC
	_user_script.reload()
	_root = Node3D.new()
	get_root().add_child(_root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 8)
	_root.add_child(cam)
	cam.make_current()
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %-62s %s" % ["ok" if ok else "FAIL", label, detail])
	if not ok:
		_pass = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _world() -> World3D:
	return _root.get_world_3d()


# World3D doesn't expose its compositor; by name, so this parses without Flow.
func _world_compositor() -> Compositor:
	return ClassDB.class_call_static("PhysXFlowRenderEffect", "get_world_compositor", _world())


func _add_flow() -> Node3D:
	var f: Node3D = ClassDB.instantiate("PhysXFlow3D")
	_root.add_child(f)
	var e: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
	e.velocity = Vector3(0, 2, 0)
	f.add_child(e)
	e.flow = NodePath("..")
	return f


func _user_effect() -> CompositorEffect:
	var e := CompositorEffect.new()
	e.set_script(_user_script)
	e.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	return e


func _user_compositor(effect: CompositorEffect) -> Compositor:
	var c := Compositor.new()
	c.compositor_effects = [effect]
	return c


# Render calls per drawn frame over n frames (1.0 = drawn exactly once).
func _draws_per_frame(flow: Node3D, n: int) -> float:
	var before: int = flow.get_stats().render_calls
	await _frames(n)
	return float(flow.get_stats().render_calls - before) / n


func _run() -> void:
	await _frames(5)

	print("1) no flow")
	_check("world has no compositor", _world_compositor() == null)

	print("2) a flow, no compositor of the user's")
	var f := _add_flow()
	await _frames(30)
	var created: Compositor = _world_compositor()
	_check("a compositor was installed on the world", created != null)
	var rate: float = await _draws_per_frame(f, 30)
	_check("smoke drawn once per frame", is_equal_approx(rate, 1.0), "%.2f" % rate)
	f.queue_free()
	await _frames(5)
	_check("removed again when the flow left (no orphan)", _world_compositor() == null)

	print("3) the user's compositor on a WorldEnvironment")
	var u := _user_effect()
	var uc := _user_compositor(u)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.compositor = uc
	_root.add_child(env)
	await _frames(10)
	var calls_before: int = u.calls
	f = _add_flow()
	await _frames(30)
	rate = await _draws_per_frame(f, 30)
	_check("smoke drawn once per frame", is_equal_approx(rate, 1.0), "%.2f" % rate)
	_check("the user's effect still runs", u.calls > calls_before, "%d calls" % (u.calls - calls_before))
	_check("the user's compositor is still the world's", _world_compositor() == uc)
	_check("its effects array is untouched", uc.compositor_effects.size() == 1 and uc.compositor_effects[0] == u)
	f.queue_free()
	await _frames(5)
	calls_before = u.calls
	await _frames(10)
	_check("after: still the user's compositor, effects untouched", _world_compositor() == uc and uc.compositor_effects.size() == 1)
	_check("after: the user's effect still runs", u.calls > calls_before)

	print("4) the user added PhysXFlowRenderEffect themselves")
	var own_flow_effect: CompositorEffect = ClassDB.instantiate("PhysXFlowRenderEffect")
	uc.compositor_effects = [u, own_flow_effect]
	f = _add_flow()
	await _frames(30)
	rate = await _draws_per_frame(f, 30)
	_check("smoke drawn once per frame (not twice)", is_equal_approx(rate, 1.0), "%.2f" % rate)
	_check("effects array untouched", uc.compositor_effects.size() == 2)
	f.queue_free()
	await _frames(5)
	env.queue_free()
	await _frames(5)

	print("5) the user's compositor on the camera")
	var cu := _user_effect()
	var cc := _user_compositor(cu)
	var cam: Camera3D = get_root().get_viewport().get_camera_3d()
	cam.compositor = cc
	await _frames(10)
	calls_before = cu.calls
	f = _add_flow()
	await _frames(30)
	rate = await _draws_per_frame(f, 30)
	_check("smoke drawn once per frame", is_equal_approx(rate, 1.0), "%.2f" % rate)
	_check("the camera compositor's effect still runs", cu.calls > calls_before)
	_check("its effects array is untouched", cc.compositor_effects.size() == 1 and cc.compositor_effects[0] == cu)
	f.queue_free()
	await _frames(5)
	cam.compositor = null
	await _frames(5)
	_check("world compositor removed (no orphan)", _world_compositor() == null)

	print("6) two flows")
	var a := _add_flow()
	var b := _add_flow()
	b.position = Vector3(4, 0, 0)
	await _frames(30)
	a.queue_free()
	await _frames(5)
	rate = await _draws_per_frame(b, 30)
	_check("the other flow keeps drawing once per frame", is_equal_approx(rate, 1.0), "%.2f" % rate)
	_check("the world compositor is still there", _world_compositor() != null)
	b.queue_free()
	await _frames(5)
	_check("removed with the last flow", _world_compositor() == null)

	print("[flow-compositor] ", "PASS" if _pass else "FAIL")
	quit(0 if _pass else 1)
