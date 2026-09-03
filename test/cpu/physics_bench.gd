extends SceneTree

# Headless physics benchmark: pile up N dynamic boxes on a static floor, let them
# collide and settle, and measure the engine-side physics step time.
#
#   godot --headless --path . --script res://test/cpu/physics_bench.gd
#
# The physics backend is whatever project.godot selects (locked at startup), so
# run once per engine, flipping physics/3d/physics_engine between runs.
#
# Output: one line per body count:
#   [bench] engine=<name> bodies=<n> step_avg_ms=<a> step_med_ms=<m> step_p95_ms=<p> active=<k>

const BODY_COUNTS := [1000, 5000, 10000, 25000]

# Two measurement windows per body count:
#   impact  -- the pile collapsing (max contact load)
#   settled -- after everything has come to rest (tests sleeping)
const WARMUP := 20
const IMPACT_TICKS := 130
const SETTLE_TICKS := 500
const SETTLED_TICKS := 100

var _engine := "?"
var _phase := 0 # 0 warmup, 1 impact-measure, 2 settle, 3 settled-measure
var _count_idx := 0
var _tick := 0
var _impact: PackedFloat64Array = PackedFloat64Array()
var _settled: PackedFloat64Array = PackedFloat64Array()
var _root: Node3D
var _bodies: Array[RigidBody3D] = []

func _initialize() -> void:
	_engine = str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	# Keep the run deterministic-ish and fast.
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0

	_root = Node3D.new()
	get_root().add_child(_root)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(200, 2, 200)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -1, 0)
	_root.add_child(floor_body)

	_spawn_pile(BODY_COUNTS[0])
	print("[bench] engine=%s  warming up..." % _engine)

func _spawn_pile(n: int) -> void:
	for b in _bodies:
		b.queue_free()
	_bodies.clear()
	# Grid footprint ~ cube-root spacing so they actually stack and collide.
	var per_side := int(ceil(pow(float(n), 1.0 / 3.0)))
	var spacing := 1.35
	var i := 0
	for x in per_side:
		for y in per_side:
			for z in per_side:
				if i >= n:
					break
				var rb := RigidBody3D.new()
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3.ONE
				cs.shape = bs
				rb.add_child(cs)
				rb.position = Vector3(
					(x - per_side * 0.5) * spacing,
					1.0 + y * spacing,
					(z - per_side * 0.5) * spacing)
				_root.add_child(rb)
				_bodies.append(rb)
				i += 1

func _physics_process(_delta: float) -> bool:
	_tick += 1
	var ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	match _phase:
		0:
			if _tick >= WARMUP:
				_phase = 1
				_tick = 0
		1:
			_impact.append(ms)
			if _tick >= IMPACT_TICKS:
				_phase = 2
				_tick = 0
		2:
			if _tick >= SETTLE_TICKS:
				_phase = 3
				_tick = 0
		3:
			_settled.append(ms)
			if _tick >= SETTLED_TICKS:
				_report()
				_count_idx += 1
				if _count_idx >= BODY_COUNTS.size():
					quit(0)
					return true
				_spawn_pile(BODY_COUNTS[_count_idx])
				_impact = PackedFloat64Array()
				_settled = PackedFloat64Array()
				_phase = 0
				_tick = 0
	return false

func _stats(samples: PackedFloat64Array) -> Dictionary:
	var arr := Array(samples)
	arr.sort()
	var n := maxi(arr.size(), 1)
	var sum := 0.0
	for v in arr:
		sum += v
	return {
		"med": arr[n / 2] if arr.size() > 0 else 0.0,
		"avg": sum / n,
		"p95": arr[int(n * 0.95)] if arr.size() > 0 else 0.0,
	}

func _report() -> void:
	var im := _stats(_impact)
	var se := _stats(_settled)
	var active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	print("[bench] engine=%s bodies=%d  impact_med=%.2f impact_p95=%.2f  settled_med=%.3f settled_active=%d" % [
		_engine, BODY_COUNTS[_count_idx], im.med, im.p95, se.med, active])

