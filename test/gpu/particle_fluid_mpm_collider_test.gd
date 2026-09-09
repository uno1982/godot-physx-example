extends SceneTree

# MPM fluid vs an analytic box collider. A StaticBody3D box platform is raised
# well above the domain floor and registered in mpm_colliders; the fluid must
# pool ON it (min_y near the platform top) rather than falling through to the
# domain floor.

var _fluid: PhysXParticleFluid3D
var _tick := 0
var _platform_top := 0.0
var _domain_floor := 0.0
var _exit_code := 1

func _initialize() -> void:
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[mpm-col] not registered -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	var center := Vector3(0, 2.0, 0)
	var domain := Vector3(3.0, 3.0, 3.0)
	_domain_floor = center.y - domain.y * 0.5

	var platform := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.3, 1.8)
	cs.shape = bs
	platform.add_child(cs)
	platform.position = center + Vector3(0, -0.5, 0) # 1.0 above the domain floor
	root.add_child(platform)
	_platform_top = platform.position.y + bs.size.y * 0.5

	_fluid = PhysXParticleFluid3D.new()
	_fluid.solver = PhysXParticleFluid3D.SOLVER_MPM
	_fluid.particle_count = 14000
	_fluid.particle_size = 0.05
	_fluid.mpm_domain_size = domain
	_fluid.mpm_grid_resolution = 44
	_fluid.mpm_substeps = 5
	_fluid.spawn_on_ready = false
	_fluid.emitting = true
	_fluid.emission_rate = 5000.0
	_fluid.emission_radius = 0.1
	_fluid.emission_velocity = Vector3(0, -2.2, 0)
	_fluid.position = center + Vector3(0, 1.0, 0)
	root.add_child(_fluid)
	_fluid.mpm_colliders = [_fluid.get_path_to(platform)]

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	if _tick == 90 and _fluid.get_live_particle_count() == 0:
		print("[mpm-col] no particles -> SKIP")
		quit(0)
		return true

	var pts := _fluid.get_particle_positions()
	var miny := 1e9
	var below := 0
	for p in pts:
		miny = minf(miny, p.y)
		if p.y < _platform_top - 0.25:
			below += 1

	if _tick % 60 == 0:
		print("[mpm-col] tick %3d  live=%d  min_y=%.2f  below_platform=%d  (top=%.2f floor=%.2f)" %
				[_tick, pts.size(), miny, below, _platform_top, _domain_floor])

	if _tick == 360:
		# fluid held on the platform: the bulk stays above it, only a little
		# overflow spills past the edges toward the floor
		var held := not pts.is_empty() and miny > _platform_top - 0.2
		var mostly_on_top := below < pts.size() * 0.25
		var ok := held and mostly_on_top
		print("[mpm-col] min_y=%.2f  below=%d/%d  -> %s" %
				[miny, below, pts.size(), "PASS" if ok else "FAIL"])
		_fluid.get_parent().free()
		_fluid = null
		_exit_code = 0 if ok else 1
		return false
	if _tick >= 364:
		quit(_exit_code)
		return true
	return false
