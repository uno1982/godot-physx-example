extends SceneTree

# A scaled PhysXDestructible3D: what a piece renders is what it collides with, after a break as before it.
# A body's pose has no scale, so taking a dynamic body's pose as the pieces' spawn transform built them with scale 1
# colliders under a mesh rendered at the node's scale, and put damage in the wrong place.
# - Points just inside each rendered piece are inside a collider, right after the break and at rest.
# - The rendered pieces rest on the floor, neither through it nor above it.
# - A small hit breaks what's at the hit, where it renders.

const SCALES := [Vector3.ONE, Vector3(2, 2, 2), Vector3(2, 1, 3)]

var _ok := true
var _asset: Resource
var _chunk_size := 0.0


func _check(cond: bool, msg: String) -> void:
	print("[destructible_scale] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _floor(parent: Node) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	body.add_child(shape)
	body.position.y = -0.5
	parent.add_child(body)


func _node(parent: Node, xform: Transform3D, dynamic: bool) -> Node3D:
	var node: Node3D = ClassDB.instantiate("PhysXDestructible3D")
	node.blast_asset = _asset
	node.transform = xform
	node.dynamic = dynamic
	node.anchor = 2 # none: everything falls
	parent.add_child(node)
	return node


# What the renderer shows: the body's rotation and position, at the node's scale.
func _rendered(node: Node3D, i: int, scale_value: Vector3) -> Transform3D:
	var xf: Transform3D = node.get_piece_transform(i)
	xf.basis = xf.basis.orthonormalized().scaled_local(scale_value)
	return xf


# How many of the points just inside each rendered piece aren't inside any collider, of how many.
func _outside(node: Node3D, scale_value: Vector3) -> Vector2i:
	var state := get_root().get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	var outside := 0
	var total := 0
	for i in node.get_piece_count():
		var pts: PackedVector3Array = _asset.chunk_points[node.get_piece_chunk(i)]
		var xf := _rendered(node, i, scale_value)
		var center := Vector3.ZERO
		for p in pts:
			center += p
		center /= pts.size()
		for k in range(0, pts.size(), 3):
			q.position = xf * center.lerp(pts[k], 0.85)
			total += 1
			if state.intersect_point(q, 1).is_empty():
				outside += 1
	return Vector2i(outside, total)


func _bottom(node: Node3D, scale_value: Vector3) -> float:
	var low := INF
	for i in node.get_piece_count():
		var xf := _rendered(node, i, scale_value)
		for p: Vector3 in _asset.chunk_points[node.get_piece_chunk(i)]:
			low = minf(low, (xf * p).y)
	return low


func _wait(ticks: int) -> void:
	for i in ticks:
		await physics_frame


func _break_all(dynamic: bool, scale_value: Vector3, rotated: bool) -> void:
	var label := "%s scale %s%s" % ["dynamic" if dynamic else "fixed", scale_value, " rotated" if rotated else ""]
	var world := Node3D.new()
	get_root().add_child(world)
	_floor(world)
	var basis := Basis().scaled(scale_value)
	if rotated:
		basis = Basis(Vector3(1, 0, 0), deg_to_rad(90.0)) * Basis(Vector3(0, 1, 0), deg_to_rad(30.0)) * basis
	var node := _node(world, Transform3D(basis, Vector3(0, 8, 0)), dynamic)
	await _wait(5)
	node.apply_radial_damage(node.global_position, 100000.0, 50.0, 60.0)
	await _wait(1)
	_check(node.get_piece_count() == _asset.get_chunk_count() - 1, "%s: breaks into all its chunks (%d)" % [label, node.get_piece_count()])
	var at_break := _outside(node, scale_value)
	_check(at_break.x * 100 <= at_break.y * 2, "%s: right after the break the rendered pieces are inside their colliders (%d of %d points outside)" % [label, at_break.x, at_break.y])
	await _wait(420)
	var at_rest := _outside(node, scale_value)
	_check(at_rest.x * 100 <= at_rest.y * 2, "%s: at rest too (%d of %d points outside)" % [label, at_rest.x, at_rest.y])
	var low := _bottom(node, scale_value)
	_check(low > -0.05 and low < 0.05, "%s: the rendered pieces rest on the floor (lowest point %.3f)" % [label, low])
	world.queue_free()
	await process_frame


# A hit on one corner of what renders breaks that corner off, on a dynamic body, which has no scale in its pose.
func _small_hit(scale_value: Vector3) -> void:
	var world := Node3D.new()
	get_root().add_child(world)
	var node := _node(world, Transform3D(Basis().scaled(scale_value), Vector3(0, 30, 0)), true)
	await _wait(3)
	var corner: Vector3 = node.global_position + Vector3(1, 1, 1) * scale_value * _chunk_size * 0.48
	var size_now := Vector3.ONE * scale_value * _chunk_size
	node.apply_radial_damage(corner, 100000.0, size_now.length() * 0.12, size_now.length() * 0.2)
	await _wait(1)
	var nearest := INF
	var count: int = node.get_piece_count()
	for i in count:
		if node.get_piece_chunk(i) == 0:
			continue
		var xf := _rendered(node, i, scale_value)
		var pts: PackedVector3Array = _asset.chunk_points[node.get_piece_chunk(i)]
		var center := Vector3.ZERO
		for p in pts:
			center += p
		nearest = minf(nearest, (xf * (center / pts.size())).distance_to(corner))
	_check(node.is_fractured(), "scale %s: a hit on a corner breaks it (%d pieces)" % [scale_value, count])
	_check(nearest < size_now.length() * 0.45, "scale %s: and a piece is near the hit (%.2f m, the mesh's diagonal is %.2f m)" % [scale_value, nearest, size_now.length()])
	world.queue_free()
	await process_frame


func _run() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	_chunk_size = 1.0
	_asset = ClassDB.instantiate("PhysXBlastAuthoring").fracture_mesh(box, 16, 7)
	for scale_value: Vector3 in SCALES:
		for dynamic in [true, false]:
			await _break_all(dynamic, scale_value, false)
	await _break_all(true, Vector3(2, 2, 2), true)
	await _small_hit(Vector3(2, 2, 2))

	print("[destructible_scale] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXBlastAuthoring"):
		print("SKIP: no Blast support in this build")
		quit(0)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)
