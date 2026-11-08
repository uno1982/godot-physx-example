extends SceneTree

# PhysXGroom3D's hair simulation (GroomSim), from what it draws:
# - Simulated hair draws, Mesh and Screen Space (the strands come from the simulation's texture).
# - Wind blowing to +x moves the hair: less of it to the left of the head, more to the right.
# - A sphere CollisionShape3D in colliders pushes the hair out of where it is (it shows up outside it); so does one on a
#   PhysicalBone3D, through the Skeleton3D's path (placed from the bone's pose: the physical bones aren't simulating).
# - Moved 5 m away and back (a teleport, not motion), the hair starts over and draws where it was.
# - simulate off: the groomed shape again.
# Needs a window (the simulation runs on the RenderingDevice):
#   godot --path . --script res://test/gpu/groom_sim_test.gd

const GROOM := "res://test/data/test_groom.abc"

var _ok := true
var _root: Node3D
var _cam: Camera3D
var _background := Color()
var _groom: Resource
var _center := Vector3()


func _check(cond: bool, msg: String) -> void:
	print("[groom_sim] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# The mean color of a 15 x 15 block around where p is on screen.
func _color_at(p: Vector3) -> Color:
	var img := get_root().get_texture().get_image()
	var at := Vector2i(_cam.unproject_position(p) * Vector2(img.get_size()) / get_root().get_visible_rect().size)
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(-7, 8):
		for x in range(-7, 8):
			var q := at + Vector2i(x, y)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				sum += img.get_pixelv(q)
				n += 1
	return sum / maxf(n, 1)


# How much hair there is at p: how far its color is from the background's.
func _hair_at(p: Vector3) -> float:
	var c := _color_at(p)
	return absf(c.r - _background.r) + absf(c.g - _background.g) + absf(c.b - _background.b)


func _hair(mode: int) -> Node3D:
	var hair: Node3D = ClassDB.instantiate("PhysXGroom3D")
	hair.groom = _groom
	hair.render_mode = mode
	hair.width_scale = 3.0
	_root.add_child(hair)
	return hair


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
	_groom = load(GROOM)
	# The head: the sphere the roots grow on (radius 0.1), in the middle of the box's top.
	var box: AABB = _groom.get_aabb()
	_center = Vector3(box.get_center().x, box.end.y - 0.1, box.get_center().z)
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.position = _center + Vector3(0, -0.05, 0.9)
	_cam.look_at(_center + Vector3(0, -0.05, 0))
	await _frames(3)
	_background = _color_at(_center)
	# Beside the head, where the hair hangs: left and right.
	var left := _center + Vector3(-0.12, -0.1, 0)
	# Out to the right, past where the hair hangs.
	var right := _center + Vector3(0.21, -0.1, 0)

	# Simulated, each mode draws.
	for mode in [1, 0]:
		var hair := _hair(mode)
		await _frames(40)
		var d := _hair_at(left)
		_check(d > 0.12, "simulated, %s draws the hair (%.2f off the background)" % [["Mesh", "Screen Space"][mode], d])
		if mode == 1:
			hair.queue_free()
			await _frames(3)

	var hair: Node3D = _root.get_child(_root.get_child_count() - 1)
	var left_still := _hair_at(left)
	var right_still := _hair_at(right)

	# Wind to +x.
	hair.wind = Vector3(15, 0, 0)
	await _frames(60)
	var left_wind := _hair_at(left)
	var right_wind := _hair_at(right)
	_check(left_wind < left_still - 0.05, "wind to +x: less hair on the left (%.2f -> %.2f)" % [left_still, left_wind])
	_check(right_wind > right_still + 0.02, "wind to +x: more hair on the right (%.2f -> %.2f)" % [right_still, right_wind])
	hair.wind = Vector3.ZERO
	await _frames(120)

	# A sphere collider where the hair hangs on the left.
	var spot := _center + Vector3(-0.11, -0.12, 0.0)
	# Just outside it, away from the head: where the hair it pushes out goes.
	var outside := spot + Vector3(-0.065, 0, 0)
	var before := _hair_at(spot)
	var before_outside := _hair_at(outside)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.05
	shape.shape = sphere
	body.add_child(shape)
	body.position = spot
	_root.add_child(body)
	hair.colliders = [hair.get_path_to(shape)]
	await _frames(40)
	var with_shape := _hair_at(spot)
	var with_shape_outside := _hair_at(outside)
	print("[groom_sim] sphere: at %.2f -> %.2f, outside %.2f -> %.2f" % [before, with_shape, before_outside, with_shape_outside])
	# (Where it is, the hair it pushed aside still covers it from the front.)
	_check(with_shape_outside > before_outside + 0.1, "a sphere collider pushes the hair out of its place")
	hair.colliders = []
	body.queue_free()
	await _frames(120)
	var after_outside := _hair_at(outside)
	_check(after_outside < with_shape_outside - 0.1, "the collider gone, the hair falls back (outside %.2f)" % after_outside)

	# The same sphere on a physical bone, through the skeleton.
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Bone")
	skeleton.set_bone_rest(0, Transform3D(Basis(), spot))
	skeleton.set_bone_pose_position(0, spot)
	var simulator := PhysicalBoneSimulator3D.new()
	skeleton.add_child(simulator)
	var bone := PhysicalBone3D.new()
	bone.bone_name = "Bone"
	simulator.add_child(bone)
	var bone_shape := CollisionShape3D.new()
	bone_shape.shape = sphere
	bone.add_child(bone_shape)
	_root.add_child(skeleton)
	hair.colliders = [hair.get_path_to(skeleton)]
	await _frames(40)
	var with_bone := _hair_at(spot)
	var with_bone_outside := _hair_at(outside)
	print("[groom_sim] bone: at %.2f -> %.2f, outside %.2f -> %.2f" % [before, with_bone, before_outside, with_bone_outside])
	_check(with_bone_outside > before_outside + 0.1, "a physical bone's sphere pushes the hair out")
	hair.colliders = []
	skeleton.queue_free()
	await _frames(40)

	# A teleport and back.
	hair.position.x = 5.0
	await _frames(3)
	hair.position.x = 0.0
	await _frames(30)
	var d_back := _hair_at(left)
	_check(d_back > 0.12, "teleported away and back, it draws where it was (%.2f)" % d_back)

	# Simulation off: as groomed.
	hair.simulate = false
	await _frames(5)
	var static_left := _hair_at(left)
	hair.queue_free()
	await _frames(3)
	var groomed := _hair(0)
	groomed.simulate = false
	await _frames(5)
	var groomed_left := _hair_at(left)
	_check(absf(static_left - groomed_left) < 0.03, "simulate off draws the groomed shape (%.2f, groomed %.2f)" % [static_left, groomed_left])

	print("[groom_sim] %s" % ("PASS" if _ok else "FAIL"))
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
	Engine.max_fps = 60
	process_frame.connect(_run, CONNECT_ONE_SHOT)
