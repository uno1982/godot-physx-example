extends SceneTree

# A CharacterBody3D standing still on a layer of loose boxes stays put, and so
# do the boxes. A capsule resting in true contact, not safe_margin above the
# box, rubbed it through friction, and riding the box's spin fed that back: the
# box spun up and the character was walked off a stack it stood still on
# (0.3 m in 10 s; Jolt: 0). A real turning platform still carries a rider
# (body_parity_test).
#   godot --path . --script res://test/cpu/character_on_boxes_test.gd

const FP = preload("res://demo/common/first_person_character.gd")

var _char: CharacterBody3D
var _fp
var _boxes: Array[RigidBody3D] = []
var _t := 0
var _start := Vector3.ZERO
var _box_max := 0.0


func _initialize() -> void:
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(40, 1, 40)
	gs.shape = gb
	ground.add_child(gs)
	ground.position = Vector3(0, -0.5, 0)
	get_root().add_child(ground)
	for x in 5:
		for z in 5:
			var b := RigidBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = BoxShape3D.new()
			b.add_child(cs)
			b.position = Vector3((x - 2) * 1.02, 0.5, (z - 2) * 1.02)
			get_root().add_child(b)
			_boxes.append(b)
	_char = CharacterBody3D.new()
	var cc := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cc.shape = cap
	_char.add_child(cc)
	_char.position = Vector3(0.3, 2.2, 0.2) # on the boxes, off a seam
	get_root().add_child(_char)
	var cam := Camera3D.new()
	_char.add_child(cam)
	var spawn := Node3D.new()
	get_root().add_child(spawn)
	_fp = FP.new(_char, cam, spawn) # the demos' controller, no input
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	_fp.physics_process(1.0 / Engine.physics_ticks_per_second)
	if _t == 120:
		_start = _char.global_position
	if _t > 120:
		for b in _boxes:
			_box_max = maxf(_box_max, b.linear_velocity.length())
	if _t == 720:
		var drift := _char.global_position.distance_to(_start)
		var ok := drift < 0.02 and _box_max < 0.05
		print("[on_boxes] %s 10 s standing still on loose boxes: drift %.3f m (want < 0.02), fastest box %.3f m/s (want < 0.05)" % ["PASS" if ok else "FAIL", drift, _box_max])
		quit(0 if ok else 1)
