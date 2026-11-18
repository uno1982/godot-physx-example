extends Node3D

# PXTGI and materials it can't read in full: a closed room lit by one light under the ceiling, its left and back walls
# a StandardMaterial3D whose color is all in its texture (orange; its albedo color is white), its right wall a
# ShaderMaterial (teal). Off screen, PXTGI reads the first as white (its albedo color, not the texture's colors) and
# the second as neutral gray, so the bounce light and the mirror ball's view of the wall behind the camera come out
# wrong. Select the GI node and use Measure Materials... in its inspector: Tag Selected gives the walls a
# pxtgi_albedo of their measured color (save the scene), and the bounce light takes their colors. GI runs in the
# running scene only (not in the editor).
#
#   T        the walls' pxtgi_albedo tags off / on (to compare; needs them tagged first)
#   WASD, Space / Ctrl, Shift, hold right mouse: fly

@onready var _label: Label = $HUD/Label

var _saved := {} # material -> its pxtgi_albedo, while switched off
var _tags_on := true


func _ready() -> void:
	_show()


func _materials() -> Array[Material]:
	var out: Array[Material] = []
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var m := mesh.get_active_material(0)
		if m and not out.has(m):
			out.append(m)
	return out


func _tagged_count() -> int:
	var n := 0
	for m in _materials():
		n += 1 if m.has_meta("pxtgi_albedo") or _saved.has(m) else 0
	return n


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_T:
		_tags_on = not _tags_on
		for m in _materials():
			if _tags_on and _saved.has(m):
				m.set_meta("pxtgi_albedo", _saved[m])
			elif not _tags_on and m.has_meta("pxtgi_albedo"):
				_saved[m] = m.get_meta("pxtgi_albedo")
				m.remove_meta("pxtgi_albedo")
		if _tags_on:
			_saved.clear()
		_show()


func _show() -> void:
	var tagged := _tagged_count()
	var text := "PXTGI and material colors\n"
	if tagged == 0:
		text += "No material here has a pxtgi_albedo tag: off screen, PXTGI sees the orange walls as white and the teal one as gray.\nIn the editor: select GI, Measure Materials..., Tag Selected, save, run again."
	else:
		text += "T  albedo tags: %s (%d materials tagged)" % ["ON" if _tags_on else "OFF", tagged]
	text += "\nWASD, Space / Ctrl, Shift, hold right mouse: fly"
	_label.text = text
