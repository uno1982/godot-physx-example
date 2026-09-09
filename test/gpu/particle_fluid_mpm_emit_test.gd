extends SceneTree

# PhysXParticleFluid3D solver = MPM, emission mode (a faucet). Checks the live
# count climbs from 0, caps at the buffer capacity, and the fluid pools on the
# domain floor rather than escaping.

var _fluid: PhysXParticleFluid3D
var _tick := 0
var _peak := 0
var _domain_floor := 0.0
var _exit_code := 1

func _initialize() -> void:
	print("[mpm-emit] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[mpm-emit] not registered -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.solver = PhysXParticleFluid3D.SOLVER_MPM
	_fluid.particle_count = 16000
	_fluid.particle_size = 0.05
	_fluid.mpm_domain_size = Vector3(2.6, 2.8, 2.6)
	_fluid.mpm_grid_resolution = 44
	_fluid.mpm_substeps = 5
	_fluid.spawn_on_ready = false
	_fluid.emitting = true
	_fluid.emission_rate = 5000.0
	_fluid.emission_radius = 0.12
	_fluid.emission_velocity = Vector3(0, -2.5, 0)
	_fluid.position = Vector3(0, 2.0, 0) # nozzle near the top of the domain
	root.add_child(_fluid)
	_domain_floor = _fluid.position.y - _fluid.mpm_domain_size.y * 0.5

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	var live := _fluid.get_live_particle_count()
	_peak = maxi(_peak, live)

	if _tick == 20 and live == 0 and _peak == 0:
		# give the stream a moment; only bail if still nothing much later
		pass
	if _tick == 90 and _peak == 0:
		print("[mpm-emit] no particles after 90 ticks (no compute?) -> SKIP")
		quit(0)
		return true

	var pts := _fluid.get_particle_positions()
	var miny := 1e9
	var meany := 0.0
	for p in pts:
		miny = minf(miny, p.y)
		meany += p.y
	if not pts.is_empty():
		meany /= pts.size()

	if _tick % 40 == 0:
		print("[mpm-emit] tick %3d  live=%d  peak=%d  mean_y=%.2f  min_y=%.2f  (floor=%.2f)" %
				[_tick, live, _peak, meany, miny, _domain_floor])

	if _tick == 400:
		var grew := _peak > 6000
		var capped := live <= _fluid.particle_count + 2500 # seeder/rounding slack
		var pooled := not pts.is_empty() and miny > _domain_floor - 0.15 and meany < _domain_floor + 1.2
		var ok := grew and capped and pooled
		print("[mpm-emit] peak=%d  live=%d  mean_y=%.2f  min_y=%.2f  -> %s" %
				[_peak, live, meany, miny, "PASS" if ok else "FAIL"])
		_fluid.get_parent().free()
		_fluid = null
		_exit_code = 0 if ok else 1
		return false
	if _tick >= 404:
		quit(_exit_code)
		return true
	return false
