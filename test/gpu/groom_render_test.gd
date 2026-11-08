extends SceneTree

# PhysXGroom3D draws, both render modes, and keeps doing so through what broke it before:
# - Mesh and Screen Space each draw the groom (the frame changes where the hair is).
# - render_mode set before the node enters the tree (Screen Space never got its strands).
# - Screen Space, Mesh, Screen Space again (the Tab toggle in the hair demo: it came back empty).
# - Screen Space hidden and shown again (its proxy stayed hidden).
# - Two Screen Space grooms each keep their own look (both took the colors of the one nearest the camera).
# Needs a window (the screen-space passes run on the RenderingDevice):
#   godot --path . --script res://test/gpu/groom_render_test.gd

const GROOM := "res://test/data/test_groom.abc"

var _ok := true
var _root: Node3D
var _cam: Camera3D
var _background := Color()


func _check(cond: bool, msg: String) -> void:
	print("[groom_render] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# The mean color of a 21 x 21 block around where p is on screen.
func _color_at(p: Vector3) -> Color:
	var img := get_root().get_texture().get_image()
	# unproject_position works in the viewport's size, which needn't be the image's (window scaling).
	var at := Vector2i(_cam.unproject_position(p) * Vector2(img.get_size()) / get_root().get_visible_rect().size)
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(-10, 11):
		for x in range(-10, 11):
			var q := at + Vector2i(x, y)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				sum += img.get_pixelv(q)
				n += 1
	return sum / maxf(n, 1)


func _differs(c: Color) -> float:
	return absf(c.r - _background.r) + absf(c.g - _background.g) + absf(c.b - _background.b)


func _hair(groom: Resource, x: float, mode: int) -> Node3D:
	var hair: Node3D = ClassDB.instantiate("PhysXGroom3D")
	hair.groom = groom
	# Set before it enters the tree.
	hair.render_mode = mode
	hair.width_scale = 3.0
	hair.position.x = x
	_root.add_child(hair)
	return hair


# Where the hair hangs thickest in front of the camera: below the sphere's middle.
func _spot(hair: Node3D, groom: Resource) -> Vector3:
	var box: AABB = groom.get_aabb()
	return hair.global_position + box.get_center() + Vector3(0, -box.size.y * 0.2, 0)


func _run() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 20, 0)
	_root.add_child(sun)
	var groom: Resource = load(GROOM)
	var box: AABB = groom.get_aabb()
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.position = box.get_center() + Vector3(0, 0, 1.1)
	_cam.look_at(box.get_center())
	await _frames(3)
	_background = _color_at(box.get_center())

	# Each mode draws; Screen Space set before entering the tree.
	for mode in [0, 1]:
		var hair := _hair(groom, 0.0, mode)
		await _frames(8)
		var d := _differs(_color_at(_spot(hair, groom)))
		_check(d > 0.15, "%s draws the hair (%.2f off the background)" % [["Mesh", "Screen Space"][mode], d])
		hair.queue_free()
		await _frames(3)

	# Screen Space, Mesh, Screen Space.
	var toggled := _hair(groom, 0.0, 1)
	await _frames(6)
	toggled.render_mode = 0
	await _frames(6)
	toggled.render_mode = 1
	await _frames(8)
	var d_toggle := _differs(_color_at(_spot(toggled, groom)))
	_check(d_toggle > 0.15, "Screen Space draws again after Mesh and back (%.2f)" % d_toggle)

	# Hidden, then shown.
	toggled.visible = false
	await _frames(6)
	var d_hidden := _differs(_color_at(_spot(toggled, groom)))
	_check(d_hidden < 0.05, "hidden, it's gone (%.2f)" % d_hidden)
	toggled.visible = true
	await _frames(8)
	var d_shown := _differs(_color_at(_spot(toggled, groom)))
	_check(d_shown > 0.15, "shown again, it draws (%.2f)" % d_shown)
	toggled.queue_free()
	await _frames(3)

	# Two Screen Space grooms side by side, red and blue; the camera nearer the blue one.
	var red := _hair(groom, -0.17, 1)
	red.root_color = Color(0.9, 0.05, 0.05)
	red.tip_color = Color(0.9, 0.05, 0.05)
	var blue := _hair(groom, 0.17, 1)
	blue.root_color = Color(0.05, 0.1, 0.9)
	blue.tip_color = Color(0.05, 0.1, 0.9)
	_cam.position = box.get_center() + Vector3(0.1, 0, 1.0)
	_cam.look_at(box.get_center())
	await _frames(8)
	var c_red := _color_at(_spot(red, groom))
	var c_blue := _color_at(_spot(blue, groom))
	# Measured against the (bluish) background: red where the red groom is, more blue where the blue one is.
	_check(c_red.r > _background.r + 0.05 and c_red.b < _background.b - 0.05, "the red groom draws red (%s)" % c_red)
	_check(c_blue.r < _background.r - 0.05 and c_blue.b - c_blue.r > _background.b - _background.r + 0.05, "the blue groom draws blue (%s)" % c_blue)

	print("[groom_render] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXGroom3D"):
		print("SKIP: no PhysXGroom3D in this build")
		quit(0)
		return
	if not ResourceLoader.exists(GROOM):
		print("SKIP: test_groom.abc isn't imported (an editor built without alembic_sdk= can't import .abc files)")
		quit(0)
		return
	if RenderingServer.get_rendering_device() == null:
		print("SKIP: no RenderingDevice (run with a window, Forward+ or Mobile)")
		quit(0)
		return
	DisplayServer.window_set_size(Vector2i(1280, 720))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
