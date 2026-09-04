extends SceneTree

# Generic6DOFJoint3D linear/angular springs, mapped by the PhysX module onto
# PxD6JointDrive. Two checks:
#  1. A single body hung on a linear spring settles near its equilibrium offset
#     under gravity instead of falling away.
#  2. A 6-link 6DOF chain with linear springs on every axis stays taut under a
#     constant sideways force -- the case plain PGS limits drift on.

var _phase := 0
var _tick := 0
var _spring_body: RigidBody3D
var _anchor_pos := Vector3(0, 8, 0)
var _links: Array[RigidBody3D] = []
const LW := 0.6
const N := 6
const FORCE := Vector3(0, 0, 2.5)

func _make_linear_spring(root: Node3D, a: Node3D, b: Node3D, at: Vector3, k: float) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.position = at
	root.add_child(j)
	for axis in ["x", "y", "z"]:
		j.set("linear_spring_%s/enabled" % axis, true)
		j.set("linear_spring_%s/stiffness" % axis, k)
		j.set("linear_spring_%s/damping" % axis, 2.0 * sqrt(k))
		j.set("linear_spring_%s/equilibrium_point" % axis, 0.0)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	return j

# Rigid linear connection (default), plus angular springs that resist bending --
# the "hold a loaded chain together" case.
func _make_chain_link(root: Node3D, a: Node3D, b: Node3D, at: Vector3) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.position = at
	root.add_child(j)
	for axis in ["x", "y", "z"]:
		j.set("angular_spring_%s/enabled" % axis, true)
		j.set("angular_spring_%s/stiffness" % axis, 30.0)
		j.set("angular_spring_%s/damping" % axis, 6.0)
		j.set("angular_spring_%s/equilibrium_point" % axis, 0.0)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	return j

func _initialize() -> void:
	print("[jspring] engine=%s solver=%s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		ProjectSettings.get_setting("physics/physx_3d/simulation/solver_type", 0)])
	var root := Node3D.new()
	get_root().add_child(root)

	var anchor := StaticBody3D.new()
	anchor.position = _anchor_pos
	root.add_child(anchor)

	_spring_body = RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.3, 0.3, 0.3)
	cs.shape = b
	_spring_body.add_child(cs)
	_spring_body.collision_layer = 0
	_spring_body.collision_mask = 0
	_spring_body.mass = 1.0
	_spring_body.can_sleep = false
	_spring_body.position = _anchor_pos
	root.add_child(_spring_body)
	_make_linear_spring(root, anchor, _spring_body, _anchor_pos, 400.0)

	# chain
	var prev: Node3D = anchor
	for i in N:
		var seg := RigidBody3D.new()
		var scs := CollisionShape3D.new()
		var sb := BoxShape3D.new()
		sb.size = Vector3(LW, 0.3, 0.04)
		scs.shape = sb
		seg.add_child(scs)
		seg.collision_layer = 0
		seg.collision_mask = 0
		seg.mass = 0.4
		seg.can_sleep = false
		seg.position = Vector3(4.0 + (i + 0.5) * LW, 8, 0)
		root.add_child(seg)
		_make_chain_link(root, prev, seg, Vector3(4.0 + i * LW, 8, 0))
		prev = seg
		_links.append(seg)

func _physics_process(_d: float) -> bool:
	_tick += 1
	for seg in _links:
		seg.apply_central_force(FORCE)

	if _tick == 250:
		var drop := _anchor_pos.y - _spring_body.global_position.y
		var spring_ok := drop > 0.0 and drop < 0.5
		print("[jspring] spring body sag=%.3f m -> %s" % [drop, "ok" if spring_ok else "BAD"])

		var maxgap := 0.0
		for i in range(1, _links.size()):
			maxgap = maxf(maxgap, _links[i].global_position.distance_to(_links[i - 1].global_position))
		var chain_ok := maxgap < LW * 1.8
		print("[jspring] chain max link spacing=%.2f (rest %.2f) -> %s" % [maxgap, LW, "ok" if chain_ok else "BAD"])

		var ok := spring_ok and chain_ok
		print("[jspring] %s" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false
