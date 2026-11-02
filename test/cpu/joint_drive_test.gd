extends SceneTree

# uno1982/godot#7: active-ragdoll joint drives, beyond Godot's joint API (PhysX.joint_*).
# Unit boxes (1 kg, I = 1/6 kg m^2) on joints to static anchors, gravity off:
#   SLERP drive: a Generic6DOF with its default (locked) angular limits, a cone twist
#     and a hinge each turn body B to the drive target -- set in one call, as a
#     relative transform or from two poses -- and follow a target that moves every frame;
#   a driven hinge (rebuilt as a D6) keeps the revolute hinge's limits, motor direction
#     and motor torque;
#   spring force limits: a stiff angular spring capped at 0.5 N m spins up at
#     3 rad/s^2, a stiff linear spring capped at 2 N slides at 2 m/s^2;
#   acceleration drives turn a 1 kg and a 10 kg box alike (force drives don't);
#   a new spring equilibrium point takes over from a drive target; drives set before
#     the Joint3D has made its joint act once it has;
#   a target given with the time since the last one (delta) is driven at its own
#     velocity too: a 6DOF SLERP and a hinge then trail a moving target by only the
#     step it waits for, where without it the drive's damping holds them back;
#   PhysX.physical_bone_get_joint() finds every PhysicalBone3D's joint, and a mannequin
#     whose joints are SLERP-driven to the pose they start in holds that pose as it
#     falls, where a limp one crumples.

var _ok := true
var _t := 0
var _x := 0.0
var _boxes := {}
var _joints := {}
var _anchors := {}
var _driven_bones: Array[PhysicalBone3D] = []
var _limp_bones: Array[PhysicalBone3D] = []
var _bone_rest := {}
var _hinge_spin := {}
var _simulators: Array[PhysicalBoneSimulator3D] = []


