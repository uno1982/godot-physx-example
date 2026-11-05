extends SceneTree

# PhysXWaterSurface3D.cull_margin (R13), the wake's and spray's script-set
# propeller_thrust (R9), PhysXWaterWake3D.hull_offset (R10) and
# PhysXWaterSurface3D.sample_vertical_speed (R7).
# Needs a windowed run (the water and wakes simulate on the GPU).

const SETTLE := 150
const MEASURE := 60
const TICK := 1.0 / 60.0

var _still: Node3D # calm water carrying the wakes
var _sea: Node3D # waves, far from the wakes
var _offset_wake: Node
var _center_wake: Node
var _offset_body: RigidBody3D
var _center_body: RigidBody3D
var _thrust_wake: Node
var _thrust_body: RigidBody3D
var _spray: Node
var _emitter: GPUParticles3D
var _idle_spray: Node
var _idle_emitter: GPUParticles3D
var _t := 0
var _ok := true
var _speed_sum := 0.0
var _height_start := 0.0
var _impulse_peak := 0.0
var _measured := false # a script error partway through _measure must not read as a pass


func _check(cond: bool, msg: String) -> void:
	print("[water_batch] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _water(pos: Vector3, amplitude: float) -> Node3D:
	var w: Node3D = ClassDB.instantiate("PhysXWaterSurface3D")
	w.set("domain_size", Vector2(80, 80))
	w.set("wave_amplitude", amplitude)
	w.position = pos
	get_root().add_child(w)
	return w


func _body(pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.freeze = true
	b.position = pos
	get_root().add_child(b)
	return b


func _wake(body: RigidBody3D, setup: Callable) -> Node:
	var w: Node = ClassDB.instantiate("PhysXWaterWake3D")
	w.set("hull_length", 4.0)
	w.set("hull_beam", 1.5)
	w.set("rest_depth", 0.0)
	w.set("foam_slope", 2.0) # the only foam here is the propeller's
	setup.call(w)
	body.add_child(w)
	w.set("water_surface_path", w.get_path_to(_still))
	return w


func _emitter_on(body: RigidBody3D) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.process_material = ParticleProcessMaterial.new()
	e.amount = 4
	body.add_child(e)
	return e


func _spray_on(body: RigidBody3D, emitter: GPUParticles3D, thrust: float) -> Node:
	var s: Node = ClassDB.instantiate("PhysXWaterSpray3D")
	s.set("propeller_thrust", thrust)
	body.add_child(s)
	s.set("water_surface_path", s.get_path_to(_still))
	s.set("stern_emitters", [s.get_path_to(emitter)])
	return s


func _mesh_of(water: Node3D) -> MeshInstance3D:
	for c in water.get_children(true):
		if c is MeshInstance3D:
			return c
	return null


func _initialize() -> void:
	_still = _water(Vector3.ZERO, 0.0)
	_sea = _water(Vector3(400, 0, 0), 1.0)
	# Two hulls at rest, each dipping the water along its keel: one centred, one 6 m ahead of its body.
	_offset_body = _body(Vector3(-20, 0, 0))
	_offset_wake = _wake(_offset_body, func(w): w.set("hull_offset", 6.0); w.set("rest_depth", 0.3))
	_center_body = _body(Vector3(20, 0, 0))
	_center_wake = _wake(_center_body, func(w): w.set("rest_depth", 0.3))
	# A propeller from a script, on a body with no PhysXBoat3D, 3 m to the body's left.
	_thrust_body = _body(Vector3(0, 0, -20))
	_thrust_wake = _wake(_thrust_body, func(w): w.set("propeller_thrust", 1.0); w.set("propeller_position", Vector3(3, 0, 0)))
	var spray_body := _body(Vector3(0, 0, 20))
	_emitter = _emitter_on(spray_body)
	_spray = _spray_on(spray_body, _emitter, 0.8)
	var idle_body := _body(Vector3(10, 0, 20))
	_idle_emitter = _emitter_on(idle_body)
	_idle_spray = _spray_on(idle_body, _idle_emitter, 0.0)
	physics_frame.connect(_step)


func _share(wake: Node, p: Vector3) -> float:
	return _still.sample_height(p) - _still.sample_height_excluding_wake(p, wake)


func _propeller_foam(wake: Node) -> Array:
	# From the wake's texture (b = propeller foam): [amount, world centre].
	var img: Image = wake.get_height_texture().get_image()
	var size: float = wake.get("size")
	var origin: Vector2 = wake.get_grid_origin()
	var total := 0.0
	var sum := Vector2.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var foam := img.get_pixel(x, y).b
			if foam > 0.001:
				total += foam
				sum += Vector2(x + 0.5, y + 0.5) * foam
	if total <= 0.0:
		return [0.0, Vector3.ZERO]
	var uv := sum / total / Vector2(img.get_width(), img.get_height())
	return [total, Vector3(origin.x + uv.x * size, 0, origin.y + uv.y * size)]


func _step() -> void:
	_t += 1
	var sea_point := Vector3(407, 0, 3)
	if _t == SETTLE:
		_height_start = _sea.sample_height(sea_point)
	if _t > SETTLE and _t <= SETTLE + MEASURE:
		_speed_sum += _sea.sample_vertical_speed(sea_point) * TICK
	if _t == SETTLE + MEASURE:
		_measure()
		_still.submit_impulse(Vector3(0, 0, 32), 1.5, 2.0)
	if _t > SETTLE + MEASURE:
		_impulse_peak = maxf(_impulse_peak, absf(_still.sample_vertical_speed(Vector3(0, 0, 32))))
	if _t == SETTLE + MEASURE + 30:
		_check(_impulse_peak > 0.01, "an impulse on still water moves the surface: peak %.3f m/s" % _impulse_peak)
		_ok = _ok and _measured
		print("[water_batch] %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)


func _measure() -> void:
	# R7: the speed summed over a second is the height change over that second.
	var change: float = _sea.sample_height(Vector3(407, 0, 3)) - _height_start
	_check(absf(change) > 0.02 and absf(_speed_sum - change) < maxf(0.15 * absf(change), 0.02),
			"vertical speed integrates to the height change: %.3f m against %.3f m" % [_speed_sum, change])
	_check(absf(_still.sample_vertical_speed(Vector3(0, 0, 32))) < 0.001, "still water: %.5f m/s" % _still.sample_vertical_speed(Vector3(0, 0, 32)))

	# R10: the dip is where the hull is.
	var o := _offset_body.global_position
	var c := _center_body.global_position
	var at_offset := _share(_offset_wake, o + Vector3(0, 0, 6))
	var away_offset := _share(_offset_wake, o + Vector3(0, 0, -6))
	var at_center := _share(_center_wake, c)
	var away_center := _share(_center_wake, c + Vector3(0, 0, 6))
	_check(at_offset < -0.02 and absf(away_offset) < absf(at_offset) * 0.4,
			"hull_offset 6: dip %.3f m at 6 m ahead, %.3f m at 6 m behind" % [at_offset, away_offset])
	_check(at_center < -0.02 and absf(away_center) < absf(at_center) * 0.4,
			"hull_offset 0: dip %.3f m at the body, %.3f m at 6 m ahead" % [at_center, away_center])

	# R9: foam behind a propeller set from a script, and stern spray with it.
	var foam := _propeller_foam(_thrust_wake)
	var none := _propeller_foam(_center_wake)
	var want := _thrust_body.global_position + Vector3(3, 0, -0.6)
	_check(foam[0] > 0.1 and foam[1].distance_to(want) < 1.0, "propeller_thrust: foam %.1f around %s, want around %s" % [foam[0], foam[1].snappedf(0.1), want])
	_check(none[0] == 0.0, "no thrust, no propeller foam: %.3f" % none[0])
	_check(_emitter.amount_ratio > 0.5 and _idle_emitter.amount_ratio == 0.0, "stern spray: ratio %.2f at thrust 0.8, %.2f at thrust 0" % [_emitter.amount_ratio, _idle_emitter.amount_ratio])

	# R13: the bounds grow with the margin, also on a plain surface.
	var mesh := _mesh_of(_still)
	var plain := mesh.custom_aabb
	_check(plain.size.y >= 4.0, "plain surface has room for its waves: %.1f m tall" % plain.size.y)
	_still.set("cull_margin", 10.0)
	_check(is_equal_approx(mesh.custom_aabb.size.y, plain.size.y + 20.0), "cull_margin 10: %.1f m tall, was %.1f m" % [mesh.custom_aabb.size.y, plain.size.y])
	_still.set("cull_margin", 0.0)
	_check(is_equal_approx(mesh.custom_aabb.size.y, plain.size.y), "cull_margin 0 restores it")
	_measured = true
