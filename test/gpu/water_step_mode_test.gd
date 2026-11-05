extends SceneTree

# PhysXWaterSurface3D.step_mode and ripple_rest_threshold.
# Needs a windowed run (the water simulates on the GPU).
#
# Surfaces at the same place get the same bodies and impulses:
# - per frame reads the same heights as per tick, also during the frame's ticks;
# - one switched from per frame to per tick mid-run loses no ticks.
#
# Then calm water with and without a rest threshold.

const TPS := 240
const MAX_FPS := 30
const TICKS_RUN := 720 # 3 s of simulated water
const SWITCH_AT := 360
const POINTS: Array[Vector3] = [Vector3(0, 0, 0), Vector3(6, 0, -3), Vector3(-8, 0, 5), Vector3(14, 0, 12)]

const REST_WAIT := 240 # ticks of calm water before it must be resting
const WAKE_WAIT := 60 # ticks after the impulse

var _tick: Node3D
var _frame: Node3D
var _switched: Node3D
var _calm: Node3D
var _resting: Node3D
var _t := 0
var _frames := 0
var _worst_frame := 0.0
var _worst_switched := 0.0
var _lo := INF
var _hi := -INF
var _ok := true
var _impulse_at := -1
var _rested := false
var _rest_speed := 0.0
var _peak_calm := 0.0
var _peak_resting := 0.0
var _worst_rest := 0.0
var _done := false


func _check(cond: bool, msg: String) -> void:
	print("[step_mode] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _water(pos: Vector3, amplitude: float, mode: int, rest: float) -> Node3D:
	var w: Node3D = ClassDB.instantiate("PhysXWaterSurface3D")
	w.set("domain_size", Vector2(64, 64))
	w.set("grid_resolution", 128)
	w.set("ocean_grid_resolution", 128)
	w.set("wave_amplitude", amplitude)
	w.set("step_mode", mode)
	w.set("ripple_rest_threshold", rest)
	w.position = pos
	get_root().add_child(w)
	return w


func _initialize() -> void:
	Engine.physics_ticks_per_second = TPS
	Engine.max_physics_steps_per_frame = 16
	Engine.max_fps = MAX_FPS
	_tick = _water(Vector3.ZERO, 1.0, 0, 0.0)
	_frame = _water(Vector3.ZERO, 1.0, 1, 0.0)
	_switched = _water(Vector3.ZERO, 1.0, 1, 0.0)
	_calm = _water(Vector3(500, 0, 0), 0.0, 1, 0.0)
	_resting = _water(Vector3(500, 0, 0), 0.0, 1, 0.001)
	physics_frame.connect(_step)
	process_frame.connect(func(): _frames += 1)


func _step() -> void:
	if _done:
		return
	_t += 1
	if _t <= TICKS_RUN:
		_waves()
	if _t == SWITCH_AT:
		_switched.set("step_mode", 0)
		_check(_switched.get("step_mode") == 0, "step_mode switches back")
	_rest()
	if _t == TICKS_RUN + 1:
		_finish()


func _waves() -> void:
	# A body circling and a splash now and then, on every surface alike.
	var a := _t * 0.01
	var body := Vector3(cos(a) * 10.0, 0, sin(a) * 10.0)
	for w: Node3D in [_tick, _frame, _switched]:
		w.submit_sphere(1, body, 1.0, 1.0)
		if _t % 60 == 0:
			w.submit_impulse(Vector3(-5, 0, 3), 2.0, 1.0)
	if _t < 60:
		return # still reading back the first steps
	for p in POINTS:
		var h: float = _tick.sample_height(p)
		_lo = minf(_lo, h)
		_hi = maxf(_hi, h)
		_worst_frame = maxf(_worst_frame, absf(_frame.sample_height(p) - h))
		_worst_switched = maxf(_worst_switched, absf(_switched.sample_height(p) - h))


func _rest() -> void:
	var p := Vector3(500, 0, 0)
	if _t == REST_WAIT:
		_rested = _resting.is_ripple_resting()
		_check(_rested, "calm water rests")
		_check(not _calm.is_ripple_resting(), "no threshold, no rest")
		_rest_speed = absf(_resting.sample_vertical_speed(p))
		_check(_rest_speed == 0.0, "vertical speed at rest: %.6f m/s" % _rest_speed)
		_calm.submit_impulse(p, 3.0, 1.0)
		_resting.submit_impulse(p, 3.0, 1.0)
		_impulse_at = _t
	if _impulse_at < 0:
		return
	_peak_calm = maxf(_peak_calm, absf(_calm.sample_height(p)))
	_peak_resting = maxf(_peak_resting, absf(_resting.sample_height(p)))
	_worst_rest = maxf(_worst_rest, absf(_calm.sample_height(p + Vector3(4, 0, 0)) - _resting.sample_height(p + Vector3(4, 0, 0))))
	if _t == _impulse_at + WAKE_WAIT:
		_check(not _resting.is_ripple_resting(), "an impulse wakes it")


func _finish() -> void:
	_done = true
	var per_frame := float(_t) / maxi(_frames, 1)
	_check(per_frame >= 2.0, "several ticks a frame: %.1f" % per_frame)
	_check(_hi - _lo > 0.2, "the water moved: %.3f m" % (_hi - _lo))
	_check(_worst_frame < 0.002, "per frame reads the same heights, during ticks too: worst %.5f m" % _worst_frame)
	_check(_worst_switched < 0.002, "switched mid-run, same heights: worst %.5f m" % _worst_switched)
	_check(_peak_calm > 0.02, "the impulse raised calm water: %.3f m" % _peak_calm)
	_check(absf(_peak_calm - _peak_resting) < 0.002, "a rested surface wakes to the same ripple: %.4f m, %.4f m" % [_peak_resting, _peak_calm])
	_check(_worst_rest < 0.002, "and stays with it: worst %.5f m" % _worst_rest)
	print("[step_mode] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
