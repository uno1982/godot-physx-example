extends SceneTree

# Convex hull (dynamic) + primitive sphere falling onto a trimesh (static) floor.

var _hull: RigidBody3D
var _sphere: RigidBody3D
var _tick := 0

func _initialize() -> void:
	print("[mesh] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var boxmesh := BoxMesh.new()
	boxmesh.size = Vector3(20, 1, 20)
	var tri := ConcavePolygonShape3D.new()
	tri.set_faces(boxmesh.get_faces())
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	fcs.shape = tri
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var hbox := BoxMesh.new()
	hbox.size = Vector3(1.4, 1.4, 1.4)
	var hull := ConvexPolygonShape3D.new()
	hull.points = hbox.get_faces()
	_hull = RigidBody3D.new()
	var hcs := CollisionShape3D.new()
	hcs.shape = hull
	_hull.add_child(hcs)
	_hull.position = Vector3(-3, 5, 0)
	root.add_child(_hull)

	_sphere = RigidBody3D.new()
	var scs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.5
	scs.shape = ss
	_sphere.add_child(scs)
	_sphere.position = Vector3(3, 5, 0)
	root.add_child(_sphere)

	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick >= 240:
		var hy := _hull.global_position.y
		var sy := _sphere.global_position.y
		var ok := hy > 0.5 and hy < 0.95 and sy > 0.35 and sy < 0.65
		print("[mesh] hull.y=%.3f (want ~0.7)  sphere.y=%.3f (want ~0.5)  -> %s" % [
			hy, sy, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
