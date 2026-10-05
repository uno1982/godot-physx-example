extends Node3D

# ConcavePolygonShape3D.backface_collision -- one-sided vs two-sided trimesh.
# Both platforms are the same flat trimesh (a PlaneMesh's faces, front side
# up). Select a platform's CollisionShape3D to see the setting.
#
#   One-way (backface_collision off)  only the front collides: jump up through
#                                     it from below and land on top. Rays,
#                                     shape casts and bodies coming from
#                                     below pass too.
#   Solid (backface_collision on)     both sides collide: you bump your head.
#
# Step on a glowing pad to be launched up at a platform.
#
#   WASD move   SPACE jump   click: capture mouse / look   ESC release mouse
#   F  fire a ball up under each platform   R  reset

const PAD_RADIUS := 0.9
const PAD_LAUNCH := 11.0 # m/s up: clears the 3 m platforms
const BALL_SPEED := 12.0
const MAX_BALLS := 40

@onready var _char: CharacterBody3D = $Player
@onready var _cam: Camera3D = $Player/Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _pads: Array[Node3D] = [$OneWay/Pad, $Solid/Pad]
@onready var _platforms: Array[Node3D] = [$OneWay, $Solid]
var _fp: FirstPersonCharacter
var _balls: Array[RigidBody3D] = []
var _ball_mesh := SphereMesh.new()
var _ball_shape := SphereShape3D.new()


func _ready() -> void:
	_fp = FirstPersonCharacter.new(_char, _cam, self)
	_ball_mesh.radius = 0.25
	_ball_mesh.height = 0.5
	_ball_shape.radius = 0.25


func _physics_process(delta: float) -> void:
	_fp.physics_process(delta)
	if _char.is_on_floor():
		for pad in _pads:
			var d := _char.global_position - pad.global_position
			# On the pad itself, not on the platform above it.
			if Vector2(d.x, d.z).length() < PAD_RADIUS and d.y < 1.5:
				# Move off the floor now: next tick the controller would see
				# the floor and cancel the launch.
				_char.velocity.y = PAD_LAUNCH
				_char.move_and_slide()
	_hud.text = "WASD move  SPACE jump  click look  F fire balls up  R reset\nstand on a glowing pad to launch -- one-way lets you through, solid stops you"


func _fire_balls() -> void:
	for platform in _platforms:
		var rb := RigidBody3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = _ball_mesh
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = _ball_shape
		rb.add_child(cs)
		rb.position = platform.global_position + Vector3(randf_range(-1.2, 1.2), -2.4, randf_range(-1.6, -0.8))
		rb.linear_velocity = Vector3(0, BALL_SPEED, 0)
		add_child(rb)
		_balls.append(rb)
	while _balls.size() > MAX_BALLS:
		_balls.pop_front().queue_free()


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
			KEY_F:
				_fire_balls()
			KEY_R:
				get_tree().reload_current_scene()
