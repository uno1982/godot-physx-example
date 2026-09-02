extends SceneTree

# Spawns a fixed chaotic pile, steps it, and prints a hash of the final state.
# Run the whole process twice and diff the hash: with
# physics/physx_3d/simulation/enhanced_determinism = true the two runs must
# match; without it they typically differ (thread-order dependent).

const N := 60
var _bodies: Array[RigidBody3D] = []
var _tick := 0

func _initialize() -> void:
	print("[det] engine=%s enhanced_determinism=%s threads=auto" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
		ProjectSettings.get_setting("physics/physx_3d/simulation/enhanced_determinism", "n/a")])

	var root := Node3D.new()
	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(20, 1, 20)
	fc.shape = fs
	fb.add_child(fc)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in N:
		var rb := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE
		cs.shape = bs
		rb.add_child(cs)
		rb.position = Vector3(rng.randf_range(-2, 2), 2.0 + i * 0.6, rng.randf_range(-2, 2))
		root.add_child(rb)
		_bodies.append(rb)
	get_root().add_child(root)

func _physics_process(_delta: float) -> bool:
	_tick += 1
	if _tick < 400:
		return false
	var h := ""
	for b in _bodies:
		var p := b.global_position
		h += "%.4f,%.4f,%.4f;" % [p.x, p.y, p.z]
	print("[det] final hash = ", h.sha256_text().substr(0, 20))
	quit(0)
	return true
