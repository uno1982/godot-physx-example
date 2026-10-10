extends SceneTree

# PhysXDestructible3D.anchor on a STATIC wall cut clean through at mid height
# (a row of hits across the full width), so it splits into an upper and a
# lower island plus debris:
#   FRAMED   -> both islands stay static (the upper one still touches the top/left/right edges)
#   GROUNDED -> only the lower island stays static; the upper one is released (a rigid body --
#               here it just rests on the lower half, as a real slab would)
#   NONE     -> nothing stays static
# "Static" = still exactly at the wall's pose 3 s later; a released piece drifts at least slightly.

var _walls := {}
var _t := 0

func _wall(anchor: int, x: float):
	var w = ClassDB.instantiate("PhysXDestructible3D")
	w.blast_asset = load("res://demo/common/blast/MeshInstance3D3_blast.tres")
	w.auto_mass = false
	w.mass = 1.317
	w.dynamic = false
	w.anchor = anchor
	w.position = Vector3(x, 8, 0)
	get_root().add_child(w)
	return w

func _initialize() -> void:
	if not ClassDB.class_exists("PhysXDestructible3D"):
		print("SKIP: PhysXDestructible3D not registered (build without blast_sdk=)")
		quit(0)
		return
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(600, 1, 600)
	cs.shape = b
	f.add_child(cs)
	f.position = Vector3(0, -0.5, 0)
	get_root().add_child(f)
	_walls = {"framed": _wall(0, -40), "grounded": _wall(1, 0), "none": _wall(2, 40)}

func _physics_process(_d: float) -> bool:
	_t += 1
	if _t == 5:
		for k in _walls:
			var w = _walls[k]
			var n := 0
			for i in 15: # the tank-wall asset is ~25.6 x 11.6 m, centered
				n += w.apply_radial_damage(w.global_transform * Vector3(-12.8 + 25.6 * i / 14.0, 0.0, 0.0), 6.0, 0.05, 2.6)
			if n == 0:
				print("[anchor] FAIL: the cut broke nothing on %s (test setup)" % k)
				quit(1)
				return true
	if _t < 185:
		return false
	var held := {}
	for k in _walls:
		var w = _walls[k]
		held[k] = 0
		for i in w.get_piece_count():
			var d: Vector3 = (w.call("get_piece_transform", i) as Transform3D).origin - w.global_position
			if d.is_zero_approx():
				held[k] += 1
	print("[anchor] static islands left: framed=%d grounded=%d none=%d" % [held.framed, held.grounded, held.none])
	var ok: bool = held.framed == 2 and held.grounded == 1 and held.none == 0
	if ok:
		print("[anchor] PASS -- framed holds both halves, grounded releases the top, none releases everything")
	else:
		print("[anchor] FAIL: expected static islands framed=2 grounded=1 none=0")
	quit(0 if ok else 1)
	return true
