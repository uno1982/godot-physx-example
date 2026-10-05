extends Node3D
# Root script for vehicle_demo.tscn: six vehicles -- stock VehicleBody3D car,
# PhysXVehicle3D car, stock VehicleBody3D motorcycle, PhysXMotorcycle3D
# motorcycle, PhysXTank3D, and a stock VehicleBody3D prop plane on its own
# runway -- with one control set + camera cycling between them on a single
# key. The plane has a ring course to fly through.
#
#   Tab   cycle control/camera focus between the vehicles
#   R     (plane) back to the runway, rings reset

@export var godot_car_path: NodePath
@export var physx_car_path: NodePath
@export var godot_motorcycle_path: NodePath
@export var physx_motorcycle_path: NodePath
@export var physx_tank_path: NodePath
@export var plane_path: NodePath
@export var plane_stats_path: NodePath
@export var camera_path: NodePath
@export var hud_label_path: NodePath
@export var wall_path: NodePath
@export var screenshot_cam_path: NodePath
@export var impact_distance := 4.5
@export var screenshot_path := "res://excluded/wall_impact.png"

var _vehicles: Array[Node3D] = []
var _hints: Array[String] = []
var _active_index := 0
var _camera: Node3D
var _hud_label: Label

var _wall: Node3D
var _screenshot_cam: Camera3D
var _play_cam: Camera3D
var _impact_captured := false

const HINT_GODOT_CAR := "Driving: Godot VehicleBody3D car (stock)  |  W/S throttle-reverse, A/D steer, Space brake, Tab cycle vehicle, P screenshot, Mouse look (Esc to release)"
const HINT_PHYSX_CAR := "Driving: PhysX PhysXVehicle3D car  |  W/S throttle-brake, A/D steer, Space brake, Tab cycle vehicle, P screenshot, Mouse look (Esc to release)"
const HINT_GODOT_MOTO := "Driving: Godot VehicleBody3D motorcycle (stock, script-side lean balance)  |  W/S throttle-reverse, A/D steer+lean, Space brake, Tab cycle vehicle"
const HINT_PHYSX_MOTO := "Driving: PhysX PhysXMotorcycle3D  |  W/S throttle-brake, A/D steer+lean, Space brake, Tab cycle vehicle"
const HINT_PHYSX_TANK := "Driving: PhysX PhysXTank3D  |  W/S drive, A/D pivot (skid-steer), Space brake, Left click fire, Tab cycle vehicle"
const HINT_PLANE := "Flying: Godot VehicleBody3D stunt plane (stock)  |  W/S throttle, Mouse aim (arcade) or arrows (manual), Q/E roll, A/D yaw, C switch mode, Space brake, R runway, Tab cycle vehicle"

var _plane: Node3D
var _plane_stats: Label

func _ready() -> void:
	_vehicles = [get_node(godot_car_path), get_node(physx_car_path), get_node(godot_motorcycle_path), get_node(physx_motorcycle_path), get_node(physx_tank_path)]
	_hints = [HINT_GODOT_CAR, HINT_PHYSX_CAR, HINT_GODOT_MOTO, HINT_PHYSX_MOTO, HINT_PHYSX_TANK]
	if not plane_path.is_empty():
		_plane = get_node(plane_path)
		_vehicles.append(_plane)
		_hints.append(HINT_PLANE)
	if not plane_stats_path.is_empty():
		_plane_stats = get_node(plane_stats_path)
	_camera = get_node(camera_path)
	_hud_label = get_node(hud_label_path)
	_apply_active()

	if not wall_path.is_empty():
		_wall = get_node(wall_path)
	if not screenshot_cam_path.is_empty():
		_screenshot_cam = get_node(screenshot_cam_path)
	# The chase camera's own current Camera3D child -- restored after a
	# screenshot swaps to screenshot_cam, so normal driving resumes.
	_play_cam = get_viewport().get_camera_3d()

# Left as a commented-out example of how to trigger a screenshot (or any
# other one-shot reaction) directly off a destruction event -- proximity to
# the wall here, but the same pattern applies to PhysXDestructible3D signals
# like a chunk breaking off. P still captures a screenshot manually below.
#func _physics_process(_delta: float) -> void:
#	if _impact_captured or not _wall or not _screenshot_cam:
#		return
#	var active_vehicle: Node3D = _vehicles[_active_index]
#	if active_vehicle.global_position.distance_to(_wall.global_position) <= impact_distance:
#		_impact_captured = true
#		_capture_impact_screenshot()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_active_index = (_active_index + 1) % _vehicles.size()
			_apply_active()
		elif event.keycode == KEY_P:
			_capture_impact_screenshot()
		elif event.keycode == KEY_R and _plane and _vehicles[_active_index] == _plane:
			_plane.reset_to_runway()
			_camera.set_target(_plane) # aim straight down the runway again
			for ring in get_tree().get_nodes_in_group("flight_rings"):
				ring.reset()


func _process(_delta: float) -> void:
	if not _plane_stats:
		return
	var flying := _plane and _vehicles[_active_index] == _plane
	_plane_stats.visible = flying
	if flying:
		var rings := get_tree().get_nodes_in_group("flight_rings")
		var passed := 0
		for ring in rings:
			passed += 1 if ring.is_passed else 0
		_plane_stats.text = "%s   airspeed %3.0f km/h   altitude %4.0f m   throttle %3.0f%%   rings %d / %d" % [
			"ARCADE (C: manual)" if _plane.control_mode == _plane.ControlMode.ARCADE else "MANUAL (C: arcade)",
			_plane.airspeed() * 3.6, _plane.global_position.y, _plane.throttle * 100.0, passed, rings.size()]

func _apply_active() -> void:
	for i in _vehicles.size():
		_vehicles[i].active = (i == _active_index)
	_camera.set_target(_vehicles[_active_index])
	_hud_label.text = _hints[_active_index]

func _capture_impact_screenshot() -> void:
	if not _screenshot_cam:
		return
	_screenshot_cam.current = true
	# The viewport needs at least one render pass with the new camera
	# active before get_texture() reflects it.
	await get_tree().process_frame
	await get_tree().process_frame

	var base := screenshot_path.get_basename()
	var ext := screenshot_path.get_extension()
	for i in range(1, 4):
		var tex := get_viewport().get_texture()
		var img := tex.get_image() if tex else null
		var numbered_path := "%s_%d.%s" % [base, i, ext]
		if img:
			img.save_png(numbered_path)
			print("[vehicle_swap] screenshot saved: %s" % numbered_path)
		else:
			print("[vehicle_swap] no renderable viewport texture (e.g. headless run) -- screenshot skipped")
		if i < 3:
			# A few frames apart so the burst shows the moment of impact
			# unfolding, not three near-identical shots.
			for _f in range(6):
				await get_tree().process_frame

	if _play_cam:
		_play_cam.current = true
