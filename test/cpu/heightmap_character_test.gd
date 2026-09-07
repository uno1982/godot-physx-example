extends SceneTree

# A CharacterBody3D must be able to walk across a HeightMapShape3D without
# snagging on the cooked triangle-mesh facet edges (buildTriangleAdjacencies).

var _char: CharacterBody3D
var _t := 0
var _start_x := 0.0


func _initialize() -> void:
	print("[hmap-char] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	var grid := 61
	var height := 6.0

	var st := SurfaceTool.new()
	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.03
	for z in grid:
		for x in grid:
			heights[z * grid + x] = (noise.get_noise_2d(x, z) * 0.5 + 0.5) * height

	var shape := HeightMapShape3D.new()
	shape.map_width = grid
	shape.map_depth = grid
	shape.map_data = heights
	var terrain := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	terrain.add_child(cs)
	get_root().add_child(terrain)

	_char = CharacterBody3D.new()
	var ccs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	ccs.shape = cap
	_char.add_child(ccs)
	get_root().add_child(_char)
	var mid := (grid - 1) * 0.5
	_char.global_position = Vector3(-mid + 3.0, height + 3.0, 0.0)
	await physics_frame
	await physics_frame
	_start_x = _char.global_position.x
	print("  start x = %.1f" % _start_x)

	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	var v := _char.velocity
	v.x = 5.0
	v.y = 0.0 if _char.is_on_floor() else v.y - 20.0 * (1.0 / 60.0)
	_char.velocity = v
	_char.move_and_slide()

	if _t % 100 == 0:
		var nrm := Vector3.ZERO
		if _char.get_slide_collision_count() > 0:
			nrm = _char.get_slide_collision(0).get_normal()
		print("  t=%d  pos=%.2v  on_floor=%s  floor_n=%.2v  hit_n=%.2v" % [_t, _char.global_position, _char.is_on_floor(), _char.get_floor_normal(), nrm])

	if _t == 600: # 10 s at 5 m/s -> ~50 m of terrain
		var dist := _char.global_position.x - _start_x
		if dist > 35.0 and _char.global_position.y > -5.0:
			print("[hmap-char] PASS  walked %.1f m across the terrain (no snag)" % dist)
			quit(0)
		else:
			printerr("[hmap-char] FAIL  only advanced %.1f m (y=%.1f)" % [dist, _char.global_position.y])
			quit(1)
