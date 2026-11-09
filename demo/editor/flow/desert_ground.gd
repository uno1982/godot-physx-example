extends MeshInstance3D

## The desert floor, generated: a grid size meters across, rolling into low dunes (dune_height, dune_scale) except
## around the middle, where the tornado wanders (flat out to flat_radius, the dunes rising over flat_fade beyond).
## UV spans the whole floor once (the material's large light and dark patches); UV2 the same (its detail layer tiles
## the fine ripples). height_at() gives the floor's height anywhere, for what's scattered on it (desert_scrub.gd).

@export var size := 400.0
@export var resolution := 200
@export var dune_height := 6.0
@export var dune_scale := 70.0
@export var flat_radius := 20.0
@export var flat_fade := 40.0
## More flat places, each (x, z, radius): where the camera starts, say, so it isn't inside a dune.
@export var flat_spots: Array[Vector3] = []

var _noise: FastNoiseLite


func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / resolution
	for j in resolution + 1:
		for i in resolution + 1:
			var x := -size * 0.5 + i * step
			var z := -size * 0.5 + j * step
			var uv := Vector2(float(i) / resolution, float(j) / resolution)
			st.set_uv(uv)
			st.set_uv2(uv)
			st.add_vertex(Vector3(x, height_at(x, z), z))
	var row := resolution + 1
	for j in resolution:
		for i in resolution:
			var a := j * row + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + row)
			st.add_index(a + 1)
			st.add_index(a + row + 1)
			st.add_index(a + row)
	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()


## The floor's height at a point (world x, z; this node at the origin).
func height_at(x: float, z: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 11
		_noise.frequency = 1.0 / dune_scale
		_noise.fractal_octaves = 3
	var rise := smoothstep(flat_radius, flat_radius + flat_fade, Vector2(x, z).length())
	for spot in flat_spots:
		rise *= smoothstep(spot.z, spot.z + flat_fade, Vector2(x - spot.x, z - spot.y).length())
	return (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * dune_height * rise