func _check(cond: bool, msg: String) -> void:
	print("[joint_drive] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _box(name: String, joint: Joint3D, mass := 1.0) -> RigidBody3D:
	var anchor := StaticBody3D.new()
	anchor.position = Vector3(_x, 5, 0)
	get_root().add_child(anchor)
	var box := RigidBody3D.new()
	box.position = Vector3(_x, 5, 0)
	box.gravity_scale = 0.0
	box.mass = mass
	box.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	box.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	box.can_sleep = false
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3.ONE
	cs.shape = b
	box.add_child(cs)
	get_root().add_child(box)
	joint.position = Vector3(_x, 5, 0)
	get_root().add_child(joint)
	joint.node_a = joint.get_path_to(anchor)
	joint.node_b = joint.get_path_to(box)
	_x += 6.0
	_boxes[name] = box
	_joints[name] = joint
	_anchors[name] = anchor
	return box


func _angle(a: Basis, b: Basis) -> float:
	return (a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()).get_angle()


func _rid(name: String) -> RID:
	return (_joints[name] as Joint3D).get_rid()


func _bone_parent(bone: PhysicalBone3D, bones: Array[PhysicalBone3D]) -> PhysicalBone3D:
	var skel: Skeleton3D = bone.get_parent().get_parent()
	var id := skel.get_bone_parent(bone.get_bone_id())
	while id >= 0:
		for b in bones:
			if b.get_bone_id() == id:
				return b
		id = skel.get_bone_parent(id)
	return null


# The mass of a bone and every bone beyond it.
func _carried(bone: PhysicalBone3D) -> float:
	var m := bone.mass
	for other in _driven_bones:
		if other != bone and _bone_parent(other, _driven_bones) == bone:
			m += _carried(other)
	return m


func _relative(bone: PhysicalBone3D, bones: Array[PhysicalBone3D]) -> Basis:
	var parent := _bone_parent(bone, bones)
	return parent.global_basis.inverse() * bone.global_basis


func _ragdoll(x: float) -> void:
	var mann: Node3D = (load("res://demo/common/mannequin/mannequin_ragdoll.tscn") as PackedScene).instantiate()
	mann.position = Vector3(x, 1.2, 40)
	get_root().add_child(mann)
	_simulators.append(mann.find_child("PhysicalBoneSimulator3D", true, false))


# Once the mannequins are ready (they add their clavicle bones then).
func _gather_bones() -> void:
	for i in 2:
		for c in _simulators[i].get_children():
			if c is PhysicalBone3D:
				(_driven_bones if i == 0 else _limp_bones).append(c)


func _initialize() -> void:
	print("[joint_drive] engine: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	_box("slerp6", Generic6DOFJoint3D.new())
	var cone := ConeTwistJoint3D.new()
	cone.swing_span = deg_to_rad(60.0)
	_box("cone", cone)
	var hinge := HingeJoint3D.new()
	_box("hinge", hinge)
	_box("follow", Generic6DOFJoint3D.new())
	_box("follow_vel", Generic6DOFJoint3D.new())
	_box("hinge_vel", HingeJoint3D.new())
	# Revolute vs D6 hinges side by side: limit [-0.1, 0.5] under a steady torque, then a torque-limited motor.
	for n in ["hinge_rev", "hinge_d6"]:
		var h := HingeJoint3D.new()
		h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -0.1)
		h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, 0.5)
		_box(n, h)
	for n in ["motor_rev", "motor_d6"]:
		var h := HingeJoint3D.new()
		h.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
		h.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 10.0)
		h.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, 0.5 / 60.0) # 0.5 N m at 60 Hz
		_box(n, h)
	var torque := Generic6DOFJoint3D.new()
	torque.set("angular_spring_y/enabled", true)
	torque.set("angular_spring_y/stiffness", 1.0e4)
	torque.set("angular_spring_y/damping", 0.0)
	torque.set("angular_limit_y/enabled", false)
	_box("torque", torque)
	var force := Generic6DOFJoint3D.new()
	force.set("linear_spring_x/enabled", true)
	force.set("linear_spring_x/stiffness", 1.0e4)
	force.set("linear_spring_x/damping", 0.0)
	force.set("linear_limit_x/enabled", false)
	_box("force", force)
	for n in ["acc_light", "acc_heavy", "frc_light", "frc_heavy"]:
		_box(n, Generic6DOFJoint3D.new(), 10.0 if n.ends_with("heavy") else 1.0)
	var eq := Generic6DOFJoint3D.new()
	eq.set("angular_spring_z/enabled", true)
	_box("eq", eq)
	# Set before the Joint3D has made its joint (the root isn't in the tree yet): kept for when it is.
	_box("early", Generic6DOFJoint3D.new())
	PhysX.joint_set_slerp_drive(_rid("early"), true, 200.0, 30.0)
	PhysX.joint_set_drive_target(_rid("early"), Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3.ZERO))
	var floor := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(20, 1, 20)
	fcs.shape = fb
	floor.add_child(fcs)
	floor.position = Vector3(2, -0.5, 40)
	get_root().add_child(floor)
	_ragdoll(0.0)
	_ragdoll(4.0)
	physics_frame.connect(_tick)


