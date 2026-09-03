extends SceneTree

# CharacterBody3D on the PhysX backend: it should walk into a wall and stop,
# and rest on the floor under gravity (both driven by body_test_motion).

var _char: CharacterBody3D
var _tick := 0
var _start_x := 0.0

func _initialize() -> void:
	print("[char] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(40, 1, 40)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var wall := StaticBody3D.new()
	var wc := CollisionShape3D.new()
	var ws := BoxShape3D.new()
	ws.size = Vector3(1, 4, 10)
	wc.shape = ws
	wall.add_child(wc)
	wall.position = Vector3(5, 2, 0)
	root.add_child(wall)

	_char = CharacterBody3D.new()
	var cc := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.4
	cs.height = 1.8
	cc.shape = cs
	_char.add_child(cc)
	_char.position = Vector3(-3, 3, 0)
	root.add_child(_char)

	get_root().add_child(root)
	_start_x = _char.global_position.x

func _physics_process(delta: float) -> bool:
	_tick += 1
	# Walk right into the wall, with gravity.
	_char.velocity.x = 6.0
	_char.velocity.y -= 20.0 * delta
	if _char.is_on_floor():
		_char.velocity.y = 0.0
	_char.move_and_slide()

	if _tick % 30 == 0:
		print("[char] t%d  pos=(%.2f, %.2f)  on_floor=%s  on_wall=%s" % [
			_tick, _char.global_position.x, _char.global_position.y,
			_char.is_on_floor(), _char.is_on_wall()])

	if _tick >= 150:
		var p := _char.global_position
		# Should have settled on the floor (y ~ capsule half-height 0.9) and
		# stopped against the wall (x < ~4.1, wall face at x=4.5 minus radius).
		var ok := p.y > 0.5 and p.y < 1.3 and p.x > 3.5 and p.x < 4.3
		print("[char] final pos=(%.2f, %.2f) -> %s" % [p.x, p.y, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
