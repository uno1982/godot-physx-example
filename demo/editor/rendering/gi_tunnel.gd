extends Node3D

# PXTGI, the module's global illumination (PXTGI3D, experimental), walking from light into dark: a room lit by the sun
# through a window in its left wall, and a closed tunnel 20 m long off its back wall, with no light of its own. The
# environment's ambient and reflected light come from the sky (Godot's defaults) and the camera's auto exposure is on,
# as a game's would be. PXTGI's light replaces Godot's ambient light where its rays hit something; where they miss
# (out of the window), the sky's ambient light fills in that share. Walk slowly down the tunnel and look down: it should
# stay dark. (PXTGI used to carry the room's hit fraction in with the camera, so a few percent of the sky's light
# glowed on the tunnel floor, following the view until it turned away; auto exposure made it plain.
# test/gpu/pxtgi_light_carry_test.gd checks it.) GI runs in the running scene only (not in the editor).
#
#   G        GI: PXTGI / Godot's SDFGI (decent settings) / none
#   B        debug view: off / world only / world hits / world position
#   M        multi-bounce (the radiance cache: off-screen hits carry bounce light) on / off
#   E        auto exposure on / off
#   R        back to the room
#   WASD, Space / Ctrl, Shift, hold right mouse: fly

@onready var _env: Environment = $WorldEnvironment.environment
@onready var _gi: Node3D = $GI
@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $HUD/Label

var _gi_mode := 0 # 0 PXTGI, 1 SDFGI, 2 none
var _start: Transform3D


func _ready() -> void:
	_start = _camera.transform
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _set_gi(mode: int) -> void:
	_gi_mode = mode
	_gi.visible = mode == 0
	_env.sdfgi_enabled = mode == 1
	if mode == 1:
		_env.sdfgi_cascades = 4
		_env.sdfgi_min_cell_size = 0.1
		_env.sdfgi_use_occlusion = true
		_env.sdfgi_bounce_feedback = 0.5
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_64)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
		RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_G:
			_set_gi((_gi_mode + 1) % 3)
		KEY_M:
			_gi.set("multi_bounce", not _gi.get("multi_bounce"))
		KEY_B:
			var views: Array[int] = [0, 3, 4, 5]
			_gi.set("debug", views[(views.find(int(_gi.get("debug"))) + 1) % views.size()])
		KEY_E:
			var attributes := _camera.attributes as CameraAttributesPractical
			attributes.auto_exposure_enabled = not attributes.auto_exposure_enabled
		KEY_R:
			_camera.transform = _start
		_:
			return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var gi_names: Array[String] = ["PXTGI", "Godot SDFGI (decent)", "none"]
	var debug_names := {0: "off", 3: "world only", 4: "world hits", 5: "world position"}
	var dbg: String = debug_names.get(int(_gi.get("debug")), "?") if _gi_mode == 0 else "-"
	var exposure := (_camera.attributes as CameraAttributesPractical).auto_exposure_enabled
	var vp := get_viewport().get_viewport_rid()
	_label.text = "GI: %s [G]   debug: %s [B]   multi-bounce: %s [M]   auto exposure: %s [E]\nWASD + right mouse: fly   Shift: fast   R: back to the room\nFPS %d   %s" % [
		gi_names[_gi_mode], dbg, "on" if _gi.get("multi_bounce") else "off", "on" if exposure else "off",
		Engine.get_frames_per_second(), RenderTime.gpu(vp)]
