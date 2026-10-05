extends Node3D

# Ragdolls with Godot's own workflow -- PhysicalBoneSimulator3D + PhysicalBone3D.
# The mannequins play animations; their physical bones follow along until a
# shot knocks one over, then physics takes the body (the bone that was hit
# takes the impulse). Dropped ones tumble down the steps.
#
# To make your own (see demo/common/mannequin/mannequin_ragdoll.tscn):
#   1. Select the character's Skeleton3D and use Skeleton3D > Create Physical
#      Skeleton: one PhysicalBone3D per bone, with a capsule each, under a
#      PhysicalBoneSimulator3D. Delete the bones you don't need (fingers, toes).
#   2. On each PhysicalBone3D, under Joint, pick a type and its limits:
#      Cone at the spine (25 deg swing here), shoulders (95), hips (60) and
#      ankles (30); Hinge at the knees and elbows, limited so they bend one
#      way (0..140 deg); None at the root (the hips). A cone twists about its
#      joint's X axis, a hinge turns about its Z -- turn Joint Offset so X
#      runs along the bone and a hinge's Z across the limb. Godot's hinge
#      angle turns clockwise about Z.
#   3. Give the bones realistic masses (the torso heaviest): a light bone
#      carrying a heavy limb is what joint limits hold worst.
#   4. Call physical_bones_start_simulation() to go limp.
#
#   L-click  shoot (knocks a mannequin over, or shoves a ragdoll)
#   SPACE    drop a ragdoll down the steps
#   WASD + hold RMB  fly     R  reset     ESC  quit

const RAGDOLL := preload("res://demo/common/mannequin/mannequin_ragdoll.tscn")
const SHOT_IMPULSE := 90.0 # N*s
const SHOT_RANGE := 200.0

@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _dropped: Node3D = $Dropped
var _fly: FlyCamera


func _ready() -> void:
	_fly = FlyCamera.new(_camera)


func _unhandled_input(event: InputEvent) -> void:
	if _fly.handle_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_drop()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()


func _process(delta: float) -> void:
	_fly.process(delta)
	var limp := 0
	for m in get_tree().get_nodes_in_group("ragdolls"):
		limp += 1 if m.is_limp() else 0
	_hud.text = "Ragdolls -- Godot's Create Physical Skeleton (PhysicalBoneSimulator3D + PhysicalBone3D)\n" \
			+ "Cone joints: spine, shoulders, hips, ankles.  Hinges: knees, elbows (bend one way).\n" \
			+ "L-click shoot   SPACE drop one   WASD + hold RMB fly   R reset   ESC\n" \
			+ "ragdolls: %d (%d limp)   physics %.1f ms   FPS %d" % [get_tree().get_nodes_in_group("ragdolls").size(), limp,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Engine.get_frames_per_second()]


# A ray from the camera through the cursor: a mannequin's physical bone goes
# limp with the shot's impulse where it was hit.
func _shoot(screen: Vector2) -> void:
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * SHOT_RANGE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is PhysicalBone3D:
		return
	var bone: PhysicalBone3D = hit.collider
	var mannequin := bone.get_parent()
	while mannequin and not mannequin.has_method("go_limp"):
		mannequin = mannequin.get_parent()
	if mannequin:
		mannequin.go_limp(dir * SHOT_IMPULSE, hit.position, bone)


func _drop() -> void:
	var m := RAGDOLL.instantiate()
	m.position = Vector3(randf_range(-1.5, 1.5), 5.0, -5.0)
	m.rotation = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), 0.0)
	m.initial_velocity = Vector3(randf_range(-1, 1), 0, randf_range(2.0, 4.0))
	m.add_to_group("ragdolls")
	_dropped.add_child(m)
