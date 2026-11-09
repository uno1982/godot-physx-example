extends Node3D

## Desert scrub, generated: thick clumps of grass (blades rooted over a patch) and thin tufts of dry grass (a fan of
## blades from one point), scattered at random over the ground around this node, each its own size, turn and shade. One
## MultiMeshInstance3D per kind, so thousands cost a draw each. They sway in the wind and, near the tornado (tornado's
## position, every frame), whip around it (desert_grass.gdshader).

@export var clumps := 2500
@export var tufts := 2500
## How far from this node they're scattered (meters), and none closer than clear_radius (the camera's foreground).
@export var radius := 160.0
@export var clear_radius := 0.0
@export var clump_color := Color(0.3, 0.34, 0.18)
@export var tuft_color := Color(0.66, 0.6, 0.4)
@export var layout_seed := 7
## The tornado the grass near it bends around.
@export var tornado: Node3D
## The floor the scrub grows on (desert_ground.gd: height_at); none: flat at this node's height.
@export var ground: Node

@export_group("Wind")
## The breeze: its direction, how far the tips move in it, and how fast the gusts come.
@export var wind_direction := Vector3(1.0, 0.0, 0.3):
	set(v):
		wind_direction = v
		_apply_wind()
@export_range(0.0, 0.5, 0.005) var sway := 0.06:
	set(v):
		sway = v
		_apply_wind()
@export_range(0.0, 8.0, 0.05) var sway_speed := 1.6:
	set(v):
		sway_speed = v
		_apply_wind()
## How far from the tornado the grass feels it (meters), and how hard it's dragged around it and in toward it.
@export_range(0.0, 100.0, 0.5) var vortex_reach := 22.0:
	set(v):
		vortex_reach = v
		_apply_wind()
@export_range(0.0, 4.0, 0.01) var vortex_strength := 1.0:
	set(v):
		vortex_strength = v
		_apply_wind()

var _rng := RandomNumberGenerator.new()
var _grass_mat := ShaderMaterial.new()


func _ready() -> void:
	_rng.seed = layout_seed
	_grass_mat.shader = preload("res://demo/editor/flow/desert_grass.gdshader")
	_apply_wind()
	_scatter(_grass_mesh(55, 0.35, 0.3, 0.65, 0.04), clumps, 0.6, 1.4, clump_color, 0.3)
	_scatter(_grass_mesh(16, 0.0, 0.45, 0.8, 0.045), tufts, 0.6, 1.5, tuft_color, 0.2)


# Grass: p_blades blades, each a thin pointed triangle leaning out from where it grows, rooted over a patch
# p_spread wide (0: all from one point, a tuft); the outer ones shorter and leaning further (a full, rounded clump).
# Both sides drawn.
func _grass_mesh(p_blades: int, p_spread: float, p_min_tall: float, p_max_tall: float, p_width: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in p_blades:
		var a := TAU * i / p_blades + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x) * p_width
		var from_middle := sqrt(_rng.randf())
		var base := out * (0.03 + from_middle * p_spread)
		var lean := _rng.randf_range(0.15, 0.35) + from_middle * 0.3
		var tall := _rng.randf_range(p_min_tall, p_max_tall) * (1.0 - from_middle * 0.4)
		var tip := base + out * lean + Vector3.UP * tall
		st.set_normal(Vector3.UP)
		st.add_vertex(base - side)
		st.add_vertex(base + side)
		st.add_vertex(tip)
	var mesh := st.commit()
	mesh.surface_set_material(0, _grass_mat)
	return mesh


func _apply_wind() -> void:
	_grass_mat.set_shader_parameter("wind_dir", wind_direction)
	_grass_mat.set_shader_parameter("sway", sway)
	_grass_mat.set_shader_parameter("sway_speed", sway_speed)
	_grass_mat.set_shader_parameter("vortex_reach", vortex_reach)
	_grass_mat.set_shader_parameter("vortex_strength", vortex_strength)


func _floor_at(x: float, z: float) -> float:
	return ground.height_at(x, z) if ground != null and ground.has_method("height_at") else 0.0


func _process(_delta: float) -> void:
	if tornado != null:
		_grass_mat.set_shader_parameter("vortex_center", tornado.global_position)


func _scatter(p_mesh: Mesh, p_count: int, p_min_size: float, p_max_size: float, p_color: Color, p_shade: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = p_mesh
	mm.instance_count = p_count
	for i in p_count:
		# Even over the disk's area, outside the clear middle.
		var r := sqrt(_rng.randf_range(clear_radius * clear_radius / (radius * radius), 1.0)) * radius
		var a := _rng.randf() * TAU
		var s := _rng.randf_range(p_min_size, p_max_size)
		var xf := Transform3D(Basis().rotated(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.2), s)), Vector3(cos(a) * r, _floor_at(cos(a) * r, sin(a) * r) - 0.05, sin(a) * r))
		mm.set_instance_transform(i, xf)
		var shade := _rng.randf_range(1.0 - p_shade, 1.0 + p_shade)
		mm.set_instance_color(i, Color(p_color.r * shade, p_color.g * shade, p_color.b * shade))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
