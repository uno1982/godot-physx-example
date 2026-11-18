extends SceneTree

# PXTGI3D's off-screen look of a mesh of several surfaces: their colors averaged by their areas, not the first
# surface's. A wall behind the camera is seen only in a mirror filling the view (so PXTGI's trace gives its color):
#   A. a thin yellow strip (surface 0, about a tenth of the area) on a large white body (surface 1);
#   B. all white; C. all yellow.
# Read as blue / red at the mirror's center (white ~1, yellow ~0): A must sit between, near white (the strip's
# share), not at yellow (the first surface alone, as before).
# Windowed only (PXTGI needs a RenderingDevice).

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("[surface-area-look] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	_run.call_deferred()


func _box_arrays(size: Vector3, offset: Vector3) -> Array:
	var b := BoxMesh.new()
	b.size = size
	var arrays := b.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = v
	return arrays


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _scene(kind: String) -> Node3D:
	var root3 := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)

	var yellow := _material(Color(1, 1, 0))
	var white := _material(Color(1, 1, 1))
	# The wall, 4 x 4, behind the camera (at z = +3), facing it.
	var mesh := ArrayMesh.new()
	match kind:
		"A":
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 0.4, 0.2), Vector3(0, 0, -0.15)))
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 4, 0.2), Vector3.ZERO))
			mesh.surface_set_material(0, yellow)
			mesh.surface_set_material(1, white)
		"B":
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 4, 0.2), Vector3.ZERO))
			mesh.surface_set_material(0, white)
		"C":
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 4, 0.2), Vector3.ZERO))
			mesh.surface_set_material(0, yellow)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 0, 3)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	wall.add_child(mi)
	root3.add_child(wall)

	# The mirror, in front of the camera, filling the view.
	var mirror := StaticBody3D.new()
	mirror.position = Vector3(0, 0, -1)
	var ms := CollisionShape3D.new()
	var mbox := BoxShape3D.new()
	mbox.size = Vector3(6, 6, 0.1)
	ms.shape = mbox
	mirror.add_child(ms)
	var mm := MeshInstance3D.new()
	var mq := BoxMesh.new()
	mq.size = Vector3(6, 6, 0.1)
	mm.mesh = mq
	var chrome := StandardMaterial3D.new()
	chrome.metallic = 1.0
	chrome.roughness = 0.0
	mm.material_override = chrome
	mirror.add_child(mm)
	root3.add_child(mirror)

	# A light on the wall (the camera side), so it has something to bounce.
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0, 1.0)
	light.omni_range = 6.0
	light.light_energy = 0.3
	root3.add_child(light)

	root3.add_child(ClassDB.instantiate("PXTGI3D"))

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 0.5)
	cam.fov = 40.0
	root3.add_child(cam)
	return root3


func _measure(kind: String) -> Color:
	var s := _scene(kind)
	root.add_child(s)
	for c in s.get_children():
		if c is Camera3D:
			c.current = true
	for i in 180:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://excluded/surface_area_look_%s.png" % kind)
	var w := img.get_width()
	var h := img.get_height()
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(int(h * 0.4), int(h * 0.6), 2):
		for x in range(int(w * 0.4), int(w * 0.6), 2):
			sum += img.get_pixel(x, y)
			n += 1
	s.queue_free()
	await process_frame
	return sum / float(n)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: PXTGI needs a windowed run")
		quit(0)
		return
	root.size = Vector2i(640, 360)
	var ratio := {}
	for kind in ["A", "B", "C"]:
		var c := await _measure(kind)
		ratio[kind] = c.b / maxf(c.r, 0.0001)
		print("[surface-area-look] %s: center %s, blue / red %.3f" % [kind, c, ratio[kind]])
	_check(ratio["B"] > 0.8, "all white reads white (%.3f)" % ratio["B"])
	_check(ratio["C"] < 0.2, "all yellow reads yellow (%.3f)" % ratio["C"])
	var span: float = ratio["B"] - ratio["C"]
	var a_share: float = (ratio["A"] - ratio["C"]) / maxf(span, 0.0001)
	_check(a_share > 0.6 and a_share < 0.98, "strip + body reads near white, tinted (%.2f of the way from yellow to white)" % a_share)
	print("[surface-area-look] %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
