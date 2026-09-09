extends SceneTree

# PhysXGranular3D. The MPM granular solver
# runs on plain RenderingDevice compute (no CUDA).
#  1. a cube of grains seeds inside the domain and drops onto the floor
#  2. it must slump into a *pile* -- hold a slope, not spread to a flat pancake
#  3. no NaN / escape: every grain stays finite and inside the domain

var _fluid: PhysXGranular3D
var _tick := 0
var _spread_at_60 := 0.0
var _exit_code := 1

func _initialize() -> void:
	print("[gran] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXGranular3D"):
		print("[gran] PhysXGranular3D not registered -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	# The sand slumps onto the MPM domain floor (no separate collider needed).
	_fluid = PhysXGranular3D.new()
	_fluid.solver = PhysXGranular3D.SOLVER_MPM
	_fluid.particle_count = 40000
	_fluid.particle_size = 0.02
	_fluid.mpm_domain_size = Vector3(4, 4, 4)
	_fluid.spawn_region_size = Vector3(0.7, 0.7, 0.7)
	_fluid.friction = 44.0
	_fluid.grain_cohesion = 0.004
	_fluid.position = Vector3(0, 1.2, 0)
	root.add_child(_fluid)

func _process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	if _tick == 6 and _fluid.get_live_particle_count() == 0:
		print("[gran] 0 live particles (no RenderingDevice / compute) -> SKIP")
		quit(0)
		return true

	# Only sample at the checkpoints -- reading positions forces a GPU sync.
	if _tick != 60 and _tick % 120 != 0 and _tick != 360:
		return false
	var pts := _fluid.get_particle_positions()
	if pts.is_empty():
		return false

	var top := -1e9
	var base := 1e9
	var half_w := 0.0
	var finite := true
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			finite = false
		top = maxf(top, p.y)
		base = minf(base, p.y)
		half_w = maxf(half_w, maxf(absf(p.x), absf(p.z)))

	if _tick == 240:
		_spread_at_60 = half_w   # first post-slump measurement
	if _tick % 120 == 0 or _tick == 60:
		print("[gran] tick %3d  n=%d  top=%.3f base=%.3f half_w=%.3f" % [_tick, pts.size(), top, base, half_w])

	if _tick == 360:
		var height := top - base
		# a real pile holds a slope: height / half-width well above a pancake
		# (a flat spread is ~0.1; a slumped heap ~0.4+).
		var repose := height / maxf(half_w, 0.001)
		var settled := half_w < _spread_at_60 + 0.12   # not still creeping wide between t240 and t360
		var bounded := half_w < 1.9 and top < 3.5       # stayed inside the domain
		var ok := finite and pts.size() > 8000 and repose > 0.35 and settled and bounded
		print("[gran] n=%d  height=%.2f half_w=%.2f  repose=%.2f  finite=%s  -> %s" %
				[pts.size(), height, half_w, repose, finite, "PASS" if ok else "FAIL"])
		_fluid.get_parent().free()
		_fluid = null
		_exit_code = 0 if ok else 1
		return false
	if _tick >= 363:
		quit(_exit_code)
		return true
	return false
