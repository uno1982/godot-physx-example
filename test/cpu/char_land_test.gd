extends SceneTree

# A CharacterBody3D dropped onto a static box must come to rest ON the surface
# without punching through and being shoved back out over the next frames -- that
# recovery pop is what jerks a child camera on every landing.
#
# Runs the drop twice, onto a thin box and a thick one.

const STICK := 0.0 # velocity.y on the floor; a negative "stick" fights depenetration

var _char: CharacterBody3D
var _surf_y := 0.0
var _t := 0
var _worst_pen := 0.0      # deepest the capsule bottom went below the surface
var _post_land_settle := 0 # frames from first ground contact to a steady y
var _grounded_at := -1
var _phase := 0
var _thick := false
var _results: Array[bool] = []

func _initialize() -> void:
	print("[cland] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	_start(false)

func _start(thick: bool) -> void:
	_thick = thick
	for c in get_root().get_children():
		c.queue_free()
	var root := Node3D.new()
	get_root().add_child(root)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	var h := 6.0 if thick else 0.4
	b.size = Vector3(20, h, 20)
	cs.shape = b
	body.add_child(cs)
	body.position = Vector3(0, -h * 0.5, 0) # top at y=0
	root.add_child(body)
	_surf_y = 0.0

	_char = CharacterBody3D.new()
	var ccs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	ccs.shape = cap
	_char.add_child(ccs)
	_char.position = Vector3(0, 3.0, 0) # capsule bottom 1.3 below centre -> falls ~1.7 m
	root.add_child(_char)

	_t = 0
	_worst_pen = 0.0
	_grounded_at = -1

func _physics_process(delta: float) -> bool:
	_t += 1
	var v := _char.velocity
	if _char.is_on_floor():
		if _grounded_at < 0:
			_grounded_at = _t
		v.y = STICK
	else:
		v.y -= 18.0 * delta
	_char.velocity = v
	_char.move_and_slide()

	var bottom := _char.global_position.y - 0.9 # capsule centre to bottom (height 1.8)
	if _grounded_at > 0:
		_worst_pen = maxf(_worst_pen, _surf_y - bottom)

	if _grounded_at > 0 and _t >= _grounded_at + 20:
		var resting_bottom := _char.global_position.y - 0.9
		var offset := absf(resting_bottom - _surf_y)
		var ok := _worst_pen < 0.05 and offset < 0.05
		print("[cland] %s box: worst punch-through=%.3f m, rest offset=%.3f m -> %s" % [
			"thick" if _thick else "thin", _worst_pen, offset, "ok" if ok else "BAD"])
		_results.append(ok)
		if not _thick:
			_start(true)
		else:
			var all_ok := _results.all(func(r): return r)
			print("[cland] %s" % ("PASS" if all_ok else "FAIL"))
			quit(0 if all_ok else 1)
	return false
