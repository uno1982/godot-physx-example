extends PhysXVehicle3D
# Same arcade drive controls as vehicle_rig.gd (W/S throttle, A/D steer,
# Space brake), mapped onto PhysXVehicle3D's own throttle/brake/steer inputs
# (PxVehicleCommandState's [0,1]/[0,1]/[-1,1] convention) instead of
# VehicleBody3D's raw engine_force/steering -- different units, same keys,
# so the two cars feel directly comparable side by side.
#
# With drivetrain = Engine there is a gearbox too:
#   E / Q  shift up / down, M gearbox mode, Shift clutch (gearbox_keys.gd)

@export var steer_speed := 2.0 # normalized steering input/sec toward the target

# Only the active car reads keyboard input -- see vehicle_rig.gd's own note
# on why the inactive one must relax to neutral instead of coasting.
var active := false

var _gearbox := preload("res://demo/common/gearbox_keys.gd").new()

func _physics_process(delta: float) -> void:
	if not active:
		throttle = 0.0
		brake = 0.0
		steer = move_toward(steer, 0.0, steer_speed * delta)
		return

	# W always drives forward. S brakes while still moving forward (matching
	# a real car -- you brake to a stop before a gear can safely reverse),
	# then switches to real reverse (PxVehicleDirectDriveTransmissionCommandState
	# .eREVERSE, a gear-level throttle-sign flip, not a raw negative throttle)
	# once forward speed has actually dropped near zero.
	if Input.is_key_pressed(KEY_W):
		reverse = false
		throttle = 1.0
		brake = 0.0
	elif Input.is_key_pressed(KEY_S):
		if not reverse and get_forward_speed() > 0.5:
			throttle = 0.0
			brake = 1.0
		else:
			reverse = true
			throttle = 1.0
			brake = 0.0
	else:
		throttle = 0.0
		brake = 0.0

	if Input.is_key_pressed(KEY_SPACE):
		brake = 1.0
		throttle = 0.0

	if drivetrain == DRIVETRAIN_ENGINE:
		_gearbox.update(self)

	var s := 0.0
	if Input.is_key_pressed(KEY_A):
		s += 1.0
	if Input.is_key_pressed(KEY_D):
		s -= 1.0
	steer = move_toward(steer, s, steer_speed * delta)

