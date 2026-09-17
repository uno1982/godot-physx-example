extends Node3D
# Root script for vehicle_demo.tscn: both cars (stock VehicleBody3D vs. the
# PhysX-specific PhysXVehicle3D) sit on the same track so they're directly
# comparable, and one control set + camera swaps between them with a single
# key -- rather than two separate demo scenes compared from memory.
#
#   Tab   swap control/camera focus between the two cars

@export var godot_car_path: NodePath
@export var physx_car_path: NodePath
@export var camera_path: NodePath
@export var hud_label_path: NodePath

var _godot_car: Node
var _physx_car: Node
var _camera: Node3D
var _hud_label: Label
var _active_is_physx := false

const HINT_GODOT := "Driving: Godot VehicleBody3D (stock)  |  W/S throttle-reverse, A/D steer, Space brake, Tab swap car, Mouse look (Esc to release)"
const HINT_PHYSX := "Driving: PhysX PhysXVehicle3D  |  W/S throttle-brake, A/D steer, Space brake, Tab swap car, Mouse look (Esc to release)"

func _ready() -> void:
	_godot_car = get_node(godot_car_path)
	_physx_car = get_node(physx_car_path)
	_camera = get_node(camera_path)
	_hud_label = get_node(hud_label_path)
	_apply_active()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_active_is_physx = not _active_is_physx
		_apply_active()

func _apply_active() -> void:
	_godot_car.active = not _active_is_physx
	_physx_car.active = _active_is_physx
	var target: Node3D = _physx_car if _active_is_physx else _godot_car
	_camera.set_target(target)
	_hud_label.text = HINT_PHYSX if _active_is_physx else HINT_GODOT
