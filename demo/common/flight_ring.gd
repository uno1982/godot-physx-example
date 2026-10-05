extends Area3D
# A ring to fly through: an Area3D whose disc-shaped collision fills the hole.
# The first time something in the "plane" group passes through, it turns
# green and emits `passed`. reset() makes it count again.

signal passed

@export var idle_color := Color(1.0, 0.75, 0.15)
@export var passed_color := Color(0.25, 0.95, 0.35)

var is_passed := false
var _mat: StandardMaterial3D


func _ready() -> void:
	var mesh := $Mesh as MeshInstance3D
	_mat = (mesh.get_active_material(0) as StandardMaterial3D).duplicate()
	mesh.material_override = _mat
	body_entered.connect(_on_body_entered)
	_paint()


func _on_body_entered(body: Node3D) -> void:
	if is_passed or not body.is_in_group("plane"):
		return
	is_passed = true
	_paint()
	passed.emit()


func reset() -> void:
	is_passed = false
	_paint()


func _paint() -> void:
	var c := passed_color if is_passed else idle_color
	_mat.albedo_color = c
	_mat.emission = c
