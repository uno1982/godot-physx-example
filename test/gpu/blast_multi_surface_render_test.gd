extends SceneTree

# PhysXDestructible3D draws each source surface with its own material (R22): a 2 m box whose top is red, sides blue
# and bottom green (unshaded), seen from above at an angle, counted by colour:
# - intact: red and blue, nothing in the default white;
# - broken with interior_material (yellow): red, blue and yellow;
# - broken without it: the cut faces take the first surface's material (red), no yellow or white;
# - material_override (magenta) replaces every surface, and an asset from before surfaces were kept still takes it.
# Writes blast_multi_surface_render.png to user:// for a look.

var _ok := true
var _root: Node3D
var _images: Array[Image] = []


func _check(cond: bool, msg: String) -> void:
	print("[blast_multi_render] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _surface_of_normal(n: Vector3) -> int:
	if n.y > 0.5:
		return 0
	if n.y < -0.5:
		return 2
	return 1


func _box(materials: Array) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 2.0
	var a := box.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var mesh := ArrayMesh.new()
	for s in 3:
		var sv := PackedVector3Array()
		var sn := PackedVector3Array()
		var si := PackedInt32Array()
		var remap := {}
		for t in range(0, indices.size(), 3):
			if _surface_of_normal(normals[indices[t]]) != s:
				continue
			for v in 3:
				var i := indices[t + v]
				if not remap.has(i):
					remap[i] = sv.size()
					sv.append(verts[i])
					sn.append(normals[i])
				si.append(remap[i])
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = sv
		out[Mesh.ARRAY_NORMAL] = sn
		out[Mesh.ARRAY_INDEX] = si
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		mesh.surface_set_material(s, materials[s])
	return mesh


# Pixel counts by colour: red, blue, green, yellow, magenta, white.
func _count(img: Image) -> Dictionary:
	var counts := {"red": 0, "blue": 0, "green": 0, "yellow": 0, "magenta": 0, "white": 0}
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var hi := 0.7
			var lo := 0.3
			if c.r > hi and c.g > hi and c.b > hi:
				counts.white += 1
			elif c.r > hi and c.g > hi and c.b < lo:
				counts.yellow += 1
			elif c.r > hi and c.b > hi and c.g < lo:
				counts.magenta += 1
			elif c.r > hi and c.g < lo and c.b < lo:
				counts.red += 1
			elif c.b > hi and c.r < lo and c.g < lo:
				counts.blue += 1
			elif c.g > hi and c.r < lo and c.b < lo:
				counts.green += 1
	return counts


func _shot() -> Dictionary:
	for i in 4:
		await process_frame
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_images.append(img)
	return _count(img)


func _node(asset: Resource) -> Node3D:
	var node: Node3D = ClassDB.instantiate("PhysXDestructible3D")
	node.blast_asset = asset
	node.dynamic = false
	_root.add_child(node)
	return node


# Breaks it into pieces that stay near: no gravity, a few ticks after the break.
func _break(node: Node3D) -> void:
	for i in 3:
		await physics_frame
	node.apply_radial_damage(Vector3.ZERO, 1000.0, 5.0, 10.0)
	for i in 6:
		await physics_frame


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(640, 480))
	PhysicsServer3D.area_set_param(get_root().world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	_root = Node3D.new()
	get_root().add_child(_root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.4, 0.4)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_root.add_child(env)
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.look_at_from_position(Vector3(3.2, 4.0, 4.2), Vector3.ZERO)

	var materials := [_unshaded(Color.RED), _unshaded(Color.BLUE), _unshaded(Color.GREEN)]
	var yellow := _unshaded(Color.YELLOW)
	var magenta := _unshaded(Color.MAGENTA)
	var authoring: Object = ClassDB.instantiate("PhysXBlastAuthoring")
	var asset: Resource = authoring.fracture_mesh(_box(materials), 12, 7)
	if asset == null:
		_check(false, "fractures")
		quit(1)
		return

	var node := _node(asset)
	var intact := await _shot()
	_check(intact.red > 500 and intact.blue > 500 and intact.white == 0 and intact.yellow == 0, "intact: the top red and the sides blue (%s)" % intact)
	node.interior_material = yellow
	await _break(node)
	_check(node.is_fractured(), "breaks")
	var broken := await _shot()
	_check(broken.red > 300 and broken.blue > 300 and broken.yellow > 100 and broken.white == 0, "broken: each surface its own colour and the cut faces yellow (%s)" % broken)
	node.interior_material = null
	var plain := await _shot()
	_check(plain.yellow == 0 and plain.white == 0 and plain.red > broken.red, "without interior_material the cut faces take the first surface's material (%s)" % plain)
	node.material_override = magenta
	var over := await _shot()
	_check(over.magenta > 500 and over.red + over.blue + over.green + over.yellow + over.white == 0, "material_override replaces every surface (%s)" % over)
	node.queue_free()

	var old_asset: Resource = ClassDB.instantiate("PhysXBlastAsset")
	old_asset.asset_bytes = asset.asset_bytes
	old_asset.chunk_points = asset.chunk_points
	old_asset.chunk_normals = asset.chunk_normals
	old_asset.chunk_uvs = asset.chunk_uvs
	old_asset.chunk_interior_starts = asset.chunk_interior_starts
	var old := _node(old_asset)
	old.material_override = magenta
	old.interior_material = yellow
	await _break(old)
	var old_shot := await _shot()
	_check(old_shot.magenta > 300 and old_shot.yellow > 100 and old_shot.red + old_shot.blue + old_shot.white == 0, "an asset from before surfaces: material_override and interior_material as before (%s)" % old_shot)

	var w := 320
	var h := 240
	var sheet := Image.create(w * _images.size() + 10 * (_images.size() - 1), h, false, Image.FORMAT_RGB8)
	for i in _images.size():
		var im := _images[i]
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * (w + 10), 0))
	sheet.save_png("user://blast_multi_surface_render.png")
	print("[blast_multi_render] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXBlastAuthoring"):
		print("SKIP: no Blast support in this build")
		quit(0)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)
