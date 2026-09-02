extends SceneTree

# Playground-style pin-joint pendulums and a hanging chain, under gravity only.
# Checks they settle to their rest length instead of stretching.

var _bobs: Array[RigidBody3D] = []
var _chain: Array[RigidBody3D] = []
var _anchors: Array[Vector3] = []
var _tick := 0

func _initialize() -> void:
	print("[pend] engine=%s solver=%s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		ProjectSettings.get_setting("physics/physx_3d/simulation/solver_type", 0)])
	var root := Node3D.new()
	get_root().add_child(root)

	# Pendulum row: 0.5 m boxes on 2.5 m strings (like demo/physx_playground.gd).
	for i in 5:
		var a := Vector3(-2 + i * 1.0, 5, 0)
		var anchor := StaticBody3D.new()
		anchor.position = a
		root.add_child(anchor)
		var bob := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.5, 0.5, 0.5)
		cs.shape = b
		bob.add_child(cs)
		bob.position = Vector3(a.x, 2.5, 0)
		bob.mass = 2.0
		root.add_child(bob)
		var pin := PinJoint3D.new()
		pin.position = a
		root.add_child(pin)
		pin.node_a = pin.get_path_to(anchor)
		pin.node_b = pin.get_path_to(bob)
		if i == 0:
			bob.position = Vector3(-4.5, 5, 0) # pulled out
		_bobs.append(bob)
		_anchors.append(a)

	# Hanging chain: 6 links, 0.5 m tall, 2 kg (like _build_chain).
	var top := Vector3(6, 6.5, 0)
	var anchor := StaticBody3D.new()
	anchor.position = top
	root.add_child(anchor)
	var prev: Node3D = anchor
	for i in 6:
		var seg := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.4, 0.5, 0.4)
		cs.shape = b
		seg.add_child(cs)
		seg.position = top - Vector3(0, (i + 0.5) * 0.5, 0)
		seg.mass = 2.0
		root.add_child(seg)
		var j := PinJoint3D.new()
		j.position = top - Vector3(0, i * 0.5, 0)
		root.add_child(j)
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(seg)
		prev = seg
		_chain.append(seg)

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _tick == 240:
		var maxpend := 0.0
		for i in _bobs.size():
			var d := _bobs[i].global_position.distance_to(_anchors[i])
			maxpend = maxf(maxpend, d)
		var chain_span := _chain[0].global_position.distance_to(_chain[5].global_position)
		var pend_ok := maxpend < 3.2 # 2.5 string + half the box + slack
		var chain_ok := chain_span < 3.5 # 6 * 0.5 = 3.0 rest
		print("[pend] max pendulum string=%.2f (rest ~2.75)  chain span=%.2f (rest 3.0)  -> %s" %
				[maxpend, chain_span, "PASS" if pend_ok and chain_ok else "FAIL (stretched)"])
		quit(0 if pend_ok and chain_ok else 1)
	return false
