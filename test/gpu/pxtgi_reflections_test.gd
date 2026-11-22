extends SceneTree

# PXTGI3D's reflections. A closed room (6 x 4 x 8 m) lit by one light under the ceiling, a chrome mirror on its front
# wall (z -4), the camera in front of it. The back wall (z +4, behind the camera) is red with a gray checker texture:
# PXTGI's own color for it off screen is its albedo color (red, flat), while a reflection probe's capture has the
# checker. The room's ReflectionProbe (intensity 0, shadows, updated once) captures from a point off to the side.
#   1. traced: the mirror shows the red wall behind the camera (red over green well above 1);
#   2. traced + probes: the same wall shows its checker (texture from the probe's capture; a flat red in traced);
#   3. traced + probes, a moving body left out of the probe's capture standing between that wall and the probe's
#      capture point (out of the mirror's view itself): the wall where the probe can't see past the body reads the
#      same as without the body (it used to read flat: the body hid it from the probe);
#   4. a pxtgi_traced skinned mesh, green in front and blue behind, between the camera and the mirror, its back on
#      screen: the mirror shows its green front, not its blue back from the screen;
#   5. the mirror rougher than the roughness cutoff keeps Godot's reflection (no sky, no probe: dark), not the traced
#      red wall.
# Windowed only (PXTGI needs a RenderingDevice).

const MIRROR_Z := -3.94 # the mirror's front face
const BODY_LAYER := 1 << 1 # the moving body: left out of the probe's capture and of the camera

var failures := 0
var _room: Node3D
var _gi: Node3D
var _probe: ReflectionProbe
var _camera: Camera3D
var _mirror_material: StandardMaterial3D


func _check(ok: bool, what: String) -> void:
	print("[reflections] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, body := true) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	if not body:
		mesh.position = at
		parent.add_child(mesh)
		return mesh
	var sb := StaticBody3D.new()
	sb.position = at
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	sb.add_child(mesh)
	parent.add_child(sb)
	return sb


func _checker() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(1, 1, 1) if on else Color(0.25, 0.25, 0.25))
	return ImageTexture.create_from_image(img)


func _build() -> void:
	_room = Node3D.new()
	root.add_child(_room)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_room.add_child(we)

	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.8, 0.8, 0.8)
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(1.0, 0.25, 0.25)
	back.albedo_texture = _checker()
	back.uv1_triplanar = true
	back.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_box(_room, Vector3(6, 0.2, 8), Vector3(0, -0.1, 0), white) # floor
	_box(_room, Vector3(6, 0.2, 8), Vector3(0, 4.1, 0), white) # ceiling
	_box(_room, Vector3(0.2, 4, 8), Vector3(-3.1, 2, 0), white)
	_box(_room, Vector3(0.2, 4, 8), Vector3(3.1, 2, 0), white)
	_box(_room, Vector3(6, 4, 0.2), Vector3(0, 2, -4.1), white) # the mirror's wall
	_box(_room, Vector3(6, 4, 0.2), Vector3(0, 2, 4.1), back) # behind the camera

	_mirror_material = StandardMaterial3D.new()
	_mirror_material.metallic = 1.0
	_mirror_material.roughness = 0.0
	_box(_room, Vector3(3, 2.5, 0.12), Vector3(0, 1.8, MIRROR_Z - 0.06), _mirror_material, false)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.5, 0)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.shadow_enabled = true
	_room.add_child(light)

	_probe = ReflectionProbe.new()
	_probe.position = Vector3(0, 2, 0)
	_probe.size = Vector3(6.2, 4.2, 8.2)
	_probe.origin_offset = Vector3(2.5, 0, 0) # captured from (2.5, 2, 0)
	_probe.box_projection = true
	_probe.intensity = 0.0
	_probe.enable_shadows = true
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_probe.cull_mask = 0xFFFFF & ~BODY_LAYER
	_probe.visible = false
	_room.add_child(_probe)

	_gi = ClassDB.instantiate("PXTGI3D")
	_room.add_child(_gi)

	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.cull_mask = 0xFFFFF & ~BODY_LAYER
	_room.add_child(_camera)
	_camera.position = Vector3(0, 1.8, -1.5)
	_camera.look_at(Vector3(0, 1.8, MIRROR_Z))
	_camera.current = true


