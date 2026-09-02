extends SceneTree

# A short chain of boxes pin-jointed to a static anchor, each pushed by a
# constant force every tick (as area wind would). Guards the default PGS solver:
# a 3-link chain must stay taut under a light sustained load.
#
# Longer or more heavily loaded joint chains under sustained force need
# physics/physx_3d/simulation/solver_type = TGS -- PGS drifts on them. See NOTES.

var _links: Array[RigidBody3D] = []
var _tick := 0
const FORCE := Vector3(0, 0, 2.0) # per-link, newtons
const N := 3
const LW := 0.6

func _initialize() -> void:
	print("[chain] engine=%s solver=%s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		ProjectSettings.get_setting("physics/physx_3d/simulation/solver_type", 0)])
	var root := Node3D.new()
	get_root().add_child(root)

	var anchor := StaticBody3D.new()
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(0.2, 0.2, 0.2)
	acs.shape = ab
	anchor.add_child(acs)
	anchor.position = Vector3(0, 8, 0)
	root.add_child(anchor)

	var prev: Node3D = anchor
	for i in N:
		var seg := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(LW, 0.4, 0.04)
		cs.shape = b
		seg.add_child(cs)
		seg.collision_layer = 0
		seg.collision_mask = 0
		seg.mass = 0.5
		seg.can_sleep = false
		seg.position = Vector3((i + 0.5) * LW, 8, 0)
		root.add_child(seg)
		var j := PinJoint3D.new()
		j.position = Vector3(i * LW, 8, 0)
		root.add_child(j)
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(seg)
		prev = seg
		_links.append(seg)

func _physics_process(_d: float) -> bool:
	_tick += 1
	for seg in _links:
		seg.apply_central_force(FORCE)
	if _tick == 200:
		var maxgap := 0.0
		for i in range(1, _links.size()):
			maxgap = maxf(maxgap, _links[i].global_position.distance_to(_links[i - 1].global_position))
		var root_pull := _links[0].global_position.distance_to(Vector3(0, 8, 0))
		var ok := maxgap < LW * 2.0 and root_pull < LW * 2.0
		print("[chain] max link spacing=%.2f (rest %.2f), root anchor dist=%.2f -> %s" %
				[maxgap, LW, root_pull, "PASS" if ok else "FAIL (chain stretched/tore)"])
		quit(0 if ok else 1)
	return false
