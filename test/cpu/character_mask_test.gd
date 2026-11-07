extends SceneTree

# A CharacterBody3D's motion goes by its own collision_mask only, as on Godot Physics and Jolt: a body it doesn't mask
# isn't an obstacle or a floor to it, even if that body masks the character (which still bounces off it).
# Reported as debris carrying the player off: thin leaves on layer 2, mask 3, sliding along the floor under its feet.

const LEAF_MASK := 3 # the character's layer: leaves still bounce off the character

var _rigs := {}
var _t := 0
var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[char_mask] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _character(key: String, pos: Vector3) -> CharacterBody3D:
	var c := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	c.add_child(cs)
	c.position = pos
	get_root().add_child(c)
	if not key.is_empty():
		_rigs[key] = {"char": c, "start": pos, "moved": 0.0, "rise": 0.0}
	return c


func _box(body: PhysicsBody3D, size: Vector3, pos: Vector3, layer: int, mask: int) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = mask
	get_root().add_child(body)


# Slides along the floor, right under the character's feet.
func _skim(z: float, layer: int, mask: int) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 0.12
	rb.linear_velocity = Vector3(-15, 0, 0)
	_box(rb, Vector3(0.3, 0.03, 0.3), Vector3(3, 0.016, z), layer, mask)


func _initialize() -> void:
	print("[char_mask] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	_box(StaticBody3D.new(), Vector3(200, 1, 200), Vector3(0, -0.5, 0), 1 | 16, 0)
	_character("not masked", Vector3(0, 0.91, -6))
	_character("masked", Vector3(0, 0.91, 6))
	_character("alone", Vector3(0, 0.91, 12))

	# test_move, either way round.
	_box(StaticBody3D.new(), Vector3(0.2, 3, 3), Vector3(21, 1.5, 0), 2, 1) # masks the character, isn't masked by it
	_box(StaticBody3D.new(), Vector3(0.2, 3, 3), Vector3(21, 1.5, 20), 1, 0) # masked by the character, masks nothing
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t == 2:
		var a := _character("", Vector3(20, 0.91, 0))
		var b := _character("", Vector3(20, 0.91, 20))
		_check(not a.test_move(a.global_transform, Vector3(2, 0, 0)), "test_move: a wall that masks the character but isn't masked by it isn't in the way")
		_check(b.test_move(b.global_transform, Vector3(2, 0, 0)), "test_move: a wall the character masks is")
		a.queue_free()
		b.queue_free()
	if _t >= 30 and _t <= 300 and _t % 10 == 0:
		_skim(-6.0, 2, LEAF_MASK)
		_skim(6.0, 1, 1)
	for k in _rigs:
		var r: Dictionary = _rigs[k]
		var c: CharacterBody3D = r.char
		c.velocity = Vector3(0, -0.1 if c.is_on_floor() else c.velocity.y - 18.0 / 60.0, 0)
		c.move_and_slide()
		if _t > 20:
			r.moved = maxf(r.moved, Vector2(c.position.x - r.start.x, c.position.z - r.start.z).length())
			r.rise = maxf(r.rise, c.position.y - r.start.y)
	if _t == 360:
		_check(_rigs["alone"].moved < 0.0001, "alone it stands still: %.4f m" % _rigs["alone"].moved)
		_check(_rigs["not masked"].moved < 0.001, "what it doesn't mask doesn't carry it: %.3f m" % _rigs["not masked"].moved)
		_check(_rigs["not masked"].rise < 0.001, "or lift it: %.3f m" % _rigs["not masked"].rise)
		_check(_rigs["masked"].moved > 0.01 or _rigs["masked"].rise > 0.005, "what it does mask still reaches it: moved %.3f m, rose %.3f m" % [_rigs["masked"].moved, _rigs["masked"].rise])
		print("[char_mask] %s" % ("PASS" if _ok else "FAIL"))
		quit(0 if _ok else 1)
