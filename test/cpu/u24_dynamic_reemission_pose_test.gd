extends SceneTree

# U24 follow-up: pose/velocity inheritance on re-emission, node path,
# DYNAMIC variant. The static test (u24_duplicate_chunk_bodies_test.gd)
# proves the one-live-body-per-chunk invariant; this one proves WHERE and
# HOW the re-emitted pieces move. A dynamic island is fractured once
# (corner partial -> lone leaves + falling island), then given settle
# ticks with NO floor so the real piece bodies fall far from wherever the
# node's transform froze at fracture. A deeper hit then splits the island
# and re-emits its chunks: pre-fix those spawned at the frozen node
# transform (visually "snapping back" into the island's original shape)
# with zero inherited motion; post-fix they spawn at their superseded
# piece's live pose and keep falling. impact_strength is pinned to a huge
# value so contact impulses can't auto-shatter the drop, and shatter_speed
# is zeroed so ALL motion is gravity + inheritance -- nothing else can
# explain a piece's pose. Verdict needs re-emissions to have happened,
# the one-live-body invariant to hold, and enough accumulated drift to
# make the pose check meaningful.

const ASSET := "res://test/data/blast_cube.asset"
const CHUNKS := "res://test/data/blast_cube.chunks"
const LEAF_COUNT := 8
const NODE_ORIGIN := Vector3(0, 5, 0)
# Node-local corner (0.75,0.75,0.75) in world space (node starts there).
const CORNER := Vector3(0.75, 5.75, 0.75)

var _node
var _tick := 0
var _total := 0
var _max_live := 0
var _settle_sum_y := NAN
var _post_sum_y := NAN

func _initialize() -> void:
	print("[u24d] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXDestructible3D"):
		print("[u24d] PhysXDestructible3D not registered (build without blast_sdk=) -> SKIP")
		quit(0)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	# Deliberately NO floor: the island must free-fall away from the frozen
	# node transform so a stale-pose re-emission is unmistakable.
	_node = ClassDB.instantiate("PhysXDestructible3D")
	_node.asset_path = ProjectSettings.globalize_path(ASSET)
	_node.chunks_path = ProjectSettings.globalize_path(CHUNKS)
	_node.dynamic = true
	_node.impact_strength = 1e9
	_node.shatter_speed = 0.0
	_node.position = NODE_ORIGIN
	root.add_child(_node)

func _hit(pos: Vector3, damage: float, max_r: float, label: String) -> int:
	var spawned: int = _node.apply_radial_damage(pos, damage, 0.05, max_r)
	_total += spawned
	print("[u24d] ", label, " d=", damage, " r=", max_r, " -> spawned=", spawned,
			" live=", _node.get_piece_count(), " total=", _total)
	return spawned

func _sum_piece_y() -> float:
	var n: int = _node.get_piece_count()
	var sum := 0.0
	for i in n:
		sum += _node.get_piece_transform(i).origin.y
	return sum