func _start() -> void:
	_gather_bones()
	PhysX.joint_set_slerp_drive(_rid("slerp6"), true, 200.0, 30.0)
	PhysX.joint_set_drive_target(_rid("slerp6"), Transform3D(Basis(Vector3(1, 1, 0).normalized(), 0.8), Vector3.ZERO))
	_check(PhysX.joint_is_slerp_drive_enabled(_rid("slerp6")), "joint_is_slerp_drive_enabled")
	var got := PhysX.joint_get_drive_target(_rid("slerp6"))
	_check(_angle(got.basis, Basis(Vector3(1, 1, 0).normalized(), 0.8)) < 1e-4, "joint_get_drive_target returns the target")

	PhysX.joint_set_slerp_drive(_rid("cone"), true, 200.0, 30.0)
	var anchor: StaticBody3D = _anchors["cone"]
	PhysX.joint_set_drive_target_from_poses(_rid("cone"), anchor.global_transform,
			Transform3D(Basis(Vector3.UP, 0.5), (_boxes["cone"] as Node3D).global_position))

	PhysX.joint_set_slerp_drive(_rid("hinge"), true, 200.0, 30.0)
	PhysX.joint_set_drive_target(_rid("hinge"), Transform3D(Basis(Vector3.BACK, 0.6), Vector3.ZERO))

	PhysX.joint_set_slerp_drive(_rid("follow"), true, 2000.0, 40.0)
	PhysX.joint_set_slerp_drive(_rid("follow_vel"), true, 2000.0, 90.0)
	PhysX.joint_set_slerp_drive(_rid("hinge_vel"), true, 2000.0, 90.0)

	PhysX.joint_set_slerp_drive(_rid("hinge_d6"), true) # no stiffness, no damping: only the D6 rebuild
	PhysX.joint_set_slerp_drive(_rid("motor_d6"), true)

	PhysX.joint_set_drive_target(_rid("torque"), Transform3D(Basis(Vector3.UP, 1.5), Vector3.ZERO))
	PhysX.joint_set_angular_spring_torque_limit(_rid("torque"), Vector3.AXIS_Y, 0.5)
	PhysX.joint_set_linear_spring_force_limit(_rid("force"), Vector3.AXIS_X, 2.0)
	PhysX.joint_set_drive_target(_rid("force"), Transform3D(Basis(), Vector3(2, 0, 0)))
	_check(is_equal_approx(PhysX.joint_get_angular_spring_torque_limit(_rid("torque"), Vector3.AXIS_Y), 0.5), "torque limit reads back")
	_check(is_inf(PhysX.joint_get_angular_spring_torque_limit(_rid("torque"), Vector3.AXIS_X)), "unset limits are infinite")

	for n in ["acc_light", "acc_heavy", "frc_light", "frc_heavy"]:
		PhysX.joint_set_slerp_drive(_rid(n), true, 50.0, 2.0)
		PhysX.joint_set_drive_acceleration(_rid(n), n.begins_with("acc"))
		PhysX.joint_set_drive_target(_rid(n), Transform3D(Basis(Vector3.UP, 0.5), Vector3.ZERO))
	_check(PhysX.joint_is_drive_acceleration(_rid("acc_light")) and not PhysX.joint_is_drive_acceleration(_rid("frc_light")), "joint_is_drive_acceleration")

	PhysX.joint_set_drive_target(_rid("eq"), Transform3D(Basis(Vector3.UP, 0.3), Vector3.ZERO))
	(_joints["eq"] as Generic6DOFJoint3D).set("angular_spring_z/equilibrium_point", 0.4)
	var eq_target := PhysX.joint_get_drive_target(_rid("eq"))
	_check(_angle(eq_target.basis, Basis(Vector3.BACK, -0.4)) < 1e-4, "a new equilibrium point replaces the drive target (got %s)" % eq_target.basis.get_euler())

	# The ragdolls: every bone's joint found, and the driven one held at the pose it starts in.
	var found := 0
	var with_joint := 0
	var type_ok := true
	var map := {PhysicalBone3D.JOINT_TYPE_PIN: PhysicsServer3D.JOINT_TYPE_PIN, PhysicalBone3D.JOINT_TYPE_CONE: PhysicsServer3D.JOINT_TYPE_CONE_TWIST,
			PhysicalBone3D.JOINT_TYPE_HINGE: PhysicsServer3D.JOINT_TYPE_HINGE, PhysicalBone3D.JOINT_TYPE_SLIDER: PhysicsServer3D.JOINT_TYPE_SLIDER,
			PhysicalBone3D.JOINT_TYPE_6DOF: PhysicsServer3D.JOINT_TYPE_6DOF}
	for b in _driven_bones:
		var j := PhysX.physical_bone_get_joint(b)
		if b.joint_type == PhysicalBone3D.JOINT_TYPE_NONE or _bone_parent(b, _driven_bones) == null:
			_check(not j.is_valid(), "%s has no joint" % b.name)
			continue
		with_joint += 1
		if j.is_valid():
			found += 1
			type_ok = type_ok and PhysicsServer3D.joint_get_type(j) == map[b.joint_type]
			# Acceleration drives count only the two bones at the joint: scale by the mass the joint carries.
			var k := 2000.0 * _carried(b) / b.mass
			PhysX.joint_set_slerp_drive(j, true, k, 2.0 * sqrt(k))
			PhysX.joint_set_drive_acceleration(j, true)
			PhysX.joint_set_drive_target_from_poses(j, _bone_parent(b, _driven_bones).global_transform, b.global_transform)
	_check(found == with_joint and with_joint >= 10, "physical_bone_get_joint finds %d / %d bone joints" % [found, with_joint])
	_check(type_ok, "each bone's joint is of the bone's joint type")
	for bones in [_driven_bones, _limp_bones]:
		for b in bones:
			if _bone_parent(b, bones) != null:
				_bone_rest[b] = _relative(b, bones)


