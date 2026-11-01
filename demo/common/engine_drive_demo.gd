extends Node3D
# Root script for engine_drive.tscn: PhysX's engine drive (torque curve, clutch,
# gearbox, autobox) on a muscle car (PhysXVehicle3D, rear-wheel drive) and a
# speed bike (PhysXMotorcycle3D), on a long straight with a marker every 100 m.
#
#   W/S    throttle / brake, then reverse     A/D  steer     Space  brake
#   E / Q  shift up / down (manual)           Shift  clutch
#   M      manual / manual without clutch assist (hold Shift to change gear)
#          / automatic                        R    back to the start
#   Tab    swap between the car and the bike
# Both start in manual, first gear.

@export var vehicle_paths: Array[NodePath] = []
@export var gauge_path: NodePath
@export var hint_path: NodePath
@export var camera_path: NodePath

const HINTS := [
	"PhysXVehicle3D muscle car, drivetrain = Engine",
	"PhysXMotorcycle3D speed bike, drivetrain = Engine",
]
const KEYS := "W/S throttle-brake-reverse, A/D steer, Space brake, E/Q shift up/down, Shift clutch, M manual / manual without clutch assist / automatic, R reset, Tab swap vehicle"

var _vehicles: Array[Node3D] = []
var _starts: Array[Transform3D] = []
var _active := 0
var _gauge: Label
var _hint: Label
var _camera: Node3D


func _ready() -> void:
	for path in vehicle_paths:
		var v: Node3D = get_node(path)
		_vehicles.append(v)
		_starts.append(v.global_transform)
	_gauge = get_node(gauge_path)
	_hint = get_node(hint_path)
	_camera = get_node(camera_path)
	_apply_active()


func _apply_active() -> void:
	for i in _vehicles.size():
		_vehicles[i].active = i == _active
	_camera.set_target(_vehicles[_active])
	_hint.text = "%s  |  %s" % [HINTS[_active], KEYS]


func _process(_delta: float) -> void:
	var v: Node3D = _vehicles[_active]
	var gear_text := _gear_name(v.get_target_gear())
	if v.get_current_gear() != v.get_target_gear():
		gear_text = "%s > %s" % [_gear_name(v.get_current_gear()), gear_text] # shifting
	_gauge.text = "%s   gear %s   %5.0f RPM   %3.0f km/h%s" % [
		"Automatic" if v.automatic_transmission else ("Manual" if v.clutch_assist else "Manual, no clutch assist"),
		gear_text,
		v.get_engine_rpm(),
		absf(v.get_forward_speed()) * 3.6,
		"   clutch" if v.clutch > 0.0 else ""]


func _gear_name(g: int) -> String:
	return "R" if g < 0 else ("N" if g == 0 else str(g))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_R:
		_vehicles[_active].teleport(_starts[_active])
	elif event.keycode == KEY_TAB:
		_active = (_active + 1) % _vehicles.size()
		_apply_active()
