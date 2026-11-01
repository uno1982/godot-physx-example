extends RefCounted
# The engine drive's gearbox keys, for any PhysX vehicle with drivetrain = Engine
# (physx_vehicle_rig.gd, physx_motorcycle_rig.gd). Call update(vehicle) every
# physics tick while the vehicle is driven:
#   E / Q  shift up / down (switches to manual)
#   M      cycle manual / manual without clutch assist (a shift needs
#          Shift held) / automatic
#   Shift  hold the clutch

var _held := {} # key -> held last tick, so a shift happens once per press


func update(vehicle: Node3D) -> void:
	vehicle.clutch = 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	# Clutch assist only means anything in manual, so M cycles three modes:
	# manual -> manual without clutch assist -> automatic -> manual.
	if _pressed(KEY_M):
		if vehicle.automatic_transmission:
			_take_over(vehicle)
		elif vehicle.clutch_assist:
			vehicle.clutch_assist = false
		else:
			vehicle.automatic_transmission = true
	var up := _pressed(KEY_E)
	var down := _pressed(KEY_Q)
	# Without the assist the gearbox won't move unless the clutch is down, so don't queue a gear it won't take.
	if (up or down) and (vehicle.clutch_assist or vehicle.clutch >= 0.5):
		if vehicle.automatic_transmission:
			_take_over(vehicle)
		vehicle.gear = clampi(vehicle.gear + (1 if up else -1), 0, vehicle.gear_ratios.size())


func _pressed(key: Key) -> bool:
	var down := Input.is_key_pressed(key)
	var pressed: bool = down and not _held.get(key, false)
	_held[key] = down
	return pressed


# Manual from here on, starting in the gear the autobox is in (or shifting to).
func _take_over(vehicle: Node3D) -> void:
	vehicle.automatic_transmission = false
	vehicle.clutch_assist = true
	vehicle.gear = maxi(vehicle.get_target_gear(), 1)
