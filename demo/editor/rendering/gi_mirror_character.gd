extends Node3D

# A character in a PXTGI mirror: the mannequin plays an animation in front of a wall mirror. The camera starts past
# it, looking at the mirror, so the mannequin is off screen: the screen has none of it, and PXTGI traces the
# reflection against the scene's shapes instead.
#
# What the mirror can show of a character (M):
#   - its mesh: a skinned MeshInstance3D with "pxtgi_traced" true in its metadata is traced as its own triangles (its
#     coarsest LOD with about 3000, skinned to the pose every frame), each in its surface's color: the mirror shows the
#     character's shape and colors (here the purple joints too);
#   - its physical bones' capsules, which follow the animation while the body isn't limp: a figure of capsules in the
#     character's pose. PXTGI colors a body by the mesh it belongs to, and a bone isn't next to the character's mesh,
#     so the script gives every bone a pxtgi_albedo tag of the mesh's color (T switches them off: gray);
#   - nothing: a character with neither has no shapes, and the mirror shows only the room.
# With reflections on screen only (R), the mirror is black: nothing it shows is on screen. Behind the mannequin (C),
# its back is on screen; where a reflected ray passes behind it on screen, the reflection may take the back from the
# screen. Reflection probes don't help with a character (traced + probes takes probe colors on static bodies only).
#
#   1 / 2 / 3  idle / walk / dance
#   M          the mirror shows: the traced mesh / the bones' capsules / nothing
#   T          the bones' pxtgi_albedo tags on / off
#   R          reflections: traced (on screen and off) / on screen only
#   C          camera: past the mannequin / behind it
#   WASD, Space / Ctrl, Shift, hold right mouse: fly

const ANIMATIONS := ["Idle", "Walk", "Dance"]
const SOURCES := ["the traced mesh", "the bones' capsules", "nothing"]
# Camera [position, look-at target]: past the mannequin (it's off screen) and behind it (its back is on screen).
const VIEWS := [
	[Vector3(0.9, 1.5, -1.0), Vector3(-0.4, 1.0, -3.0)],
	[Vector3(0.7, 1.6, 1.6), Vector3(-0.2, 1.15, -3.0)],
]
const VIEW_NAMES := ["the mannequin off screen", "behind the mannequin"]

@onready var _label: Label = $HUD/Label
@onready var _gi: Node3D = $GI
@onready var _mannequin: Node3D = $Mannequin
@onready var _camera: Camera3D = $Camera3D

var _mesh: MeshInstance3D
var _bones: Array[PhysicalBone3D] = []
var _color := Color(0.5, 0.5, 0.5)
var _animation := 0
var _view := 0
var _source := 0
var _tags_on := true


func _ready() -> void:
	_set_view()
	_mesh = _mannequin.find_children("*", "MeshInstance3D", true, false)[0]
	for bone in _mannequin.find_children("*", "PhysicalBone3D", true, false):
		_bones.append(bone)
	_color = _mesh_color()
	_tag_bones()
	_set_source()
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


func _set_view() -> void:
	var view: Array = VIEWS[_view]
	_camera.position = view[0]
	_camera.look_at(view[1])


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
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3:
			_animation = event.keycode - KEY_1
			var player: AnimationPlayer = _mannequin.find_child("AnimationPlayer", true, false)
			player.play(ANIMATIONS[_animation])
		KEY_M:
			_source = (_source + 1) % SOURCES.size()
			_set_source()
		KEY_T:
			_tags_on = not _tags_on
			_tag_bones()
		KEY_R:
			_gi.set("reflection_mode", 1 if int(_gi.get("reflection_mode")) == 2 else 2)
		KEY_C:
			_view = (_view + 1) % VIEWS.size()
			_set_view()
		_:
			return
	_show()


func _show() -> void:
	var text := "A character in a PXTGI mirror\n"
	text += "1 / 2 / 3  animation: %s\n" % ANIMATIONS[_animation]
	text += "M  the mirror shows: %s\n" % SOURCES[_source]
	text += "T  bone color tags: %s\n" % ["ON" if _tags_on else "OFF (gray)"]
	text += "R  reflections: %s\n" % ["traced, on screen and off" if int(_gi.get("reflection_mode")) == 2 else "on screen only"]
	text += "C  camera: %s\n" % VIEW_NAMES[_view]
	text += "WASD, Space / Ctrl, Shift, hold right mouse: fly"
	_label.text = text
