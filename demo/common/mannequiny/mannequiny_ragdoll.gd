extends Node3D

## The velocity to apply to every bone on the first physics frame -- used to give
## the ragdoll a bit of recoil when it spawns.
@export var initial_velocity: Vector3


func _ready() -> void:
	$"root/root_001/Skeleton3D/PhysicalBoneSimulator3D".physical_bones_start_simulation()
	if not initial_velocity.is_zero_approx():
		for physical_bone in $"root/root_001/Skeleton3D/PhysicalBoneSimulator3D".get_children():
			if physical_bone is PhysicalBone3D:
				physical_bone.apply_central_impulse(initial_velocity)
