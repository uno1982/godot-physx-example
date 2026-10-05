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
