extends SceneTree

# uno1982/godot#34: an area's shapes are PhysX triggers only while something uses them (a body monitor, a gravity /
# damping / wind override); otherwise they're query-only and cost the step nothing. What must still hold:
#   a passive area (monitoring off) makes no trigger pairs (step stats), but is still hit by intersect_ray /
#     intersect_shape with collide_with_areas (and not without), and a CharacterBody3D walks through it;
#   turning monitoring on reports the body already inside it (body_entered), off and on again reports it again;
#   a gravity override works with monitoring off, also when switched on at runtime (from the step after: the area's
#     trigger pairs are found during the step it's switched on in), and stops when switched off;
#   a monitoring area still sees a passive one (area_entered: area-area overlaps are polled, not triggers).

var _ok := true
var _t := 0
var _space: RID
var _passive: Area3D
var _gravity_area: Area3D
var _late_area: Area3D
var _watcher: Area3D
var _floater: RigidBody3D
var _late_box: RigidBody3D
var _inside_box: RigidBody3D
var _character: CharacterBody3D
var _entered := 0
var _area_entered := 0
var _late_y0 := 0.0


func _check(cond: bool, msg: String) -> void:
	print("[passive_area] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _shape(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	return cs


func _area(pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.monitoring = false
	a.monitorable = true
	a.position = pos
	a.add_child(_shape(size))
	get_root().add_child(a)
	return a


func _box(pos: Vector3, gravity := true) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.position = pos
	b.can_sleep = false
	b.gravity_scale = 1.0 if gravity else 0.0
	b.add_child(_shape(Vector3(0.5, 0.5, 0.5)))
	get_root().add_child(b)
	return b


func _initialize() -> void:
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "?")
	print("[passive_area] engine = ", engine)
	if engine != "PhysX":
		print("SKIP: not running on PhysX")
		quit(0)
		return

	var floor_body := StaticBody3D.new()
	floor_body.add_child(_shape(Vector3(60, 1, 60)))
	floor_body.position.y = -0.5
	get_root().add_child(floor_body)

	# A passive area with a box resting inside it.
	_passive = _area(Vector3(0, 1, 0), Vector3(3, 2, 3))
	_inside_box = _box(Vector3(0, 0.25, 0))
	_passive.body_entered.connect(func(b: Node3D) -> void:
		if b == _inside_box:
			_entered += 1)

	# Gravity override, monitoring off: a box inside floats up.
	_gravity_area = _area(Vector3(10, 3, 0), Vector3(3, 6, 3))
	_gravity_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	_gravity_area.gravity_direction = Vector3.UP
	_gravity_area.gravity = 9.8
	_floater = _box(Vector3(10, 0.25, 0))

	# A passive area that gets its override later.
	_late_area = _area(Vector3(-10, 3, 0), Vector3(3, 6, 3))
	_late_box = _box(Vector3(-10, 3, 0), true)
	_late_box.gravity_scale = 0.0 # held still until the override comes on

	# A monitoring area overlapping the passive one.
	_watcher = Area3D.new()
	_watcher.monitoring = true
	_watcher.position = Vector3(1.5, 1, 0)
	_watcher.add_child(_shape(Vector3(1, 1, 1)))
	get_root().add_child(_watcher)
	_watcher.area_entered.connect(func(a: Area3D) -> void:
		if a == _passive:
			_area_entered += 1)

	# A character walking through the passive area (x 20 -> 26, the area at 23).
	_area(Vector3(23, 1, 0), Vector3(2, 2, 2))
	_character = CharacterBody3D.new()
	var ccs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	ccs.shape = cap
	_character.add_child(ccs)
	_character.position = Vector3(20, 0.85, 0)
	get_root().add_child(_character)

	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t == 1:
		_space = _passive.get_world_3d().space
	_character.velocity = Vector3(3, 0, 0)
	if _t <= 120:
		_character.move_and_slide()

	if _t == 30:
		var s: Dictionary = PhysX.space_get_step_stats(_space)
		_check(int(s.trigger_pairs) == 1, "only the gravity area's pair is a trigger pair (%d)" % s.trigger_pairs)
		_check(_entered == 0, "monitoring off: no body_entered (%d)" % _entered)
		_check(_area_entered == 1, "a monitoring area sees the passive one (area_entered %d)" % _area_entered)

		var dss := _passive.get_world_3d().direct_space_state
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, 1.5, 0))
		ray.collide_with_areas = true
		var hit := dss.intersect_ray(ray)
		_check(hit.get("collider") == _passive, "intersect_ray with collide_with_areas hits the passive area (%s)" % hit.get("collider"))
		ray.collide_with_areas = false
		_check(dss.intersect_ray(ray).is_empty(), "without collide_with_areas it doesn't")
		var q := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.2
		q.shape = sph
		q.transform = Transform3D(Basis(), Vector3(1.2, 1.8, 1.2))
		q.collide_with_areas = true
		var found := dss.intersect_shape(q)
		_check(found.size() == 1 and found[0].collider == _passive, "intersect_shape finds the passive area (%d hits)" % found.size())

		_passive.monitoring = true
	if _t == 34:
		_check(_entered == 1, "monitoring on: the body already inside enters (%d)" % _entered)
		_passive.monitoring = false
	if _t == 36:
		_passive.monitoring = true
	if _t == 40:
		_check(_entered == 2, "off and on again: it enters again (%d)" % _entered)

	if _t == 60:
		_check(_floater.position.y > 2.0, "gravity override with monitoring off lifts the box (y %.2f)" % _floater.position.y)
		_late_box.gravity_scale = 1.0
		_late_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
		_late_area.gravity_direction = Vector3.UP
		_late_area.gravity = 9.8
		_late_y0 = _late_box.position.y
	if _t == 80:
		_check(_late_box.position.y > _late_y0 + 0.35, "an override switched on at runtime lifts its box (a step late: its trigger pairs come with that step) (%.2f -> %.2f)" % [_late_y0, _late_box.position.y])
		_late_area.gravity_space_override = Area3D.SPACE_OVERRIDE_DISABLED
		_late_box.linear_velocity = Vector3.ZERO
		_late_y0 = _late_box.position.y
	if _t == 100:
		_check(_late_box.position.y < _late_y0 - 0.3, "switched off, the box falls again (%.2f -> %.2f)" % [_late_y0, _late_box.position.y])
	if _t == 121:
		_check(_character.position.x > 25.5, "a character walks through a passive area (x %.2f)" % _character.position.x)
		quit(0 if _ok else 1)