func _pose_drift(bones: Array[PhysicalBone3D]) -> Vector2:
	var worst := 0.0
	var sum := 0.0
	var n := 0
	for b in bones:
		if _bone_rest.has(b):
			var d := _angle(_bone_rest[b], _relative(b, bones))
			if OS.get_environment("JOINT_DRIVE_VERBOSE") != "":
				print("[joint_drive]   %s (joint type %d): %.3f rad" % [b.name, b.joint_type, d])
			worst = maxf(worst, d)
			sum += d
			n += 1
	return Vector2(sum / maxf(n, 1), worst)


func _tick() -> void:
	_t += 1
	if _t == 5:
		_start()
	if _t > 5:
		# 6 Nm on both limited hinges (B turns positively about the joint's Z).
		for n in ["hinge_rev", "hinge_d6"]:
			(_boxes[n] as RigidBody3D).apply_torque(Vector3(0, 0, 6.0))
			(_boxes[n] as RigidBody3D).apply_torque(Vector3(0, 0, -12.0) if _t > 65 else Vector3.ZERO)
		# A moving target, set every frame in one call: a turn about Y at 1 rad/s.
		PhysX.joint_set_drive_target(_rid("follow"), Transform3D(Basis(Vector3.UP, (_t - 5) / 60.0), Vector3.ZERO))
		# The same turn (heavier damping, which alone would lag 0.045 rad), with the time since the last target.
		PhysX.joint_set_drive_target(_rid("follow_vel"), Transform3D(Basis(Vector3.UP, (_t - 5) / 60.0), Vector3.ZERO), 1.0 / 60.0)
		PhysX.joint_set_drive_target(_rid("hinge_vel"), Transform3D(Basis(Vector3.BACK, (_t - 5) / 60.0), Vector3.ZERO), 1.0 / 60.0)
	if _t == 35: # 0.5 s
		var w := absf((_boxes["torque"] as RigidBody3D).angular_velocity.y)
		_check(absf(w - 1.5) < 0.25, "angular spring torque limit: 0.5 N m spins up to 1.5 rad/s in 0.5 s (got %.2f)" % w)
		var v := absf((_boxes["force"] as RigidBody3D).linear_velocity.x)
		_check(absf(v - 1.0) < 0.15, "linear spring force limit: 2 N slides 1 kg to 1.0 m/s in 0.5 s (got %.2f)" % v)
		for n in ["motor_rev", "motor_d6"]:
			_hinge_spin[n] = (_boxes[n] as RigidBody3D).angular_velocity.z
		print("[joint_drive] hinge motor after 0.5 s: revolute %.3f, D6 %.3f rad/s" % [_hinge_spin.motor_rev, _hinge_spin.motor_d6])
		_check(absf(_hinge_spin.motor_d6 - _hinge_spin.motor_rev) < 0.1 and absf(_hinge_spin.motor_rev) > 0.5,
				"a driven hinge's motor turns the same way, as hard, as the revolute one")
	if _t == 17: # 0.2 s into the acceleration drives
		var a := {}
		for n in ["acc_light", "acc_heavy", "frc_light", "frc_heavy"]:
			a[n] = _angle(Basis(), (_boxes[n] as Node3D).global_basis)
		print("[joint_drive] after 0.2 s: accel light %.3f heavy %.3f, force light %.3f heavy %.3f rad" % [a.acc_light, a.acc_heavy, a.frc_light, a.frc_heavy])
		_check(absf(a.acc_light - a.acc_heavy) < 0.05 * a.acc_light and a.acc_light > 0.05, "acceleration drives turn a 1 kg and a 10 kg box alike")
		_check(a.frc_heavy < 0.5 * a.frc_light, "force drives turn the 10 kg box slower")
	if _t == 65:
		var lim := {}
		for n in ["hinge_rev", "hinge_d6"]:
			lim[n] = (_boxes[n] as Node3D).global_basis.get_euler().z
		print("[joint_drive] hinge pushed +z to its limit: revolute %.3f, D6 %.3f rad" % [lim.hinge_rev, lim.hinge_d6])
		_check(absf(lim.hinge_d6 - lim.hinge_rev) < 0.03, "a driven hinge stops at the revolute hinge's upper limit")
	if _t == 125:
		var lim := {}
		for n in ["hinge_rev", "hinge_d6"]:
			lim[n] = (_boxes[n] as Node3D).global_basis.get_euler().z
		print("[joint_drive] hinge pushed -z to its limit: revolute %.3f, D6 %.3f rad" % [lim.hinge_rev, lim.hinge_d6])
		_check(absf(lim.hinge_d6 - lim.hinge_rev) < 0.03, "a driven hinge stops at the revolute hinge's lower limit")
	if _t == 125: # 2 s
		var b6: Node3D = _boxes["slerp6"]
		var e := _angle(b6.global_basis, Basis(Vector3(1, 1, 0).normalized(), 0.8))
		_check(e < 0.03, "SLERP drive on a Generic6DOF (locked angular limits) reaches the target: %.3f rad off" % e)
		var bc: Node3D = _boxes["cone"]
		e = _angle(bc.global_basis, Basis(Vector3.UP, 0.5))
		_check(e < 0.03, "SLERP drive on a cone twist, target from poses: %.3f rad off" % e)
		var bh: Node3D = _boxes["hinge"]
		e = _angle(bh.global_basis, Basis(Vector3.BACK, 0.6))
		_check(e < 0.03, "SLERP drive on a hinge turns it to the target angle: %.3f rad off (at %s)" % [e, bh.global_basis.get_euler()])
		var be: Node3D = _boxes["early"]
		e = _angle(be.global_basis, Basis(Vector3.RIGHT, 0.7))
		_check(e < 0.03, "drives set before the joint was made act once it is: %.3f rad off" % e)
		var bf: Node3D = _boxes["follow"]
		e = _angle(bf.global_basis, Basis(Vector3.UP, (_t - 5) / 60.0))
		# A drive damps toward zero velocity: it lags a moving target by damping * speed / stiffness = 0.02 rad, plus the
		# step the new target waits for (1/60 rad).
		_check(e < 0.05, "a target set every frame is followed: %.3f rad behind" % e)
		var bv: Node3D = _boxes["follow_vel"]
		e = _angle(bv.global_basis, Basis(Vector3.UP, (_t - 5) / 60.0))
		_check(e < 0.02, "with delta, a 6DOF SLERP moves with the target: %.4f rad behind (one step: 0.0167)" % e)
		var bhv: Node3D = _boxes["hinge_vel"]
		e = _angle(bhv.global_basis, Basis(Vector3.BACK, (_t - 5) / 60.0))
		_check(e < 0.02, "with delta, a hinge moves with the target: %.4f rad behind (one step: 0.0167)" % e)
		var held := _pose_drift(_driven_bones)
		var limp := _pose_drift(_limp_bones)
		print("[joint_drive] ragdoll pose drift after 2 s: driven mean %.3f max %.3f, limp mean %.3f max %.3f rad" % [held.x, held.y, limp.x, limp.y])
		# Dropped 1.2 m onto the floor with nothing holding it up: the joints take the landing (~0.2 rad on average,
		# the clavicles and knees most); the limp one folds up.
		_check(held.x < 0.25 and held.y < 0.7 and limp.x > 4.0 * held.x, "a SLERP-driven ragdoll holds its pose, a limp one doesn't")
		print("[joint_drive] ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
