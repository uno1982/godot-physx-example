extends SceneTree

# A Blast actor whose piece fell past kill_y must stay gone. It used to stay
# live: a later hit mapped through some other piece's pose could split it and
# re-spawn its chunks out of nowhere (live 0 -> 36 pieces from one hit).
# Also: a hit on a still-live piece keeps working after others were freed.

var _w
var _t := 0

func _initialize() -> void:
	if not ClassDB.class_exists("PhysXDestructible3D"):
		print("SKIP: PhysXDestructible3D not registered (build without blast_sdk=)")
		quit(0)
		return
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(400, 1, 400)
	cs.shape = b
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	get_root().add_child(floor_body)
	_w = ClassDB.instantiate("PhysXDestructible3D")
	_w.blast_asset = load("res://demo/common/blast/MeshInstance3D3_blast.tres")
	_w.auto_mass = false
	_w.mass = 1.317
	_w.dynamic = true
	_w.position = Vector3(0, 1, 0)
	get_root().add_child(_w)

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 60:
		var s: int = _w.apply_radial_damage(_w.global_position, 4.0, 0.05, 2.6)
		print("[ghost] first hit spawned=%d live=%d" % [s, _w.get_piece_count()])
		if s == 0:
			print("[ghost] FAIL: the first hit broke nothing (test setup)")
			quit(1)
			return true
	if _t == 240:
		_w.kill_y = 1000.0 # every piece is "below" it: all freed on the next sync
	if _t == 245:
		_w.kill_y = -1000.0
		var live_before: int = _w.get_piece_count()
		var s: int = _w.apply_radial_damage(_w.global_position + Vector3(0, 2, 0), 6.0, 0.05, 6.0)
		print("[ghost] after kill_y sweep live=%d; hit on the empty spot spawned=%d live=%d" % [live_before, s, _w.get_piece_count()])
		if live_before != 0:
			print("[ghost] FAIL: kill_y did not free every piece (test setup)")
			quit(1)
		elif s != 0 or _w.get_piece_count() != 0:
			print("[ghost] FAIL: freed debris came back from a later hit")
			quit(1)
		else:
			print("[ghost] PASS -- debris freed by kill_y stays gone")
			quit(0)
		return true
	return false
