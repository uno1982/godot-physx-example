extends Node3D

# PXTGI, the module's global illumination (PXTGI3D, experimental), in a sunlit courtyard with a mirror sphere, under the light shafts demo's sky
# and sun (its light shafts, lens flare and lens dirt). Everything is a node in the scene: edit the walls, the sphere's
# material, the probe or the GI node's settings directly. GI runs in the editor viewport too.
#
#   G        GI: PXTGI / Godot's SDFGI (decent settings) / none
#   R        our reflections: traced + probes / traced / screen space / Godot's own (traced + probes: PXTGI draws
#            the probes whose intensity is 0 itself, tracing below the roughness cutoff)
#   F        Godot's screen-space reflections (SSR) on / off
#   P        reflection probe on / off (inside its box the probe's cubemap replaces the traced reflections, as it
#            does SDFGI's: compare the mirror sphere)
#   B        debug view: off / world only / world hits / world position
#   M        multi-bounce (the radiance cache: off-screen hits carry bounce light) on / off
#   L        lens flare and lens dirt on / off
#   arrows   move the sun
#   WASD, Space / Ctrl, Shift, hold right mouse: fly

@onready var _env: Environment = $WorldEnvironment.environment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _gi: Node3D = $GI
@onready var _probe: ReflectionProbe = $ReflectionProbe
@onready var _label: Label = $HUD/Label

var _gi_mode := 0 # 0 PXTGI, 1 SDFGI, 2 none
var _sun_distance := 0.0
var _sun_yaw := 0.0
var _sun_pitch := 0.0


func _ready() -> void:
	var at := _sun.position
	_sun_distance = at.length()
	_sun_yaw = atan2(at.x, at.z)
	_sun_pitch = asin(at.y / _sun_distance)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _set_gi(mode: int) -> void:
	_gi_mode = mode
	# PXTGI runs while its node is visible: hidden, Godot's own GI step is back.
	_gi.visible = mode == 0
	# Godot's SDFGI at settings a project would ship for a small, detailed space.
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
		KEY_R:
			# Traced + probes -> traced -> screen space -> Godot's own.
			_gi.set("reflection_mode", (int(_gi.get("reflection_mode")) + 3) % 4)
		KEY_F:
			_env.ssr_enabled = not _env.ssr_enabled
		KEY_P:
			_probe.visible = not _probe.visible
		KEY_M:
			_gi.set("multi_bounce", not _gi.get("multi_bounce"))
		KEY_B:
			var views: Array[int] = [0, 3, 4, 5]
			_gi.set("debug", views[(views.find(int(_gi.get("debug"))) + 1) % views.size()])
		KEY_L:
			for lens in ["LensDirt", "LensFlare"]:
				var node := _sun.get_node_or_null(lens) as Node3D
				if node:
					node.visible = not node.visible
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var turn := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_down", "ui_up"))
	if turn != Vector2.ZERO:
		_sun_yaw += turn.x * 0.6 * delta
		_sun_pitch = clampf(_sun_pitch + turn.y * 0.4 * delta, 0.03, 1.4)
		var at := Vector3(sin(_sun_yaw) * cos(_sun_pitch), sin(_sun_pitch), cos(_sun_yaw) * cos(_sun_pitch)) * _sun_distance
		_sun.transform = Transform3D(Basis.looking_at(-at), at)

	var gi_names: Array[String] = ["PXTGI", "Godot SDFGI (decent)", "none"]
	var refl_names: Array[String] = ["Godot's own", "screen space", "traced", "traced + probes"]
	var debug_names := {0: "off", 3: "world only", 4: "world hits", 5: "world position"}
	var refl: String = refl_names[int(_gi.get("reflection_mode"))] if _gi_mode == 0 else "-"
	var dbg: String = debug_names.get(int(_gi.get("debug")), "?") if _gi_mode == 0 else "-"
	var lens_on := (_sun.get_node_or_null("LensDirt") as Node3D).visible
	var vp := get_viewport().get_viewport_rid()
	_label.text = "GI: %s [G]   reflections: %s [R]   Godot SSR: %s [F]   probe: %s [P]   debug: %s [B]   multi-bounce: %s [M]   lens: %s [L]\narrows: move the sun   WASD + right mouse: fly   Shift: fast\nFPS %d   %s" % [
		gi_names[_gi_mode], refl, "on" if _env.ssr_enabled else "off", "on" if _probe.visible else "off", dbg, "on" if _gi.get("multi_bounce") else "off", "on" if lens_on else "off",
		Engine.get_frames_per_second(), RenderTime.gpu(vp)]
