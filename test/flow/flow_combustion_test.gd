extends SceneTree

# PhysXFlow3D's combustion_* terms and ray_march_step_scale (#10). Three grids 8 m apart, each with the same
# burning emitter (fuel, hot enough to ignite, no smoke of its own), read back after 3 s:
#   - the defaults are the Flow SDK's (4 / 0.25 / 5 / 3 / 0 / 0, step 0.75);
#   - combustion_smoke_per_burn = 0: burning makes no smoke (the default grid's flame is smoky);
#   - combustion_temperature_per_burn = 0: burning adds no heat (cooler than the default grid's flame);
#   - ray_march_step_scale changed on a running grid: it keeps running and drawing.
# Needs a window (headless has no RenderingDevice):
#   godot --path . --script res://test/flow/flow_combustion_test.gd

const AT := [Vector3(-8, 0, 0), Vector3(0, 0, 0), Vector3(8, 0, 0)]

var _flows: Array[Node3D] = []
var _tick := 0
var _pass := true
var _render_calls_before := 0


func _initialize() -> void:
	# A broken test must fail and close its window, not hang.
	create_timer(30.0).timeout.connect(func() -> void:
		print("[flow_combustion] FAIL: timed out")
		quit(1))
	if not ClassDB.class_exists("PhysXFlow3D"):
		print("[flow_combustion] SKIP: this build has no Flow support (flow_sdk=)")
		quit(0)
		return
	var root := Node3D.new()
	get_root().add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 14)
	root.add_child(cam)
	for i in 3:
		var f: Node3D = ClassDB.instantiate("PhysXFlow3D")
		f.cpu_readback = true
		f.position = AT[i]
		root.add_child(f)
		_flows.append(f)
		var e: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
		e.position = AT[i]
		e.radius = 0.35
		e.velocity = Vector3(0, 1, 0)
		e.temperature = 0.5
		e.fuel = 1.0
		e.smoke = 0.0
		root.add_child(e)
		e.flow = e.get_path_to(f)
	var d := _flows[0]
	_check("defaults are the SDK's", is_equal_approx(d.combustion_burn_per_temperature, 4.0) and is_equal_approx(d.combustion_fuel_per_burn, 0.25)
			and is_equal_approx(d.combustion_temperature_per_burn, 5.0) and is_equal_approx(d.combustion_smoke_per_burn, 3.0)
			and d.combustion_divergence_per_burn == 0.0 and d.combustion_buoyancy_per_smoke == 0.0 and is_equal_approx(d.ray_march_step_scale, 0.75),
			"%.2f %.2f %.2f %.2f %.2f %.2f step %.2f" % [d.combustion_burn_per_temperature, d.combustion_fuel_per_burn, d.combustion_temperature_per_burn,
			d.combustion_smoke_per_burn, d.combustion_divergence_per_burn, d.combustion_buoyancy_per_smoke, d.ray_march_step_scale])
	_flows[1].combustion_smoke_per_burn = 0.0
	_flows[2].combustion_temperature_per_burn = 0.0


func _check(label: String, ok: bool, detail: String) -> void:
	print("  [%s] %-56s %s" % ["ok" if ok else "FAIL", label, detail])
	if not ok:
		_pass = false


# The most smoke / heat in the column above a grid's emitter.
func _column_max(f: Node3D, smoke: bool) -> float:
	var m := 0.0
	for k in 12:
		var p: Vector3 = f.position + Vector3(0, 0.2 + k * 0.2, 0)
		m = maxf(m, f.sample_smoke(p) if smoke else f.sample_temperature(p))
	return m


func _physics_process(_delta: float) -> bool:
	if _flows.is_empty():
		return true # skipped: no Flow in this build
	_tick += 1
	if _tick == 120:
		_render_calls_before = int(_flows[0].get_stats().get("render_calls", 0))
		_flows[0].ray_march_step_scale = 2.0
	if _tick == 180:
		for f in _flows:
			var s: Dictionary = f.get_stats()
			_check("grid running", s.running, str(s.error))
		var smoke_default := _column_max(_flows[0], true)
		var smoke_none := _column_max(_flows[1], true)
		var heat_default := _column_max(_flows[0], false)
		var heat_none := _column_max(_flows[2], false)
		_check("the default flame makes smoke", smoke_default > 0.1, "%.3f" % smoke_default)
		_check("smoke_per_burn = 0: burning makes no smoke", smoke_none < 0.1 * smoke_default, "%.3f vs %.3f" % [smoke_none, smoke_default])
		_check("temperature_per_burn = 0: the flame is cooler", heat_none < 0.8 * heat_default, "%.3f vs %.3f" % [heat_none, heat_default])
		var calls := int(_flows[0].get_stats().get("render_calls", 0))
		_check("step scale 2.0: still drawing", is_equal_approx(_flows[0].ray_march_step_scale, 2.0) and calls > _render_calls_before,
				"render calls %d -> %d" % [_render_calls_before, calls])
		print("[flow_combustion] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false
