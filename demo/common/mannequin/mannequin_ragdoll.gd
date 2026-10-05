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
