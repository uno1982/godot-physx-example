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
@export var wall_path: NodePath
@export var screenshot_cam_path: NodePath
@export var impact_distance := 4.5
@export var screenshot_path := "res://excluded/wall_impact.png"

var _godot_car: Node3D
var _physx_car: Node3D
var _camera: Node3D
var _hud_label: Label
var _active_is_physx := false

var _wall: Node3D
var _screenshot_cam: Camera3D
var _play_cam: Camera3D
var _impact_captured := false

const HINT_GODOT := "Driving: Godot VehicleBody3D (stock)  |  W/S throttle-reverse, A/D steer, Space brake, Tab swap car, P screenshot, Mouse look (Esc to release)"
const HINT_PHYSX := "Driving: PhysX PhysXVehicle3D  |  W/S throttle-brake, A/D steer, Space brake, Tab swap car, P screenshot, Mouse look (Esc to release)"

func _ready() -> void:
	_godot_car = get_node(godot_car_path)
	_physx_car = get_node(physx_car_path)
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

func _physics_process(_delta: float) -> void:
	if _impact_captured or not _wall or not _screenshot_cam:
		return
	var active_car: Node3D = _physx_car if _active_is_physx else _godot_car
	if active_car.global_position.distance_to(_wall.global_position) <= impact_distance:
		_impact_captured = true
		_capture_impact_screenshot()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_active_is_physx = not _active_is_physx
			_apply_active()
		elif event.keycode == KEY_P:
			_capture_impact_screenshot()

func _apply_active() -> void:
	_godot_car.active = not _active_is_physx
	_physx_car.active = _active_is_physx
	var target: Node3D = _physx_car if _active_is_physx else _godot_car
	_camera.set_target(target)
	_hud_label.text = HINT_PHYSX if _active_is_physx else HINT_GODOT

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
