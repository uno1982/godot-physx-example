extends SceneTree

# Non-uniform node scale must bake into the collision shape (box per-axis,
# convex/trimesh via PxMeshScale, height field via row/col/height scale),
# matching Jolt. Sphere/capsule are uniform-only.

var _checks: Array = []
var _t := 0


func _initialize() -> void:
	print("[scale] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	var root := get_root()

	# 1. Box floor scaled 3x tall (y). Its top should sit at y = 0.5 (half of a
	#    unit box) * 3 = 1.5, so a ball rests at ~1.5 + ball radius.
	var box_body := StaticBody3D.new()
	box_body.transform = Transform3D(Basis().scaled(Vector3(4, 3, 4)), Vector3(0, 0, 0))
	var box_cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	box_cs.shape = box
	box_body.add_child(box_cs)
	root.add_child(box_body)
	_ball(Vector3(0, 6, 0), "box_scaled_y", 1.5 + 0.3)

	# 2. Convex (unit box hull) floor at x=20, scaled 2.5x tall -> top at y = 1.25.
	var cvx_body := StaticBody3D.new()
	cvx_body.transform = Transform3D(Basis().scaled(Vector3(4, 2.5, 4)), Vector3(20, 0, 0))
	var cvx_cs := CollisionShape3D.new()
	var cvx := ConvexPolygonShape3D.new()
	cvx.points = PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)])
	cvx_cs.shape = cvx
	cvx_body.add_child(cvx_cs)
	root.add_child(cvx_body)
	_ball(Vector3(20, 6, 0), "convex_scaled_y", 1.25 + 0.3)

	# 3. Trimesh floor (a closed unit box) at x=40, scaled 3x on y -> its top
	#    face (local y=0.5) lands at world y=1.5.
	var tri_body := StaticBody3D.new()
	tri_body.transform = Transform3D(Basis().scaled(Vector3(6, 3, 6)), Vector3(40, 0, 0))
	var tri_cs := CollisionShape3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	tri_cs.shape = bm.create_trimesh_shape()
	tri_body.add_child(tri_cs)
	root.add_child(tri_body)
	_ball(Vector3(40, 5, 0), "trimesh_scaled_y", 1.5 + 0.3)

	# 3b. Height field (flat 5x5) at x=-20, scaled 3x on y. Flat height 2.0 in
	#     the data -> world 6.0 after scale.
	var hf_body := StaticBody3D.new()
	hf_body.transform = Transform3D(Basis().scaled(Vector3(1, 3, 1)), Vector3(-20, 0, 0))
	var hf_cs := CollisionShape3D.new()
	var hf := HeightMapShape3D.new()
	hf.map_width = 5
	hf.map_depth = 5
	var hd := PackedFloat32Array()
	for i in 25:
		hd.append(2.0)
	hf.map_data = hd
	hf_cs.shape = hf
	hf_body.add_child(hf_cs)
	root.add_child(hf_body)
	_ball(Vector3(-20, 12, 0), "heightfield_scaled_y", 6.0 + 0.3)

	# 4. Control: same box shape, NO scale -> ball rests at 0.5 + 0.3.
	var ctl := StaticBody3D.new()
	ctl.position = Vector3(60, 0, 0)
	var ctl_cs := CollisionShape3D.new()
	var ctl_box := BoxShape3D.new()
	ctl_box.size = Vector3(4, 1, 4)
	ctl_cs.shape = ctl_box
	ctl.add_child(ctl_cs)
	root.add_child(ctl)
	_ball(Vector3(60, 6, 0), "box_unscaled_control", 0.5 + 0.3)

	get_root().get_tree() # noop


func _ball(pos: Vector3, name: String, expect_y: float) -> void:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	get_root().add_child(rb)
	_checks.append({ "rb": rb, "name": name, "expect": expect_y })
	if _checks.size() == 5:
		physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t < 240:
		return
	var ok := true
	for c in _checks:
		var y: float = c.rb.position.y
		var pass_c: bool = abs(y - c.expect) < 0.25 and y > -5.0
		ok = ok and pass_c
		print("  %-24s rest y=%.2f  expect ~%.2f  %s" % [c.name, y, c.expect, "OK" if pass_c else "FAIL"])
	print("[scale] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
