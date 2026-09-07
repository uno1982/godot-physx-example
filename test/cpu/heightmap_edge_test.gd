extends SceneTree

# Regression for the PhysX 5 GPU-narrowphase illegal-address crash: rigid bodies
# rolling off the edge of a HeightMapShape3D. Spawns balls near the rim with
# outward velocity and runs long past the old ~17-40s fault window.

var _scene: Node3D
var _t := 0
var _balls: Array[RigidBody3D] = []


func _initialize() -> void:
	_scene = load("res://demo/editor/cpu/heightmap.tscn").instantiate()
	get_root().add_child(_scene)
	await process_frame
	var grid: int = _scene.grid
	var edge := (grid - 1) * 0.5 - 2.0
	for i in 24:
		var rb := RigidBody3D.new()
		rb.mass = 3.0
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.4
		cs.shape = s
		rb.add_child(cs)
		var ang := TAU * i / 24.0
		rb.position = Vector3(cos(ang) * edge, _scene.height + 3.0, sin(ang) * edge)
		rb.linear_velocity = Vector3(cos(ang), 0.2, sin(ang)) * 14.0
		_scene.add_child(rb)
		_balls.append(rb)
	print("[hmap-edge] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	for b in _balls:
		if is_instance_valid(b) and (is_nan(b.position.x) or b.position.y < -500.0):
			b.queue_free()
	if _t == 3600: # 60 s at 60 Hz -- 3x the old crash window
		print("[hmap-edge] PASS  survived %d physics ticks, no GPU narrowphase fault" % _t)
		quit(0)
