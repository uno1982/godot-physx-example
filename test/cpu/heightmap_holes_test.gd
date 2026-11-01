extends SceneTree

# HeightMapShape3D holes (uno1982/godot#20): a NaN height leaves out every
# triangle with that corner, as Jolt does. A 65 x 65 map with a 6 x 6 NaN patch:
# rays down the patch miss and rays 1 m outside it hit, a shape cast and a
# falling rigid capsule and character go through the patch, and bodies beside it
# land. Also a map whose first sample is NaN (HeightMapShape3D then reports NaN
# min/max heights) and a map that is all holes. The expectations are Jolt's
# results; run on any engine:
#   godot --headless --path . --script res://test/cpu/heightmap_holes_test.gd

const SIZE := 65
const PATCH_FROM := 30 # samples 30..35 are NaN on both axes -> cells 29..35 are holed
const PATCH_TO := 35

var _pass := true
var _t := 0
var _shape: HeightMapShape3D
var _rigid_in: RigidBody3D
var _rigid_out: RigidBody3D
var _char_in: CharacterBody3D
var _char_out: CharacterBody3D


func _check(label: String, ok: bool) -> void:
	print("[hm holes] %s %s" % [label, "OK" if ok else "FAIL"])
	_pass = _pass and ok


# Sample (x, z) of a SIZE map sits at x - 32, z - 32.
func _sample_pos(x: float, z: float) -> Vector3:
	return Vector3(x - (SIZE - 1) * 0.5, 0, z - (SIZE - 1) * 0.5)


func _static(shape: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return body


func _capsule() -> CapsuleShape3D:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	return cap


func _rigid(at: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = _capsule()
	b.add_child(cs)
	b.collision_layer = 2 # out of the queries below
	b.position = at
	root.add_child(b)
	return b


func _character(at: Vector3) -> CharacterBody3D:
	var c := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = _capsule()
	c.add_child(cs)
	c.collision_layer = 2
	c.position = at
	root.add_child(c)
	return c


func _ray(from: Vector3) -> Dictionary:
	var sp := root.get_world_3d().direct_space_state
	return sp.intersect_ray(PhysicsRayQueryParameters3D.create(from + Vector3(0, 10, 0), from - Vector3(0, 10, 0), 1))


func _initialize() -> void:
	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	for z in SIZE:
		for x in SIZE:
			var nan := x >= PATCH_FROM and x <= PATCH_TO and z >= PATCH_FROM and z <= PATCH_TO
			heights[z * SIZE + x] = NAN if nan else 0.2 * sin(x * 0.3) * cos(z * 0.2)
	_shape = HeightMapShape3D.new()
	_shape.map_width = SIZE
	_shape.map_depth = SIZE
	_shape.map_data = heights
	_static(_shape)

	# The patch's middle (cells 29..35 are holed: 7 m across, centred on sample 32.5).
	var mid := _sample_pos(32.5, 32.5)
	_rigid_in = _rigid(mid + Vector3(0, 2, 0))
	_rigid_out = _rigid(_sample_pos(20, 20) + Vector3(0, 2, 0))
	_char_in = _character(mid + Vector3(0.6, 2, -0.6))
	_char_out = _character(_sample_pos(45, 20) + Vector3(0, 2, 0))
	physics_frame.connect(_step)


func _step() -> void:
	_t += 1
	if _t == 3:
		# Rays: every point inside the fully holed cells misses, a ring 1 m outside them hits.
		var inside_hits := 0
		var inside := 0
		var outside_hits := 0
		var outside := 0
		for i in 13:
			for j in 13:
				var x := 30.1 + i * 0.4 # 30.1 .. 34.9: cells 30..34, every corner NaN
				var z := 30.2 + j * 0.39
				inside += 1
				if not _ray(_sample_pos(x, z)).is_empty():
					inside_hits += 1
		for i in 28:
			var a := TAU * i / 28.0
			var p := _sample_pos(32.5, 32.5) + Vector3(cos(a), 0, sin(a)) * 5.2 # cells reach 3.5 m from the middle
			outside += 1
			if not _ray(p).is_empty():
				outside_hits += 1
		_check("rays down the hole: %d / %d hit (expected 0)" % [inside_hits, inside], inside_hits == 0)
		_check("rays 1 m outside the hole: %d / %d hit (expected all)" % [outside_hits, outside], outside_hits == outside)

		# A sphere cast down the hole passes through; one beside it stops on the ground.
		var sp := root.get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.5
		q.shape = ball
		q.collision_mask = 1
		q.motion = Vector3(0, -20, 0)
		q.transform = Transform3D(Basis(), _sample_pos(32.5, 32.5) + Vector3(0, 5, 0))
		var free_cast := sp.cast_motion(q)
		_check("sphere cast down the hole: safe fraction %.2f (expected 1)" % free_cast[0], free_cast[0] == 1.0)
		q.transform = Transform3D(Basis(), _sample_pos(20, 45) + Vector3(0, 5, 0))
		var blocked := sp.cast_motion(q)
		_check("sphere cast beside the hole: safe fraction %.2f (expected < 1)" % blocked[0], blocked[0] < 1.0)

	if _t <= 120:
		for c in [_char_in, _char_out]:
			c.velocity.y -= 9.8 / 60.0
			c.move_and_slide()

	if _t == 120:
		_check("rigid capsule over the hole falls through: y %.2f" % _rigid_in.position.y, _rigid_in.position.y < -3.0)
		_check("rigid capsule beside the hole lands: y %.2f" % _rigid_out.position.y, _rigid_out.position.y > 0.5 and _rigid_out.position.y < 1.5)
		_check("character over the hole falls through: y %.2f" % _char_in.position.y, _char_in.position.y < -3.0)
		_check("character beside the hole lands: y %.2f, on floor %s" % [_char_out.position.y, _char_out.is_on_floor()], _char_out.is_on_floor() and _char_out.position.y > 0.5)

		# First sample NaN: HeightMapShape3D reports NaN min/max heights; the rest of the map must still collide.
		var first := HeightMapShape3D.new()
		first.map_width = 9
		first.map_depth = 9
		var h := PackedFloat32Array()
		h.resize(81)
		h.fill(0.0)
		h[0] = NAN
		first.map_data = h
		var body := _static(first)
		body.position = Vector3(100, 0, 0)
		# All holes: nothing to hit, no errors.
		var none := HeightMapShape3D.new()
		none.map_width = 4
		none.map_depth = 4
		var n := PackedFloat32Array()
		n.resize(16)
		n.fill(NAN)
		none.map_data = n
		var body2 := _static(none)
		body2.position = Vector3(200, 0, 0)

	if _t == 123:
		# A point in each half of every cell: (0.25, 0.25) is in the half with the cell's first corner, (0.75, 0.75)
		# in the other. Only the corner cell's first half touches the NaN sample.
		var hits := 0
		for i in 8:
			for j in 8:
				for f in [0.25, 0.75]:
					var r := _ray(Vector3(100 - 4 + i + f, 0, -4 + j + f))
					if not r.is_empty() and absf(r.position.y) < 0.01:
						hits += 1
		_check("first sample NaN: %d / 128 half-cells hit at y = 0 (expected 127)" % hits, hits == 127)
		_check("all holes: a ray misses", _ray(Vector3(200, 0, 0)).is_empty())
		print("[hm holes] %s" % ("PASS" if _pass else "FAIL"))
		quit(0 if _pass else 1)
