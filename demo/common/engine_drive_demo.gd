extends Node3D
# Root script for engine_drive.tscn: a PhysXVehicle3D with drivetrain = Engine
# (PhysX's engine drive: torque curve, clutch, gearbox, autobox, differential)
# on a long straight with a marker every 100 m.
#
#   W/S    throttle / brake, then reverse     A/D  steer     Space  brake
#   E / Q  shift up / down (manual)           M    automatic / manual
#   Shift  clutch                             R    back to the start
#   C      clutch assist on / off (off: hold Shift to change gear in manual)

@export var car_path: NodePath
@export var gauge_path: NodePath

var _car: PhysXVehicle3D
var _gauge: Label
var _start: Transform3D


func _ready() -> void:
	_car = get_node(car_path)
	_gauge = get_node(gauge_path)
	_car.active = true
	_start = _car.global_transform


func _process(_delta: float) -> void:
	var gear_text := _gear_name(_car.get_target_gear())
	if _car.get_current_gear() != _car.get_target_gear():
		gear_text = "%s > %s" % [_gear_name(_car.get_current_gear()), gear_text] # shifting
	_gauge.text = "%s   gear %s   %4.0f RPM   %3.0f km/h%s" % [
		"Automatic" if _car.automatic_transmission else "Manual",
		gear_text,
		_car.get_engine_rpm(),
		absf(_car.get_forward_speed()) * 3.6,
		("   clutch" if _car.clutch > 0.0 else "") + ("" if _car.clutch_assist else "   (no clutch assist)")]


func _gear_name(g: int) -> String:
	return "R" if g < 0 else ("N" if g == 0 else str(g))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_car.teleport(_start)
