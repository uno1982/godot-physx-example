extends SceneTree

# PhysXParticleFluid3D with solver = MPM (compute). The MPM backend runs on plain
# RenderingDevice compute (no CUDA), so this should work on any GPU build.
#  1. a block of fluid seeds inside the domain box and settles onto the domain floor
#  2. a RigidBody3D ball listed in mpm_colliders is dropped into it: the fluid must
#     slow its fall (coupling reaction) rather than letting it free-fall through.

var _fluid: PhysXParticleFluid3D
var _ball: RigidBody3D
var _tick := 0
var _y_at_30 := 0.0
var _domain_floor := 0.0
var _ball_min_y := 1e9
var _exit_code := 1

func _initialize() -> void:
	print("[mpm] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[mpm] PhysXParticleFluid3D not registered -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.solver = PhysXParticleFluid3D.SOLVER_MPM
	_fluid.particle_count = 60000
	_fluid.particle_size = 0.05
	_fluid.mpm_domain_size = Vector3(3, 3, 3)
	_fluid.spawn_region_size = Vector3(2.6, 1.6, 2.6) # wide shallow pool
	_fluid.mpm_grid_resolution = 40
	_fluid.mpm_substeps = 6
	_fluid.mpm_stiffness = 7000.0
	_fluid.surface_mesh = true # also exercise the marching-tetrahedra isosurface path
	_fluid.position = Vector3(0, 3, 0)
	root.add_child(_fluid)
	_domain_floor = _fluid.position.y - _fluid.mpm_domain_size.y * 0.5

	_ball = RigidBody3D.new()
	_ball.mass = 6.0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	cs.shape = sph
	_ball.add_child(cs)
	_ball.freeze = true # released once the pool has settled
	_ball.position = Vector3(0.1, _fluid.position.y + 0.9, 0.0)
	root.add_child(_ball)
	_fluid.mpm_colliders = [_fluid.get_path_to(_ball)]

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	if _tick == 6 and _fluid.get_live_particle_count() == 0:
		print("[mpm] 0 live particles (no RenderingDevice / compute) -> SKIP")
		quit(0)
		return true
	if _tick == 90 and is_instance_valid(_ball):
		_ball.freeze = false # pool has settled -- drop the ball into it

	var pts := _fluid.get_particle_positions()
	if pts.is_empty():
		return false
	var sum := 0.0
	var miny := 1e9
	for p in pts:
		sum += p.y
		miny = minf(miny, p.y)
	var mean_y := sum / pts.size()
	if _tick == 30:
		_y_at_30 = mean_y
	if is_instance_valid(_ball):
		_ball_min_y = minf(_ball_min_y, _ball.position.y)
	if _tick % 40 == 0:
		print("[mpm] tick %3d  particles=%d  mean_y=%.2f  min_y=%.2f  ball_y=%.2f  (floor=%.2f)" %
				[_tick, pts.size(), mean_y, miny, _ball.position.y if is_instance_valid(_ball) else 0.0, _domain_floor])
	if _tick == 320:
		var settled_low := mean_y < _y_at_30 + 0.05
		var above_floor := miny > _domain_floor - 0.15
		var in_box := mean_y < _domain_floor + 1.0
		# free-fall from +0.9 over ~5.3 s would be far below the floor; coupling
		# must keep the ball near the pool surface.
		var ball_held := _ball.position.y > _domain_floor - 0.05
		var ok := pts.size() > 9000 and settled_low and above_floor and in_box and ball_held
		print("[mpm] count=%d  y@30=%.2f  mean_y=%.2f  min_y=%.2f  ball_y=%.2f  ball_min_y=%.2f  -> %s" %
				[pts.size(), _y_at_30, mean_y, miny, _ball.position.y, _ball_min_y, "PASS" if ok else "FAIL"])
		_fluid.get_parent().free()
		_fluid = null
		_ball = null
		_exit_code = 0 if ok else 1
		return false
	if _tick >= 323:
		quit(_exit_code)
		return true
	return false