func _set_mode(mode: int) -> void:
	_gi.set("reflection_mode", mode)
	_probe.visible = mode == 3


# Where a world point shows in the mirror: the point mirrored through the glass, projected.
func _in_mirror(p: Vector3) -> Vector2:
	return _camera.unproject_position(Vector3(p.x, p.y, 2.0 * MIRROR_Z - p.z))


func _image() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


# The pixels around a point in the viewport's coordinates (the project's base size; the image is the window's).
func _window(img: Image, at: Vector2, half: int) -> Array:
	var center := at * Vector2(img.get_size()) / root.get_visible_rect().size
	var cols: Array[Color] = []
	for y in range(int(center.y) - half, int(center.y) + half + 1):
		for x in range(int(center.x) - half, int(center.x) + half + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				cols.append(img.get_pixel(x, y))
	return cols


func _mean(cols: Array) -> Color:
	var s := Color(0, 0, 0, 0)
	for c: Color in cols:
		s += c
	return s / maxf(cols.size(), 1)


func _lum_spread(cols: Array) -> float:
	var m := 0.0
	for c: Color in cols:
		m += c.get_luminance()
	m /= maxf(cols.size(), 1)
	var v := 0.0
	for c: Color in cols:
		v += (c.get_luminance() - m) * (c.get_luminance() - m)
	return sqrt(v / maxf(cols.size(), 1))


func _skinned_slabs() -> Node3D:
	# A character: one bone, two surfaces (a green slab in front, -z, and a blue one behind), skinned to the bone.
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("root")
	var mesh := ArrayMesh.new()
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.1, 0.9, 0.1)
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.1, 0.2, 1.0)
	for slab in [[-0.08, green], [0.08, blue]]:
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 1.6, 0.14)
		var arrays := b.get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] += Vector3(0, 0.8, slab[0])
		arrays[Mesh.ARRAY_VERTEX] = v
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for i in v.size():
			bones.append_array([0, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, slab[1])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var skin := Skin.new()
	skin.add_bind(0, Transform3D())
	mi.skin = skin
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.set_meta("pxtgi_traced", true)
	return skeleton


func _run() -> void:
	await process_frame
	if RenderingServer.get_rendering_device() == null or DisplayServer.get_name() == "headless":
		print("SKIP: PXTGI needs a windowed run")
		quit(0)
		return
	if not ClassDB.class_exists("PXTGI3D"):
		print("SKIP: no PXTGI3D in this build")
		quit(0)
		return
	_build()
	# The back wall in the mirror, around its middle (left of the probe's side).
	var wall_spot := _in_mirror(Vector3(-0.6, 1.9, 4.0))

	# 1. Traced.
	_set_mode(2)
	await _frames(150)
	var img := await _image()
	img.save_png("res://excluded/reflections_traced.png")
	var traced := _window(img, wall_spot, 14)
	var tc := _mean(traced)
	print("[reflections] traced: wall in the mirror %s, spread %.3f" % [tc, _lum_spread(traced)])
	_check(tc.r > 2.0 * tc.g and tc.r > 0.05, "traced: the mirror shows the red wall behind the camera")

	# 2. Traced + probes: the checker.
	_set_mode(3)
	await _frames(150)
	img = await _image()
	img.save_png("res://excluded/reflections_probes.png")
	var probed := _window(img, wall_spot, 14)
	print("[reflections] traced + probes: wall %s, spread %.3f" % [_mean(probed), _lum_spread(probed)])
	_check(_lum_spread(probed) > 2.0 * _lum_spread(traced) + 0.01, "traced + probes: the wall shows its texture (from the probe's capture)")

	# 3. A moving body between the wall and the probe's capture point, out of the mirror's view: where the probe can't
	# see past it on the wall (from the capture point, through the body), the same as without it.
	var capture := _probe.global_position + _probe.origin_offset
	var body_at := Vector3(1.9, 2.0, 2.5)
	var shade_on_wall := capture + (body_at - capture) * ((4.0 - capture.z) / (body_at.z - capture.z))
	var shade_spot := _in_mirror(shade_on_wall)
	img = await _image()
	var without := _window(img, shade_spot, 8)
	var body := AnimatableBody3D.new()
	body.position = body_at
	var bcs := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(0.5, 0.5, 0.5)
	bcs.shape = bshape
	body.add_child(bcs)
	var bmesh := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.5, 0.5, 0.5)
	bmesh.mesh = bbox
	bmesh.layers = BODY_LAYER
	body.add_child(bmesh)
	_room.add_child(body)
	await _frames(90)
	img = await _image()
	img.save_png("res://excluded/reflections_probes_body.png")
	var with_body := _window(img, shade_spot, 8)
	var diff := 0.0
	for i in mini(without.size(), with_body.size()):
		diff += absf(without[i].get_luminance() - with_body[i].get_luminance())
	diff /= maxf(mini(without.size(), with_body.size()), 1)
	print("[reflections] where the body hides the wall from the probe (%s on screen): mean change %.4f, spread there %.3f" % [shade_spot, diff, _lum_spread(without)])
	_check(_lum_spread(without) > 0.02, "(that spot shows the checker, so a flat fallback would show)")
	_check(diff < 0.25 * _lum_spread(without), "traced + probes: a moving body the probe left out doesn't shade its outline on the wall")
	body.queue_free()

	# 4. A pxtgi_traced character between the camera and the mirror, its blue back on screen, its green front facing
	# the mirror.
	_set_mode(2)
	var character := _skinned_slabs()
	character.position = Vector3(0.8, 0.2, -2.2)
	_room.add_child(character)
	_camera.position = Vector3(0, 1.4, -0.4)
	_camera.look_at(Vector3(0.45, 1.1, MIRROR_Z))
	await _frames(150)
	img = await _image()
	img.save_png("res://excluded/reflections_character.png")
	var seen_back := _window(img, _camera.unproject_position(Vector3(0.8, 1.0, -2.1)), 6)
	var in_mirror := _window(img, _in_mirror(Vector3(0.8, 1.0, -2.3)), 6)
	var back_c := _mean(seen_back)
	var mirror_c := _mean(in_mirror)
	print("[reflections] character: its back on screen %s, in the mirror %s" % [back_c, mirror_c])
	_check(back_c.b > 2.0 * back_c.g, "(its blue back is on screen)")
	_check(mirror_c.g > 2.0 * mirror_c.b and mirror_c.g > 0.05, "the mirror shows its green front, not its back from the screen")
	character.queue_free()

	# 5. Rougher than the cutoff: Godot's reflection (nothing here), not the traced wall.
	_camera.position = Vector3(0, 1.8, -1.5)
	_camera.look_at(Vector3(0, 1.8, MIRROR_Z))
	_mirror_material.roughness = 0.85
	await _frames(120)
	img = await _image()
	img.save_png("res://excluded/reflections_rough.png")
	var rough := _mean(_window(img, wall_spot, 14))
	print("[reflections] rough mirror: %s (smooth showed %s)" % [rough, tc])
	_check(rough.r < 0.5 * tc.r or rough.r < 1.3 * rough.g, "past the roughness cutoff the traced wall isn't reflected")

	print("[reflections] %s" % ("PASS" if failures == 0 else "FAIL: %d" % failures))
	quit(0 if failures == 0 else 1)
