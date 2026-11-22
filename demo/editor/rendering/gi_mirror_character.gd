extends Node3D

# A character in a mirror: you are the mannequin, in a room with a wall mirror. In first person the camera is in its
# head and its body isn't drawn for the camera (it's on a render layer the camera leaves out), but the mirror still
# shows it: you see yourself only in the mirror (and in your shadow). Two ways to make the mirror (P):
#
# PXTGI's traced reflection. PXTGI traces off-screen rays against the scene's collision shapes. By default a character
# is seen only through its collision shapes, which for this mannequin are its physical bones' capsules: a gray figure
# of capsules (M off). With "pxtgi_traced" true in its skinned mesh's metadata (set in this scene on Mannequin >
# Mannequin > Armature > GeneralSkeleton > Mannequin, the Inspector's Metadata; an int instead of true is the number
# of triangles to trace it with), PXTGI traces the mesh's own triangles (its coarsest LOD with about 3000, skinned to
# the pose every frame) in its surfaces' colors, and leaves out its skeleton's capsules: the mirror shows the
# character's shape and colors (the purple joints too), in first and third person (C). Cheap, and works on any smooth
# surface (curved metal, glossy floors, many at once), but a character is its traced mesh: one color per triangle.
#
# A PhysXMirror3D (CaptureMirror in this scene, in front of the mirror's glass): a scene capture, as Unreal's
# SceneCaptureComponent2D. A second camera renders the mirrored view into a texture its glass shows: the real render
# (textures, normal maps, Godot's shadows) of one flat rectangle, at the cost of drawing what it sees again. It can be
# lit by PXTGI (G), which costs PXTGI again at its resolution (K).
#
#   WASD       walk          mouse  look (click to capture it, Esc to let go)
#   3          dance (until you walk)
#   P          the mirror: PXTGI's traced reflection / the PhysXMirror3D
#   M          the mannequin's pxtgi_traced tag on / off (off: PXTGI sees its physical bones' capsules)
#   C          camera: first person / third person
#   K          the PhysXMirror3D's resolution: the full view's height / half / a quarter
#   G          the PhysXMirror3D lit by PXTGI or not (off: direct light only, and PXTGI doesn't run for it)

const WALK_SPEED := 1.3 # m/s, about the Walk clip's pace
const TURN := 0.003 # rad per pixel of mouse motion
const ROOM := 2.6 # how far from the room's middle the mannequin may walk (the walls are at 3)
const BODY_LAYER := 1 << 1 # the mannequin's mesh: drawn for everything but the first person camera
const CAPTURE_SCALES := [1.0, 0.5, 0.25]

@onready var _label: Label = $HUD/Label
@onready var _mannequin: Node3D = $Mannequin
@onready var _camera: Camera3D = $Camera3D
@onready var _capture: Node3D = $CaptureMirror

var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _head := -1
var _first_person := true
var _yaw := 0.0 # the mannequin's heading (0: facing the mirror, -z)
var _pitch := -0.1
var _animation := ""
var _capture_scale := 0


func _ready() -> void:
	_mesh = _mannequin.find_children("*", "MeshInstance3D", true, false)[0]
	_skeleton = _mannequin.find_children("*", "Skeleton3D", true, false)[0]
	_player = _mannequin.find_child("AnimationPlayer", true, false)
	_head = _skeleton.find_bone("Head")
	_mesh.layers = BODY_LAYER
	_mannequin.position = Vector3(0, 0, 1.0) # a few steps back from the mirror
	_set_camera()
	_play("Idle")
	_show()


func _traced() -> bool:
	return bool(_mesh.get_meta("pxtgi_traced", false))


func _play(clip: String) -> void:
	if _animation != clip:
		_animation = clip
		_player.play(clip, 0.2)


func _physics_process(delta: float) -> void:
	var input := Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	# The mannequin faces its local +z; turned by _yaw from facing the mirror (-z).
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	if input != Vector2.ZERO:
		var step := (forward * input.y + right * input.x).normalized() * WALK_SPEED * delta
		var p := _mannequin.position + step
		_mannequin.position = Vector3(clampf(p.x, -ROOM, ROOM), 0, clampf(p.z, -ROOM, ROOM))
		_play("Walk")
	elif _animation == "Walk":
		_play("Idle")
	_mannequin.basis = Basis(Vector3.UP, _yaw + PI)


func _process(_delta: float) -> void:
	_set_camera()


# First person: at the eyes (the head bone, a little forward and up), looking where the mannequin faces, tilted by
# the mouse. Third person: behind its right shoulder.
func _set_camera() -> void:
	var look := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	if _first_person:
		var head := (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head)).origin
		var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
		_camera.global_transform = Transform3D(look, head + forward * 0.12 + Vector3(0, 0.04, 0))
		_camera.cull_mask = 0xFFFFF & ~BODY_LAYER
	else:
		var back := look * Vector3(0.45, 0.25, 1.9)
		_camera.global_transform = Transform3D(look, _mannequin.global_position + Vector3(0, 1.55, 0) + back)
		_camera.cull_mask = 0xFFFFF


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * TURN
		_pitch = clampf(_pitch - event.relative.y * TURN, -1.2, 1.2)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_3:
			_play("Dance")
		KEY_P:
			_capture.visible = not _capture.visible
		KEY_M:
			_mesh.set_meta("pxtgi_traced", not _traced())
		KEY_C:
			_first_person = not _first_person
			_set_camera()
		KEY_K:
			_capture_scale = (_capture_scale + 1) % CAPTURE_SCALES.size()
			_capture.resolution_scale = CAPTURE_SCALES[_capture_scale]
		KEY_G:
			_capture.gi = not _capture.gi
		_:
			return
	_show()


func _show() -> void:
	var lines := [
		"A character in a mirror: you",
		"WASD walk   mouse look (click to capture, Esc to let go)   3 dance",
		"P  the mirror: %s" % ["PhysXMirror3D (scene capture)" if _capture.visible else "PXTGI's traced reflection"],
		"M  pxtgi_traced: %s" % ["ON (the mesh)" if _traced() else "OFF (its physical bones' capsules)"],
		"C  camera: %s" % ["first person" if _first_person else "third person"],
		"K  PhysXMirror3D resolution: %d%% of the view's height" % int(CAPTURE_SCALES[_capture_scale] * 100),
		"G  PhysXMirror3D lit by PXTGI: %s" % ["ON" if _capture.gi else "OFF"],
	]
	_label.text = "\n".join(lines)
