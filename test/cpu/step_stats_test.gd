extends SceneTree

# uno1982/godot#36: PhysX.space_get_step_stats() -- what the last step of a space cost, by stage, and what it did.
# A floor, a column of boxes falling onto it, a hinged pair kept awake, an area:
#   every key is there; the stage times add up to step_usec exactly;
#   actors added minus removed, summed over the steps, is the number of actors in the space, also after five boxes
#     are freed (and the removal shows up as five more removed);
#   PhysX's own counts: the dynamic bodies, the floor as a static, the area (a kinematic actor), the hinge as an
#     active constraint, pairs found in the broad phase, touches as the boxes land, contact pairs once they rest
#     (CPU dynamics only: on the GPU the narrow phase doesn't count them);
#   a stats read every step sees every step (each read sees the step before it).

const BOXES := 20
const KEYS := ["step_usec", "pre_solve_usec", "area_overrides_usec", "area_overlaps_usec", "simulate_usec",
		"fetch_results_usec", "sync_back_usec", "callbacks_usec", "actors_added", "actors_removed", "synced_bodies",
		"bodies", "areas", "active_dynamic_bodies", "active_kinematic_bodies", "dynamic_bodies", "kinematic_bodies",
		"static_bodies", "active_constraints", "aggregates", "broadphase_adds", "broadphase_removes", "contact_pairs",
		"contact_pairs_cache_hits", "contact_pairs_touching", "new_pairs", "lost_pairs", "new_touches",
		"lost_touches", "trigger_pairs", "solver_partitions", "axis_solver_constraints", "gpu_dynamics"]
const STAGES := ["pre_solve_usec", "area_overrides_usec", "area_overlaps_usec", "simulate_usec",
		"fetch_results_usec", "sync_back_usec"]

var _ok := true
var _t := 0
var _space: RID
var _boxes: Array[RigidBody3D] = []
var _net_actors := 0
var _removed_after_free := 0
var _new_pairs := 0
var _steps_seen := 0
var _stages_add_up := true
var _max_contact_pairs := 0
var _max_constraints := 0
var _new_touches := 0


func _check(cond: bool, msg: String) -> void:
	print("[step_stats] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box_shape(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	return cs


func _body(pos: Vector3, awake := false) -> RigidBody3D:
	var box := RigidBody3D.new()
	box.position = pos
	box.can_sleep = not awake
	box.add_child(_box_shape(Vector3.ONE))
	get_root().add_child(box)
	return box


func _initialize() -> void:
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "?")
	print("[step_stats] engine = ", engine)
	if engine != "PhysX":
		print("SKIP: not running on PhysX")
		quit(0)
		return

	var floor_body := StaticBody3D.new()
	floor_body.add_child(_box_shape(Vector3(40, 1, 40)))
	floor_body.position = Vector3(0, -0.5, 0)
	get_root().add_child(floor_body)

	for i in BOXES:
		_boxes.append(_body(Vector3((i % 5) * 1.5 - 3.0, 0.6 + (i / 5) * 1.1, 0)))

	# A hinged pair in the air, gravity off and kept awake: an active constraint on every step.
	var a := _body(Vector3(10, 5, 0), true)
	var b := _body(Vector3(11.2, 5, 0), true)
	a.gravity_scale = 0.0
	b.gravity_scale = 0.0
	var hinge := HingeJoint3D.new()
	hinge.position = Vector3(10.6, 5, 0)
	get_root().add_child(hinge)
	hinge.node_a = hinge.get_path_to(a)
	hinge.node_b = hinge.get_path_to(b)

	var area := Area3D.new()
	area.add_child(_box_shape(Vector3(2, 2, 2)))
	area.position = Vector3(-10, 1, 0)
	get_root().add_child(area)

	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t == 1:
		_space = _boxes[0].get_world_3d().space # (not in the world yet during _initialize)
	var s: Dictionary = PhysX.space_get_step_stats(_space)
	if _t == 1:
		var missing := []
		for k in KEYS:
			if not s.has(k):
				missing.append(k)
		_check(missing.is_empty(), "every key is in the dictionary (missing %s)" % [missing])
		_check(PhysX.space_get_step_stats(RID()).is_empty(), "an invalid space RID gives an empty dictionary")
	if s.get("step_usec", 0) > 0:
		_steps_seen += 1
		var total := 0
		for k in STAGES:
			total += int(s[k])
		_stages_add_up = _stages_add_up and total == int(s.step_usec)
	_net_actors += int(s.get("actors_added", 0)) - int(s.get("actors_removed", 0))
	_new_pairs += int(s.get("new_pairs", 0))
	_new_touches += int(s.get("new_touches", 0))
	_max_contact_pairs = maxi(_max_contact_pairs, int(s.get("contact_pairs", 0)))
	_max_constraints = maxi(_max_constraints, int(s.get("active_constraints", 0)))
	if _t > 60: # (the frees at tick 60 are done before that frame's step)
		_removed_after_free += int(s.get("actors_removed", 0))

	if _t == 60:
		var actors := BOXES + 2 + 1 + 1 # boxes, hinged pair, floor, area
		_check(_net_actors == actors, "actors added - removed over the steps = %d actors (got %d)" % [actors, _net_actors])
		_check(int(s.bodies) == BOXES + 3 and int(s.areas) == 1, "bodies %d (want %d), areas %d (want 1)" % [s.bodies, BOXES + 3, s.areas])
		_check(int(s.dynamic_bodies) == BOXES + 2, "PhysX dynamic bodies %d (want %d)" % [s.dynamic_bodies, BOXES + 2])
		_check(int(s.static_bodies) >= 1, "the floor counted as a static (%d)" % s.static_bodies)
		_check(int(s.kinematic_bodies) >= 1, "the area counted as a kinematic actor (%d)" % s.kinematic_bodies)
		_check(_max_constraints >= 1, "the hinge is an active constraint (max %d)" % _max_constraints)
		_check(_new_pairs > 0, "broad-phase pairs found (%d)" % _new_pairs)
		_check(_new_touches >= 5, "new touches as boxes land (%d)" % _new_touches)
		# On GPU dynamics the narrow phase runs on the device: its contact pair counts stay 0.
		if s.gpu_dynamics:
			print("[step_stats] GPU dynamics: contact pairs (CPU narrow phase only) max %d" % _max_contact_pairs)
		else:
			_check(_max_contact_pairs >= 5, "contact pairs once boxes rest on the floor (max %d)" % _max_contact_pairs)
		_check(_stages_add_up, "the stage times add up to step_usec on every step")
		_check(_steps_seen >= 58, "a read every step sees a step every time (%d of 59)" % _steps_seen)
		for i in 5:
			_boxes[i].queue_free()
	if _t == 70:
		_check(_removed_after_free >= 5, "freeing five boxes counts five actors removed (%d)" % _removed_after_free)
		var actors := BOXES - 5 + 2 + 1 + 1
		_check(_net_actors == actors, "actors added - removed after the frees = %d (got %d)" % [actors, _net_actors])
		print("[step_stats] last step: ", s)
		quit(0 if _ok else 1)
