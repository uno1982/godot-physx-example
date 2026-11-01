extends PhysXVehicle3D
# Same arcade drive controls as vehicle_rig.gd (W/S throttle, A/D steer,
# Space brake), mapped onto PhysXVehicle3D's own throttle/brake/steer inputs
# (PxVehicleCommandState's [0,1]/[0,1]/[-1,1] convention) instead of
# VehicleBody3D's raw engine_force/steering -- different units, same keys,
# so the two cars feel directly comparable side by side.
#
# With drivetrain = Engine there is a gearbox too:
#   E / Q  shift up / down (switches to manual)
#   M      back to automatic
#   Shift  hold the clutch

@export var steer_speed := 2.0 # normalized steering input/sec toward the target

# Only the active car reads keyboard input -- see vehicle_rig.gd's own note
# on why the inactive one must relax to neutral instead of coasting.
var active := false

var _shift_keys := {} # key -> held last tick, so a shift happens once per press

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
		_gearbox_input()

	var s := 0.0
	if Input.is_key_pressed(KEY_A):
		s += 1.0
	if Input.is_key_pressed(KEY_D):
		s -= 1.0
	steer = move_toward(steer, s, steer_speed * delta)


func _pressed(key: Key) -> bool:
	var down := Input.is_key_pressed(key)
	var pressed: bool = down and not _shift_keys.get(key, false)
	_shift_keys[key] = down
	return pressed


func _gearbox_input() -> void:
	clutch = 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	if _pressed(KEY_M):
		automatic_transmission = true
	var up := _pressed(KEY_E)
	var down := _pressed(KEY_Q)
	if up or down:
		if automatic_transmission:
			# Take over from the gear the autobox is in.
			automatic_transmission = false
			gear = maxi(get_target_gear(), 1)
		gear = clampi(gear + (1 if up else -1), 0, gear_ratios.size())
