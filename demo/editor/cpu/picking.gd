extends Node3D

# Mouse picking and area queries -- CollisionObject3D.input_ray_pickable and
# collide_with_areas, all set in the Inspector.
#
#   Hover an object: it lights up (mouse_entered / mouse_exited). Click it:
#   it reacts (input_event). Areas are pickable too -- the zones are Area3D.
#
#   Left zone   behind a glass pane with input_ray_pickable OFF: the mouse
#               goes through the glass and picks the zone.
#   Middle zone behind a glass pane with input_ray_pickable ON: the glass
#               takes the mouse; the zone behind it can't be picked.
#   Crate       a RigidBody3D -- click to kick it.
#   Laser       a RayCast3D sweeping across the zones; T toggles its
#               collide_with_areas (off: it passes through the zones and
#               only stops at bodies).
#
#   T  toggle the laser's collide_with_areas   R  reset   ESC quit

const KICK := 6.0

@onready var _hud: Label = $HUD/Label
@onready var _laser: RayCast3D = $Laser
@onready var _beam: MeshInstance3D = $Laser/Beam
var _hovered := "-"
var _last_click := "-"
var _time := 0.0


func _ready() -> void:
	for co in get_tree().get_nodes_in_group("pickable"):
		var mesh := _mesh_of(co)
		if mesh:
			# Each object highlights on its own.
			mesh.material_override = (mesh.get_active_material(0) as StandardMaterial3D).duplicate()
		co.mouse_entered.connect(_on_enter.bind(co))
		co.mouse_exited.connect(_on_exit.bind(co))
		co.input_event.connect(_on_input_event.bind(co))


func _mesh_of(co: Node) -> MeshInstance3D:
	for c in co.get_children():
		if c is MeshInstance3D:
			return c
	return null


func _glow(co: Node, on: bool) -> void:
	var mesh := _mesh_of(co)
	if mesh:
		var mat := mesh.material_override as StandardMaterial3D
		mat.emission_enabled = on
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 1.2


func _on_enter(co: CollisionObject3D) -> void:
	_hovered = co.name
	_glow(co, true)


func _on_exit(co: CollisionObject3D) -> void:
	if _hovered == co.name:
		_hovered = "-"
	_glow(co, false)


func _on_input_event(_camera: Node, event: InputEvent, pos: Vector3, _normal: Vector3, _shape: int, co: CollisionObject3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_last_click = co.name
		if co is RigidBody3D:
			co.apply_impulse(Vector3(0, KICK, -KICK * 0.5), pos - co.global_position)
		else:
			# Spin the clicked mesh a little so the click is visible.
			var mesh := _mesh_of(co)
			if mesh:
				create_tween().tween_property(mesh, "rotation:y", mesh.rotation.y + PI * 0.5, 0.25)


func _physics_process(delta: float) -> void:
	_time += delta
	# Sweep the laser left and right across the zones.
	_laser.rotation.y = sin(_time * 0.5) * 0.75
	_laser.force_raycast_update()
	var length := 30.0
	var hit := "-"
	if _laser.is_colliding():
		length = _laser.global_position.distance_to(_laser.get_collision_point())
		hit = _laser.get_collider().name
	_beam.scale = Vector3(1, 1, length)
	_beam.position = Vector3(0, 0, length * 0.5)
	_hud.text = "hover: %s   last click: %s\nlaser collide_with_areas: %s (T)   laser hits: %s\nR reset   ESC quit" % [_hovered, _last_click, "ON" if _laser.collide_with_areas else "off", hit]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				_laser.collide_with_areas = not _laser.collide_with_areas
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()
