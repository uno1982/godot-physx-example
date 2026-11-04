extends SceneTree

# MPM fluid vs a tilted CylinderShape3D. The stream lands 0.6 m from the cylinder's axis:
# inside its 0.8 m radius, but outside the 0.5 m sphere an unsupported shape collides as,
# so the fluid only lands if the shape is really a cylinder. Windowed: MPM needs the main device.
#
# After "--":
#   control  the body isn't listed: the fluid must pour through (the test can fail)

const RADIUS := 0.8
const HALF_HEIGHT := 0.2

var _fluid: PhysXParticleFluid3D
var _body: StaticBody3D
var _tick := 0
var _control := false
var _exit_code := 1


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[mpm-cyl] not registered -> SKIP")
		quit(0)
		return
	_control = OS.get_cmdline_user_args().has("control")

	var root := Node3D.new()
	get_root().add_child(root)

	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = HALF_HEIGHT * 2.0
	cs.shape = shape
	_body.add_child(cs)
	_body.position = Vector3(0.3, 1.5, -0.2)
	_body.rotation = Vector3(0.0, deg_to_rad(40.0), deg_to_rad(15.0))
	root.add_child(_body)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.solver = PhysXParticleFluid3D.SOLVER_MPM
	_fluid.particle_count = 14000
	_fluid.particle_size = 0.05
	_fluid.mpm_domain_size = Vector3(4.0, 6.0, 4.0)
	_fluid.mpm_substeps = 5
	_fluid.spawn_on_ready = false
	_fluid.emitting = true
	_fluid.emission_rate = 5000.0
	_fluid.emission_radius = 0.08
	_fluid.emission_velocity = Vector3(0, -2.2, 0)
	_fluid.position = _body.transform * Vector3(0.6, 0.0, 0.0) + Vector3(0, 1.5, 0)
	root.add_child(_fluid)
	if not _control:
		_fluid.mpm_colliders = [_fluid.get_path_to(_body)]


func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		if _tick >= 244:
			quit(_exit_code)
			return true
		return false
	if _tick == 90 and _fluid.get_live_particle_count() == 0:
		print("[mpm-cyl] no particles -> SKIP (needs a window)")
		quit(0)
		return true

	var pts := _fluid.get_particle_positions()
	var to_local := _body.global_transform.affine_inverse()
	var inside := 0
	var on_top := 0
	for world in pts:
		var p: Vector3 = to_local * world
		var radial := Vector2(p.x, p.z).length()
		if radial < RADIUS - 0.06 and absf(p.y) < HALF_HEIGHT - 0.06:
			inside += 1
		elif radial < RADIUS and p.y >= HALF_HEIGHT - 0.06 and p.y < HALF_HEIGHT + 0.5:
			on_top += 1

	if _tick % 60 == 0:
		print("[mpm-cyl] tick %3d  live=%d  inside=%d  on_top=%d" % [_tick, pts.size(), inside, on_top])

	if _tick == 180:
		var ok := pts.size() > 1000 and inside < pts.size() * 0.005 and on_top > 200
		if _control:
			ok = inside > pts.size() * 0.005 # nothing to stop it: the check above has to fail
		print("[mpm-cyl] inside=%d on_top=%d of %d -> %s" % [inside, on_top, pts.size(), "PASS" if ok else "FAIL"])
		_exit_code = 0 if ok else 1
		_body.get_parent().free()
		_fluid = null
	return false
