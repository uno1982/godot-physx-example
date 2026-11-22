extends SceneTree

# PhysXMirror3D: a scene capture mirror. The mirror demo (demo/editor/rendering/gi_mirror_character.tscn) with its
# PhysXMirror3D shown (P), the mannequin dancing about a meter and a half from it, in first person (its body isn't
# drawn for the camera, only for the capture). Checks:
#   - the capture renders, and the glass shows the mannequin (orange) in it;
#   - mirrored correctly: a red box put on the room's +x side shows on the glass's +x half of the screen;
#   - looking away from the mirror, the capture doesn't render (its viewport isn't updated);
#   - with gi off, the capture costs less than with it.
# Windowed only.

var failures := 0
var _scene: Node
var _mirror: Node3D
var _capture_rid: RID
var _capture: SubViewport


func _check(ok: bool, what: String) -> void:
	print("[mirror] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	_run.call_deferred()


func _key(k: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	_scene._unhandled_input(ev)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# The mean GPU time of the capture's viewport over n frames.
func _capture_time(n: int) -> float:
	var sum := 0.0
	for i in n:
		await process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(_capture_rid)
	return sum / n


# Orange (the mannequin) and red (the box) pixels on the screen's left and right halves.
func _count() -> Dictionary:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := {"orange": 0, "red_left": 0, "red_right": 0}
	var half := img.get_width() / 2
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.4 and c.g > 0.35 * c.r and c.g < 0.8 * c.r and c.b < 0.45 * c.r:
				out["orange"] += 1
			elif c.r > 0.35 and c.g < 0.25 * c.r and c.b < 0.25 * c.r:
				out["red_left" if x < half else "red_right"] += 1
	return out


func _run() -> void:
	await process_frame
	if RenderingServer.get_rendering_device() == null or DisplayServer.get_name() == "headless":
		print("SKIP: PhysXMirror3D needs a windowed run")
		quit(0)
		return
	_scene = (load("res://demo/editor/rendering/gi_mirror_character.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	await process_frame
	_mirror = _scene.get_node("CaptureMirror")
	_scene.get_node("Mannequin").position = Vector3(0, 0, -1.4)
	# A red box on the room's +x side behind the camera: seen only in the mirror, which shows it on its +x side (the
	# screen's right, the camera facing -z). Flipped the wrong way, it would show on the left.
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	box.mesh = mesh
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.05, 0.05)
	box.material_override = red
	box.position = Vector3(1.6, 1.6, 0.4)
	_scene.add_child(box)
	_key(KEY_P)
	_key(KEY_3)
	for c in _mirror.get_children(true):
		if c is SubViewport:
			_capture = c
			_capture_rid = c.get_viewport_rid()
	_check(_capture_rid.is_valid(), "the mirror has its capture viewport")
	RenderingServer.viewport_set_measure_render_time(_capture_rid, true)
	await _frames(150)
	var seen: Dictionary = await _count()
	root.get_texture().get_image().save_png("res://excluded/shots/mirror_test_facing.png")
	print("[mirror] facing it: %s" % seen)
	_check(seen["orange"] > 300, "the glass shows the mannequin")
	_check(seen["red_right"] > 50 and seen["red_right"] > 4 * seen["red_left"], "a box on the room's +x side shows on the right (mirrored correctly)")
	var lit: float = await _capture_time(60)
	_mirror.gi = false
	await _frames(20)
	var unlit: float = await _capture_time(60)
	print("[mirror] capture GPU time: gi %.3f ms, no gi %.3f ms" % [lit, unlit])
	_check(lit > 0.05, "facing the mirror, the capture renders")
	_check(unlit < 0.8 * lit, "without gi the capture costs less")
	# Turned away from the mirror (it's behind the camera now), the capture stops.
	_scene._yaw = PI
	await _frames(20)
	var disabled := true
	for i in 30:
		await process_frame
		disabled = disabled and _capture.render_target_update_mode == SubViewport.UPDATE_DISABLED
	_check(disabled, "looking away, the capture doesn't render")
	_scene._yaw = 0.0
	await _frames(5)
	_check(_capture.render_target_update_mode != SubViewport.UPDATE_DISABLED, "facing it again, it renders again")
	print("PASS" if failures == 0 else "FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
