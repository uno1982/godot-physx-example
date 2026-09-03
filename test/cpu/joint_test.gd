extends SceneTree

var _pendulum: RigidBody3D
var _door: RigidBody3D
var _tick := 0
var _setup := false

func _initialize() -> void:
	print("[joint] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	root.name = "Root"

	var anchor := StaticBody3D.new()
	anchor.name = "Anchor"
	_box_shape(anchor, Vector3(0.4, 0.4, 0.4))
	anchor.position = Vector3(0, 5, 0)
	root.add_child(anchor)

	_pendulum = RigidBody3D.new()
	_pendulum.name = "Pendulum"
	_box_shape(_pendulum, Vector3(0.5, 0.5, 0.5))
	_pendulum.position = Vector3(3, 5, 0)
	root.add_child(_pendulum)

	var pin := PinJoint3D.new()
	pin.name = "Pin"
	pin.position = Vector3(0, 5, 0)
	root.add_child(pin)

	var frame := StaticBody3D.new()
	frame.name = "Frame"
	_box_shape(frame, Vector3(0.2, 3, 0.2))
	frame.position = Vector3(-5, 1.5, 0)
	root.add_child(frame)

	_door = RigidBody3D.new()
	_door.name = "Door"
	_box_shape(_door, Vector3(2, 3, 0.15))
	_door.position = Vector3(-4, 1.5, 0)
	_door.gravity_scale = 0.0
	root.add_child(_door)

	var hinge := HingeJoint3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(-5, 1.5, 0)
	hinge.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(hinge)

	get_root().add_child(root)

	# Now that everything is in the tree, wire the joints.
	pin.node_a = pin.get_path_to(anchor)
	pin.node_b = pin.get_path_to(_pendulum)
	hinge.node_a = hinge.get_path_to(frame)
	hinge.node_b = hinge.get_path_to(_door)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, 0.0)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(90))

func _box_shape(body: Node, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)

func _physics_process(_delta: float) -> bool:
	_tick += 1
	if not _setup:
		_setup = true
		_door.apply_torque_impulse(Vector3(0, 8, 0))
	if _tick % 40 == 0:
		var pd := _pendulum.global_position.distance_to(Vector3(0, 5, 0))
		print("[joint] t%d  pendulum_dist=%.2f  door_yaw=%.1f deg" % [
			_tick, pd, rad_to_deg(_door.global_rotation.y)])
	if _tick >= 200:
		var pd := _pendulum.global_position.distance_to(Vector3(0, 5, 0))
		var yaw := absf(rad_to_deg(_door.global_rotation.y))
		var ok := pd > 2.5 and pd < 3.6 and yaw > 10.0 and yaw < 96.0
		print("[joint] pendulum_dist=%.2f  door_yaw=%.1f -> %s" % [pd, yaw, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
