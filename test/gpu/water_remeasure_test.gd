extends SceneTree

# PhysXWaterSurface3D.remeasure_seabed(), and a PhysXBuoyancy3D finding a wake
# added or removed after its READY. Needs a windowed run (the water simulates on
# the GPU).
#
# Each lake sits over its own floor, with a wall waiting under the floor.
# - Same ripple on "kept" (re-measured) and "control": the heights must not differ.
# - The wall of "walled" comes up and it's re-measured: the shoreline moves, and
#   the ripple on one side no longer reaches the other, which only happens if
#   the GPU's depth textures got the new floor.
# - "resting" rests, then re-measures: it has to wake.
# - "frame" is "kept" in per-frame stepping.

const SPACING := 200.0
const SIZE := 40.0
const RIPPLE_AT := 60
const REMEASURE_AT := 75
const WALL_AT := 120
const WALL_SPLASH_AT := 125
const END := 300

const SOURCE := Vector3(-8, 0, 0)
const OBSERVER := Vector3(8, 0, 0)

var _control: Node3D
var _kept: Node3D
var _frame: Node3D
var _walled: Node3D
var _open: Node3D
var _resting: Node3D
var _wall: StaticBody3D
var _lake: Node3D
var _body: RigidBody3D
var _buoy: Node
var _wake: Node
var _t := 0
var _ok := true
var _kept_worst := 0.0
var _frame_worst := 0.0
var _peak_kept := 0.0
var _peak_open := 0.0
var _peak_walled := 0.0
var _peak_source := 0.0
var _rested := false
var _done := false


func _check(cond: bool, msg: String) -> void:
	print("[remeasure] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var s := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	s.shape = box
	b.add_child(s)
	b.position = pos
	get_root().add_child(b)
	return b


func _surface(slot: int, mode := 0, rest := 0.0) -> Node3D:
	var pos := Vector3(slot * SPACING, 0, 0)
	_box(pos + Vector3(0, -3.5, 0), Vector3(SIZE + 20, 1, SIZE + 20))
	var w: Node3D = ClassDB.instantiate("PhysXWaterSurface3D")
	w.set("domain_size", Vector2(SIZE, SIZE))
	w.set("grid_resolution", 128)
	w.set("ocean_grid_resolution", 64)
	w.set("wave_amplitude", 0.0)
	w.set("seabed_from_floor", true)
	w.set("step_mode", mode)
	w.set("ripple_rest_threshold", rest)
	w.position = pos
	get_root().add_child(w)
	return w


func _initialize() -> void:
	_control = _surface(0)
	_kept = _surface(1)
	_frame = _surface(2, 1)
	_walled = _surface(3)
	_open = _surface(4)
	_resting = _surface(5, 0, 0.001)
	# Under the floor for now, so the first measure doesn't see it.
	_wall = _box(Vector3(3 * SPACING, -20, 0), Vector3(2, 10, SIZE + 20))

	_lake = _surface(6)
	_lake.set("seabed_from_floor", false)
	_body = RigidBody3D.new()
	_body.freeze = true
	_body.position = _lake.position
	_buoy = ClassDB.instantiate("PhysXBuoyancy3D")
	_buoy.set("disturb_water", false)
	_body.add_child(_buoy)
	get_root().add_child(_body)
	_buoy.set("water_surface_path", _buoy.get_path_to(_lake))
	physics_frame.connect(_step)


func _at(w: Node3D, p: Vector3) -> float:
	return w.sample_height(w.global_position + p)


func _step() -> void:
	if _done:
		return
	_t += 1
	if _t == RIPPLE_AT:
		for w: Node3D in [_control, _kept, _frame]:
			w.submit_impulse(w.global_position, 3.0, 1.0)
		_late_wake_added()
	if _t == REMEASURE_AT:
		var before := absf(_at(_kept, OBSERVER * 0.4))
		_check(before > 0.02, "a ripple before re-measuring: %.3f m" % before)
		_kept.remeasure_seabed()
		_frame.remeasure_seabed()
		_check(_kept.get("seabed_from_floor"), "still measuring from the floor")
	if _t > REMEASURE_AT and _t < WALL_AT:
		for x in [0.0, 3.0, 6.0, 9.0]:
			var p := Vector3(x, 0, 0)
			var h := _at(_control, p)
			_peak_kept = maxf(_peak_kept, absf(h))
			_kept_worst = maxf(_kept_worst, absf(_at(_kept, p) - h))
			_frame_worst = maxf(_frame_worst, absf(_at(_frame, p) - h))
	if _t == WALL_AT:
		_wall.global_position = Vector3(3 * SPACING, 0, 0)
	if _t == WALL_AT + 2:
		_walled.remeasure_seabed()
	if _t == WALL_SPLASH_AT:
		_check(not _walled.is_wet(_walled.global_position), "the wall is dry land now")
		_check(_walled.is_wet(_walled.global_position + SOURCE), "either side of it is still water")
		for w: Node3D in [_walled, _open]:
			w.submit_impulse(w.global_position + SOURCE, 2.0, 1.0)
	if _t > WALL_SPLASH_AT:
		_peak_open = maxf(_peak_open, absf(_at(_open, OBSERVER)))
		_peak_walled = maxf(_peak_walled, absf(_at(_walled, OBSERVER)))
		_peak_source = maxf(_peak_source, absf(_at(_walled, SOURCE * 0.5)))
	if _t == 200:
		_rested = _resting.is_ripple_resting()
		_check(_rested, "calm water rests")
		_resting.remeasure_seabed()
	if _t == 203:
		_check(not _resting.is_ripple_resting(), "re-measuring wakes it")
	if _t == 240:
		_late_wake_removed()
	if _t == 260:
		_after_wake_removed()
	if _t == END:
		_finish()


func _late_wake_added() -> void:
	_wake = ClassDB.instantiate("PhysXWaterWake3D")
	_wake.set("hull_length", 4.0)
	_wake.set("hull_beam", 1.5)
	_wake.set("rest_depth", 0.3)
	_body.add_child(_wake)
	_wake.set("water_surface_path", _wake.get_path_to(_lake))


func _late_wake_removed() -> void:
	var p := _body.global_position
	var dip: float = _lake.sample_height(p)
	_check(dip < -0.05, "the wake dips the water: %.3f m" % dip)
	_check(absf(_buoy.get_water_height(p)) < 0.005, "a wake added late isn't counted by the buoyancy: %.4f m" % _buoy.get_water_height(p))
	_wake.free()
	_wake = null


func _after_wake_removed() -> void:
	var p := _body.global_position
	_check(absf(_buoy.get_water_height(p) - _lake.sample_height(p)) < 0.001, "with it gone, the buoyancy reads the surface: %.4f m" % _buoy.get_water_height(p))


func _finish() -> void:
	_done = true
	_check(_peak_kept > 0.02, "the ripple was still there to compare: %.3f m" % _peak_kept)
	_check(_kept_worst < 0.0005, "re-measuring keeps the ripple: worst %.5f m from the control" % _kept_worst)
	_check(_frame_worst < 0.0005, "per frame too: worst %.5f m" % _frame_worst)
	_check(_peak_open > 0.01, "with no wall the splash crosses: %.4f m" % _peak_open)
	_check(_peak_source > 0.01, "it splashed on the wall's near side: %.4f m" % _peak_source)
	_check(_peak_walled < _peak_open * 0.1, "the new wall stops it: %.4f m" % _peak_walled)
	print("[remeasure] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
