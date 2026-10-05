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
#   4. Bones whose capsules overlap at rest but aren't joined to each other
#      (the stacked torso, the two thighs, the feet) need a collision
#      exception: Godot only skips collisions between joined bones, and an
#      overlapping pair pushes on itself forever -- the limp body crawls
#      along the floor and strains its joints past their limits.
#      mannequin_ragdoll.gd adds them from the capsules at start-up.
#   5. Call physical_bones_start_simulation() to go limp.
#
#   L-click  shoot a mannequin over; on a limp ragdoll, hold to drag it by
#            the point you grabbed (mouse wheel: nearer / further)
#   F        drop a ragdoll down the steps
#   WASD + SPACE/CTRL + hold RMB  fly     R  reset     ESC  quit

const RAGDOLL := preload("res://demo/common/mannequin/mannequin_ragdoll.tscn")
const SHOT_IMPULSE := 90.0 # N*s
const SHOT_RANGE := 200.0
# Dragging: a PinJoint3D holds the grabbed point to a kinematic anchor that
# follows the cursor, no faster than DRAG_MAX_SPEED (m/s) -- the joint solver
# carries the whole body hanging off it, which a push on the one bone didn't.
const DRAG_MAX_SPEED := 14.0

@onready var _camera: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _dropped: Node3D = $Dropped
var _fly: FlyCamera
var _drag_bone: PhysicalBone3D # held, or null
var _drag_local: Vector3 # grabbed point, in the bone's space
var _drag_distance := 0.0 # from the camera, along the cursor's ray
var _drag_anchor: AnimatableBody3D
var _drag_joint: PinJoint3D
var _drag_line: ImmediateMesh


func _ready() -> void:
	_fly = FlyCamera.new(_camera)
	# A thin line from the grabbed point to where it's being pulled.
	_drag_line = ImmediateMesh.new()
	var line := MeshInstance3D.new()
	line.mesh = _drag_line
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.2)
	material.no_depth_test = true
	line.material_override = material
	add_child(line)


func _unhandled_input(event: InputEvent) -> void:
	if _fly.handle_input(event):
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_click(event.position if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED else _cursor())
				else:
					_release()
			MOUSE_BUTTON_WHEEL_UP when _drag_bone:
				_drag_distance = maxf(_drag_distance - 0.5, 1.0)
			MOUSE_BUTTON_WHEEL_DOWN when _drag_bone:
				_drag_distance = minf(_drag_distance + 0.5, 40.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
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
			+ "L-click shoot (hold on a limp one to drag it, wheel nearer/further)   F drop one   WASD + hold RMB fly   R reset   ESC\n" \
			+ "ragdolls: %d (%d limp)   physics %.1f ms   FPS %d" % [get_tree().get_nodes_in_group("ragdolls").size(), limp,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Engine.get_frames_per_second()]


func _physics_process(delta: float) -> void:
	_drag_line.clear_surfaces()
	if not _drag_bone:
		return
	if not is_instance_valid(_drag_bone):
		_release()
		return
	var screen := _cursor()
	var target := _camera.project_ray_origin(screen) + _camera.project_ray_normal(screen) * _drag_distance
	_drag_anchor.global_position = _drag_anchor.global_position.move_toward(target, DRAG_MAX_SPEED * delta)
	_drag_line.surface_begin(Mesh.PRIMITIVE_LINES)
	_drag_line.surface_add_vertex(_drag_bone.global_transform * _drag_local)
	_drag_line.surface_add_vertex(target)
	_drag_line.surface_end()


func _grab(bone: PhysicalBone3D, at: Vector3, distance: float) -> void:
	_release()
	_drag_bone = bone
	_drag_local = bone.global_transform.affine_inverse() * at
	_drag_distance = distance
	# A shapeless kinematic body for the joint's other end.
	_drag_anchor = AnimatableBody3D.new()
	_drag_anchor.sync_to_physics = false
	_drag_anchor.collision_layer = 0
	_drag_anchor.collision_mask = 0
	_drag_anchor.top_level = true
	add_child(_drag_anchor)
	_drag_anchor.global_position = at
	_drag_joint = PinJoint3D.new()
	_drag_joint.top_level = true
	add_child(_drag_joint)
	_drag_joint.global_position = at
	_drag_joint.node_a = _drag_joint.get_path_to(_drag_anchor)
	_drag_joint.node_b = _drag_joint.get_path_to(bone)


func _release() -> void:
	_drag_bone = null
	if _drag_joint:
		_drag_joint.queue_free()
		_drag_joint = null
	if _drag_anchor:
		_drag_anchor.queue_free()
		_drag_anchor = null


# Where the cursor points: the mouse, or the middle of the view while the
# fly camera has the mouse captured.
func _cursor() -> Vector2:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_mouse_position()


# A ray from the camera through the cursor. A standing mannequin's physical
# bone goes limp with the shot's impulse where it was hit; a limp ragdoll's is
# grabbed there, to drag.
func _click(screen: Vector2) -> void:
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
	if not mannequin:
		return
	if mannequin.is_limp():
		_grab(bone, hit.position, from.distance_to(hit.position))
	else:
		mannequin.go_limp(dir * SHOT_IMPULSE, hit.position, bone)


func _drop() -> void:
	var m := RAGDOLL.instantiate()
	m.position = Vector3(randf_range(-1.5, 1.5), 5.0, -5.0)
	m.rotation = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), 0.0)
	m.initial_velocity = Vector3(randf_range(-1, 1), 0, randf_range(2.0, 4.0))
	m.add_to_group("ragdolls")
	_dropped.add_child(m)
