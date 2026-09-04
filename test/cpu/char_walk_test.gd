extends SceneTree

# Minimal CharacterBody3D walk check on the PhysX backend: a capsule on a big
# thick static box, driven +X for 2 s. It must actually travel.
#
# Note: the controller holds velocity.y at 0 on the floor. A constant downward
# "stick" velocity there fights the backend's depenetration on thick box shapes
# and jams horizontal motion -- keep grounded adherence to floor snap.

var _char: CharacterBody3D
var _t := 0
var _x0 := 0.0

func _initialize() -> void:
	print("[cwalk] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(40, 6, 40) # thick box, like the bridge shelves
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, 0, 0) # top at y=3
	root.add_child(floor_body)

	_char = CharacterBody3D.new()
	var ccs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	ccs.shape = cap
	_char.add_child(ccs)
	_char.position = Vector3(-8, 5, 0)
	root.add_child(_char)
	_x0 = _char.position.x

func _physics_process(delta: float) -> bool:
	_t += 1
	var v := _char.velocity
	v.x = 5.0
	if _char.is_on_floor():
		v.y = 0.0
	else:
		v.y -= 18.0 * delta
	_char.velocity = v
	_char.move_and_slide()

	if _t % 30 == 0:
		print("[cwalk] t=%d x=%.2f onfloor=%s slides=%d vel=(%.1f,%.1f,%.1f)" % [
			_t, _char.position.x, _char.is_on_floor(), _char.get_slide_collision_count(),
			_char.velocity.x, _char.velocity.y, _char.velocity.z])
	if _t == 120:
		var moved := _char.position.x - _x0
		var ok := moved > 8.0
		print("[cwalk] moved %.2f m in 2 s -> %s" % [moved, "PASS" if ok else "FAIL (stuck)"])
		quit(0 if ok else 1)
	return false
