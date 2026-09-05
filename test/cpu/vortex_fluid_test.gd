extends SceneTree

# Does the vortex's RID-level PhysicsServer3D pull/push reach GPU fluid
# particles? Prediction: no -- PxPBDParticleSystem is a completely different
# simulation object from PxRigidDynamic, with no owning "body" RID in the
# generic PhysicsServer3D sense, so intersect_shape() shouldn't even return
# it and body_apply_central_force() has nothing to apply to. This measures
# it directly rather than assuming.

const VortexScript := preload("res://demo/common/physx_vortex_3d.gd")

var _fluid: PhysXParticleFluid3D
var _vortex
var _t := 0
var _before: PackedVector3Array
var _spread_before := 0.0
var _use_vortex := true

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_use_vortex = args.size() == 0 or args[0] != "control"
	print("[vf] engine=%s use_vortex=%s" % [ProjectSettings.get_setting("physics/3d/physics_engine", "?"), _use_vortex])
	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(30, 1, 30)
	cs.shape = b
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -6, 0)
	root.add_child(floor_body)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.particle_count = 800
	_fluid.spawn_on_ready = true
	_fluid.emitting = false
	_fluid.position = Vector3(0, 2, 0)
	_fluid.spawn_region_size = Vector3(2, 2, 2)
	root.add_child(_fluid)

	_vortex = VortexScript.new()
	_vortex.pull_radius = 15.0
	_vortex.gather_radius = 6.0
	root.add_child(_vortex)

func _physics_process(_delta: float) -> bool:
	_t += 1
	if _t == 90:
		# Let the fluid settle first, then measure its spread before the vortex.
		_before = _fluid.get_particle_positions()
		var center := Vector3.ZERO
		for p in _before:
			center += p
		center /= maxf(_before.size(), 1)
		for p in _before:
			_spread_before += p.distance_to(center)
		_spread_before /= maxf(_before.size(), 1)
		print("[vf] pre-vortex: particles=%d avg_spread=%.3f" % [_before.size(), _spread_before])
		if _use_vortex:
			_vortex.launch(_fluid.global_position, Vector3(0, -1, 0))
	if _t == 250:
		var after := _fluid.get_particle_positions()
		var center := Vector3.ZERO
		for p in after:
			center += p
		center /= maxf(after.size(), 1)
		var spread_after := 0.0
		for p in after:
			spread_after += p.distance_to(center)
		spread_after /= maxf(after.size(), 1)
		# How much each particle moved, matched by index (emission order is
		# stable enough for a coarse "did anything change a lot" signal).
		var moved := 0.0
		var n: int = mini(_before.size(), after.size())
		for i in n:
			moved += _before[i].distance_to(after[i])
		moved /= maxf(n, 1)
		print("[vf] post-vortex: particles=%d avg_spread=%.3f avg_moved=%.3f" % [after.size(), spread_after, moved])
		print("[vf] vortex reached the fluid: %s" % (moved > 0.5 or absf(spread_after - _spread_before) > 0.5))
		quit(0)
	return false
