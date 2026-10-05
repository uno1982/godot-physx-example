extends Node3D

# Rigid-body features you set in the Inspector, one station each. Walk up to
# them; everything here is plain Godot nodes and properties.
#
#   Carousel / Elevator   MovingPlatform (demo/common/moving_platform.gd), an
#                         AnimatableBody3D with spin / travel / period. Stand
#                         on one: CharacterBody3D picks up the platform's
#                         motion -- spin included -- and so do the crates.
#   Constant force        RigidBody3D > Constant Forces. The crates' upward
#                         force equals their weight, so they float where you
#                         shove them; the pinwheel's constant torque keeps it
#                         turning (its angular damp sets the top speed).
#   Inertia               RigidBody3D > Mass Distribution > Inertia. Both
#                         flywheels are the same disc; the gold one's inertia
#                         is 5x the shape's own, so the same kick (F) spins it
#                         5x slower. Zero = computed from the shape.
#   Center of mass        RigidBody3D > Mass Distribution > Center Of Mass
#                         Mode = Custom. The green toy's center of mass sits
#                         low in its round base, so it rights itself when
#                         knocked over (G); the red one (Auto) stays down.
#
#   WASD move   SPACE jump   click: capture mouse / look   ESC release mouse
#   F  kick both flywheels   G  knock the toys over   R  reset

const FLYWHEEL_KICK := 50.0 # N*m*s about the axle
const TOY_KNOCK := 2.5 # N*s, sideways at the top

@onready var _char: CharacterBody3D = $Player
@onready var _cam: Camera3D = $Player/Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _flywheels: Array[RigidBody3D] = [$Inertia/Flywheel, $Inertia/HeavyFlywheel]
@onready var _toys: Array[RigidBody3D] = [$CenterOfMass/LowCenter, $CenterOfMass/AutoCenter]
var _fp: FirstPersonCharacter


func _ready() -> void:
	_fp = FirstPersonCharacter.new(_char, _cam, self)


func _physics_process(delta: float) -> void:
	_fp.physics_process(delta)
	var lines := PackedStringArray()
	lines.append("WASD move  SPACE jump  click look  F kick flywheels  G knock toys  R reset")
	lines.append("flywheels  %.1f rad/s  |  %.1f rad/s (5x inertia)" % [_flywheels[0].angular_velocity.y, _flywheels[1].angular_velocity.y])
	lines.append("toys tilt  %.0f deg (custom COM)  |  %.0f deg (auto)" % [_tilt(_toys[0]), _tilt(_toys[1])])
	_hud.text = "\n".join(lines)


func _tilt(rb: RigidBody3D) -> float:
	return rad_to_deg(rb.global_basis.y.angle_to(Vector3.UP))


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
				for w in _flywheels:
					w.apply_torque_impulse(Vector3(0, FLYWHEEL_KICK, 0))
			KEY_G:
				for toy in _toys:
					# Sideways at the head: tips the toy over.
					toy.apply_impulse(Vector3(TOY_KNOCK, 0, 0), toy.global_basis.y * 1.0)
			KEY_R:
				get_tree().reload_current_scene()
