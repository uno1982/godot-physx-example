extends SceneTree

# Verifies contact reporting: body_entered / body_exited signals and the
# per-frame contact list on a RigidBody3D with contact_monitor enabled.

var _box: RigidBody3D
var _tick := 0
var _entered := 0
var _exited := 0
var _saw_contacts := false
var _floor_id := 0

func _initialize() -> void:
	print("[contact] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(10, 1, 10)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	_floor_id = floor_body.get_instance_id()

	_box = RigidBody3D.new()
	_box.contact_monitor = true
	_box.max_contacts_reported = 8
	var bc := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE
	bc.shape = bs
	_box.add_child(bc)
	_box.position = Vector3(0, 4, 0)
	_box.body_entered.connect(func(rid): _entered += 1; print("[contact]   body_entered"))
	_box.body_exited.connect(func(rid): _exited += 1; print("[contact]   body_exited"))
	root.add_child(_box)

	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1

	var state := PhysicsServer3D.body_get_direct_state(_box.get_rid())
	if state and state.get_contact_count() > 0:
		if not _saw_contacts:
			var c := state.get_contact_count()
			var col_id := state.get_contact_collider_id(0)
			var nrm := state.get_contact_local_normal(0)
			print("[contact]   first contact: count=%d collider_is_floor=%s normal=%s" % [
				c, col_id == _floor_id, nrm.snappedf(0.01)])
			_saw_contacts = true

	# Fling the box off the floor so body_exited fires.
	if _tick == 90:
		print("[contact]   launching box upward")
		_box.linear_velocity = Vector3(0, 25, 0)

	if _tick >= 200:
		var ok := _entered >= 1 and _exited >= 1 and _saw_contacts
		print("[contact] entered=%d exited=%d saw_contacts=%s -> %s" % [
			_entered, _exited, _saw_contacts, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
