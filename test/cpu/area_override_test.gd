extends SceneTree

# Verifies Area3D space overrides on the PhysX backend:
#   - wind pushes a light body sideways
#   - point gravity pulls a body toward the area origin (against world gravity)
#   - high linear damp inside an area arrests a moving body

var _wind_body: RigidBody3D
var _grav_body: RigidBody3D
var _damp_body: RigidBody3D
var _damp_speed_in := 0.0
var _tick := 0

func _initialize() -> void:
	print("[ovr] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	# --- wind ---------------------------------------------------------------
	var wind := Area3D.new()
	wind.gravity_space_override = Area3D.SPACE_OVERRIDE_DISABLED
	var wc := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(20, 20, 20)
	wc.shape = wbox
	wind.add_child(wc)
	wind.position = Vector3(0, 10, 0)
	wind.wind_force_magnitude = 60.0
	root.add_child(wind)
	# Wind blows along the source node's -Z; rotate it so that points along +X.
	var wsrc := Marker3D.new()
	wsrc.rotation_degrees = Vector3(0, -90, 0)
	wind.add_child(wsrc)
	wind.wind_source_path = wind.get_path_to(wsrc)

	_wind_body = _mk_body(root, Vector3(0, 10, 0), 0.2)
	_wind_body.gravity_scale = 0.0

	# --- point gravity -----------------------------------------------------
	var gwell := Area3D.new()
	gwell.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	gwell.gravity_point = true
	gwell.gravity = 25.0
	gwell.gravity_point_unit_distance = 0.0
	var gc := CollisionShape3D.new()
	var gsph := SphereShape3D.new()
	gsph.radius = 12.0
	gc.shape = gsph
	gwell.add_child(gc)
	gwell.position = Vector3(40, 10, 0)
	root.add_child(gwell)

	_grav_body = _mk_body(root, Vector3(40, 4, 0), 1.0) # below the well centre

	# --- linear damp -----------------------------------------------------
	var thick := Area3D.new()
	thick.linear_damp_space_override = Area3D.SPACE_OVERRIDE_COMBINE
	thick.linear_damp = 8.0
	thick.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	thick.gravity = 0.0
	var tc := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(30, 30, 30)
	tc.shape = tbox
	thick.add_child(tc)
	thick.position = Vector3(-40, 10, 0)
	root.add_child(thick)

	_damp_body = _mk_body(root, Vector3(-40, 10, 0), 1.0)
	_damp_body.gravity_scale = 0.0
	_damp_body.linear_velocity = Vector3(20, 0, 0)

func _mk_body(root: Node3D, pos: Vector3, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	var c := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	c.shape = s
	b.add_child(c)
	b.position = pos
	b.mass = mass
	b.can_sleep = false
	root.add_child(b)
	return b

func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 2:
		_damp_speed_in = _damp_body.linear_velocity.length()
	if _tick >= 90:
		var wind_dx := _wind_body.global_position.x
		var grav_dy := _grav_body.global_position.y - 4.0
		var damp_speed := _damp_body.linear_velocity.length()
		var ok_wind := wind_dx > 2.0
		var ok_grav := grav_dy > 1.0 # pulled up toward the well centre at y=10
		var ok_damp := damp_speed < _damp_speed_in * 0.5
		print("[ovr] wind dx=%.2f (%s)" % [wind_dx, "ok" if ok_wind else "BAD"])
		print("[ovr] point-grav dy=%.2f (%s)" % [grav_dy, "ok" if ok_grav else "BAD"])
		print("[ovr] damp %.2f -> %.2f (%s)" % [_damp_speed_in, damp_speed, "ok" if ok_damp else "BAD"])
		var ok := ok_wind and ok_grav and ok_damp
		print("[ovr] ", "PASS" if ok else "FAIL")
		quit(0 if ok else 1)
	return false
