extends SceneTree

# RigidBody3D / PhysicsDirectBodyState3D features that must behave the same as
# on Jolt: constant forces, direct-state torque and mass queries, custom
# inertia, center-of-mass reset, axis velocity, and a CharacterBody3D riding a
# spinning platform (velocity at a point includes the spin).
# Run on any engine; Jolt is the reference:
#   godot --headless --path . --script res://test/cpu/body_parity_test.gd

const DT := 1.0 / 60.0

var _tick := 0
var _pass := true

var _push: RigidBody3D # constant_force
var _spin: RigidBody3D # constant_torque
var _offset: RigidBody3D # add_constant_force at an offset -> torque
var _ds_torque: RigidBody3D # direct-state apply_torque every tick
var _ds_force: RigidBody3D # direct-state apply_force at an offset every tick
var _inertia: RigidBody3D # custom inertia
var _auto_inertia: RigidBody3D # same box, shape-computed inertia
var _com: RigidBody3D # custom COM, then back to AUTO
var _spinner: RigidBody3D # velocity at a point
var _axis: RigidBody3D # body_set_axis_velocity
var _platform: AnimatableBody3D
var _rider: CharacterBody3D
var _rider_start_angle := 0.0
var _platform_angle := 0.0

const PLATFORM_SPIN := 0.5 # rad/s
const RIDER_RADIUS := 3.0


