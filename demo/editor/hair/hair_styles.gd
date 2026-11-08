extends Node3D

## Two of Blender's demo hairstyles (long and curly), drawn one way at a time: the Mesh group or the
## ScreenSpace group (PhysXGroom3D.render_mode). Tab switches; in the editor,
## toggle the groups' visibility.

@onready var _mesh: Node3D = $Mesh
@onready var _screen_space: Node3D = $ScreenSpace
@onready var _label: Label = $HUD/Mode


func _ready() -> void:
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_mesh.visible = not _mesh.visible
		_screen_space.visible = not _mesh.visible
		_show()


func _show() -> void:
	_label.text = "%s  (Tab: switch)" % ("Mesh" if _mesh.visible else "Screen Space")
