extends Node3D

## Two of Blender's demo hairstyles (long and curly), simulated on heads that move: each head turns, nods, tilts or
## sways on its stand, and the hair swings with it, stays off the head and the stand's neck and shoulders (the Body's
## capsules, in PhysXGroom3D.colliders) and blows in the wind. Each head has the hair twice, one per render mode
## (PhysXGroom3D.render_mode), one shown at a time; a hidden groom isn't simulated.
##   1 still, 2 turn, 3 nod, 4 tilt, 5 sway   G wind   R reset   Tab Mesh / Screen Space

enum Motion { STILL, TURN, NOD, TILT, SWAY }
const MOTION_NAMES := ["still", "turn", "nod", "tilt", "sway"]

var _motion := Motion.TURN
var _wind := false
var _screen_space := true
var _time := 0.0
var _rest_x := {}

@onready var _help: Label = $HUD/Help


func _ready() -> void:
	for bust in get_tree().get_nodes_in_group("bust"):
		_rest_x[bust] = bust.position.x
	_show_mode()


func _hair() -> Array:
	return get_tree().get_nodes_in_group("mesh_hair") + get_tree().get_nodes_in_group("screen_hair")


func _show_mode() -> void:
	for hair in get_tree().get_nodes_in_group("mesh_hair"):
		hair.visible = not _screen_space
	for hair in get_tree().get_nodes_in_group("screen_hair"):
		hair.visible = _screen_space
	_help.text = "%s   motion: %s   wind: %s\n1 still  2 turn  3 nod  4 tilt  5 sway   G wind   R reset   Tab render mode" % [
		"Screen Space" if _screen_space else "Mesh", MOTION_NAMES[_motion], "on" if _wind else "off"]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_motion = event.keycode - KEY_1
			_time = 0.0
		KEY_G:
			_wind = not _wind
			if not _wind:
				for hair in _hair():
					hair.wind = Vector3.ZERO
		KEY_R:
			_time = 0.0
			_pose(0.0)
			for hair in _hair():
				hair.reset_simulation()
		KEY_TAB:
			_screen_space = not _screen_space
		_:
			return
	_show_mode()


func _process(delta: float) -> void:
	_time += delta
	_pose(_time)
	if _wind:
		# Gusts from the front right, 3 to 11 m/s.
		var gust := 7.0 + 3.0 * sin(_time * 1.3) + sin(_time * 3.7)
		for hair in _hair():
			hair.wind = Vector3(-0.8, 0.1, -0.6).normalized() * gust


# Where the heads are t seconds into the motion: from rest, eased in over the first second.
func _pose(t: float) -> void:
	var ease_in := clampf(t, 0.0, 1.0)
	for bust in get_tree().get_nodes_in_group("bust"):
		var head: Node3D = bust.get_node("Head")
		head.rotation = Vector3.ZERO
		bust.position.x = _rest_x[bust]
		match _motion:
			Motion.TURN:
				# Looking left and right, a quick turn each way and a pause.
				var s := sin(t * TAU * 0.45)
				head.rotation.y = 0.9 * ease_in * signf(s) * pow(absf(s), 0.4)
			Motion.NOD:
				head.rotation.x = 0.35 * ease_in * sin(t * TAU * 0.8)
			Motion.TILT:
				# Ear to shoulder, each side: the long hair falls on the shoulders.
				head.rotation.z = 0.5 * ease_in * sin(t * TAU * 0.3)
			Motion.SWAY:
				bust.position.x = _rest_x[bust] + 0.12 * ease_in * sin(t * TAU * 0.7)
