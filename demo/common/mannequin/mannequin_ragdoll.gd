extends Node3D

## The mannequin as a ragdoll: its physical skeleton (made with Godot's Create
## Physical Skeleton) -- cone joints at the spine, shoulders, hips and ankles,
## hinges at the knees and elbows -- under a PhysicalBoneSimulator3D.
## Until it goes limp the physical bones follow the animation, so they can be
## hit (or collide with cloth); go_limp() hands the body over to physics.

## The velocity to apply to every bone as it goes limp -- e.g. a bit of recoil
## when it spawns.
@export var initial_velocity: Vector3
## Limp from the start (true), or play [member animation] until [method go_limp].
@export var start_limp := true
## The mannequin animation to play while not limp.
@export var animation := "Idle"

var _simulator: PhysicalBoneSimulator3D
var _animation_player: AnimationPlayer
var _limp := false


func _ready() -> void:
	_simulator = find_child("PhysicalBoneSimulator3D", true, false)
	_animation_player = find_child("AnimationPlayer", true, false)
	_add_clavicles()
	_except_overlapping_bones()
	if start_limp:
		go_limp()
	elif _animation_player and _animation_player.has_animation(animation):
		_animation_player.play(animation)


## Hands the body over to physics. [param impulse], if any, hits [param bone]
## at the world position [param at] -- a shot.
func go_limp(impulse := Vector3(), at := Vector3(), bone: PhysicalBone3D = null) -> void:
	if not _limp:
		_limp = true
		if _animation_player:
			_animation_player.pause()
		_simulator.physical_bones_start_simulation()
		if not initial_velocity.is_zero_approx():
			for physical_bone in _simulator.get_children():
				if physical_bone is PhysicalBone3D:
					physical_bone.apply_central_impulse(initial_velocity)
	if bone and not impulse.is_zero_approx():
		bone.apply_impulse(impulse, at - bone.global_position)


func is_limp() -> bool:
	return _limp


# The clavicles (Shoulder bones) get physical bones of their own, between the
# upper chest and the upper arms. Without them, a clavicle stays in whatever
# pose the animation left it in while the arm hangs from the shoulder socket
# of the rest pose the joints were made in -- this retargeted skeleton's rest
# is a T-pose, far from the clips' shoulders, so the mesh tore open ~17 cm at
# the shoulder. Made here as Create Physical Skeleton would (a capsule along
# the bone, a cone joint at its root), except where the joint is made: a
# joint's limits sit around the pose it's made in, and the clips hold the
# clavicles 33-47 deg from the T-pose but move them only 3-14 deg within a
# clip -- so the joint is made with the clavicle in the clip's pose (its first
# frame), and kept tight, as a shoulder girdle moves. Adding one re-parents the
# upper arm's joint onto it.
const CLAVICLE_MASS := 3.0
const CLAVICLE_RADIUS := 0.05
const CLAVICLE_SWING := 20.0 # deg
const CLAVICLE_TWIST := 10.0 # deg


func _add_clavicles() -> void:
	var skeleton: Skeleton3D = _simulator.get_parent()
	for side in ["Left", "Right"]:
		var bone := skeleton.find_bone(side + "Shoulder")
		var arm := skeleton.find_bone(side + "UpperArm")
		if bone < 0 or arm < 0 or _simulator.get_node_or_null("Physical Bone %sShoulder" % side):
			continue
		var along := skeleton.get_bone_rest(arm).origin # the bone, in its own space
		var axis := along.normalized()
		var pb := PhysicalBone3D.new()
		pb.name = "Physical Bone %sShoulder" % side
		pb.bone_name = side + "Shoulder"
		pb.mass = CLAVICLE_MASS
		pb.body_offset = Transform3D(Basis(), along * 0.5)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		# The cone twists about its joint's X: along the bone, at its root.
		pb.joint_offset = Transform3D(Basis(Quaternion(Vector3.RIGHT, axis)), -along * 0.5)
		var shape := CapsuleShape3D.new()
		shape.radius = CLAVICLE_RADIUS
		shape.height = along.length() + 2.0 * CLAVICLE_RADIUS
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), Vector3())
		pb.add_child(cs)
		# In the clip's pose before it joins, and the upper arm on its socket there: both joints are made as it
		# does (the arm's is remade against it), around these poses.
		var chest := skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone))
		var clavicle := chest * Transform3D(Basis(_clip_rotation(side + "Shoulder", skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())), skeleton.get_bone_rest(bone).origin)
		var to_simulator := _simulator.transform.affine_inverse()
		var arm_pb: PhysicalBone3D = _simulator.get_node_or_null("Physical Bone %sUpperArm" % side)
		if arm_pb:
			arm_pb.transform = to_simulator * clavicle * skeleton.get_bone_rest(arm) * arm_pb.body_offset
		pb.transform = to_simulator * clavicle * pb.body_offset
		_simulator.add_child(pb)
		# Entering the tree put it back at its bone's current (rest) pose and made its joint there: make that again
		# in the clip's pose (a joint type change remakes the joint where the bodies are, with default limits).
		pb.transform = to_simulator * clavicle * pb.body_offset
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		pb.set("joint_constraints/swing_span", CLAVICLE_SWING)
		pb.set("joint_constraints/twist_span", CLAVICLE_TWIST)


# A bone's local rotation in the first frame of the clip this mannequin plays (or Idle), else p_default.
func _clip_rotation(bone_name: String, p_default: Quaternion) -> Quaternion:
	if not _animation_player:
		return p_default
	var clip := animation if _animation_player.has_animation(animation) else "Idle"
	if not _animation_player.has_animation(clip):
		return p_default
	var anim := _animation_player.get_animation(clip)
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D and String(anim.track_get_path(t)).ends_with(":" + bone_name):
			return anim.rotation_track_interpolate(t, 0.0)
	return p_default


# Bones whose capsules overlap in the rest pose -- the stacked torso, the
# thighs, the feet -- never collide with each other. Godot only skips
# collisions between bones joined to each other, and an overlapping pair
# further apart pushes on itself forever once limp: the body crawls along
# the floor instead of coming to rest.
func _except_overlapping_bones() -> void:
	var bones: Array[PhysicalBone3D] = []
	for child in _simulator.get_children():
		if child is PhysicalBone3D:
			bones.append(child)
	for i in bones.size():
		for j in range(i + 1, bones.size()):
			if _capsules_overlap(bones[i], bones[j]):
				bones[i].add_collision_exception_with(bones[j])


func _capsules_overlap(a: PhysicalBone3D, b: PhysicalBone3D) -> bool:
	var sa := _capsule_of(a)
	var sb := _capsule_of(b)
	if sa.is_empty() or sb.is_empty():
		return false
	var closest := Geometry3D.get_closest_points_between_segments(sa[0], sa[1], sb[0], sb[1])
	return closest[0].distance_to(closest[1]) < sa[2] + sb[2]


# [segment end, segment end, radius] of a bone's capsule, in the bone's
# parent space (the rest pose), or [] if it has none.
func _capsule_of(bone: PhysicalBone3D) -> Array:
	for child in bone.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = child.shape
			var xf: Transform3D = bone.transform * child.transform
			var half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
			return [xf * Vector3(0, -half, 0), xf * Vector3(0, half, 0), capsule.radius]
	return []
