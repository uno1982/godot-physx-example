extends SceneTree

# Verifies Area3D-vs-Area3D overlap detection: PhysX reports no trigger-trigger
# event on its own (see godot_physx_area_3d.h), so this backend polls it
# manually every step. Confirms the poll actually respects Area3D.monitoring:
# a monitoring probe sees area_entered/area_exited on the stationary target,
# a non-monitoring probe sees nothing at all despite taking the same path.

var _target: Area3D
var _probe_on: Area3D
var _probe_off: Area3D
var _tick := 0

var _on_entered := 0
var _on_exited := 0
var _off_entered := 0
var _off_exited := 0

func _make_area(p_monitoring: bool, p_size: Vector3 = Vector3(1, 1, 1)) -> Area3D:
	var a := Area3D.new()
	a.monitoring = p_monitoring
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = p_size
	cs.shape = box
	a.add_child(cs)
	return a

func _initialize() -> void:
	print("[area_area] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	# Stationary target box, wide enough on X to span both probes' fall lines
	# (x=0 and x=3) -- default monitorable=true.
	_target = _make_area(false, Vector3(8, 1, 1))
	_target.name = "Target"
	_target.position = Vector3.ZERO
	root.add_child(_target)

	# Falls straight through the target; monitoring left at its default (true).
	_probe_on = _make_area(true)
	_probe_on.name = "ProbeMonitoring"
	_probe_on.position = Vector3(0, 8, 0)
	_probe_on.area_entered.connect(func(a): _on_entered += 1; print("[area_area]   ProbeMonitoring area_entered: ", a.name))
	_probe_on.area_exited.connect(func(a): _on_exited += 1; print("[area_area]   ProbeMonitoring area_exited: ", a.name))
	root.add_child(_probe_on)

	# Same fall, offset 3m away on X from the monitoring probe (well clear of
	# its 1x1x1 box) so the two probes never overlap EACH OTHER -- only
	# monitoring is different between them, not what they pass through.
	_probe_off = _make_area(false)
	_probe_off.name = "ProbeNotMonitoring"
	_probe_off.position = Vector3(3, 8, 0)
	_probe_off.area_entered.connect(func(a): _off_entered += 1; print("[area_area]   ProbeNotMonitoring area_entered (SHOULD NOT HAPPEN): ", a.name))
	_probe_off.area_exited.connect(func(a): _off_exited += 1; print("[area_area]   ProbeNotMonitoring area_exited (SHOULD NOT HAPPEN): ", a.name))
	root.add_child(_probe_off)

	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1

	# Both probes fall from y=8 to y=-8 over 160 ticks, straight down, passing
	# through the target box (size 8x1x1, spanning both probes' X) around the
	# midpoint. They stay 3m apart on X the whole time, so they never overlap
	# each other -- only the target.
	if _tick <= 160:
		var t := float(_tick) / 160.0
		var y := 8.0 - 16.0 * t
		_probe_on.position = Vector3(0, y, 0)
		_probe_off.position = Vector3(3, y, 0)

	# A little slack past the fall's end for the last poll's exit event to
	# reach call_queries() before the check below reads the counters.
	if _tick >= 200:
		var on_ok := _on_entered >= 1 and _on_exited >= 1
		var off_ok := _off_entered == 0 and _off_exited == 0
		print("[area_area] monitoring probe: entered=%d exited=%d -> %s" % [_on_entered, _on_exited, "PASS" if on_ok else "FAIL"])
		print("[area_area] non-monitoring probe: entered=%d exited=%d -> %s" % [_off_entered, _off_exited, "PASS" if off_ok else "FAIL"])
		var ok := on_ok and off_ok
		print("[area_area] overall -> %s" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false
