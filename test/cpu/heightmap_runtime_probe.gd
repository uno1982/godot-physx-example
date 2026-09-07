extends Node3D

# Attach-free probe: runs the real heightmap showcase at RUNTIME (not editor),
# with rendering on, auto-spawns balls and walks them off the rim so we can see
# exactly what the console logs when they cross the edge.

var _t := 0
var _balls: Array[RigidBody3D] = []
var _half := 0.0
var _top := 0.0


func _ready() -> void:
	var scene: Node3D = load("res://demo/editor/cpu/heightmap.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	_half = (scene.grid - 1) * 0.5
	_top = scene.height
	print("PROBE up: grid=%d half=%.1f" % [scene.grid, _half])
	for i in 20:
		var rb := RigidBody3D.new()
		rb.mass = 2.0
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.5
		cs.shape = s
		rb.add_child(cs)
		rb.position = Vector3(randf_range(-_half + 6, _half - 6), _top + randf_range(1, 5),
			randf_range(-_half + 6, _half - 6))
		scene.add_child(rb)
		_balls.append(rb)


func _physics_process(_d: float) -> void:
	_t += 1
	for rb in _balls:
		var p := rb.position
		var flat := Vector3(p.x, 0, p.z)
		if flat.length() > 0.1:
			rb.apply_central_force(flat.normalized() * 45.0) # gentle -- roll, don't fling
		if p.y < -25.0:
			rb.position = Vector3(randf_range(-_half + 6, _half - 6), _top + 3.0,
				randf_range(-_half + 6, _half - 6))
			rb.linear_velocity = Vector3.ZERO
	if _t % 180 == 0:
		print("PROBE t=%ds fps=%d" % [_t / 60, Engine.get_frames_per_second()])
	if _t == 3600:
		print("PROBE done, no fatal exit")
		get_tree().quit(0)
