extends SceneTree

# PXTGI3D traces a skinned mesh with "pxtgi_traced" true as its own triangles, posed by its skeleton and colored by
# its surfaces: the mirror demo (demo/editor/rendering/gi_mirror_character.tscn), its camera looking at the wall mirror
# with the mannequin off screen. The mannequin's reflection: with the traced mesh, orange (its body) and purple (its
# joint bands, a second surface) both show in the mirror, and the figure moves with the animation; with nothing traced,
# no orange at all. Windowed only (PXTGI needs a RenderingDevice).

var failures := 0
var _scene: Node


func _check(ok: bool, what: String) -> void:
	print("[traced-mesh] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	_run.call_deferred()


func _key(k: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	_scene._unhandled_input(ev)


# The mirror's orange and purple pixels (the mannequin's body and joints), and the orange pixels' mean position.
func _measure() -> Array:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var orange := 0
	var purple := 0
	var at := Vector2()
	for y in range(80, 700, 2):
		for x in range(80, 740, 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.55 and c.g > 0.3 and c.g < 0.75 * c.r and c.b < 0.35 * c.r:
				orange += 1
				at += Vector2(x, y)
			elif c.b > 0.3 and c.r > 0.6 * c.b and c.r < 1.1 * c.b and c.b > c.g + 0.12:
				purple += 1
	return [orange, purple, at / maxf(orange, 1)]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await process_frame
	if RenderingServer.get_rendering_device() == null or DisplayServer.get_name() == "headless":
		print("SKIP: PXTGI needs a windowed run")
		quit(0)
		return
	_scene = (load("res://demo/editor/rendering/gi_mirror_character.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	await _frames(200)
	var mesh: Array = await _measure()
	print("[traced-mesh] traced mesh: orange %d purple %d at %s" % [mesh[0], mesh[1], mesh[2]])
	_check(mesh[0] > 150, "the traced mesh shows orange in the mirror")
	# Dancing, the figure moves.
	_key(KEY_3)
	await _frames(40)
	var moved := false
	var last: Vector2 = (await _measure())[2]
	for i in 6:
		await _frames(15)
		var now: Vector2 = (await _measure())[2]
		moved = moved or now.distance_to(last) > 4.0
		last = now
	_check(moved, "the reflection follows the animation")
	# Nothing traced (M twice: capsules, then nothing): no mannequin in the mirror.
	_key(KEY_M)
	_key(KEY_M)
	await _frames(120)
	var none: Array = await _measure()
	print("[traced-mesh] nothing traced: orange %d purple %d" % [none[0], none[1]])
	_check(none[0] < mesh[0] / 20, "with nothing traced the mirror shows no mannequin")
	# The wall's blue reads a little purple at its edges: the joints are what the traced mesh adds.
	_check(mesh[1] > none[1] + 100, "the traced mesh shows its purple joints too (a second surface's color)")
	print("PASS" if failures == 0 else "FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
