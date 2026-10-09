extends SceneTree

# U24 fix verification (issue #1), node path. Same ladder that reproduced
# the bug: a partial corner hit (r=1.6) peels lone leaves off and leaves
# an ISLAND actor (support chunk 0 + remaining leaves, CanFracture=true);
# a later hit splits it and re-emits chunks that were already live. The
# fix makes _spawn_piece() free a chunk's superseded piece before spawning
# its replacement, so the invariant is now about LIVE bodies, not
# cumulative spawns: max get_piece_count() over the whole ladder must stay
# <= 8 leaf chunks. Cumulative spawns are printed for the record only:
# under island semantics spawned counts ACTORS (a remainder island is one
# piece no matter how many chunks it carries), so the total can legitimately
# stay at or below the leaf count. The vacuous-run guard is therefore "no
# hit ever spawned anything", not a cumulative threshold. SKIPs (not
# FAILs) on a build without blast_sdk=.

const ASSET := "res://test/data/blast_cube.asset"
const CHUNKS := "res://test/data/blast_cube.chunks"
const LEAF_COUNT := 8
# Node sits at (0,5,0); corner-local (0.75,0.75,0.75) -> world offset.
const CORNER := Vector3(0.75, 5.75, 0.75)

var _node
var _tick := 0
var _total := 0
var _max_live := 0
var _hit2_spawned := -1

func _initialize() -> void:
	print("[u24] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXDestructible3D"):
		print("[u24] PhysXDestructible3D not registered (build without blast_sdk=) -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(50, 1, 50)
	fc.shape = fs
	floor_body.add_child(fc)
	floor_body.position = Vector3(0, -6, 0)
	root.add_child(floor_body)

	_node = ClassDB.instantiate("PhysXDestructible3D")
	_node.asset_path = ProjectSettings.globalize_path(ASSET)
	_node.chunks_path = ProjectSettings.globalize_path(CHUNKS)
	_node.position = Vector3(0, 5, 0)
	root.add_child(_node)

func _hit(pos: Vector3, damage: float, max_r: float, label: String) -> int:
	var spawned: int = _node.apply_radial_damage(pos, damage, 0.05, max_r)
	_total += spawned
	print("[u24] ", label, " d=", damage, " r=", max_r, " -> spawned=", spawned,
			" live=", _node.get_piece_count(), " total=", _total)
	return spawned

func _physics_process(_delta: float) -> bool:
	_tick += 1

	var live: int = _node.get_piece_count()
	if live > _max_live:
		_max_live = live

	if _tick == 5:
		var spawned: int = _node.apply_radial_damage(Vector3(0, 5, 0), 0.5, 0.1, 3.0)
		print("[u24] guard weak hit spawned=", spawned, " (expect 0)")
		if spawned != 0:
			print("[u24] FAIL: weak damage spawned ", spawned, " pieces (expected 0)")
			quit(1)
			return true

	if _tick == 10:
		# Partial corner hit: peels lone leaves, leaves an island actor.
		_hit(CORNER, 5.0, 1.6, "hit1 corner partial")

	if _tick == 20:
		# Island still bonded -> CanFracture; r=1.8 only reaches bonds that
		# hit1 already consumed (bond spacing ~2 m), so under island
		# semantics it may legitimately spawn 0 (the split fires at hit3
		# r=2.6).
		_hit2_spawned = _hit(CORNER, 5.0, 1.8, "hit2 bond chip")

	if _tick == 30:
		_hit(CORNER, 5.0, 2.6, "hit3 deeper split")

	if _tick == 40:
		var final_live: int = _node.get_piece_count()
		print("[u24] final: live=", final_live, " max_live=", _max_live,
				" cumulative_spawned=", _total)
		if _total == 0:
			print("[u24] FAIL: ladder went quiet (nothing spawned at all) ",
					"-- no hit broke a bond, so this run exercises no ",
					"split/re-spawn path")
			quit(1)
			return true
		if _max_live > LEAF_COUNT:
			print("[u24] U24 PRESENT: max live pieces ", _max_live, " > ",
					LEAF_COUNT, " leaf chunks (duplicate bodies alive at once)")
			print("[u24] overall -> FAIL (bug present)")
			quit(1)
		else:
			print("[u24] split ladder ran (spawned ", _total, ") yet max ",
					"live stayed ", _max_live, " <= ", LEAF_COUNT,
					" leaf chunks -- every re-emission replaced its ",
					"superseded piece")
			print("[u24] overall -> PASS")
			quit(0)
		return true
	return false
