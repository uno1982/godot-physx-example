extends SceneTree

# Space queries' collide_with_bodies / collide_with_areas -- rays, points,
# shapes, casts, rest info and a RayCast3D node. The expectations are Jolt's
# results; run on any engine:
#   godot --headless --path . --script res://test/cpu/query_filter_test.gd
#
# Along +Z from the origin: area A (z 3..5), body B (z 7..9), body C
# (z 11..13), area D (z 15..17).
#
# Mouse picking (input_ray_pickable) isn't covered: a --script run never gets
# a synthesized mouse event to an Area3D's input_event, on any engine.
# demo/editor/cpu/picking.tscn checks it by hand.

var _tick := 0
var _pass := true
var _nodes := {}
var _raycast: RayCast3D


func _initialize() -> void:
	print("[query] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)
	_add(root, "A", Area3D.new(), Vector3(0, 0, 4))
	_add(root, "B", StaticBody3D.new(), Vector3(0, 0, 8))
	_add(root, "C", StaticBody3D.new(), Vector3(0, 0, 12))
	_add(root, "D", Area3D.new(), Vector3(0, 0, 16))

	_raycast = RayCast3D.new()
	_raycast.target_position = Vector3(0, 0, 20)
	_raycast.collide_with_areas = true
	root.add_child(_raycast)


func _add(root: Node, n: String, obj: CollisionObject3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	cs.shape = box
	obj.add_child(cs)
	obj.position = pos
	obj.name = n
	root.add_child(obj)
	_nodes[n] = obj


func _name_of(rid: RID) -> String:
	for n in _nodes:
		if _nodes[n].get_rid() == rid:
			return n
	return "-" if not rid.is_valid() else "?"


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, bodies: bool, areas: bool) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0, 20))
	q.collide_with_bodies = bodies
	q.collide_with_areas = areas
	var r := space.intersect_ray(q)
	return "-" if r.is_empty() else _name_of(r.rid)


func _names(results: Array) -> String:
	var names: Array[String] = []
	for r in results:
		names.append(_name_of(r.rid))
	names.sort()
	return ",".join(names) if not names.is_empty() else "-"


func _check(label: String, got: String, want: String) -> void:
	var ok := got == want
	print("  [%s] %-58s got %-6s want %s" % ["ok" if ok else "FAIL", label, got, want])
	if not ok:
		_pass = false


func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick == 3:
		var space := get_root().world_3d.direct_space_state
		_check("ray, bodies only (default)", _ray(space, Vector3.ZERO, true, false), "B")
		_check("ray, bodies + areas", _ray(space, Vector3.ZERO, true, true), "A")
		_check("ray, areas only", _ray(space, Vector3.ZERO, false, true), "A")
		_check("ray, areas only, starting past A", _ray(space, Vector3(0, 0, 6), false, true), "D")
		_check("ray, neither", _ray(space, Vector3.ZERO, false, false), "-")

		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = Vector3(0, 0, 4)
		_check("point inside A, bodies only", _names(space.intersect_point(pq)), "-")
		pq.collide_with_areas = true
		_check("point inside A, + areas", _names(space.intersect_point(pq)), "A")

		var sphere := SphereShape3D.new()
		sphere.radius = 1.2
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = sphere
		sq.transform = Transform3D(Basis(), Vector3(0, 0, 6)) # touches A and B
		_check("shape over A and B, bodies only", _names(space.intersect_shape(sq)), "B")
		sq.collide_with_areas = true
		_check("shape over A and B, + areas", _names(space.intersect_shape(sq)), "A,B")
		sq.collide_with_bodies = false
		_check("shape over A and B, areas only", _names(space.intersect_shape(sq)), "A")

		var small := SphereShape3D.new()
		small.radius = 0.3
		var cq := PhysicsShapeQueryParameters3D.new()
		cq.shape = small
		cq.transform = Transform3D(Basis(), Vector3.ZERO)
		cq.motion = Vector3(0, 0, 20)
		var frac := space.cast_motion(cq)
		_check("cast_motion, bodies only: stops at B (z 7)", "%.1f" % (frac[0] * 20.0 + 0.3), "7.0")
		cq.collide_with_areas = true
		frac = space.cast_motion(cq)
		_check("cast_motion, + areas: stops at A (z 3)", "%.1f" % (frac[0] * 20.0 + 0.3), "3.0")

		var rq := PhysicsShapeQueryParameters3D.new()
		rq.shape = small
		rq.transform = Transform3D(Basis(), Vector3(0, 0, 4.9)) # inside A only
		_check("rest_info inside A, bodies only", _name_of(space.get_rest_info(rq).get("rid", RID())), "-")
		rq.collide_with_areas = true
		_check("rest_info inside A, + areas", _name_of(space.get_rest_info(rq).get("rid", RID())), "A")

		_raycast.force_raycast_update()
		var col := _raycast.get_collider()
		_check("RayCast3D collide_with_areas", col.name if col else "-", "A")

		print("[query] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false
