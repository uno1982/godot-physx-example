extends SceneTree

# PXTGI3D's off-screen glow of a mesh whose glow is one thin surface: only where that surface is on the collision
# shape, not the whole shape. A wall behind the camera, seen only in a mirror filling the view: a white box (surface 0)
# with a thin, bright blue glowing strip along its top (surface 1), its collision one box. In the mirror the strip's
# band reads blue and the box's middle reads as lit white (blue / red near 1), not blue all over (as when the glow
# covered the whole shape). Also a box all glowing (one surface) for scale: blue all over.
# Windowed only (PXTGI needs a RenderingDevice).

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("[emissive-region] %s %s" % ["ok  " if ok else "FAIL", what])
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


func _scene(strip: bool) -> Node3D:
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

	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0, 0, 0)
	glow.emission_enabled = true
	glow.emission = Color(0.0, 0.3, 1.0)
	glow.emission_energy_multiplier = 3.0
	var mesh := ArrayMesh.new()
	if strip:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 4, 0.2), Vector3.ZERO))
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 0.3, 0.05), Vector3(0, 1.5, -0.12)))
		mesh.surface_set_material(0, white)
		mesh.surface_set_material(1, glow)
	else:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(Vector3(4, 4, 0.2), Vector3.ZERO))
		mesh.surface_set_material(0, glow)
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

	var mirror := StaticBody3D.new()
	mirror.position = Vector3(0, 0, -1)
	var ms := CollisionShape3D.new()
	var mbox := BoxShape3D.new()
	mbox.size = Vector3(8, 8, 0.1)
	ms.shape = mbox
	mirror.add_child(ms)
	var mm := MeshInstance3D.new()
	var mq := BoxMesh.new()
	mq.size = Vector3(8, 8, 0.1)
	mm.mesh = mq
	var chrome := StandardMaterial3D.new()
	chrome.metallic = 1.0
	chrome.roughness = 0.0
	mm.material_override = chrome
	mirror.add_child(mm)
	root3.add_child(mirror)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 0, 1.0)
	light.omni_range = 6.0
	light.light_energy = 0.3
	root3.add_child(light)

	root3.add_child(ClassDB.instantiate("PXTGI3D"))

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 0.5)
	cam.fov = 50.0
	root3.add_child(cam)
	return root3


func _mean(img: Image, r: Rect2i) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			sum += img.get_pixel(x, y)
			n += 1
	return sum / float(n)


func _measure(strip: bool) -> Array:
	var s := _scene(strip)
	root.add_child(s)
	for c in s.get_children():
		if c is Camera3D:
			c.current = true
	for i in 180:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://excluded/emissive_region_%s.png" % ("strip" if strip else "all"))
	var w := img.get_width()
	var h := img.get_height()
	# The strip's band (1.5 m up the wall, about 5.4 m away in the mirror) and the wall's middle.
	var band_y := int(h * (0.5 - tan(atan(1.5 / 5.35)) / tan(deg_to_rad(25.0)) * 0.5))
	var band := _mean(img, Rect2i(int(w * 0.4), band_y - 3, int(w * 0.2), 6))
	var middle := _mean(img, Rect2i(int(w * 0.4), int(h * 0.45), int(w * 0.2), int(h * 0.1)))
	s.queue_free()
	await process_frame
	return [band, middle]


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: PXTGI needs a windowed run")
		quit(0)
		return
	root.size = Vector2i(640, 360)
	var strip: Array = await _measure(true)
	var all: Array = await _measure(false)
	print("[emissive-region] strip mesh: band %s, middle %s" % [strip[0], strip[1]])
	print("[emissive-region] all-glowing mesh: band %s, middle %s" % [all[0], all[1]])
	var middle: Color = strip[1]
	var band: Color = strip[0]
	var all_middle: Color = all[1]
	_check(all_middle.b > 2.0 * all_middle.r + 0.05, "an all-glowing box reads blue in its middle (%s)" % all_middle)
	_check(middle.b < 1.3 * middle.r + 0.02, "a box with a glowing strip doesn't glow in its middle (%s)" % middle)
	_check(band.b > 2.0 * band.r + 0.05, "its strip's band reads blue (%s)" % band)
	print("[emissive-region] %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
