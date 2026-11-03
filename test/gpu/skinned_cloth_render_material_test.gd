extends SceneTree

# uno1982/godot#23: PhysXSkinnedCloth3D drawn with your own material (render_material) and the source's other vertex
# attributes. One skinned mesh: surface 0 a red "body" panel, surfaces 1 and 2 two strips made cloth, swinging toward
# the camera under sideways gravity (seen from above). Both cloths share one ShaderMaterial whose shader positions the
# vertices from the documented inputs and draws COLOR * CUSTOM1, unshaded: the strips' vertex colour is green and
# their CUSTOM1 white, so they draw green only if the shader runs AND both attributes reach the render copy.
#   1. the strips draw green, from the simulated positions (which have swung toward the camera);
#   2. each cloth draws with its own copy of the material (same shader, its own cloth inputs); the user's material is
#      never written to;
#   3. the render copy has the source's COLOR, UV2, CUSTOM1 and TANGENT;
#   4. render_material = null switches the drawn cloth to the default look and back, without a rebuild (the same
#      render copy).
# Needs a window (the cloth solver is a compute shader):
#   godot --path . --script res://test/gpu/skinned_cloth_render_material_test.gd

const USER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D cloth_positions : filter_nearest, repeat_disable;
uniform sampler2D cloth_normals : filter_nearest, repeat_disable;
uniform int texture_width = 1;
uniform float normal_sign = 1.0;
varying vec4 custom1;
// vertex() as the class reference gives it (render_material), plus CUSTOM1 passed on.
void vertex() {
	int i = int(CUSTOM0.x + 0.5);
	ivec2 px = ivec2(i % texture_width, i / texture_width);
	float handedness = dot(cross(NORMAL, TANGENT), BINORMAL) < 0.0 ? -1.0 : 1.0;
	VERTEX = texelFetch(cloth_positions, px, 0).xyz;
	NORMAL = normalize(texelFetch(cloth_normals, px, 0).xyz * normal_sign);
	// Keep the tangent frame with the new normal, for a normal map.
	vec3 tangent = TANGENT - NORMAL * dot(NORMAL, TANGENT);
	if (dot(tangent, tangent) > 1e-8) {
		TANGENT = normalize(tangent);
		BINORMAL = cross(NORMAL, TANGENT) * handedness;
	}
	custom1 = CUSTOM1;
}
void fragment() {
	ALBEDO = COLOR.rgb * custom1.rgb;
}
"""

var _mi: MeshInstance3D
var _cloths: Array[Node3D] = []
var _cam: Camera3D
var _user_mat: ShaderMaterial
var _copy_before: MeshInstance3D
var _t := 0
var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[cloth_material] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _surface(mesh: ArrayMesh, x0: float, x1: float, rows: int, col: Color, cloth: bool) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var custom1 := PackedFloat32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for r in rows:
		for c in 2:
			verts.append(Vector3(lerpf(x0, x1, c), 1.0 + float(r) / (rows - 1), 0))
			normals.append(Vector3(0, 0, 1))
			tangents.append_array([1.0, 0.0, 0.0, 1.0])
			colors.append(Color(0.1, 0.9, 0.1) if cloth else col)
			uvs.append(Vector2(c, float(r) / (rows - 1)))
			uv2s.append(Vector2(0.25 + 0.5 * c, 0.75))
			custom1.append_array([1.0, 1.0, 1.0, 1.0])
			bones.append_array([0, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
	for r in rows - 1:
		var a := r * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(mesh.get_surface_count() - 1, m)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXSkinnedCloth3D"):
		print("[cloth_material] SKIP: no PhysXSkinnedCloth3D")
		quit(0)
		return
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	we.environment = env
	get_root().add_child(we)
	_cam = Camera3D.new()
	get_root().add_child(_cam)
	_cam.look_at_from_position(Vector3(1.5, 2.8, 2.5), Vector3(0.3, 1.6, 0.3))

	var sk := Skeleton3D.new()
	sk.add_bone("root")
	sk.add_bone("tip")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 1, 0)))
	sk.reset_bone_poses()
	get_root().add_child(sk)

	var mesh := ArrayMesh.new()
	_surface(mesh, 0.6, 1.0, 2, Color(0.9, 0.1, 0.1), false) # surface 0: the body
	_surface(mesh, -0.2, 0.0, 9, Color(1, 1, 1), true) # surface 1: a cloth strip (white material, green vertices)
	_surface(mesh, 0.25, 0.45, 9, Color(1, 1, 1), true) # surface 2: another
	var skin := Skin.new()
	skin.add_bind(1, Transform3D(Basis(), Vector3(0, -1, 0)))
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	_mi.skin = skin
	sk.add_child(_mi)
	_mi.skeleton = _mi.get_path_to(sk)

	_user_mat = ShaderMaterial.new()
	_user_mat.shader = Shader.new()
	_user_mat.shader.code = USER_SHADER
	for s in [1, 2]:
		var cloth: Node3D = ClassDB.instantiate("PhysXSkinnedCloth3D")
		cloth.set("surface", s)
		var dist := PackedFloat32Array()
		for r in 9:
			for c in 2:
				dist.append(0.0 if r == 8 else 2.0)
		cloth.set("max_distances", dist)
		cloth.set("render_material", _user_mat)
		sk.add_child(cloth)
		cloth.set("mesh_instance_path", cloth.get_path_to(_mi))
		_cloths.append(cloth)
	physics_frame.connect(_tick)


# How many sampled pixels are green-ish and white-ish.
func _count() -> Vector2i:
	var img := get_root().get_texture().get_image()
	var green := 0
	var white := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.g > 0.6 and c.r < 0.35 and c.b < 0.35:
				green += 1
			elif c.v > 0.8 and c.s < 0.2:
				white += 1
	return Vector2i(green, white)


func _copy_material(cloth: Node) -> ShaderMaterial:
	var copy: MeshInstance3D = cloth.get_render_instance()
	return copy.get_surface_override_material(0) as ShaderMaterial if copy else null


func _tick() -> void:
	_t += 1
	if _t == 10:
		PhysicsServer3D.area_set_param(get_root().get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(0, 0, 1))
	if _t == 150:
		var n := _count()
		_check(n.x > 200 and n.y < 50, "the strips draw with the user's shader, COLOR * CUSTOM1 (%d green, %d white samples)" % [n.x, n.y])
		# The positions the shader draws from have swung toward the camera (+Z): the free end left the rest plane.
		var tex: Texture2D = _copy_material(_cloths[0]).get_shader_parameter("cloth_positions") if _copy_material(_cloths[0]) else null
		var img: Image = tex.get_image() if tex else null
		var swing := 0.0
		if img:
			for x in img.get_width():
				swing = maxf(swing, img.get_pixel(x, 0).b)
		_check(swing > 0.2, "the cloth inputs carry the simulated positions (free end %.2f m toward the camera)" % swing)
		var a := _copy_material(_cloths[0])
		var b := _copy_material(_cloths[1])
		_check(a != null and b != null and a != _user_mat and b != _user_mat and a != b, "each cloth draws with its own copy of render_material")
		_check(a != null and b != null and a.shader == _user_mat.shader and b.shader == _user_mat.shader, "the copies use the user's shader")
		_check(a != null and b != null and a.get_shader_parameter("cloth_positions") != null and a.get_shader_parameter("cloth_positions") != b.get_shader_parameter("cloth_positions"), "each copy has its own cloth inputs")
		_check(_user_mat.get_shader_parameter("cloth_positions") == null, "the user's material isn't written to")
		var copy: MeshInstance3D = _cloths[0].get_render_instance()
		var got := copy.mesh.surface_get_arrays(0)
		var src := _mi.mesh.surface_get_arrays(1)
		for k in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_TANGENT]:
			_check(got[k] != null and got[k] == src[k], "the render copy carries the source's %s" % ["", "", "TANGENT", "COLOR", "", "UV2", "", "CUSTOM1"][k] if k <= 7 else str(k))
		get_root().get_texture().get_image().save_png("user://skinned_cloth_render_material_test.png")
		_copy_before = copy
		for c in _cloths:
			c.set("render_material", null)
	if _t == 160:
		var n := _count()
		_check(n.y > 200 and n.x < 50, "render_material = null: the default look (the source's white material) (%d green, %d white samples)" % [n.x, n.y])
		_check(_cloths[0].get_render_instance() == _copy_before and _copy_material(_cloths[0]).shader != _user_mat.shader, "...without a rebuild (same render copy, default shader)")
		for c in _cloths:
			c.set("render_material", _user_mat)
	if _t == 170:
		var n := _count()
		_check(n.x > 200 and n.y < 50 and _cloths[0].get_render_instance() == _copy_before, "render_material set again: green again, same render copy (%d green, %d white samples)" % [n.x, n.y])
		print("[cloth_material] ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
