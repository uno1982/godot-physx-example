extends Node3D

# An active ragdoll -- the PhysX joint drives (PhysX.joint_*). The mannequin on
# the left only plays an animation; the one on the right is a simulated
# ragdoll whose every joint is driven toward the pose the left one is in, so
# it copies the animation with physics: shoot a limb and it's knocked aside,
# then swings back.
#
# How (see _ready() and _physics_process()):
#   - PhysX.physical_bone_get_joint(bone) gives each PhysicalBone3D's joint;
#   - PhysX.joint_set_slerp_drive() turns on one spring that turns the bone
#     toward its target rotation (cones and hinges alike), and
#     PhysX.joint_set_drive_acceleration() makes its gains accelerations, so one
#     stiffness suits the light hands and the heavy torso. An acceleration only
#     counts the two bones at the joint, though: a joint that carries more (the
#     spine holds up the whole upper body) gets its stiffness scaled by the mass
#     it carries;
#   - every physics frame, PhysX.joint_set_drive_target_from_poses() sets each
#     joint's target from the animated skeleton's bone poses (a bone's body sits
#     at its bone pose * body_offset).
# The drives act at the joints only: they hold the body's shape, not its
# balance. Here a Generic6DOFJoint3D to a static anchor holds the hips where
# the animation has them (the "hand of god"); H lets go, and the body falls,
# still holding its pose as best it can.
#
#   L-click  shoot the ragdoll        1 / 2 / 3  idle / walk / dance
#   + / -    stronger / weaker drives  H  hold the hips   G  go limp
#   WASD + SPACE/CTRL + hold RMB  fly     R  reset     ESC  quit

