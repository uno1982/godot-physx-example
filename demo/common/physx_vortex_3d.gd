class_name PhysXVortex3D
extends Node3D

# Borderlands-style "Singularity": launch(from, direction) and the vortex
# itself drifts slowly forward -- immune to gravity, not a physics body at all
# -- pulling everything dynamic within pull_radius toward its (moving) centre
# the whole time it travels, so it gathers up whatever it passes over rather
# than only what happens to be at one fixed spot. Objects don't beeline
# straight in: a tangential swirl force on top of the radial pull makes them
# spiral in around the vortex's own flight direction, like debris getting
# sucked into a moving wormhole -- not settled into one flat disk on a fixed
# world axis regardless of where the thing is actually headed. Once it's
# gathered enough nearby (or travelled long enough with nothing to gather),
# it pulses everything back outward and is done.
#
# Uses PhysicsServer3D directly at the RID level (intersect_shape + apply
# force/impulse by RID) rather than Node-based RigidBody3D APIs, so it pulls
# in BOTH ordinary scene bodies and headless bodies that have no owning Node
# -- like PhysXChunkEmitter3D's chunks, which a Node-based query (the kind
# physx_playground's radial blast uses) can't see at all.

enum State { IDLE, TRAVELING, EXPLODING }

@export var travel_speed := 3.0 # m/s, slow and steady
@export var max_travel_time := 9.0 # seconds -- safety cap if it never gathers enough
@export var min_gather_time := 2.5 # seconds before gather_count_to_explode can fire early
@export var gather_count_to_explode := 10 # bodies currently within gather_radius (not pull_radius --
	# that's the wide capture net; this is "actually reeled in close", so a big
	# loose pile it merely flies near doesn't instantly satisfy the count)
@export var gather_radius := 3.5

@export var pull_radius := 13.0
@export var pull_strength := 55.0 # m/s^2 toward the center, like gravity (mass-independent)
@export var pull_drag := 3.0 # 1/s, opposes current velocity -- the pull's "weight"
@export var orbit_strength := 26.0 # m/s^2 tangential -- makes bodies circle in, not beeline
@export var orbit_axis := Vector3.UP # only used for a stationary burst (direction=ZERO);
	# while traveling the swirl axis is the flight direction itself, see launch()
@export var orbit_randomness := 0.7 # 0..1+, per-body swirl-axis jitter (stable per body, not
	# re-randomized each frame) -- without it every body circles in the exact
	# same plane, reading as one flat disk no matter which axis it's aligned to

@export var explosion_radius := 15.0
@export var explosion_speed := 22.0 # added m/s at the center, falling off with distance
@export var min_distance := 0.6 # clamps the pull/orbit falloff near the center
@export var collision_mask: int = 1

var _state := State.IDLE
var _center := Vector3.ZERO
var _travel_dir := Vector3.ZERO
var _swirl_axis := Vector3.UP
var _t := 0.0
var _visual: MeshInstance3D

func _ready() -> void:
	set_physics_process(false)
	_visual = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.0, 0.08, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.35, 0.05, 0.55)
	m.emission_energy_multiplier = 2.0
	m.rim_enabled = true
	m.rim = 1.0
	sm.material = m
	_visual.mesh = sm
	_visual.visible = false
	add_child(_visual)

