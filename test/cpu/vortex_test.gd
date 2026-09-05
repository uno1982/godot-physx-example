extends SceneTree

# PhysXVortex3D must pull in BOTH a regular RigidBody3D node and a headless
# PhysXChunkEmitter3D chunk (no owning Node -- the case a Node-based query,
# like physx_playground's radial blast, can't see), then blow them back out
# cleanly (not have the outward impulse mostly cancelled by residual inward
# velocity from the pull).

const VortexScript := preload("res://demo/common/physx_vortex_3d.gd")
const CHUNK_SPAWN := Vector3(-6, 0, 0)

var _vortex
var _crate: RigidBody3D
var _emitter: PhysXChunkEmitter3D
var _chunk_rid := RID()
var _t := 0
var _crate_start_dist := 0.0
var _min_crate_dist := 1e9
var _min_chunk_dist := 1e9

func _initialize() -> void:
	print("[vortex] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	# No floor -- keep it purely about the pull/explode forces, not resting contact.
	_crate = RigidBody3D.new()
	_crate.mass = 5.0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1, 1, 1)
	cs.shape = b
	_crate.add_child(cs)
	_crate.position = Vector3(6, 0, 0)
	_crate.gravity_scale = 0.0
	root.add_child(_crate)
	_crate_start_dist = _crate.position.length()

	_emitter = PhysXChunkEmitter3D.new()
	root.add_child(_emitter)

	_vortex = VortexScript.new()
	root.add_child(_vortex)

func _physics_process(_delta: float) -> bool:
	_t += 1
	if _t == 2:
		_emitter.spawn_at(CHUNK_SPAWN, Vector3(1, 0, 0), 1)
		# Grab the freshly-spawned chunk's RID while it's still right where it
		# spawned, so tracking it doesn't depend on guessing later.
		var params := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = 0.5
		params.shape = s
		params.transform = Transform3D(Basis(), CHUNK_SPAWN)
		params.collide_with_bodies = true
		for h in get_root().get_world_3d().direct_space_state.intersect_shape(params, 4):
			_chunk_rid = h.get("rid")
			break
		# Only 2 bodies exist in this test, so ask for both before it'll pulse,
		# rather than waiting out the full max_travel_time safety cap.
		_vortex.gather_count_to_explode = 2
		_vortex.min_gather_time = 1.2 # give the pull phase time to actually show, in this 2-body test
		_vortex.launch(Vector3.ZERO) # stationary burst -- no travel direction
	if _t > 2 and _t < 100:
		_min_crate_dist = minf(_min_crate_dist, _crate.global_position.length())
		if _chunk_rid.is_valid():
			var state := PhysicsServer3D.body_get_direct_state(_chunk_rid)
			if state:
				# Horizontal distance only -- the chunk (unlike the test crate)
				# isn't gravity-exempt, so plain .length() would conflate "pulled
				# toward the center" with "fell under normal gravity" sag.
				var o := state.transform.origin
				_min_chunk_dist = minf(_min_chunk_dist, Vector2(o.x, o.z).length())
	if _t == 120:
		var crate_dist := _crate.global_position.length()
		print("[vortex] crate: start=%.1f min_during_pull=%.2f final=%.2f vel=%.2f" % [
			_crate_start_dist, _min_crate_dist, crate_dist, _crate.linear_velocity.length()])
		print("[vortex] chunk (no owning Node): got_rid=%s min_during_pull=%.2f" % [_chunk_rid.is_valid(), _min_chunk_dist])
		var pulled_in := _min_crate_dist < _crate_start_dist * 0.5 and _min_chunk_dist < CHUNK_SPAWN.length() * 0.5
		var blown_out := crate_dist > _min_crate_dist + 3.0
		print("[vortex] pulled_in=%s blown_out=%s" % [pulled_in, blown_out])
		var ok := pulled_in and blown_out
		print("[vortex] %s" % ("PASS" if ok else "FAIL"))
		quit(0 if ok else 1)
	return false
