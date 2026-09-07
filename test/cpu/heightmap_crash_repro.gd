extends SceneTree

# Definitive repro attempt for the CUDA-700 GPU-narrowphase crash on
# HeightMapShape3D. Verifies the balls actually (a) collide with the height
# field and (b) roll off the rim while still straddling it, then runs long.

var _t := 0
var _balls: Array[RigidBody3D] = []
var _half := 0.0
var _top := 0.0
var _space: RID
var _saw_hf_contact := false
var _saw_edge_straddle := false
var _crossed := 0


func _initialize() -> void:
	print("[hmap-crash] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	var scene: Node3D = load("res://demo/editor/cpu/heightmap.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame
	var grid: int = scene.grid
	_half = (grid - 1) * 0.5
	_top = scene.height
	var terrain: StaticBody3D = scene.get_node("Terrain")
	_space = terrain.get_world_3d().space
	print("  grid=%d half=%.1f  terrain shape type=%d" % [grid, _half,
		PhysicsServer3D.shape_get_type(PhysicsServer3D.body_get_shape(terrain.get_rid(), 0))])

	for i in 24:
		var rb := RigidBody3D.new()
		rb.mass = 2.0
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.5
		cs.shape = s
		rb.add_child(cs)
		rb.position = Vector3(randf_range(-_half + 5, _half - 5), _top + randf_range(2, 8),
			randf_range(-_half + 5, _half - 5))
		scene.add_child(rb)
		_balls.append(rb)

	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	for rb in _balls:
		var p := rb.position
		# push outward so it heads for the nearest edge
		var flat := Vector3(p.x, 0, p.z)
		if flat.length() > 0.1:
			rb.apply_central_force(flat.normalized() * 120.0)
		# still touching the height field?
		if rb.get_contact_count() > 0 and abs(p.x) < _half and abs(p.z) < _half and p.y < _top + 1.0:
			_saw_hf_contact = true
		# straddling: partly past the rim (radius 0.5) but not fallen away yet
		var edge_d: float = min(_half - abs(p.x), _half - abs(p.z))
		if edge_d < 0.5 and edge_d > -0.5 and p.y > _top - 4.0:
			_saw_edge_straddle = true
		# fully crossed and falling
		if (abs(p.x) > _half + 1.0 or abs(p.z) > _half + 1.0) and p.y < _top:
			_crossed += 1
			rb.position = Vector3(randf_range(-_half + 5, _half - 5), _top + randf_range(2, 8),
				randf_range(-_half + 5, _half - 5))
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO

	if _t % 300 == 0:
		print("  %ds  hf_contact=%s  straddle=%s  rim_crossings=%d" % [
			_t / 60, _saw_hf_contact, _saw_edge_straddle, _crossed])
	if _t == 9000: # 150 s
		var ok := _saw_hf_contact and _saw_edge_straddle and _crossed > 20
		if ok:
			print("[hmap-crash] PASS  %d rim crossings, verified HF contact + straddle, no fault in 150 s" % _crossed)
			quit(0)
		else:
			printerr("[hmap-crash] INCONCLUSIVE  hf_contact=%s straddle=%s crossings=%d -- balls never exercised the edge" % [
				_saw_hf_contact, _saw_edge_straddle, _crossed])
			quit(2)
