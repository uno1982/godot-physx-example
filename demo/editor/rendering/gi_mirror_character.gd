extends Node3D

# A character in a PXTGI mirror: you are the mannequin, in a room with a wall mirror. In first person the camera is in
# its head and its body isn't drawn for the camera (it's on a render layer the camera leaves out), but PXTGI still
# traces it: the mirror shows you, walking and turning as you do, and nothing else shows you (your shadow aside).
#
# What the mirror can show of a character (M):
#   - its mesh: a skinned MeshInstance3D with "pxtgi_traced" true in its metadata (set in this scene on the
#     mannequin's mesh: Mannequin > Mannequin > Armature > GeneralSkeleton > Mannequin, the Inspector's Metadata; an
#     int instead of true is the number of triangles to trace it with) is traced as its own triangles (its coarsest
#     LOD with about 3000, skinned to the pose every frame), each in its surface's color: the mirror shows the
#     character's shape and colors (here the purple joints too). Reflections don't take the screen's view inside its
#     bounds (the side of it the camera sees): they trace the mesh, so it shows its front in third person too;
#   - its physical bones' capsules, which follow the animation while the body isn't limp: a figure of capsules in the
#     character's pose. PXTGI colors a body by the mesh it belongs to, and a bone isn't next to the character's mesh,
#     so the script gives every bone a pxtgi_albedo tag of the mesh's color (T switches them off: gray);
#   - nothing: a character with neither has no shapes, and the mirror shows only the room.
# In third person (C) the camera is behind the mannequin and its back is on screen: with the capsules or nothing
# traced, where a reflected ray passes behind it on screen, the reflection takes its back from the screen. With
# reflections on screen only (R), the mirror shows only what the camera sees (in first person, not you). Reflection probes don't help with a character
# (traced + probes takes probe colors on static bodies only).
#
#   WASD       walk          mouse  look (click to capture it, Esc to let go)
#   3          dance (until you walk)
#   M          the mirror shows: the traced mesh / the bones' capsules / nothing
#   T          the bones' pxtgi_albedo tags on / off
#   R          reflections: traced (on screen and off) / on screen only
#   C          camera: first person / third person
#   P          the mirror: PXTGI's traced reflection / a scene capture (scene_capture_mirror.gd: a second camera
#              renders the mirrored view into a texture the glass shows, as Unreal's SceneCaptureComponent2D)
#   K          the scene capture's resolution: 1024 / 512 / 256 pixels high

const SOURCES := ["the traced mesh", "the bones' capsules", "nothing"]
const WALK_SPEED := 1.3 # m/s, about the Walk clip's pace
const TURN := 0.003 # rad per pixel of mouse motion
const ROOM := 2.6 # how far from the room's middle the mannequin may walk (the walls are at 3)
const BODY_LAYER := 1 << 1 # the mannequin's mesh: drawn for everything but the first person camera
const CaptureMirror := preload("res://demo/editor/rendering/scene_capture_mirror.gd")
const CAPTURE_HEIGHTS := [1024, 512, 256]

@onready var _label: Label = $HUD/Label
@onready var _gi: Node3D = $GI
@onready var _mannequin: Node3D = $Mannequin
@onready var _camera: Camera3D = $Camera3D

var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _head := -1
var _bones: Array[PhysicalBone3D] = []
var _color := Color(0.5, 0.5, 0.5)
var _source := 0
var _tags_on := true
var _first_person := true
var _yaw := 0.0 # the mannequin's heading (0: facing the mirror, -z)
var _pitch := -0.1
var _animation := ""
var _capture: Node3D
var _capture_height := 0


func _ready() -> void:
	_mesh = _mannequin.find_children("*", "MeshInstance3D", true, false)[0]
	_skeleton = _mannequin.find_children("*", "Skeleton3D", true, false)[0]
	_player = _mannequin.find_child("AnimationPlayer", true, false)
	_head = _skeleton.find_bone("Head")
	_mesh.layers = BODY_LAYER
	_mannequin.position = Vector3(0, 0, 1.0) # a few steps back from the mirror
	for bone in _mannequin.find_children("*", "PhysicalBone3D", true, false):
		_bones.append(bone)
	_color = _mesh_color()
	_tag_bones()
	# The scene gives the mesh its pxtgi_traced tag (select Mannequin > ... > GeneralSkeleton > Mannequin: Metadata in
	# the Inspector); M changes it at run time.
	_source = 0 if bool(_mesh.get_meta("pxtgi_traced", false)) else 2
	_set_source()
	_set_camera()
	_play("Idle")
	# The scene capture mirror, on the same glass (a centimeter in front of it), shown with P.
	_capture = CaptureMirror.new()
	_capture.viewer = _camera
	_capture.size = Vector2(2.4, 2.2)
	_capture.position = Vector3(0, 1.4, -2.935)
	_capture.visible = false
	add_child(_capture)
	_show()


