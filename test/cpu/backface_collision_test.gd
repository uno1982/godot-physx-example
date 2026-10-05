extends SceneTree

# ConcavePolygonShape3D.backface_collision: a one-sided trimesh floor (front
# faces up) met from behind, with the flag off and on -- rays, shape casts,
# overlaps, rigid bodies and a character. The expectations are Jolt's
# results; run on any engine:
#   godot --headless --path . --script res://test/cpu/backface_collision_test.gd

const SPACING := 30.0

var _tick := 0
var _pass := true
var _floors: Array[StaticBody3D] = [] # [off, on]
var _rise: Array[RigidBody3D] = [] # launched up from below
var _drop: Array[RigidBody3D] = [] # dropped from above
var _sunk: Array[RigidBody3D] = [] # starts just under the face, falls
var _climb: Array[CharacterBody3D] = [] # moves up from below
var _results := {}
var _face_index := -2

# What a back face does on Jolt: it only counts with backface_collision on,
# and for rays only when hit_back_faces is set too.
const EXPECTED := {
	"ray from below, hit_back_faces=true  [off]": false,
	"ray from below, hit_back_faces=false [off]": false,
	"ray from above (front)               [off]": true,
	"cast_motion sphere up from below     [off]": false,
	"cast_motion sphere down (front)      [off]": true,
	"ray from below, hit_back_faces=true  [on]": true,
	"ray from below, hit_back_faces=false [on]": false,
	"ray from above (front)               [on]": true,
	"cast_motion sphere up from below     [on]": true,
	"cast_motion sphere down (front)      [on]": true,
	"intersect_shape sphere just below    [on]": true,
	"rigid ball up from below stopped     [off]": false,
	"rigid ball dropped on front stopped  [off]": true,
	"character up from below stopped      [off]": false,
	"rigid ball up from below stopped     [on]": true,
	"rigid ball dropped on front stopped  [on]": true,
	"character up from below stopped      [on]": true,
}
# PhysX overlap queries are two-sided: a shape just behind a one-sided mesh
# still reports it there (Jolt doesn't). Printed, not checked.
const KNOWN_DIFFERENT := ["intersect_shape sphere just below    [off]"]


func _initialize() -> void:
	print("[backface] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)
	for i in 2:
		var x := i * SPACING
		var floor_body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		var plane := PlaneMesh.new() # faces +Y: the front side is up
		plane.size = Vector2(10, 10)
		shape.set_faces(plane.get_faces())
		shape.backface_collision = i == 1
		cs.shape = shape
		floor_body.add_child(cs)
		floor_body.position = Vector3(x, 0, 0)
		root.add_child(floor_body)
		_floors.append(floor_body)

		var rise := _ball(root, Vector3(x - 3, -1.5, 0), 0.0)
		rise.linear_velocity = Vector3(0, 8, 0)
		_rise.append(rise)
		_drop.append(_ball(root, Vector3(x, 2.0, 0), 1.0))
		_sunk.append(_ball(root, Vector3(x + 3, -0.1, 0), 1.0))

		var ch := CharacterBody3D.new()
		var ccs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.2
		ccs.shape = cap
		ch.add_child(ccs)
		ch.position = Vector3(x, -1.5, 3)
		root.add_child(ch)
		_climb.append(ch)


func _ball(root: Node, pos: Vector3, gravity: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	rb.gravity_scale = gravity
	rb.can_sleep = false
	root.add_child(rb)
	return rb


func _queries(i: int) -> void:
	var x := i * SPACING
	var space := _floors[i].get_world_3d().direct_space_state
	var tag: String = "on" if i == 1 else "off"

	var ray := PhysicsRayQueryParameters3D.create(Vector3(x - 1, -2, -2), Vector3(x - 1, 2, -2))
	ray.hit_back_faces = true
	_results["ray from below, hit_back_faces=true  [%s]" % tag] = not space.intersect_ray(ray).is_empty()
	ray.hit_back_faces = false
	_results["ray from below, hit_back_faces=false [%s]" % tag] = not space.intersect_ray(ray).is_empty()
	var down := PhysicsRayQueryParameters3D.create(Vector3(x - 1, 2, -2), Vector3(x - 1, -2, -2))
	var down_hit := space.intersect_ray(down)
	_results["ray from above (front)               [%s]" % tag] = not down_hit.is_empty()
	if i == 0 and not down_hit.is_empty():
		_face_index = down_hit.face_index

	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	var sp := PhysicsShapeQueryParameters3D.new()
	sp.shape = sphere
	sp.transform = Transform3D(Basis(), Vector3(x + 1, -2, -2))
	sp.motion = Vector3(0, 4, 0)
	var frac := space.cast_motion(sp)
	_results["cast_motion sphere up from below     [%s]" % tag] = frac.size() == 2 and frac[0] < 0.99
	sp.transform = Transform3D(Basis(), Vector3(x + 1, 2, -2))
	sp.motion = Vector3(0, -4, 0)
	frac = space.cast_motion(sp)
	_results["cast_motion sphere down (front)      [%s]" % tag] = frac.size() == 2 and frac[0] < 0.99

	sp.transform = Transform3D(Basis(), Vector3(x + 1, -0.1, -2))
	sp.motion = Vector3.ZERO
	_results["intersect_shape sphere just below    [%s]" % tag] = not space.intersect_shape(sp).is_empty()


func _physics_process(delta: float) -> bool:
	_tick += 1
	for ch in _climb:
		ch.velocity = Vector3(0, 4, 0)
		ch.move_and_slide()

	if _tick == 2:
		for i in 2:
			_queries(i)

	if _tick == 90:
		for i in 2:
			var tag: String = "on" if i == 1 else "off"
			_results["rigid ball up from below stopped     [%s]" % tag] = _rise[i].position.y < 0.0
			_results["rigid ball dropped on front stopped  [%s]" % tag] = _drop[i].position.y > 0.0
			_results["ball starting under face held/pushed [%s]" % tag] = _sunk[i].position.y > -0.5
			_results["character up from below stopped      [%s]" % tag] = _climb[i].position.y < 0.0
		for k in _results.keys():
			var note := ""
			if EXPECTED.has(k) and EXPECTED[k] != _results[k]:
				note = "   <-- FAIL, Jolt: " + ("hits" if EXPECTED[k] else "passes")
				_pass = false
			elif k in KNOWN_DIFFERENT:
				note = "   (not checked)"
			print("  %-50s %s%s" % [k, "BLOCKED/HIT" if _results[k] else "passes", note])
		# The ray at (-1, -2) from the floor center crosses face 0 or 1 of the
		# two-triangle quad -- in Godot's face order, which cooking reorders.
		var plane_faces := PlaneMesh.new()
		plane_faces.size = Vector2(10, 10)
		var f := plane_faces.get_faces()
		var want := -1
		for t in f.size() / 3:
			var a := Vector2(f[t * 3].x, f[t * 3].z)
			var b := Vector2(f[t * 3 + 1].x, f[t * 3 + 1].z)
			var c := Vector2(f[t * 3 + 2].x, f[t * 3 + 2].z)
			if Geometry2D.point_is_inside_triangle(Vector2(-1, -2), a, b, c):
				want = t
		# -1 = not reported (Jolt only reports it with its
		# queries/enable_ray_cast_face_index setting on).
		var face_ok := _face_index == want or _face_index == -1
		print("  ray face_index %d (want %d) %s" % [_face_index, want, "" if face_ok else "<-- FAIL"])
		_pass = _pass and face_ok
		print("[backface] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false
