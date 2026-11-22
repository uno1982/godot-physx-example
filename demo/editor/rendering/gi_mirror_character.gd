extends Node3D

# A character in a PXTGI mirror: the mannequin plays an animation in front of a wall mirror. The camera starts past
# it, looking at the mirror, so the mannequin is off screen: the screen has none of it, and PXTGI traces the
# reflection against the collision shapes instead. A character's shapes are its physical bones' capsules, which
# follow the animation while the body isn't limp, so the mirror shows a figure of capsules that moves with it: the
# character's pose and its color, not its mesh. Without physical bones (or with them off, B), a character has no
# shapes and the mirror shows only the room. With reflections on screen only (R), the mirror is black: nothing it
# shows is on screen.
#
# Behind the mannequin (C), its back is on screen, but not the front the mirror shows. A reflected ray that passes
# behind what's on screen (the back faces away from it, or the ray never comes up to it) doesn't take the screen's
# view of it when the collision shapes have that surface (the capsules): they are traced, as off screen. With the
# bones off, nothing has it, and the mirror shows the screen's view of the back, the nearest PXTGI has.
#
# A physical bone's color: PXTGI colors a body by the mesh it belongs to, and a bone isn't next to the character's
# mesh, so it would be neutral gray. The script gives every bone a pxtgi_albedo tag of the mesh's color (T switches
# them off). Reflection probes don't help with a character (traced + probes takes probe colors on static bodies only).
#
#   1 / 2 / 3  idle / walk / dance
#   B          the physical bones traced or not (their collision shapes on / off)
#   T          the bones' pxtgi_albedo tags on / off
#   R          reflections: traced (on screen and off) / on screen only
#   WASD, Space / Ctrl, Shift, hold right mouse: fly

const ANIMATIONS := ["Idle", "Walk", "Dance"]
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

var _bones: Array[PhysicalBone3D] = []
var _color := Color(0.5, 0.5, 0.5)
var _animation := 0
var _view := 0
var _bones_on := true
var _tags_on := true


func _ready() -> void:
	_set_view()
	for bone in _mannequin.find_children("*", "PhysicalBone3D", true, false):
		_bones.append(bone)
	_color = _mesh_color()
	_tag_bones()
	_show()


# The mannequin's color: its surfaces' albedo colors averaged by their areas (the body, not its thin joint bands).
func _mesh_color() -> Color:
	for mesh: MeshInstance3D in _mannequin.find_children("*", "MeshInstance3D", true, false):
		var sum := Color(0, 0, 0, 0)
		var weight := 0.0
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			if material:
				var area := _surface_area(mesh.mesh, i)
				sum += material.albedo_color * area
				weight += area
		if weight > 0.0:
			var c := sum / weight
			c.a = 1.0
			return c
	return Color(0.5, 0.5, 0.5)


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
		KEY_B:
			_bones_on = not _bones_on
			for bone in _bones:
				for shape in bone.get_children():
					if shape is CollisionShape3D:
						shape.disabled = not _bones_on
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
	text += "B  physical bones traced: %s (%d bones)\n" % ["ON" if _bones_on else "OFF", _bones.size()]
	text += "T  bone color tags: %s\n" % ["ON" if _tags_on else "OFF (gray)"]
	text += "R  reflections: %s\n" % ["traced, on screen and off" if int(_gi.get("reflection_mode")) == 2 else "on screen only"]
	text += "C  camera: %s\n" % VIEW_NAMES[_view]
	text += "WASD, Space / Ctrl, Shift, hold right mouse: fly"
	_label.text = text
