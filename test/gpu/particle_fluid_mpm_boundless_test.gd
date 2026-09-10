extends SceneTree

# PhysXParticleFluid3D, solver = MPM (block-sparse). A prefilled block of fluid
# on a wide floor slumps and spreads OUT well past the small mpm_domain_size box
# -- the block path would clamp it at the domain edge; the block-sparse grid
# follows the fluid.
#  1. the fluid spreads past domain/2 (+ margin) from the centre
#  2. nothing NaNs, nothing falls through the floor

var _fl: PhysXParticleFluid3D
var _tick := 0
var _exit := 1
var _max_reach := 0.0

func _initialize() -> void:
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[bl] PhysXParticleFluid3D not registered -> SKIP"); quit(0); return

	var root := Node3D.new()
	get_root().add_child(root)

	var floor := StaticBody3D.new()
	floor.name = "Floor"
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(30, 0.4, 30)
	fs.shape = fb
	floor.add_child(fs)
	floor.position = Vector3(0, -0.2, 0)
	root.add_child(floor)

	# 2 m domain, 1.4 m block of fluid dropped from ~1 m up: it hits the floor and
	# slumps outward. Domain half-extent is 1.0 -- the fluid must clear that.
	_fl = PhysXParticleFluid3D.new()
	_fl.solver = PhysXParticleFluid3D.SOLVER_MPM
	_fl.particle_count = 45000
	_fl.particle_size = 0.03
	_fl.mpm_domain_size = Vector3(2, 2, 2)
	_fl.mpm_substeps = 5
	_fl.spawn_region_size = Vector3(1.4, 1.0, 1.4)
	_fl.spawn_on_ready = true
	_fl.position = Vector3(0, 1.0, 0)
	_fl.mpm_colliders = [NodePath("../Floor")]
	root.add_child(_fl)

func _process(_d: float) -> bool:
	_tick += 1
	if _fl == null:
		return true
	if _tick == 30 and _fl.get_particle_positions().is_empty():
		print("[bl] no particles (no compute device) -> SKIP"); quit(0); return true
	if _tick % 60 != 0:
		return false

	var pts := _fl.get_particle_positions()
	if pts.is_empty():
		return false
	var nan := 0
	var below := 0
	# 90th-percentile reach, so one flung outlier does not decide it
	var rs: PackedFloat32Array = PackedFloat32Array()
	for p in pts:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			nan += 1; continue
		rs.append(maxf(absf(p.x), absf(p.z)))
		if p.y < -0.6:
			below += 1
	rs.sort()
	var p90 := rs[int(rs.size() * 0.9)] if rs.size() > 0 else 0.0
	_max_reach = maxf(_max_reach, p90)
	print("[bl] tick %d  live=%d  reach(p90)=%.2f  nan=%d  below=%d" % [
		_tick, pts.size(), p90, nan, below])

	if _tick >= 360:
		var ok := _max_reach > 1.5 and nan == 0 and below == 0
		print("[bl] max_reach(p90)=%.2f (domain half=1.0)  -> %s" % [_max_reach, "PASS" if ok else "FAIL"])
		_exit = 0 if ok else 1
		_fl = null
		return false
	if _tick >= 363:
		quit(_exit)
		return true
	return false
