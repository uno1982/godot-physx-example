extends SceneTree

# Real skinned-skeleton ragdoll: Skeleton3D + PhysicalBoneSimulator3D + ~15
# PhysicalBone3D (the GDQuest mannequiny rig). Started simulating and shoved,
# it must fall to the floor, keep its joints connected (bones stay near their
# rest spacing, not flung apart), and never produce a NaN / explode.

var _bones: Array[PhysicalBone3D] = []
var _rest_links: Array[float] = []
var _tick := 0

func _initialize() -> void:
	print("[ragdoll] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	var floor := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(40, 1, 40)
	fcs.shape = fb
	floor.add_child(fcs)
	floor.position = Vector3(0, -0.5, 0)
	root.add_child(floor)

	var scene: PackedScene = load("res://demo/common/mannequiny/mannequiny_ragdoll.tscn")
	var mann: Node3D = scene.instantiate()
	mann.set("initial_velocity", Vector3(1.5, 3.0, 0.5))
	mann.position = Vector3(0, 1.2, 0)
	root.add_child(mann)

	var sim: PhysicalBoneSimulator3D = mann.find_child("PhysicalBoneSimulator3D", true, false)
	assert(sim != null, "no PhysicalBoneSimulator3D in the ragdoll scene")
	for c in sim.get_children():
		if c is PhysicalBone3D:
			_bones.append(c)
	assert(_bones.size() >= 10, "expected a full humanoid rig, got %d bones" % _bones.size())

	# Capture the rest spacing between each bone and its parent bone.
	for pb in _bones:
		var parent := pb.get_parent_node_3d()
		var d := 0.0
		if parent is PhysicalBone3D:
			d = pb.global_position.distance_to(parent.global_position)
		_rest_links.append(d)

func _physics_process(_d: float) -> bool:
	_tick += 1

	var bad := 0
	var max_stretch := 1.0
	var lo := 1e9
	for i in _bones.size():
		var p := _bones[i].global_position
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			bad += 1
			continue
		lo = minf(lo, p.y)
		var parent := _bones[i].get_parent_node_3d()
		if parent is PhysicalBone3D and _rest_links[i] > 0.01:
			var cur := p.distance_to(parent.global_position)
			max_stretch = maxf(max_stretch, cur / _rest_links[i])

	if bad > 0:
		print("[ragdoll] t%d  NaN in %d bones -> FAIL" % [_tick, bad])
		quit(1)
		return true
	if max_stretch > 3.0:
		print("[ragdoll] t%d  joint stretched %.1fx rest -> FAIL (joints broke)" % [_tick, max_stretch])
		quit(1)
		return true

	if _tick == 180:
		var settled := lo < 0.6 # some part of the body reached the floor
		print("[ragdoll] t%d  lowest bone y=%.2f  max stretch=%.2fx  -> %s" %
				[_tick, lo, max_stretch, "PASS" if settled else "FAIL (never settled)"])
		quit(0 if settled else 1)
		return true
	return false
