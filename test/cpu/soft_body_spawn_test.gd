extends SceneTree

# Regression: a SoftBody3D must stay at its authored position and fall from
# there -- never teleport to the world origin or get flung up out of the floor
# on the first frames (the node delivers its transform in a separate call from
# its mesh, and simulating from the mesh-local rest pose drops it through the
# floor).

var _sb: SoftBody3D
var _tick := 0
var _spawn := Vector3(5, 3, 0)
var _max_y := -1e9
var _min_y := 1e9
var _max_xz_dev := 0.0
var _first_center := Vector3.INF
var _settled_center := Vector3.INF
var _settle_drift := 0.0
var _fail := ""

func _initialize() -> void:
	print("[sbspawn] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(40, 1, 40)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	# A box: flat bottom contact is where a settled soft body is most prone to
	# a slow parasitic spin/creep.
	_sb = SoftBody3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.2, 1.2, 1.2)
	m.subdivide_width = 4
	m.subdivide_height = 4
	m.subdivide_depth = 4
	_sb.mesh = m
	_sb.total_mass = 2.5
	_sb.simulation_precision = 12
	_sb.pressure_coefficient = 50.0
	_sb.linear_stiffness = 0.9
	_sb.ray_pickable = false
	_sb.position = _spawn
	root.add_child(_sb)

	get_root().add_child(root)

func _physics_process(_d: float) -> bool:
	_tick += 1
	# Mid-fall, mimic the node re-sending its transform as identity after going
	# top-level -- must be ignored, not treated as a teleport to the origin.
	if _tick == 20:
		PhysicsServer3D.soft_body_set_transform(_sb.get_physics_rid(), Transform3D())
	var b := PhysicsServer3D.soft_body_get_bounds(_sb.get_physics_rid())
	var c := b.get_center()
	if not is_finite(c.x) or not is_finite(c.y) or not is_finite(c.z):
		print("[sbspawn] FAIL: non-finite center at tick %d" % _tick)
		quit(1)
		return true

	# Ignore the very first couple of ticks: bounds may briefly read the
	# pre-placement rest pose before the node delivers the transform.
	if _tick <= 3:
		return false
	if _first_center == Vector3.INF:
		_first_center = c
		if c.distance_to(_spawn) > 1.0:
			_fail = "spawned at %s, not near %s" % [c, _spawn]

	_max_y = maxf(_max_y, c.y)
	_min_y = minf(_min_y, c.y)
	var xz_dev := Vector2(c.x - _spawn.x, c.z - _spawn.z).length()
	_max_xz_dev = maxf(_max_xz_dev, xz_dev)

	# Once it has settled (tick 200+), it must stay put -- no slow spin/creep
	# across a flat contact.
	if _tick == 220:
		_settled_center = c
	if _tick > 220 and _settled_center != Vector3.INF:
		_settle_drift = maxf(_settle_drift, c.distance_to(_settled_center))

	# It must never rise more than a hair above where it started (no fling), and
	# never wander far in X/Z (no teleport to origin then slide back).
	if _fail == "" and c.y > _spawn.y + 0.3:
		_fail = "flung UP to y=%.2f (spawn y=%.2f) at tick %d" % [c.y, _spawn.y, _tick]
	if _fail == "" and _max_xz_dev > 1.0:
		_fail = "drifted %.2f m in X/Z from spawn (tick %d, center=%s)" % [_max_xz_dev, _tick, c]

	if _fail != "":
		print("[sbspawn] FAIL: " + _fail)
		quit(1)
		return true

	if _tick >= 320:
		# Should have fallen and be resting on the floor near its spawn X/Z.
		if _min_y > 1.5:
			print("[sbspawn] FAIL: never fell (min center y = %.2f)" % _min_y)
			quit(1)
		elif b.position.y < -0.7:
			print("[sbspawn] FAIL: sank through the floor (bottom y = %.2f)" % b.position.y)
			quit(1)
		elif _settle_drift > 0.15:
			print("[sbspawn] FAIL: settled body keeps drifting/spinning (%.3f m over ~1.7 s)" % _settle_drift)
			quit(1)
		else:
			print("[sbspawn] PASS  (spawned %s, max_y=%.2f min_y=%.2f xz_dev=%.2f, rest y=%.2f, settle_drift=%.3f)" % [
				_first_center, _max_y, _min_y, _max_xz_dev, b.position.y, _settle_drift])
			quit(0)
		return true
	return false
