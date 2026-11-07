extends SceneTree

# The jointed_position_iterations and jointed_velocity_iterations project settings (issue #8): defaults 8 and 2, and they
# reach the solver. Settings are read once at start, so the second half takes an override.cfg:
#   default run: both settings at their defaults, and a chain carrying a weight holds tight.
#   -- loose: run with both at 1 in override.cfg. The same chain stretches well past that.

const LINKS := 8
const LINK := 0.25
const SETTLE_TICKS := 300
const TIGHT := 0.1
const POSITION_SETTING := "physics/physx_3d/simulation/jointed_position_iterations"
const VELOCITY_SETTING := "physics/physx_3d/simulation/jointed_velocity_iterations"

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[solver_iters] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _body(parent: Node, at: Vector3, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.collision_layer = 0
	b.collision_mask = 0
	b.can_sleep = false
	var c := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.05
	c.shape = s
	b.add_child(c)
	b.position = at
	parent.add_child(b)
	return b


func _pin(parent: Node, a: PhysicsBody3D, b: PhysicsBody3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	parent.add_child(j)
	j.global_position = at
	j.node_a = a.get_path()
	j.node_b = b.get_path()


func _run() -> void:
	var loose := OS.get_cmdline_user_args().has("loose")
	var position_iterations: int = ProjectSettings.get_setting(POSITION_SETTING)
	var velocity_iterations: int = ProjectSettings.get_setting(VELOCITY_SETTING)
	if loose:
		_check(position_iterations == 1 and velocity_iterations == 1, "override.cfg has both settings at 1")
	else:
		_check(position_iterations == 8 and velocity_iterations == 2, "the defaults are 8 and 2 (got %d, %d)" % [position_iterations, velocity_iterations])

	var top := Vector3(0, 6, 0)
	var anchor := StaticBody3D.new()
	anchor.position = top
	get_root().add_child(anchor)
	var last: PhysicsBody3D = anchor
	for i in LINKS:
		var p := top + Vector3(0, -(i + 1) * LINK, 0)
		var b := _body(get_root(), p, 0.1 if i < LINKS - 1 else 3.0)
		_pin(get_root(), last, b, p + Vector3(0, LINK * 0.5, 0))
		last = b
	for i in SETTLE_TICKS:
		await physics_frame
	var stretch := top.distance_to((last as Node3D).global_position) - LINKS * LINK
	print("[solver_iters] chain stretch %.4f m at %d / %d" % [stretch, position_iterations, velocity_iterations])
	if loose:
		_check(stretch > TIGHT, "at 1 / 1 the chain stretches past %.2f m" % TIGHT)
	else:
		_check(stretch < TIGHT, "at the defaults the chain stays within %.2f m" % TIGHT)

	print("[solver_iters] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)
