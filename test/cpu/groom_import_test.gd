extends SceneTree

# PhysXGroom: what the Alembic importer makes of a Blender groom, the self-shadowing bake, and a save round trip.
# - test/data/test_groom.abc: 2000 strands on a 0.1 m sphere at Blender's (0, 0, 1.6), Z-up, every point a radius
#   of 0.4 mm. Imported: Y-up (the sphere at (0, 1.6, 0)), widths as diameters (0.8 mm), strand offsets that add up,
#   strands in a shuffled order (any first part of them is spread over the whole head), self-shadowing baked.
# - The bake: in a bundle of strands, strands all around; beside it, more strands toward the bundle than away from it;
#   a strand with no others near it, none (every ray counts -5). Inside the imported groom, roots (at the scalp, under
#   the hair) have more strands around them than tips. (A bundle of strands millimeters apart counted none at all
#   before the bake's segment distance stopped treating millimeter segments as points.)
# - A groom saved and loaded keeps its strands and its self-shadowing.
#   godot --headless --path . --script res://test/cpu/groom_import_test.gd

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[groom_import] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


# The baked strands toward d from a point, before the hair shader clamps it at 0 (groom_self_shadow.h: L1 spherical
# harmonics, the constant part then y, z, x of the direction; each ray counts the strands it passes, up to 5, and a ray
# that passes none counts -5).
func _strands_toward(groom: Resource, point: int, d: Vector3) -> float:
	var sh: PackedFloat32Array = groom.self_shadow
	var i := point * 4
	return sh[i] * 0.282095 + 0.488603 * (sh[i + 1] * d.y + sh[i + 2] * d.z + sh[i + 3] * d.x)


func _imported() -> void:
	var groom: Resource = load("res://test/data/test_groom.abc")
	_check(groom != null and groom.is_class("PhysXGroom"), "test_groom.abc imports as a PhysXGroom")
	if groom == null:
		return
	var points: PackedVector3Array = groom.points
	var offsets: PackedInt32Array = groom.strand_offsets
	var widths: PackedFloat32Array = groom.widths
	var strands: int = groom.get_strand_count()
	_check(strands == 2000, "2000 strands (%d)" % strands)
	_check(offsets.size() == strands + 1 and offsets[0] == 0 and offsets[strands] == points.size(), "strand offsets run from 0 to the point count (%d points)" % points.size())
	var ordered := true
	for s in strands:
		ordered = ordered and offsets[s + 1] - offsets[s] >= 2
	_check(ordered, "every strand has at least 2 points")

	# Y-up: roots on the sphere around (0, 1.6, 0), 0.1 m out.
	var center := Vector3(0.0, 1.6, 0.0)
	var on_sphere := true
	var worst := 0.0
	for s in strands:
		var d := points[offsets[s]].distance_to(center)
		worst = maxf(worst, absf(d - 0.1))
	on_sphere = worst < 0.002
	_check(on_sphere, "Y-up: every root on the 0.1 m sphere at (0, 1.6, 0) (worst %.4f m off)" % worst)
	var aabb: AABB = groom.get_aabb()
	_check(aabb.position.y > 1.3 and aabb.end.y < 1.75 and absf(aabb.get_center().x) < 0.02 and absf(aabb.get_center().z) < 0.02, "the hair hangs below the sphere, centred on it: %s" % aabb)

	var widths_ok := widths.size() == points.size()
	for w in widths:
		widths_ok = widths_ok and absf(w - 0.0008) < 0.00001
	_check(widths_ok, "widths are diameters: Blender's 0.4 mm radius is 0.8 mm (%f)" % widths[0])

	# Shuffled: the first tenth of the strands has its roots spread like all of them, not on one patch.
	var first := Vector3.ZERO
	var all := Vector3.ZERO
	for s in strands:
		var r := points[offsets[s]] - center
		all += r
		if s < strands / 10:
			first += r
	first /= float(strands / 10)
	all /= float(strands)
	_check(first.distance_to(all) < 0.02, "strands are shuffled: the first tenth's roots centre where all of them do (%.4f m apart)" % first.distance_to(all))

	# Self-shadowing: baked, and more strands around the roots than around the tips.
	var sh: PackedFloat32Array = groom.self_shadow
	_check(sh.size() == points.size() * 4, "self-shadowing baked: 4 values a point")
	var root_sum := 0.0
	var tip_sum := 0.0
	for s in strands:
		root_sum += sh[offsets[s] * 4]
		tip_sum += sh[(offsets[s + 1] - 1) * 4]
	_check(root_sum > tip_sum + strands * 2.0, "roots have more strands around them than tips (mean %.2f vs %.2f)" % [root_sum / strands, tip_sum / strands])


func _bake() -> void:
	# A bundle: 15 x 15 vertical strands 3 mm apart, 0.2 m long; one more strand 1 cm to the +x side of it; one
	# far away on its own.
	var groom: Resource = ClassDB.instantiate("PhysXGroom")
	var points := PackedVector3Array()
	var offsets := PackedInt32Array([0])
	var widths := PackedFloat32Array()
	var add_strand := func(x: float, z: float) -> void:
		for i in 9:
			points.append(Vector3(x, -0.2 * i / 8.0, z))
			widths.append(0.0005)
		offsets.append(points.size())
	for i in 15:
		for j in 15:
			add_strand.call(i * 0.003, j * 0.003)
	add_strand.call(14 * 0.003 + 0.01, 7 * 0.003)
	add_strand.call(5.0, 5.0)
	groom.points = points
	groom.strand_offsets = offsets
	groom.widths = widths
	groom.bake_self_shadow(64, 0.05)
	var sh: PackedFloat32Array = groom.self_shadow
	_check(sh.size() == points.size() * 4, "bake_self_shadow fills 4 values a point")

	# The middle point (the 5th of 9) of the bundle's middle strand, of the strand beside the bundle, and of the lone one.
	var inside: int = offsets[7 * 15 + 7] + 4
	var beside: int = offsets[15 * 15] + 4
	var lone: int = offsets[15 * 15 + 1] + 4
	_check(sh[inside * 4] > 0.0, "in the middle of a bundle: more rays meet strands than leave the hair (%.2f)" % sh[inside * 4])
	var toward := _strands_toward(groom, beside, Vector3(-1, 0, 0))
	var away := _strands_toward(groom, beside, Vector3(1, 0, 0))
	_check(toward > away + 1.0, "beside a bundle: more strands toward it than away (%.2f vs %.2f)" % [toward, away])
	_check(absf(sh[lone * 4] + 5.0 * 0.282095 * 4.0 * PI) < 0.01, "a strand alone: every ray leaves the hair (%.3f)" % sh[lone * 4])


func _round_trip() -> void:
	var groom: Resource = load("res://test/data/test_groom.abc")
	if groom == null:
		return
	var path := "user://groom_round_trip.res"
	_check(ResourceSaver.save(groom, path) == OK, "a groom saves")
	var back: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(back != null and back.points == groom.points and back.strand_offsets == groom.strand_offsets and back.widths == groom.widths and back.self_shadow == groom.self_shadow, "and loads with the same strands and self-shadowing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXGroom"):
		print("SKIP: no PhysXGroom in this build")
		quit(0)
		return
	if not ResourceLoader.exists("res://test/data/test_groom.abc"):
		print("SKIP: test_groom.abc isn't imported (an editor built without alembic_sdk= can't import .abc files)")
		quit(0)
		return
	_imported()
	_bake()
	_round_trip()
	print("[groom_import] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
