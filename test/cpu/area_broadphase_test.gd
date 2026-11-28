extends SceneTree

# Area-vs-area polling with many areas (#38): each monitoring area only looks at the areas its bounds meet, and the
# events are still right while areas move.
#   1. A monitoring area sweeps along a row of 20 monitorable areas: each enters once and exits once, in row order.
#   2. A monitorable area moves through a monitoring area that stays put: one enter, one exit.
#   3. Among 9,300 areas, 930 of them monitoring, the area-overlap polling takes under 15 ms a step (it checked every
#      monitoring x monitorable pair: ~53 ms, now ~0.7 ms on the dev machine).
#   godot --headless --path . --script res://test/cpu/area_broadphase_test.gd

const FILLER := 9278 # + the row, the sweeper and the two of check 2 = 9,300
const FILLER_MONITORING := 928
const ROW := 20
const STEPS := 450
var _t := 0
var _ok := true
var _space: RID
var _sweeper: Area3D
var _watcher: Area3D
var _mover: Area3D
var _row: Array[Area3D] = []
var _sweep_events := PackedStringArray()
var _watch_events := PackedStringArray()
var _overlap_sum := 0.0
var _overlap_n := 0


func _check(cond: bool, msg: String) -> void:
	print("[area-broadphase] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _area(pos: Vector3, radius: float, monitoring: bool, monitorable: bool) -> Area3D:
	var a := Area3D.new()
	a.monitoring = monitoring
	a.monitorable = monitorable
	a.position = pos
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	a.add_child(cs)
	get_root().add_child(a)
	return a


func _initialize() -> void:
	print("[area-broadphase] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	# Filler on a grid 20 m below, spheres 1 m wide 1.03 m apart (none touch).
	var side := ceili(sqrt(float(FILLER)))
	var step := 100.0 / side
	for i in FILLER:
		_area(Vector3((i % side) * step - 50.0, -20.0, (i / side) * step - 50.0), 0.5, i < FILLER_MONITORING, true)
	for i in ROW:
		var a := _area(Vector3(-28.5 + i * 3.0, 0, 0), 0.5, false, true)
		a.name = "Row%02d" % i
		_row.append(a)
	_sweeper = _area(Vector3(-32, 0, 0), 0.5, true, false)
	_sweeper.area_entered.connect(func(o: Area3D) -> void: _sweep_events.append("+" + o.name))
	_sweeper.area_exited.connect(func(o: Area3D) -> void: _sweep_events.append("-" + o.name))
	_watcher = _area(Vector3(0, 10, 0), 1.0, true, false)
	_watcher.area_entered.connect(func(o: Area3D) -> void: _watch_events.append("+" + o.name))
	_watcher.area_exited.connect(func(o: Area3D) -> void: _watch_events.append("-" + o.name))
	_mover = _area(Vector3(-10, 10, 0), 0.5, false, true)
	_mover.name = "Mover"
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t == 1:
		_space = _sweeper.get_world_3d().space
	# The sweeper crosses the row (-32 -> +32 m) over steps 20..420; the mover crosses the watcher (-10 -> +10 m).
	if _t >= 20 and _t <= 420:
		_sweeper.position.x = -32.0 + (_t - 20) * 0.16
		_mover.position.x = -10.0 + (_t - 20) * 0.05
	if _t > 60 and _t <= 360:
		_overlap_sum += float(PhysX.space_get_step_stats(_space).get("area_overlaps_usec", 0))
		_overlap_n += 1
	if _t == STEPS:
		var want := PackedStringArray()
		for a in _row:
			want.append("+" + a.name)
			want.append("-" + a.name)
		_check(_sweep_events == want, "sweeper: each row area entered then exited, in row order (%d events: %s ...)" % [_sweep_events.size(), " ".join(_sweep_events.slice(0, 6))])
		_check(_watch_events == PackedStringArray(["+Mover", "-Mover"]), "watcher: the moving area entered and exited (%s)" % " ".join(_watch_events))
		var mean_ms := _overlap_sum / maxi(_overlap_n, 1) / 1000.0
		_check(mean_ms < 15.0, "area-overlap polling with 930 of 9,300 areas monitoring: %.2f ms a step (< 15; ~53 before #38)" % mean_ms)
		print("[area-broadphase] RESULT: %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
