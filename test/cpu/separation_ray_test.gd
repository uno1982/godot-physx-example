extends SceneTree

# SeparationRayShape3D: a CharacterBody3D standing on a ray (capsule held
# 0.5 m off the ground) rests at the ray's length, walks up a 0.3 m step the
# capsule clears, and walks back down off it; a ray-only character; a
# RigidBody3D on a ray. The expectations are Jolt's results; run on any engine:
#   godot --headless --path . --script res://test/cpu/separation_ray_test.gd

const GRAVITY := 18.0
const SPEED := 3.0

var _tick := 0
var _pass := true
var _rest: CharacterBody3D # stands still on flat ground
var _climber: CharacterBody3D # walks +X up a step and on
var _ray_only: CharacterBody3D # a ray and nothing else
var _rigid: RigidBody3D # a box on a ray
var _climber_floor_ticks := 0
var _climber_ticks := 0


func _initialize() -> void:
	print("[sepray] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)
	_static_box(root, Vector3(0, -0.5, 0), Vector3(60, 1, 20)) # ground, top at 0
	_static_box(root, Vector3(6, 0.15, 5), Vector3(4, 0.3, 4)) # step, top at 0.3, x 4..8 at z 5

	_rest = _character(root, Vector3(-10, 0.5, 0), true)
	_climber = _character(root, Vector3(1, 0.5, 5), true)
	_ray_only = _character(root, Vector3(-5, 0.5, 0), false)

	_rigid = RigidBody3D.new()
	var box := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.4, 0.6)
	box.shape = bs
	box.position = Vector3(0, 1.0, 0)
	_rigid.add_child(box)
	_rigid.add_child(_ray(1.0, 1.0))
	_rigid.position = Vector3(10, 0.5, 0)
	_rigid.axis_lock_angular_x = true
	_rigid.axis_lock_angular_z = true
	root.add_child(_rigid)


func _static_box(root: Node, pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	sb.position = pos
	root.add_child(sb)


# A ray from p_from_y (body space) straight down, p_length long.
func _ray(p_from_y: float, p_length: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var ray := SeparationRayShape3D.new()
	ray.length = p_length
	cs.shape = ray
	cs.position = Vector3(0, p_from_y, 0)
	cs.rotation_degrees = Vector3(90, 0, 0) # the ray runs along +Z; this points it down
	return cs


# Body origin = the ray's tip: the ray runs from y 1.0 down to 0.0, and the
# capsule (with_capsule) spans y 0.5..1.5 -- 0.5 m of clearance for steps.
func _character(root: Node, pos: Vector3, with_capsule: bool) -> CharacterBody3D:
	var ch := CharacterBody3D.new()
	if with_capsule:
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.0
		cs.shape = cap
		cs.position = Vector3(0, 1.0, 0)
		ch.add_child(cs)
	ch.add_child(_ray(1.0, 1.0))
	ch.position = pos
	root.add_child(ch)
	return ch


func _step(ch: CharacterBody3D, vx: float, delta: float) -> void:
	var v := ch.velocity
	v.x = vx
	v.y = -0.1 if ch.is_on_floor() else v.y - GRAVITY * delta
	ch.velocity = v
	ch.move_and_slide()


func _physics_process(delta: float) -> bool:
	_tick += 1
	_step(_rest, 0.0, delta)
	_step(_ray_only, 0.0, delta)
	# Walk +X for 3 s: onto the step at x 4 (0.3 m up), off it at x 8.
	_step(_climber, SPEED if _tick <= 180 else 0.0, delta)
	if _tick > 30 and _tick <= 180:
		_climber_ticks += 1
		_climber_floor_ticks += 1 if _climber.is_on_floor() else 0
	if _tick == 120:
		# Mid-step (x ~ 6): standing on the step top.
		_check("climber up on the 0.3 m step (y)", _climber.position.y, 0.3, 0.05)
	if _tick == 240:
		_check("resting character stands on its ray (y)", _rest.position.y, 0.0, 0.03)
		_check("resting character is on the floor", 1.0 if _rest.is_on_floor() else 0.0, 1.0, 0.0)
		_check("ray-only character stands on its ray (y)", _ray_only.position.y, 0.0, 0.03)
		_check("climber walked on past the step (x)", _climber.position.x, 1.0 + SPEED * 3.0, 0.5)
		_check("climber back on the ground (y)", _climber.position.y, 0.0, 0.05)
		_check("climber on the floor most of the walk", float(_climber_floor_ticks) / _climber_ticks, 1.0, 0.1)
		_check("rigid body rests on its ray (y)", _rigid.position.y, 0.0, 0.1)
		print("[sepray] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false


func _check(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	print("  [%s] %-44s got %.3f want %.3f" % ["ok" if ok else "FAIL", label, got, want])
	if not ok:
		_pass = false