func _physics_process(_delta: float) -> bool:
	_tick += 1

	var live: int = _node.get_piece_count()
	if live > _max_live:
		_max_live = live

	if _tick == 5:
		var spawned: int = _node.apply_radial_damage(Vector3(0, 5, 0), 0.5, 0.1, 3.0)
		print("[u24d] guard weak hit spawned=", spawned, " (expect 0)")
		if spawned != 0:
			print("[u24d] FAIL: weak damage spawned ", spawned, " pieces (expected 0)")
			quit(1)
			return true

	if _tick == 10:
		# Partial corner hit: peels lone leaves off and leaves a falling
		# ISLAND actor (support chunk + remaining leaves, CanFracture).
		_hit(CORNER, 5.0, 1.6, "hit1 corner partial (dynamic drop begins)")

	if _tick == 25:
		# Bond chip on the now-falling island (spawn count not gated); its
		# real job is widening the settle window before the split.
		_hit(CORNER, 5.0, 1.8, "hit2 bond chip")

	if _tick == 39:
		# Last settle tick before the split: with shatter_speed=0 and no
		# floor the only motion is gravity, so live piece bodies MUST have
		# dropped measurably below the frozen node origin by now.
		_settle_sum_y = _sum_piece_y()
		print("[u24d] settle: mean piece y=", _settle_sum_y / live,
				" vs node y=", NODE_ORIGIN.y, " (drift window)")

	if _tick == 40:
		# Deeper hit splits the falling island and re-emits its chunks.
		# This is the moment the old code spawned replacements at the
		# frozen node transform with zero motion. Aim at the island's LIVE
		# pose (first live piece = the falling remainder): after the
		# per-actor damage-mapping fix, a world-space hit is resolved
		# through the covering piece's body transform, so a shooter aims
		# where the island IS, not where the node was authored.
		var live_count: int = _node.get_piece_count()
		var aim := CORNER
		if live_count > 0:
			var island_origin: Vector3 = _node.call("get_piece_transform", 0).origin
			aim = island_origin + (CORNER - NODE_ORIGIN)
		var spawned := _hit(aim, 5.0, 2.6, "hit3 island split (re-emission)")
		if spawned == 0:
			print("[u24d] FAIL: island split re-emitted nothing -- ",
					"the stale-pose path was never exercised")
			quit(1)
			return true

	if _tick == 50:
		_post_sum_y = _sum_piece_y()
		print("[u24d] post-split: mean piece y=", _post_sum_y / _node.get_piece_count(),
				" (was ", _settle_sum_y / LEAF_COUNT, " at settle)")

	if _tick == 90:
		var n: int = _node.get_piece_count()
		print("[u24d] final: live=", n, " max_live=", _max_live,
				" cumulative_spawned=", _total)
		if _total == 0:
			print("[u24d] FAIL: ladder went quiet (nothing spawned at all) ",
					"-- no hit ever split anything")
			quit(1)
			return true
		if n == 0:
			print("[u24d] FAIL: no live pieces left to inspect (culled early?)")
			quit(1)
			return true
		if _max_live > LEAF_COUNT:
			print("[u24d] FAIL: U24 PRESENT -- max live pieces ", _max_live,
					" > ", LEAF_COUNT, " leaf chunks (duplicate bodies)")
			quit(1)
			return true

		# The discriminator: every live piece must be FAR from the frozen
		# node transform. A re-emission spawned at get_global_transform()
		# would sit right at NODE_ORIGIN; post-fix every piece inherited
		# its predecessor's falling pose and kept falling (~1.5 s of
		# gravity by now -> several meters below).
		var min_dist := INF
		var closest_chunk := -1
		for i in n:
			var xf: Transform3D = _node.get_piece_transform(i)
			var d := xf.origin.distance_to(NODE_ORIGIN)
			if d < min_dist:
				min_dist = d
				closest_chunk = _node.get_piece_chunk(i)
		print("[u24d] closest live piece: chunk=", closest_chunk,
				" dist_to_frozen_node_pose=", snappedf(min_dist, 0.01), " m")
		if min_dist < 0.5:
			print("[u24d] FAIL: U24 PRESENT -- a piece sits at the frozen ",
					"node pose: re-emission spawned at get_global_transform() ",
					"instead of its predecessor's live pose")
			quit(1)
			return true
		if min_dist < 1.0:
			print("[u24d] FAIL: inconclusive -- drift window too small ",
					"(closest piece ", snappedf(min_dist, 0.01),
					" m < 1.0 m); can't distinguish stale spawn from inheritance")
			quit(1)
			return true
		print("[u24d] re-emissions (", _total, " total, max live ", _max_live,
				" <= ", LEAF_COUNT, ") and closest piece is ",
				snappedf(min_dist, 0.01), " m from the frozen node pose: ",
				"re-emitted chunks spawned at their predecessors' live poses ",
				"and kept the island's motion")
		print("[u24d] overall -> PASS")
		quit(0)
		return true
	return false
