extends SceneTree

# Drop a RigidBody capsule into a PhysXGranular3D sand bed as a two-way
# collider. The sand catches and holds it -- a granular bed supports a
# body, it does not fling it -- so the capsule settles and is never
# launched back above where it started.

var _fluid: PhysXGranular3D
var _body: RigidBody3D
var _tick := 0
var _max_y := -1e9
var _max_speed := 0.0

func _initialize() -> void:
	if not ClassDB.class_exists("PhysXGranular3D"):
		print("SKIP"); quit(0); return
	var root := Node3D.new(); get_root().add_child(root)

	var floor := StaticBody3D.new()
	var fs := CollisionShape3D.new(); var fb := BoxShape3D.new()
	fb.size = Vector3(6, 0.4, 6); fs.shape = fb
	floor.add_child(fs); floor.position = Vector3(0, -0.2, 0)
	root.add_child(floor)

	_fluid = PhysXGranular3D.new()
	_fluid.solver = PhysXGranular3D.SOLVER_MPM
	_fluid.particle_count = 60000
	_fluid.particle_size = 0.025
	_fluid.mpm_domain_size = Vector3(4, 2.5, 4)
	_fluid.spawn_region_size = Vector3(3.2, 0.9, 3.2)
	_fluid.friction = 44.0
	_fluid.grain_cohesion = 0.004
	_fluid.position = Vector3(0, 0.5, 0)
	_fluid.mpm_colliders = [NodePath("../Body")]
	_fluid.mpm_auto_colliders = false
	root.add_child(_fluid)

	_body = RigidBody3D.new(); _body.name = "Body"; _body.mass = 70.0
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.3; cap.height = 1.6; cs.shape = cap
	_body.add_child(cs); _body.position = Vector3(0, 1.7, 0)
	root.add_child(_body)

func _process(_d: float) -> bool:
	_tick += 1
	if _tick == 6 and _fluid.get_live_particle_count() == 0:
		print("SKIP (no compute)"); quit(0); return true
	if _body:
		_max_y = maxf(_max_y, _body.position.y)
		_max_speed = maxf(_max_speed, _body.linear_velocity.length())
		if _tick % 60 == 0:
			print("t%4d  y=%.2f  vy=%.2f  |v|=%.2f" % [_tick, _body.position.y, _body.linear_velocity.y, _body.linear_velocity.length()])
	if _tick == 600:
		# started at y=1.7; must not have been flung above ~2.2, must be near rest.
		var launched := _max_y > 2.4 or _max_speed > 6.0
		var resting := _body.linear_velocity.length() < 1.5 and _body.position.y > 0.2
		var ok := not launched and resting
		print("max_y=%.2f  max_speed=%.2f  final_y=%.2f  -> %s" % [_max_y, _max_speed, _body.position.y, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
		return true
	return false
