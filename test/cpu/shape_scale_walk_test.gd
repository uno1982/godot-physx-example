extends SceneTree

# Smoke test for demo/editor/cpu/shape_scale.tscn: build every scaled piece and
# drop a rigid ball straight onto it, confirming the baked-in node scale gives
# it a real collision surface (nothing tunnels to the ground).

var _scene: Node3D
var _t := 0
var _balls: Array = []


func _initialize() -> void:
	print("[scalewalk] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	_scene = load("res://demo/editor/cpu/shape_scale.tscn").instantiate()
	get_root().add_child(_scene)
	await physics_frame
	await physics_frame

	# drop x/z, label, expected rest y (surface + 0.3 ball radius), tolerance
	var spots := [
		[Vector2(-8, 4), "platform_low", 0.9, 0.3],
		[Vector2(-14, 4), "platform_mid", 1.9, 0.3],
		[Vector2(8, 4), "sphere_dome", 1.1, 0.5],
		[Vector2(0, 8), "convex_ramp", 0.8, 0.5],
		[Vector2(16, 8), "trimesh_hump", 1.4, 0.6],
		[Vector2(24, 2), "heightfield_mound", 1.3, 0.9],
	]
	for s in spots:
		var xz: Vector2 = s[0]
		var rb := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.3
		cs.shape = sh
		rb.add_child(cs)
		rb.position = Vector3(xz.x, 7, xz.y)
		_scene.add_child(rb)
		_balls.append({ "rb": rb, "name": s[1], "y": s[2], "tol": s[3] })

	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t < 200:
		return
	var ok := true
	for b in _balls:
		var y: float = b.rb.position.y
		var pass_b: bool = abs(y - b.y) < b.tol
		ok = ok and pass_b
		print("  %-20s rest y=%.2f  expect ~%.2f ±%.2f  %s" % [b.name, y, b.y, b.tol, "OK" if pass_b else "FAIL"])
	print("[scalewalk] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
