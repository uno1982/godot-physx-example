extends Camera3D
# Demo rig for area-to-area detection (feature/physx-area-area): a fly camera
# with an Area3D "probe" mounted on it. Flying the probe into any monitorable
# Area3D "zone" in the scene is detected purely through Area3D.area_entered/
# area_exited -- PhysX itself never reports trigger-trigger pairs, so this is
# GodotPhysXSpace3D's manual per-step overlap poll doing the work (see
# modules/godot_physx/objects/godot_physx_area_3d.h). Recolors the zone's own
# mesh and updates an on-screen label so the trigger is visually obvious
# without reading the console.

const FlyCamera = preload("res://demo/common/fly_camera.gd")

@export var fly_speed := 8.0
@export var probe_path: NodePath
@export var status_label_path: NodePath

const COLOR_IDLE := Color(0.25, 0.8, 1.0, 0.35)
const COLOR_TRIGGERED := Color(1.0, 0.25, 0.25, 0.6)

var _fly: FlyCamera
var _probe: Area3D
var _label: Label
var _inside: Array[Area3D] = []

func _ready() -> void:
	_fly = FlyCamera.new(self, fly_speed)
	_probe = get_node(probe_path)
	_label = get_node_or_null(status_label_path)
	_probe.area_entered.connect(_on_zone_entered)
	_probe.area_exited.connect(_on_zone_exited)
	_update_label()

func _process(delta: float) -> void:
	_fly.process(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _fly.handle_input(event):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_zone_entered(area: Area3D) -> void:
	print("[area_zone] entered: ", area.name)
	if not _inside.has(area):
		_inside.append(area)
	_set_zone_color(area, COLOR_TRIGGERED)
	_update_label()

func _on_zone_exited(area: Area3D) -> void:
	print("[area_zone] exited: ", area.name)
	_inside.erase(area)
	_set_zone_color(area, COLOR_IDLE)
	_update_label()

func _update_label() -> void:
	if not _label:
		return
	if _inside.is_empty():
		_label.text = "outside any zone"
	else:
		var names := _inside.map(func(a): return a.name)
		_label.text = "IN ZONE: %s" % ", ".join(names)

func _set_zone_color(area: Area3D, color: Color) -> void:
	for child in area.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			(child.material_override as StandardMaterial3D).albedo_color = color
