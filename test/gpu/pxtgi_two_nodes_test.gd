extends SceneTree

# Two PXTGI3D in one world, one stepping out: what the editor does when a scene opens over another one with a PXTGI3D
# (the other tab stays loaded, out of the tree). PXTGI's GPU side keeps one set of shape buffers, uploaded only when the
# version it's handed changes, and each node used to count its versions from 0: on a fresh editor start the two nodes
# handed it the same numbers, so the scene opened second was traced through the first one's buffers; a Vulkan editor
# lost the GPU device (the bunker's Showcase_Physical opened over BunkerTest, 3 of 3 launches). Here: a small scene (A)
# drawn alone, a big one (B) added, A's PXTGI3D out, B drawn on; several rounds. Both have triangle meshes, so their
# versions used to match. The device must survive, and B must be lit by its own shapes: its image the same before and
# after its shapes are sent again.
# A smoke test of that hand-over: with plain shapes the old code's stale buffers neither crashed nor showed (the reads
# landed out of bounds, which Vulkan reads as zero), so this passes on the old code too; the bunker's scenes were the
# real reproduction.
#   godot --path . --rendering-driver vulkan --script res://test/gpu/pxtgi_two_nodes_test.gd

const ROUNDS := 3
const TOLERANCE := 0.01 # mean luminance difference: GI noise between two settled frames stays well under it
var _t := 0
var _round := 0
var _a: Node3D
var _b: Node3D
var _ok := true
var _before: Image
var _worst := 0.0


func _check(cond: bool, msg: String) -> void:
	print("[gi-two] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _body(parent: Node3D, shape: Shape3D, mesh: Mesh, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	b.add_child(mi)
	parent.add_child(b)
	b.position = pos


func _scene(big: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "B" if big else "A"
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	root.add_child(we)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(20, 0.2, 20)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_mesh.size
	_body(root, floor_shape, floor_mesh, Vector3(0, -0.1, 0))
	var light := OmniLight3D.new()
	light.omni_range = 12.0
	root.add_child(light)
	light.position = Vector3(0, 3, 0)
	if big:
		# A few hundred shapes, a third of them triangle meshes: far more primitives, tree nodes and geometry than A.
		var sphere := SphereMesh.new()
		var tri := sphere.create_trimesh_shape()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size
		for i in 300:
			var p := Vector3(-9 + (i % 20) * 0.9, 0.5 + (i / 100) * 1.2, -9 + ((i / 20) % 5) * 3.6)
			if i % 3 == 0:
				_body(root, tri, sphere, p)
			else:
				_body(root, box_shape, box, p)
	else:
		var box := BoxMesh.new()
		var box_shape := BoxShape3D.new()
		for i in 3:
			_body(root, box_shape, box, Vector3(-2 + i * 2, 0.5, -2))
		# One small triangle mesh: A has triangle geometry too, so both nodes publish geometry version 1 (what made B's
		# far bigger geometry go un-uploaded: only the version decides, the buffer is never too small to keep).
		# Triangle meshes of its own, a lot of them and of another shape than B's: B's tree, walked through A's
		# geometry, lands on A's triangles (in bounds, wrong), as the editor's two bunker scenes did.
		var torus := TorusMesh.new()
		torus.rings = 24
		torus.ring_segments = 12
		var tri := torus.create_trimesh_shape()
		for i in 120:
			_body(root, tri, torus, Vector3(-8 + (i % 12) * 1.4, 0.4 + (i / 60) * 1.0, 3 + ((i / 12) % 5) * 1.2))
	var gi: Node3D = ClassDB.instantiate("PXTGI3D")
	gi.name = "PXTGI3D"
	root.add_child(gi)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	root.add_child(cam)
	cam.position = Vector3(0, 4, 9)
	cam.rotation_degrees = Vector3(-20, 0, 0)
	return root


func _initialize() -> void:
	if not ClassDB.class_exists("PXTGI3D"):
		print("[gi-two] SKIP: no PXTGI3D")
		quit(0)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	process_frame.connect(_frame)


func _frame() -> void:
	_t += 1
	# A round: A alone for 20 frames; B added; 5 frames on, A's PXTGI3D out; B drawn on its first versions for 40
	# frames (before); then one more small triangle mesh far off camera, so B's node rebuilds and hands over new
	# versions, which the GPU side has to upload, and 40 frames more (after). B's light must not change: before is only
	# right if B's own shapes were uploaded the first time.
	if _t == 1:
		_a = _scene(false)
		get_root().add_child(_a)
		(_a.get_node("Camera3D") as Camera3D).current = true
	elif _t == 21:
		_b = _scene(true)
		get_root().add_child(_b)
	elif _t == 26:
		# Only A's PXTGI3D steps out (hidden: out of the GI as if it had left the world); A's shapes stay, so B's node
		# has no reason to rebuild and keeps handing over its first versions.
		(_a.get_node("PXTGI3D") as Node3D).visible = false
		(_b.get_node("Camera3D") as Camera3D).current = true
	elif _t == 66:
		_before = _shot()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		_body(_b, cone.create_trimesh_shape(), cone, Vector3(0, 0.5, -40))
	elif _t == 106:
		var after := _shot()
		var diff := _diff(_before, after)
		_worst = maxf(_worst, diff)
		print("[gi-two] round %d: B's image before and after its shapes were sent again differs by %.4f" % [_round + 1, diff])
		_a.free()
		_b.queue_free()
		_round += 1
		_t = 0
		if _round >= ROUNDS:
			_finish.call_deferred()
			process_frame.disconnect(_frame)


func _shot() -> Image:
	var img := get_root().get_texture().get_image()
	img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	return img


# The mean difference in linear luminance, per pixel.
func _diff(a: Image, b: Image) -> float:
	var sum := 0.0
	for y in a.get_height():
		for x in a.get_width():
			sum += absf(a.get_pixel(x, y).srgb_to_linear().get_luminance() - b.get_pixel(x, y).srgb_to_linear().get_luminance())
	return sum / (a.get_width() * a.get_height())


func _finish() -> void:
	for i in 10:
		await process_frame
	var img := get_root().get_texture().get_image()
	_check(img != null and not img.is_empty(), "%d rounds of a big PXTGI3D scene taking over from a small one: the device survived" % ROUNDS)
	_check(_worst < TOLERANCE, "B lit by its own shapes from the start: its light didn't change when they were sent again (worst %.4f)" % _worst)
	print("[gi-two] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