# Pass a zero direction for a stationary burst at world_position; otherwise it
# drifts along direction at travel_speed while it gathers.
func launch(world_position: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	_center = world_position
	_travel_dir = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	# Swirl around the direction it's actually flying, not a fixed world axis --
	# otherwise everything settles into one flat horizontal disk (like planets
	# around a sun) no matter which way the thing is headed. A stationary burst
	# (no travel direction) falls back to the exported orbit_axis.
	_swirl_axis = _travel_dir if _travel_dir != Vector3.ZERO else orbit_axis.normalized()
	_state = State.TRAVELING
	_t = 0.0
	_visual.global_position = _center
	_visual.visible = true
	_visual.scale = Vector3.ONE * 0.6
	set_physics_process(true)

func is_active() -> bool:
	return _state != State.IDLE

func _physics_process(delta: float) -> void:
	match _state:
		State.TRAVELING:
			_t += delta
			_center += _travel_dir * travel_speed * delta
			_visual.global_position = _center
			_visual.rotate_y(delta * 2.5) # a bit of spin to read as "spinning up"
			var gathered := _pull(delta)
			var pulse := 0.5 + 0.1 * sin(_t * 10.0) # a gentle pulse while it's live
			_visual.scale = Vector3.ONE * (pulse + clampf(float(gathered) / float(gather_count_to_explode), 0.0, 1.0) * 0.5)
			var ready_to_pulse := _t >= min_gather_time and gathered >= gather_count_to_explode
			if ready_to_pulse or _t >= max_travel_time:
				_explode()
				_state = State.EXPLODING
				_t = 0.0
		State.EXPLODING:
			_t += delta
			_visual.scale = Vector3.ONE * lerpf(1.8, 0.0, clampf(_t / 0.25, 0.0, 1.0))
			if _t >= 0.25:
				_visual.visible = false
				_state = State.IDLE
				set_physics_process(false)

# A cheap deterministic "random" unit vector from a RID, stable across frames
# for the same body (so its swirl doesn't jitter frame to frame) but different
# from every other body's -- classic hash-noise trick, no RNG object needed.
func _hash_axis(rid: RID) -> Vector3:
	var id := float(rid.get_id())
	var a := fmod(sin(id * 12.9898) * 43758.5453, 1.0)
	var b := fmod(sin(id * 78.233) * 43758.5453, 1.0)
	var c := fmod(sin(id * 37.719) * 43758.5453, 1.0)
	var v := Vector3(a, b, c) * 2.0 - Vector3.ONE
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.RIGHT

func _query(radius: float) -> Array:
	var params := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	params.shape = s
	params.transform = Transform3D(Basis(), _center)
	params.collide_with_bodies = true
	params.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(params, 512)

# Pulls (and swirls) everything in range toward the current centre; returns
# how many bodies are currently within gather_radius (actually reeled in
# close, not just somewhere inside the wider pull_radius net), so the caller
# can judge when it's "gathered enough" to pulse.
func _pull(_delta: float) -> int:
	var seen := {}
	var gathered := 0
	for h in _query(pull_radius):
		var rid: RID = h.get("rid")
		if seen.has(rid):
			continue
		seen[rid] = true
		if PhysicsServer3D.body_get_mode(rid) != PhysicsServer3D.BODY_MODE_RIGID:
			continue
		var state := PhysicsServer3D.body_get_direct_state(rid)
		if not state:
			continue
		var off := _center - state.transform.origin
		if off.length() <= gather_radius:
			gathered += 1
		var dist := maxf(off.length(), min_distance)
		var dir := off / dist
		var falloff := clampf(1.0 - dist / pull_radius, 0.0, 1.0)
		var mass: float = PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_MASS)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		# Radial pull + a tangential swirl so bodies circle the centre while
		# getting reeled in, instead of beelining straight to it. Each body
		# swirls around its own axis -- the flight direction blended with a
		# fixed-per-body random jitter -- so the whole cluster doesn't settle
		# into one flat disk; some circle more "over/under", some more "side
		# to side", reading as a proper chaotic 3D vortex. Drag against current
		# velocity keeps it from turning into an ever-accelerating orbit or a
		# slingshot through the middle.
		var body_axis := (_swirl_axis + _hash_axis(rid) * orbit_randomness).normalized()
		var tangent := body_axis.cross(dir)
		if tangent.length_squared() > 0.0001:
			tangent = tangent.normalized()
		var force := (dir * pull_strength + tangent * orbit_strength) * falloff * mass
		force -= state.linear_velocity * pull_drag * mass
		PhysicsServer3D.body_apply_central_force(rid, force)
	return gathered

func _explode() -> void:
	var seen := {}
	for h in _query(explosion_radius):
		var rid: RID = h.get("rid")
		if seen.has(rid):
			continue
		seen[rid] = true
		if PhysicsServer3D.body_get_mode(rid) != PhysicsServer3D.BODY_MODE_RIGID:
			continue
		var state := PhysicsServer3D.body_get_direct_state(rid)
		if not state:
			continue
		var off := state.transform.origin - _center
		var dist := off.length()
		var dir := (off / dist) if dist > 0.001 else Vector3.UP
		var falloff := clampf(1.0 - dist / explosion_radius, 0.0, 1.0)
		var mass: float = PhysicsServer3D.body_get_param(rid, PhysicsServer3D.BODY_PARAM_MASS)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		# Bodies are still swirling inward at this instant -- kill that velocity
		# first so the outward impulse is a clean launch instead of partly
		# cancelling residual inward momentum (which made the blast look weak).
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_apply_central_impulse(rid, dir * explosion_speed * falloff * mass)
