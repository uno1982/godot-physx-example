extends SceneTree

# HeightMapShape3D on the PhysX backend (PxHeightField). A 17x17 map with a
# central bump; a ball dropped over the peak should come to rest on the raised
# surface, one over a flat corner should rest near y=0, and neither should fall
# through or float.

var _ball_peak: RigidBody3D
var _ball_flat: RigidBody3D
var _terrain: StaticBody3D
var _t := 0
var _peak_h := 3.0

func _make_ball(pos: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.4
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	return rb

func _initialize() -> void:
	print("[hmap] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var w := 17
	var heights := PackedFloat32Array()
	heights.resize(w * w)
	var mid := (w - 1) * 0.5
	for z in w:
		for x in w:
			# radial cosine bump, 0 at the edge, _peak_h at the centre.
			var d := Vector2(x - mid, z - mid).length() / mid
			var h := 0.0
			if d < 1.0:
				h = _peak_h * 0.5 * (1.0 + cos(d * PI))
			heights[z * w + x] = h

	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = heights

	var terrain := StaticBody3D.new()
	var tcs := CollisionShape3D.new()
	tcs.shape = shape
	terrain.add_child(tcs)
	root.add_child(terrain)

	_ball_peak = _make_ball(Vector3(0, 8, 0)) # straight over the peak
	_ball_flat = _make_ball(Vector3(6.5, 8, 6.5)) # near a corner (flat)
	root.add_child(_ball_peak)
	root.add_child(_ball_flat)

	get_root().add_child(root)
	_terrain = terrain

func _physics_process(_d: float) -> bool:
	_t += 1

	if _t == 2:
		# Scene query against the height field: a ray straight down near the peak
		# (offset from the falling balls) should hit near the peak height.
		var ss := get_root().world_3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(Vector3(1.5, 20, 0), Vector3(1.5, -20, 0))
		q.exclude = [_ball_peak.get_rid(), _ball_flat.get_rid()]
		var hit := ss.intersect_ray(q)
		if hit.is_empty():
			print("[hmap] FAIL: ray down over the peak missed the terrain entirely")
			quit(1)
			return true
		# x=1.5 is close to the peak; the cosine bump there is still ~2.7 m.
		if hit.position.y < 2.0 or hit.position.y > _peak_h + 0.2:
			print("[hmap] FAIL: ray hit terrain at y=%.2f near the peak, expected ~2.7" % hit.position.y)
			quit(1)
			return true
	var yp := _ball_peak.global_position.y
	var yf := _ball_flat.global_position.y

	if yp < -3.0 or yf < -3.0:
		print("[hmap] FAIL: a ball fell through the terrain (peak y=%.2f flat y=%.2f)" % [yp, yf])
		quit(1)
		return true

	if _t >= 300:
		# radius 0.4: resting on the ~3 m peak -> centre near 3.4; on the flat
		# edge -> near 0.4.
		var peak_ok := absf(yp - (_peak_h + 0.4)) < 0.6
		var flat_ok := absf(yf - 0.4) < 0.5
		if not peak_ok:
			print("[hmap] FAIL: peak ball rest y=%.2f, expected ~%.2f (bump not there?)" % [yp, _peak_h + 0.4])
			quit(1)
		elif not flat_ok:
			print("[hmap] FAIL: flat ball rest y=%.2f, expected ~0.4" % yf)
			quit(1)
		else:
			print("[hmap] PASS  (peak ball rests at y=%.2f on the %.0f m bump; flat ball at y=%.2f)" % [yp, _peak_h, yf])
			quit(0)
		return true
	return false