const ANIMATIONS := ["Idle", "Walk", "Dance"]
const SHOT_IMPULSE := 30.0 # N*s
const SHOT_RANGE := 200.0
# Drive stiffness in 1/s^2 (acceleration drives); the damping is critical for it.
const STIFFNESS_STEPS := [250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
# The hips' hold: linear springs plus a SLERP drive toward the animated hips, in
# 1/s^2 for every kg of the body (the hips carry all of it).
const HOLD_STIFFNESS := 600.0

@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _target: Node3D = $Target
@onready var _puppet: Node3D = $Puppet
@onready var _anchor: StaticBody3D = $Anchor
var _fly: FlyCamera
var _target_skeleton: Skeleton3D
var _puppet_skeleton: Skeleton3D
var _target_player: AnimationPlayer
var _bones: Array[PhysicalBone3D] = []
var _parent_of := {} # PhysicalBone3D -> its parent PhysicalBone3D
var _joint_of := {} # PhysicalBone3D -> its joint RID
var _load := {} # PhysicalBone3D -> mass of it and the bones beyond it / its own mass
var _hips: PhysicalBone3D
var _hold: Generic6DOFJoint3D
var _holding := true
var _driven := true
var _strength := 3
var _animation := 0


func _ready() -> void:
	_fly = FlyCamera.new(_camera)
	_target_skeleton = _target.find_children("*", "Skeleton3D")[0]
	_puppet_skeleton = _puppet.find_children("*", "Skeleton3D")[0]
	# The target's pose is read every physics frame: animate it there too.
	_target_player = _target.find_child("AnimationPlayer", true, false)
	_target_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	var simulator: PhysicalBoneSimulator3D = _puppet.find_child("PhysicalBoneSimulator3D", true, false)
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			_bones.append(child)
	for bone in _bones:
		var parent := _parent_bone(bone)
		if parent:
			_parent_of[bone] = parent
			_joint_of[bone] = PhysX.physical_bone_get_joint(bone)
		else:
			_hips = bone
	for bone in _joint_of:
		_load[bone] = 1.0
	for bone in _joint_of:
		var up: PhysicalBone3D = _parent_of[bone]
		while _joint_of.has(up):
			_load[up] += bone.mass / up.mass
			up = _parent_of[up]
	# The hold: free to move (no linear limits), springs pull the hips to the
	# target, a SLERP drive turns them to it.
	var body_mass := 0.0
	for bone in _bones:
		body_mass += bone.mass
	var k := HOLD_STIFFNESS * body_mass / _hips.mass
	_hold = Generic6DOFJoint3D.new()
	for axis in ["x", "y", "z"]:
		_hold.set("linear_limit_%s/enabled" % axis, false)
		_hold.set("linear_spring_%s/enabled" % axis, true)
		_hold.set("linear_spring_%s/stiffness" % axis, k)
		_hold.set("linear_spring_%s/damping" % axis, 2.0 * sqrt(k))
	add_child(_hold)
	_hold.global_transform = _hips.global_transform
	_hold.node_a = _hold.get_path_to(_anchor)
	_hold.node_b = _hold.get_path_to(_hips)
	PhysX.joint_set_drive_acceleration(_hold.get_rid(), true)
	PhysX.joint_set_slerp_drive(_hold.get_rid(), true, k, 2.0 * sqrt(k))
	_set_drives()


# The bone's nearest ancestor that has a PhysicalBone3D (what its joint ties it to).
func _parent_bone(bone: PhysicalBone3D) -> PhysicalBone3D:
	var id := _puppet_skeleton.get_bone_parent(bone.get_bone_id())
	while id >= 0:
		for other in _bones:
			if other.get_bone_id() == id:
				return other
		id = _puppet_skeleton.get_bone_parent(id)
	return null


func _set_drives() -> void:
	for bone in _joint_of:
		var joint: RID = _joint_of[bone]
		var k: float = STIFFNESS_STEPS[_strength] * _load[bone]
		PhysX.joint_set_slerp_drive(joint, _driven, k, 2.0 * sqrt(k))
		PhysX.joint_set_drive_acceleration(joint, true)


# Where the animation has a bone's body, in the puppet's space.
func _target_pose(bone: PhysicalBone3D) -> Transform3D:
	return _puppet_skeleton.global_transform * _target_skeleton.get_bone_global_pose(bone.get_bone_id()) * bone.body_offset


func _physics_process(_delta: float) -> void:
	for bone in _joint_of:
		PhysX.joint_set_drive_target_from_poses(_joint_of[bone], _target_pose(_parent_of[bone]), _target_pose(bone))
	if _holding:
		PhysX.joint_set_drive_target_from_poses(_hold.get_rid(), _anchor.global_transform, _target_pose(_hips))


func _unhandled_input(event: InputEvent) -> void:
	if _fly.handle_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else get_viewport().get_visible_rect().size * 0.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				_animation = event.keycode - KEY_1
				_target_player.play(ANIMATIONS[_animation])
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_strength = mini(_strength + 1, STIFFNESS_STEPS.size() - 1)
				_set_drives()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_strength = maxi(_strength - 1, 0)
				_set_drives()
			KEY_H:
				_holding = not _holding
				# Letting go drops the joint; taking hold again pulls the hips
				# back up to the animation. The joint goes where the hips are
				# now first: its frame on them is made there, and a frame far
				# off the body would be pulled on a lever arm instead.
				if _holding:
					_hold.global_transform = _hips.global_transform
				_hold.node_b = _hold.get_path_to(_hips) if _holding else NodePath()
			KEY_G:
				_driven = not _driven
				_set_drives()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()


func _shoot(screen: Vector2) -> void:
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * SHOT_RANGE))
	if not hit.is_empty() and hit.collider is PhysicalBone3D and _bones.has(hit.collider):
		var bone: PhysicalBone3D = hit.collider
		bone.apply_impulse(dir * SHOT_IMPULSE, hit.position - bone.global_position)


func _process(delta: float) -> void:
	_fly.process(delta)
	_hud.text = "Active ragdoll -- PhysX joint drives: every joint SLERP-driven toward the animated pose (left)\n" \
			+ "L-click shoot   1/2/3 idle/walk/dance   +/- strength   H hold hips   G go limp   WASD + hold RMB fly   R reset   ESC\n" \
			+ "%s   drives %s, stiffness %.0f /s^2   hips %s   physics %.1f ms   FPS %d" % [ANIMATIONS[_animation],
			"on" if _driven else "off (limp)", STIFFNESS_STEPS[_strength], "held" if _holding else "free",
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Engine.get_frames_per_second()]
