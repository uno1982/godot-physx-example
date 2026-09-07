extends SceneTree

# Smoke test for demo/cpu/physx_ballpit.tscn: balls settle into a pile in the
# pit (none escape, none NaN), and the wrecking ball plows into the pile.

var _scene: Node3D
var _t := 0
var _pile_top := 0.0
var _flung := false


func _initialize() -> void:
	print("[ballpit] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	_scene = load("res://demo/cpu/physx_ballpit.tscn").instantiate()
	get_root().add_child(_scene)
	await process_frame
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	var bodies: Array = _scene._bodies
	if bodies.is_empty():
		return

	var lo := 1e9
	var hi := -1e9
	var escaped := 0
	var nan := 0
	for i in bodies.size():
		var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(bodies[i])
		if not st:
			continue
		var p := st.transform.origin
		if is_nan(p.x) or is_nan(p.y):
			nan += 1
			continue
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		var lim: float = _scene.PIT.x + 2.5
		if absf(p.x) > lim or absf(p.z) > lim or p.y < -3.0:
			escaped += 1

	if nan > 0:
		printerr("[ballpit] FAIL  %d balls NaN at tick %d" % [nan, _t])
		quit(1)
	if escaped > bodies.size() / 40:
		printerr("[ballpit] FAIL  %d balls escaped the pit at tick %d" % [escaped, _t])
		quit(1)

	if _t == 420:
		_pile_top = hi
		print("  settled: pile y=%.2f..%.2f" % [lo, hi])
		# drop the wrecking ball straight down onto the pile (headless: no camera aim)
		_scene._wreck.gravity_scale = 1.0
		_scene._wreck.global_position = Vector3(0, _pile_top + 10.0, 0)
		_scene._wreck.linear_velocity = Vector3(0, -28.0, 0)
		_flung = true

	if _t == 620:
		var wy: float = _scene._wreck.position.y
		if _flung and wy < _pile_top + 3.0 and wy > -3.0:
			print("[ballpit] PASS  pile held, wrecking ball drove into it to y=%.1f (pile top %.1f), no escapes/NaN" % [wy, _pile_top])
			quit(0)
			return
		printerr("[ballpit] FAIL  wrecking ball at y=%.1f, pile top %.1f" % [wy, _pile_top])
		quit(1)
