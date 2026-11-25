extends SceneTree

# PXTGI3D: walking slowly from a room open to the sky into a closed tunnel must not bring the sky's light in. The scene
# is demo/editor/rendering/gi_tunnel.tscn as the report had it: ambient light from the sky (Godot's default), camera
# auto exposure on. Godot lets its own ambient light through where PXTGI's rays miss; in the tunnel every ray hits, but
# the texels' temporal history carried the room's hit fraction along, so a few percent of the sky's light glowed on
# the tunnel floor: it followed the camera and stayed until the view turned away (user report 2026-11-24).
# Here: settle in the room, walk 15 m in at 1 m/s, tilting down 35 degrees over the last 5 s, hold 2 s, then look away
# for 1 s and back, hold 2 s. The lower middle of the screen (the tunnel floor) must be no brighter when walked in than
# when seen fresh after looking away (what it should be: with multi-bounce on, the cache's bounce light).
# Before the fix (multi-bounce on): 0.0041 walked in, 0.0018 after; now 0.0005 and 0.0004.
# The room must still be lit.
#   godot --path . --script res://test/gpu/pxtgi_light_carry_test.gd

const SETTLE := 240
const WALK := 900
const TILT := 300
const HOLD := 120
const ROOM_MIN := 0.05 # linear mean of the room's view: the GI and the sun must be on
const TURNED := 60
const AFTER := 120
const SLACK := 0.0002 # linear: the floor's noise between the two looks
var _t := 0
var _cam: Camera3D
var _ok := true
var _from := Vector3(0, 1.7, 3)
var _to := Vector3(0, 1.7, -12)
var _walked_in := 0.0


func _check(cond: bool, msg: String) -> void:
	print("[gi-carry] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _initialize() -> void:
	if not ClassDB.class_exists("PXTGI3D"):
		print("SKIP: no PXTGI3D in this build")
		quit(0)
		return
	var demo: Node = (load("res://demo/editor/rendering/gi_tunnel.tscn") as PackedScene).instantiate()
	_cam = demo.get_node("Camera3D")
	_cam.set_script(null)
	root.add_child(demo)


# Linear mean of the screen between rows y0..y1 of the middle half (as fractions of the height).
func _measure(y0: float, y1: float) -> float:
	var img := root.get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for y in range(int(h * y0), int(h * y1), 6):
		for x in range(w / 4, 3 * w / 4, 6):
			sum += img.get_pixel(x, y).srgb_to_linear().get_luminance()
			n += 1
	return sum / n


func _process(_d: float) -> bool:
	_t += 1
	var f := _t - SETTLE
	if f == 0:
		var room := _measure(0.25, 0.75)
		_check(room > ROOM_MIN, "the room is lit: %.4f (> %.4f)" % [room, ROOM_MIN])
	if f > 0 and f <= WALK:
		_cam.position = _from.lerp(_to, float(f) / WALK)
		if f > WALK - TILT:
			_cam.rotation.x = -deg_to_rad(35.0) * float(f - (WALK - TILT)) / TILT
	if f == WALK + HOLD:
		_walked_in = _measure(0.5, 0.93)
		_cam.rotation.y = -PI / 2
	if f == WALK + HOLD + TURNED:
		_cam.rotation.y = 0.0
	if f == WALK + HOLD + TURNED + AFTER:
		var fresh := _measure(0.5, 0.93)
		_check(_walked_in <= fresh * 1.25 + SLACK, "the tunnel floor walked in (%.5f) is no brighter than seen fresh after looking away (%.5f)" % [_walked_in, fresh])
		quit(0 if _ok else 1)
	return false
