extends VehicleBody3D
# Simple arcade drive controls for the vehicle showcase.
#   W/S     throttle / reverse
#   Space   brake
#   A/D     steering

@export var max_engine_force := 120.0
@export var max_brake_force := 40.0
# What looked like a steering-angle stability limit (runaway yaw rate at
# 0.4 rad+) was actually a real bug in this backend's PhysicsDirectBodyState3D
# .apply_impulse() -- see godot_physx_body_3d.cpp's own comment on it. Fixed;
# 0.4 and 0.6 rad both retested clean (bounded yaw rate, settles cleanly on
# release, no roll/tumble) once that landed. 0.6 rad (~34 degrees) is already
# a realistic max front-wheel steering angle for a real car.
@export var max_steer_angle := 0.6 # radians, ~34 degrees
@export var steer_speed := 2.0 # radians/sec toward the target angle

# Only the active car reads keyboard input -- the demo has two cars sharing
# one set of controls (see vehicle_swap.gd), so the inactive one must relax
# its own inputs to a neutral idle instead of coasting on whatever was last
# held down before the swap.
var active := true

func _physics_process(delta: float) -> void:
	if not active:
		engine_force = 0.0
		brake = 0.0
		steering = move_toward(steering, 0.0, steer_speed * delta)
		return

	var throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	engine_force = throttle * max_engine_force

	brake = max_brake_force if Input.is_key_pressed(KEY_SPACE) else 0.0

	var steer_input := 0.0
	if Input.is_key_pressed(KEY_A):
		steer_input += 1.0
	if Input.is_key_pressed(KEY_D):
		steer_input -= 1.0
	var target_steer := steer_input * max_steer_angle
	steering = move_toward(steering, target_steer, steer_speed * delta)
