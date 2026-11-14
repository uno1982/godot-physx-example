extends SceneTree

# PXTGI3D after the window is resized: the lighting must not pick up garbage. A neutral gray room lit white (a lamp
# panel and a spot), with a mirror-smooth metal frame, a dark glossy sphere and a reflection probe, reflections on
# Traced + Probes. Nothing in it has a color, so a pixel with one (the blue clouds, the yellow specks seen on metal
# after a resize) is garbage. Counted at a few spots in the run:
#   1. settled at the first size: no garbage;
#   2. through the frames after a resize to a smaller size, and after one back: none;
#   3. dragged to a new size every frame, every frame looked at: none.
# The garbage was Godot's image right after a resize (a new texture, never drawn into) read as last frame's light:
# Vulkan hands a new texture back with whatever its memory held, D3D12 mostly zeroed, so run it on Vulkan to catch it
# (this project's default is D3D12, where it passed even with the bug). Needs a window (a compositor effect):
#   godot --path . --rendering-driver vulkan --script res://test/gpu/pxtgi_resize_test.gd
# PXTGI_RESIZE_SHOTS=<dir> saves a frame every 60 to look at.

const SETTLE := 400
const AFTER := 300
const DRAG := 60
var _t := 0
var _phase := 0
var _ok := true
var _worst := {}


func _check(cond: bool, msg: String) -> void:
	print("[gi-resize] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	root.add_child(mi)
	mi.position = pos


func _initialize() -> void:
	if not ClassDB.class_exists("PXTGI3D"):
		print("[gi-resize] SKIP: no PXTGI3D")
		quit(0)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var root := Node3D.new()
	get_root().add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	# The setup it was seen in: AgX with glow, SMAA, and a lamp far brighter than white under the exposure.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 8.27
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.03
	we.environment = env
	get_root().screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
	root.add_child(we)

	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.7, 0.7, 0.7)
	gray.roughness = 0.9
	_box(root, Vector3(6, 0.2, 6), Vector3(0, -0.1, 0), gray)
	_box(root, Vector3(6, 0.2, 6), Vector3(0, 3.1, 0), gray)
	_box(root, Vector3(0.2, 3, 6), Vector3(-3.1, 1.5, 0), gray)
	_box(root, Vector3(0.2, 3, 6), Vector3(3.1, 1.5, 0), gray)
	_box(root, Vector3(6, 3, 0.2), Vector3(0, 1.5, -3.1), gray)
	_box(root, Vector3(6, 3, 0.2), Vector3(0, 1.5, 3.1), gray)

	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0, 0, 0)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 1, 1)
	lamp.emission_energy_multiplier = 20.0
	_box(root, Vector3(2, 0.05, 2), Vector3(0, 2.97, 0), lamp)
	var spot := SpotLight3D.new()
	spot.light_energy = 4.0
	spot.spot_range = 6.0
	spot.spot_angle = 60.0
	spot.shadow_enabled = true
	root.add_child(spot)
	spot.position = Vector3(0, 2.9, -1)
	spot.rotation_degrees = Vector3(-90, 0, 0)

	# A bench-like frame of mirror-smooth metal, and a dark glossy sphere.
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.9, 0.9, 0.9)
	chrome.metallic = 1.0
	chrome.roughness = 0.05
	for x in [-1.3, 1.3]:
		_box(root, Vector3(0.06, 0.6, 0.6), Vector3(x - 0.4, 0.3, -1.6), chrome)
	_box(root, Vector3(2.6, 0.06, 0.6), Vector3(-0.4, 0.4, -1.6), chrome)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	dark.roughness = 0.28
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.material_override = dark
	root.add_child(sphere)
	sphere.position = Vector3(1.6, 0.5, -1.2)

	var gi: Node3D = ClassDB.instantiate("PXTGI3D")
	gi.set("reflection_mode", 3)
	gi.set("reflection_roughness_cutoff", 0.35)
	root.add_child(gi)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(6, 3, 6)
	probe.interior = true
	probe.box_projection = true
	probe.enable_shadows = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.intensity = 0.0
	gi.add_child(probe)
	probe.position = Vector3(0, 1.5, 0)

	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0.4, 1.4, 1.8), Vector3(0.2, 0.5, -1.4))
	process_frame.connect(_frame)


# Pixels with a color, out of a 160 x 90 sampling of the frame: the room is gray and lit white, so any is garbage.
func _garbage() -> int:
	var img := get_root().get_texture().get_image()
	img.resize(160, 90, Image.INTERPOLATE_NEAREST)
	var n := 0
	for y in 90:
		for x in 160:
			var c := img.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) > 0.08:
				n += 1
	return n


func _frame() -> void:
	_t += 1
	var shots := OS.get_environment("PXTGI_RESIZE_SHOTS")
	if not shots.is_empty() and _t % 60 == 0:
		get_root().get_texture().get_image().save_png("%s/p%d_f%d.png" % [shots, _phase, _t])
	if _phase == 0:
		if _t == SETTLE:
			var n := _garbage()
			print("[gi-resize] settled at %s: %d colored samples" % [get_root().get_texture().get_size(), n])
			_check(n == 0, "settled: no garbage")
			DisplayServer.window_set_size(Vector2i(960, 540))
			_phase = 1
			_t = 0
		return
	# Dragged: a new size every frame, as dragging an editor split does, and every frame looked at (the GI buffers are
	# remade each time, and one frame of garbage each time was what showed).
	if _phase == 3:
		if _t <= DRAG:
			var n := _garbage()
			_worst["drag"] = maxi(_worst.get("drag", 0), n)
			if n > 0:
				print("[gi-resize] drag f%d (%s): %d colored samples" % [_t, get_root().get_texture().get_size(), n])
			DisplayServer.window_set_size(Vector2i(1280 - 6 * _t, 720 - 3 * _t))
			return
		_check(_worst.get("drag", 0) == 0, "while dragged to a new size every frame: no garbage in any frame (worst %d)" % _worst.get("drag", 0))
		print("[gi-resize] %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
		return
	if _t % 15 == 0:
		var n := _garbage()
		var key := "smaller" if _phase == 1 else "back"
		_worst[key] = maxi(_worst.get(key, 0), n)
		print("[gi-resize] %s f%d (%s): %d colored samples" % [key, _t, get_root().get_texture().get_size(), n])
	if _t < AFTER:
		return
	if _phase == 1:
		_check(_worst.get("smaller", 0) == 0, "after a resize to a smaller window: no garbage (worst %d)" % _worst.get("smaller", 0))
		DisplayServer.window_set_size(Vector2i(1280, 720))
		_phase = 2
		_t = 0
		return
	if _phase == 2:
		_check(_worst.get("back", 0) == 0, "after a resize back: no garbage (worst %d)" % _worst.get("back", 0))
		_phase = 3
		_t = 0
		return
