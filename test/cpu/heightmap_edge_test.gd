extends SceneTree

# Regression for the PhysX 5 GPU-narrowphase illegal-address crash: rigid
# bodies rolling off the edge of a HeightMapShape3D. Balls spawn resting on
# the REAL terrain surface -- found via an actual downward raycast against
# the real collision shape, not a re-derived noise sample -- right at the
# rim, then roll off under a gentle push. A catch floor below confirms they
# actually left the terrain; the first ball to confirm BOTH contacts
# (terrain, then the floor) passes the test -- a real, fast, event-driven
# check instead of an arbitrary fixed wait.

var _scene: Node3D
var _t := 0
var _terrain: StaticBody3D
var _floor_body: StaticBody3D
var _hit_terrain: Dictionary = {} # RigidBody3D -> true
var _hit_floor: Dictionary = {} # RigidBody3D -> true
var _balls: Array[RigidBody3D] = []

func _initialize() -> void:
	_scene = load("res://demo/editor/cpu/heightmap.tscn").instantiate()
	get_root().add_child(_scene)
	await process_frame
	var grid: int = _scene.grid
	var rim := (grid - 1) * 0.5
	var spawn_r := rim - 0.6 # just inside the rim, not near the peak

	_terrain = _scene.get_node("Terrain")
	# Strip the demo's own script: heightmap.gd has a fully live WASD/mouse
	# character controller and its own unrelated "B spawns balls on the
	# slope" feature -- left attached, watching this test run was actually
	# watching that live interactive demo, not this test (confirmed: the HUD
	# text and free camera control were both heightmap.gd's, gone once this
	# is stripped).
	_scene.set_script(null)

	var floor_y := -15.0
	_floor_body = StaticBody3D.new()
	var floor_cs := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(400, 1, 400)
	floor_cs.shape = floor_shape
	_floor_body.add_child(floor_cs)
	var floor_mi := MeshInstance3D.new()
	var floor_bm := BoxMesh.new()
	floor_bm.size = floor_shape.size
	floor_mi.mesh = floor_bm
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.2, 0.2)
	floor_mi.material_override = floor_mat
	_floor_body.add_child(floor_mi)
	_floor_body.position = Vector3(0, floor_y, 0)
	_scene.add_child(_floor_body)

	var space := get_root().world_3d.direct_space_state
	for i in 24:
		var ang := TAU * i / 24.0
		var x := cos(ang) * spawn_r
		var z := sin(ang) * spawn_r
		# Real raycast against the actual collision surface -- exactly what
		# the terrain's own PxHeightField will report contact at, not a
		# separate re-derived noise sample that could quietly disagree with it.
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -50.0, z))
		var hit := space.intersect_ray(q)
		var surface_y: float = hit.position.y if not hit.is_empty() else 0.0

		var rb := RigidBody3D.new()
		rb.mass = 3.0
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.4
		cs.shape = s
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		mi.mesh = sm
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = Color.from_hsv(float(i) / 24.0, 0.8, 1.0)
		mmat.emission_enabled = true
		mmat.emission = mmat.albedo_color * 0.6
		mi.material_override = mmat
		rb.add_child(mi)
		# Resting on the real surface + a tiny buffer so it settles under
		# real contact, not floating -- and a gentle (not launched) outward
		# push so it actually rolls across the rim in contact the whole way.
		rb.position = Vector3(x, surface_y + 0.45, z)
		rb.linear_velocity = Vector3(cos(ang), 0, sin(ang)) * 1.5
		_scene.add_child(rb)
		_balls.append(rb)
		rb.body_entered.connect(_on_ball_hit.bind(rb))

	# Real overhead camera, looking straight down at the whole ring -- no
	# look_at ambiguity (a straight-down look direction needs an up vector
	# that isn't parallel to it), just a direct -90 degree pitch.
	var cam := Camera3D.new()
	cam.position = Vector3(0, rim * 1.8, 0)
	cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_scene.add_child(cam)
	cam.current = true

	print("[hmap-edge] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("[hmap-edge] grid=%d, rim=%.1f, spawn_radius=%.1f, floor_y=%.1f" % [grid, rim, spawn_r, floor_y])
	physics_frame.connect(_tick)


func _on_ball_hit(other: Node, ball: RigidBody3D) -> void:
	if other == _terrain:
		_hit_terrain[ball] = true
	elif other == _floor_body:
		_hit_floor[ball] = true


func _tick() -> void:
	_t += 1
	for b in _balls:
		if is_instance_valid(b) and is_nan(b.position.x):
			print("[hmap-edge] FAIL: ball position went NaN at t+%d" % _t)
			quit(1)
			return

	var confirmed := 0
	for b in _balls:
		if _hit_terrain.get(b, false) and _hit_floor.get(b, false):
			confirmed += 1

	if _t % 60 == 0:
		print("[hmap-edge] t+%d (%.1fs) confirmed(terrain+floor)=%d/24  terrain_only=%d  floor_only=%d" % [
			_t, _t / 60.0, confirmed, _hit_terrain.size() - confirmed, _hit_floor.size() - confirmed])

	if confirmed >= 1:
		print("[hmap-edge] PASS  at least one ball confirmed contact with the terrain, then the floor below it, at t+%d (%.1fs) -- rolled off the edge for real, no GPU narrowphase fault" % [_t, _t / 60.0])
		quit(0)
		return

	if _t >= 900: # 15s safety cap
		print("[hmap-edge] FAIL: no ball confirmed both contacts after 15s (terrain hit=%d, floor hit=%d)" % [_hit_terrain.size(), _hit_floor.size()])
		quit(1)
