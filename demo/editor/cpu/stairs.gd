extends Node3D

# SeparationRayShape3D -- a body standing on a ray. Select a ray's
# CollisionShape3D to see it (and its length / slide_on_slope) in the editor.
#
#   Stair bots   two identical bots walk up identical 0.3 m stairs. The left
#                one stands on a ray reaching 0.5 m below its capsule: when
#                the ray's tip meets a step it lifts the bot onto it. The
#                right one is just a capsule and stops at the first step.
#   You          the same setup as the left bot: walk the stairs yourself.
#   Hover sled   a RigidBody3D on four rays, one per corner -- it floats over
#                the bumps; walk into it to push it.
#
#   WASD move   SPACE jump   click: capture mouse / look   ESC release mouse
#   R reset

const BOT_SPEED := 2.0
const BOT_GRAVITY := 18.0
const BOT_LOOP := 4.5 # s, then the bots start over

@onready var _char: CharacterBody3D = $Player
@onready var _cam: Camera3D = $Player/Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _bots: Array[CharacterBody3D] = [$RayBot, $CapsuleBot]
var _bot_starts: Array[Vector3] = []
var _bot_time := 0.0
var _fp: FirstPersonCharacter


func _ready() -> void:
	_fp = FirstPersonCharacter.new(_char, _cam, self)
	for bot in _bots:
		_bot_starts.append(bot.position)


func _physics_process(delta: float) -> void:
	_fp.physics_process(delta)

	_bot_time += delta
	if _bot_time > BOT_LOOP:
		_bot_time = 0.0
		for i in _bots.size():
			_bots[i].position = _bot_starts[i]
			_bots[i].velocity = Vector3.ZERO
	for bot in _bots:
		var v := bot.velocity
		v.z = -BOT_SPEED
		v.y = -0.1 if bot.is_on_floor() else v.y - BOT_GRAVITY * delta
		bot.velocity = v
		bot.move_and_slide()

	_hud.text = "WASD move  SPACE jump  click look  R reset\nray bot height %.2f m   capsule bot height %.2f m" % [_bots[0].position.y, _bots[1].position.y]


func _unhandled_input(event: InputEvent) -> void:
	if _fp.handle_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()
			KEY_R:
				get_tree().reload_current_scene()