# The mannequin's color: its surfaces' albedo colors averaged by their areas (the body, not its thin joint bands).
func _mesh_color() -> Color:
	var sum := Color(0, 0, 0, 0)
	var weight := 0.0
	for i in _mesh.mesh.get_surface_count():
		var material := _mesh.get_active_material(i) as BaseMaterial3D
		if material:
			var area := _surface_area(_mesh.mesh, i)
			sum += material.albedo_color * area
			weight += area
	if weight <= 0.0:
		return Color(0.5, 0.5, 0.5)
	var c := sum / weight
	c.a = 1.0
	return c


func _surface_area(mesh: Mesh, surface: int) -> float:
	var arrays := mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	for t in range(0, idx.size() - 2, 3):
		area += (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]]).length()
	return area * 0.5


func _play(clip: String) -> void:
	if _animation != clip:
		_animation = clip
		_player.play(clip, 0.2)


func _physics_process(delta: float) -> void:
	var input := Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	# The mannequin faces its local +z; turned by _yaw from facing the mirror (-z).
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	if input != Vector2.ZERO:
		var step := (forward * input.y + right * input.x).normalized() * WALK_SPEED * delta
		var p := _mannequin.position + step
		_mannequin.position = Vector3(clampf(p.x, -ROOM, ROOM), 0, clampf(p.z, -ROOM, ROOM))
		_play("Walk")
	elif _animation == "Walk":
		_play("Idle")
	_mannequin.basis = Basis(Vector3.UP, _yaw + PI)


func _process(_delta: float) -> void:
	_set_camera()


# First person: at the eyes (the head bone, a little forward and up), looking where the mannequin faces, tilted by
# the mouse. Third person: behind its right shoulder.
func _set_camera() -> void:
	var look := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	if _first_person:
		var head := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head)).origin
		var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
		_camera.global_transform = Transform3D(look, head + forward * 0.12 + Vector3(0, 0.04, 0))
		_camera.cull_mask = 0xFFFFF & ~BODY_LAYER
	else:
		var back := look * Vector3(0.45, 0.25, 1.9)
		_camera.global_transform = Transform3D(look, _mannequin.global_position + Vector3(0, 1.55, 0) + back)
		_camera.cull_mask = 0xFFFFF


# The traced mesh, the bones' capsules or neither: the mesh's pxtgi_traced flag, the bones' collision shapes.
func _set_source() -> void:
	_mesh.set_meta("pxtgi_traced", _source == 0)
	for bone in _bones:
		for shape in bone.get_children():
			if shape is CollisionShape3D:
				shape.disabled = _source != 1


func _tag_bones() -> void:
	for bone in _bones:
		if _tags_on:
			bone.set_meta("pxtgi_albedo", _color)
		elif bone.has_meta("pxtgi_albedo"):
			bone.remove_meta("pxtgi_albedo")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * TURN
		_pitch = clampf(_pitch - event.relative.y * TURN, -1.2, 1.2)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_3:
			_play("Dance")
		KEY_M:
			_source = (_source + 1) % SOURCES.size()
			_set_source()
		KEY_T:
			_tags_on = not _tags_on
			_tag_bones()
		KEY_R:
			_gi.set("reflection_mode", 1 if int(_gi.get("reflection_mode")) == 2 else 2)
		KEY_C:
			_first_person = not _first_person
			_set_camera()
		KEY_P:
			_capture.visible = not _capture.visible
		KEY_K:
			_capture_height = (_capture_height + 1) % CAPTURE_HEIGHTS.size()
			_capture.set_resolution(CAPTURE_HEIGHTS[_capture_height])
		_:
			return
	_show()


func _show() -> void:
	var text := "A character in a PXTGI mirror: you\n"
	text += "WASD walk   mouse look (click to capture, Esc to let go)   3 dance\n"
	text += "M  the mirror shows: %s\n" % SOURCES[_source]
	text += "T  bone color tags: %s\n" % ["ON" if _tags_on else "OFF (gray)"]
	text += "R  reflections: %s\n" % ["traced, on screen and off" if int(_gi.get("reflection_mode")) == 2 else "on screen only"]
	text += "C  camera: %s
" % ["first person" if _first_person else "third person"]
	text += "P  mirror: %s
" % ["scene capture" if _capture.visible else "PXTGI traced"]
	text += "K  capture resolution: %d high" % CAPTURE_HEIGHTS[_capture_height]
	_label.text = text
