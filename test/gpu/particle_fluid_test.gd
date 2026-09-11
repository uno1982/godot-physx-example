extends SceneTree

# A block of PhysXParticleFluid3D particles is dropped over a floor. Checks the
# GPU particle system actually simulates: particles fall, then pool (mean height
# drops toward the floor and stabilizes). GPU-only -- skips cleanly otherwise.

var _fluid: PhysXParticleFluid3D
var _floor: StaticBody3D
var _tick := 0
var _y_at_60 := 0.0

func _initialize() -> void:
	print("[fluid] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[fluid] PhysXParticleFluid3D not registered -> SKIP")
		quit(0)
		return
	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(20, 1, 20)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	_floor = floor_body

	_fluid = PhysXParticleFluid3D.new()
	_fluid.particle_count = 4000
	_fluid.particle_size = 0.08
	_fluid.spawn_region_size = Vector3(1.0, 1.0, 1.0)
	_fluid.position = Vector3(0, 4, 0)
	# The MPM path's implicit floor sits mpm_domain_size.y/2 below the spawn
	# point regardless of mpm_colliders -- the default has to cover the actual
	# drop (spawn y=4 to the floor at y=0) or particles freeze on that plane
	# well above the real floor. See PhysXParticleFluid3D.mpm_domain_size doc.
	_fluid.mpm_domain_size = Vector3(3, 9, 3)
	root.add_child(_fluid)
	# The MPM fallback path (Auto without CUDA, e.g. enhanced_determinism=true)
	# only collides with what it's told to -- wire the real floor in so a
	# MPM-resolved run tests against it instead of the implicit domain-bottom
	# floor plane (mpm_domain_size.y below spawn). get_path() needs the node's
	# tree entry to have fully propagated, which hasn't happened yet inside
	# _initialize() -- deferred to the first physics tick instead.
	call_deferred("_wire_mpm_collider")

func _wire_mpm_collider() -> void:
	if _fluid != null and _floor != null:
		_fluid.mpm_colliders = [_floor.get_path()]

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	if _tick == 6:
		if _fluid.get_live_particle_count() == 0:
			print("[fluid] 0 live particles (no CUDA device / CPU build) -> SKIP")
			quit(0)
			return true
	var pts := _fluid.get_particle_positions()
	if pts.is_empty():
		return false
	var sum := 0.0
	var miny := 1e9
	for p in pts:
		sum += p.y
		miny = minf(miny, p.y)
	var mean_y := sum / pts.size()
	if _tick == 60:
		_y_at_60 = mean_y
	if _tick % 40 == 0:
		print("[fluid] tick %3d  particles=%d  mean_y=%.2f  min_y=%.2f" % [_tick, pts.size(), mean_y, miny])
	if _tick == 260:
		var fell := _y_at_60 < 3.8 # dropped from y=4 by tick 60
		var pooled := mean_y < 1.0 and mean_y > -0.2 # resting on/near the floor top (y~0)
		var ok := pts.size() > 1200 and fell and pooled
		print("[fluid] count=%d  y@60=%.2f  final_mean_y=%.2f  -> %s" %
				[pts.size(), _y_at_60, mean_y, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