func _initialize() -> void:
	print("[parity] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	_push = _body(root, Vector3(0, 50, 0), _sphere(0.5), 2.0)
	_push.constant_force = Vector3(10, 0, 0)

	_spin = _body(root, Vector3(5, 50, 0), _sphere(0.5), 1.0)
	_spin.constant_torque = Vector3(0, 1, 0)

	_offset = _body(root, Vector3(10, 50, 0), _sphere(0.5), 1.0)

	_ds_torque = _body(root, Vector3(15, 50, 0), _sphere(0.5), 1.0)
	_ds_force = _body(root, Vector3(45, 50, 0), _sphere(0.5), 1.0)

	_inertia = _body(root, Vector3(20, 50, 0), _box(Vector3.ONE), 1.0)
	_inertia.inertia = Vector3(1, 1, 1)
	_auto_inertia = _body(root, Vector3(25, 50, 0), _box(Vector3.ONE), 1.0)

	_com = _body(root, Vector3(30, 50, 0), _box(Vector3.ONE), 1.0)
	_com.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_com.center_of_mass = Vector3(0.5, 0, 0)

	_spinner = _body(root, Vector3(35, 50, 0), _sphere(0.5), 1.0)
	_axis = _body(root, Vector3(40, 50, 0), _sphere(0.5), 1.0)

	# Spinning platform with a character standing near its rim.
	_platform = AnimatableBody3D.new()
	_platform.sync_to_physics = false
	var pc := CollisionShape3D.new()
	pc.shape = _box(Vector3(10, 1, 10))
	_platform.add_child(pc)
	_platform.position = Vector3(0, -0.5, -40)
	root.add_child(_platform)

	_rider = CharacterBody3D.new()
	var rc := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	rc.shape = cap
	_rider.add_child(rc)
	_rider.position = _platform.position + Vector3(RIDER_RADIUS, 1.0, 0)
	root.add_child(_rider)
	# Root sits at the origin, so local positions are global ones.
	_rider_start_angle = _rider_angle()


func _sphere(r: float) -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _box(size: Vector3) -> Shape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _body(root: Node, pos: Vector3, shape: Shape3D, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	rb.position = pos
	rb.mass = mass
	rb.gravity_scale = 0.0
	rb.can_sleep = false
	# No project-default damping, so the expected velocities are exact.
	rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	rb.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.add_child(rb)
	return rb


func _rider_angle() -> float:
	var d := _rider.position - _platform.position
	return atan2(-d.z, d.x)


func _ds(rb: RigidBody3D) -> PhysicsDirectBodyState3D:
	return PhysicsServer3D.body_get_direct_state(rb.get_rid())


func _physics_process(_delta: float) -> bool:
	_tick += 1

	# The platform turns about +Y; the rider just stands still on it.
	_platform_angle += PLATFORM_SPIN * DT
	_platform.rotation.y = _platform_angle
	_rider.velocity.y -= 9.8 * DT
	_rider.velocity.x = 0.0
	_rider.velocity.z = 0.0
	_rider.move_and_slide()

	_ds(_ds_torque).apply_torque(Vector3(0, 1, 0))
	_ds(_ds_force).apply_force(Vector3(0, 0, 1), Vector3(1, 0, 0))

	if _tick == 1:
		# Needs the body in a space (Jolt errors otherwise).
		_offset.add_constant_force(Vector3(0, 0, 1), Vector3(1, 0, 0))
	if _tick == 2:
		_inertia.apply_torque_impulse(Vector3(0, 1, 0))
		_auto_inertia.apply_torque_impulse(Vector3(0, 1, 0))
		_spinner.angular_velocity = Vector3(0, 1, 0)
		_axis.linear_velocity = Vector3(3, 4, 0)
		PhysicsServer3D.body_set_axis_velocity(_axis.get_rid(), Vector3(0, 7, 0))
	if _tick == 4:
		_check_near("custom inertia (1,1,1): torque impulse 1 -> w.y 1", _inertia.angular_velocity.y, 1.0, 0.05)
		_check_near("auto inertia unit box: torque impulse 1 -> w.y 6", _auto_inertia.angular_velocity.y, 6.0, 0.3)
		_check_near("custom inertia readback (param)", Vector3(PhysicsServer3D.body_get_param(_inertia.get_rid(), PhysicsServer3D.BODY_PARAM_INERTIA)).y, 1.0, 0.001)
		_check_near("inverse inertia of custom body", _ds(_inertia).inverse_inertia.y, 1.0, 0.01)
		_check_near("inverse inertia of auto unit box", _ds(_auto_inertia).inverse_inertia.y, 6.0, 0.3)
		_check_near("axis velocity keeps x", _axis.linear_velocity.x, 3.0, 0.05)
		_check_near("axis velocity replaces y", _axis.linear_velocity.y, 7.0, 0.05)

		var com_local: Vector3 = _ds(_com).center_of_mass_local
		_check_near("custom COM local x", com_local.x, 0.5, 0.01)
		_com.rotation.y = PI / 2.0 # local +X now points to world -Z
	if _tick == 6:
		var com_rel: Vector3 = _ds(_com).center_of_mass
		_check_near("custom COM relative, rotated: z", com_rel.z, -0.5, 0.02)
		_check_near("custom COM relative, rotated: x", com_rel.x, 0.0, 0.02)
		var vel := _ds(_spinner).get_velocity_at_local_position(Vector3(1, 0, 0))
		_check_near("velocity at +X on a +Y spin: z", vel.z, -1.0, 0.02)
		_com.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
	if _tick == 8:
		_check_near("COM back to AUTO is centered", _ds(_com).center_of_mass_local.length(), 0.0, 0.01)

		_ds(_push).collision_layer = 4
		_check("direct-state collision_layer round trips", _ds(_push).collision_layer == 4)

	if _tick == 61:
		# ~1 s after start: v = F/m * t, w = T/I * t (sphere I = 0.4 m r^2 = 0.1).
		var t := 60 * DT
		_check_near("constant_force: v.x = F/m t", _push.linear_velocity.x, 10.0 / 2.0 * t, 0.3)
		_check_near("constant_force readback", _push.constant_force.x, 10.0, 0.001)
		_check_near("constant_torque: w.y = T/I t", _spin.angular_velocity.y, 1.0 / 0.1 * t, 0.6)
		_check_near("offset constant force -> torque about -Y", _offset.angular_velocity.y, -1.0 / 0.1 * t, 0.6)
		_check_near("direct-state apply_torque each tick", _ds_torque.angular_velocity.y, 1.0 / 0.1 * t, 0.6)
		_check_near("direct-state apply_force at offset: v.z", _ds_force.linear_velocity.z, 1.0 * t, 0.1)
		_check_near("direct-state apply_force at offset: w.y", _ds_force.angular_velocity.y, -1.0 / 0.1 * t, 0.6)

	if _tick >= 240:
		var turned := wrapf(_rider_angle() - _rider_start_angle, -PI, PI)
		var expected := wrapf(_platform_angle, -PI, PI)
		print("[parity] rider turned %.2f rad, platform %.2f rad, radius %.2f" % [turned, expected, Vector2(_rider.position.x - _platform.position.x, _rider.position.z - _platform.position.z).length()])
		_check_near("rider rides the spinning platform", turned, expected, 0.15)
		print("[parity] ", "PASS" if _pass else "FAIL")
		quit(0 if _pass else 1)
		return true
	return false


func _check_near(label: String, got: float, want: float, tol: float) -> void:
	var ok := absf(got - want) <= tol
	print("  [%s] %s (got %.3f, want %.3f)" % ["ok" if ok else "FAIL", label, got, want])
	if not ok:
		_pass = false


func _check(label: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_pass = false
