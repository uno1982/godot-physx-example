extends Node3D

# Node-authored cloth demo -- select a cloth to use its gizmo and inspector. Every piece -- the wind volume,
# the flag and the banner -- is a real scene node, so you can select a cloth,
# drag its grid handles, move its pins and tweak its inspector in the editor.
# Press Play and the wind gusts.
#
#   SPACE  pause/resume the cloth     R  reset     ESC  quit

@onready var _wind: Area3D = $Wind
@onready var _cloths: Array = [$Flag, $Banner]
@onready var _hud: Label = $HUD/Label
var _t := 0.0
var _base := 12.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				for c in _cloths:
					c.simulating = not c.simulating
			KEY_R:
				for c in _cloths:
					c.reset()
			KEY_ESCAPE:
				get_tree().quit()

func _physics_process(delta: float) -> void:
	_t += delta
	var swell := 0.6 + 0.4 * sin(_t * 0.7)
	_wind.wind_force_magnitude = _base * clampf(swell + 0.15 * sin(_t * 3.9), 0.0, 1.4)

func _process(_dt: float) -> void:
	_hud.text = "PhysXCloth3D showcase (node-based)   SPACE pause   R reset   ESC\nwind: %4.1f   flag verts: %d   FPS: %d" % [
		_wind.wind_force_magnitude, $Flag.get_vertex_count(), Engine.get_frames_per_second()]
