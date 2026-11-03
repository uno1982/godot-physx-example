extends SceneTree

# uno1982/godot#19: PhysXSkinnedCloth3D builds share their shaders instead of compiling them again, and hand their
# render copy to scripts. character_cloth.tscn (a skirt and a cape on the mannequin):
#   1. get_render_instance() is the cloth's render copy, and get_vertex_particles() has one particle per vertex of it,
#      each a valid particle index;
#   2. both garments draw with the same render shader (one Shader, a material each);
#   3. the skirt rebuilt three times gets a new render copy each time, the getters follow, and both garments still
#      simulate afterwards (their position textures change from frame to frame), sharing one compute pipeline.
# Needs a window (the cloth solver is a compute shader):
#   godot --path . --script res://test/gpu/skinned_cloth_rebuild_test.gd

var _scene: Node
var _skirt: Node
var _cape: Node
var _t := 0
var _ok := true
var _first_copy: MeshInstance3D
var _copies := {}
var _snap := {}


func _check(cond: bool, msg: String) -> void:
	print("[cloth_rebuild] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXSkinnedCloth3D"):
		print("[cloth_rebuild] SKIP: no PhysXSkinnedCloth3D")
		quit(0)
		return
	change_scene_to_file("res://demo/editor/cloth/character_cloth.tscn")
	process_frame.connect(_frame)


func _material(cloth: Node) -> ShaderMaterial:
	var copy: MeshInstance3D = cloth.get_render_instance()
	return copy.get_surface_override_material(0) as ShaderMaterial if copy else null


# The cloth's simulated positions, read back from its position texture.
func _positions(cloth: Node) -> PackedByteArray:
	var mat := _material(cloth)
	var tex: Texture2D = mat.get_shader_parameter("cloth_positions") if mat else null
	if tex == null:
		return PackedByteArray()
	var img := tex.get_image()
	return img.get_data() if img else PackedByteArray()


func _check_copy(cloth: Node, label: String) -> void:
	var copy: MeshInstance3D = cloth.get_render_instance()
	_check(copy != null and copy.mesh != null, "%s: get_render_instance() is the render copy" % label)
	if copy == null or copy.mesh == null:
		return
	var vp: PackedInt32Array = cloth.get_vertex_particles()
	var verts := (copy.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var n: int = cloth.get_particle_count()
	var in_range := true
	for p in vp:
		in_range = in_range and p >= 0 and p < n
	_check(vp.size() == verts and in_range and n > 0, "%s: get_vertex_particles() maps its %d vertices to %d particles" % [label, verts, n])


func _frame() -> void:
	_t += 1
	if _scene == null:
		_scene = current_scene
		if _scene == null:
			return
		_skirt = _scene.find_child("SkirtCloth", true, false)
		_cape = _scene.find_child("CapeCloth", true, false)
	if _t == 60:
		_check_copy(_skirt, "skirt")
		_check_copy(_cape, "cape")
		var a := _material(_skirt)
		var b := _material(_cape)
		_check(a != null and b != null and a != b and a.shader == b.shader, "the garments share one render shader, a material each")
		_first_copy = _skirt.get_render_instance()
	for t in [70, 90, 110]:
		if _t == t:
			_skirt.call("rebuild")
		if _t == t + 5:
			var copy: MeshInstance3D = _skirt.get_render_instance()
			_check(copy != null and copy != _first_copy and not _copies.has(copy), "rebuild at frame %d: a new render copy" % t)
			_copies[copy] = true
			_check_copy(_skirt, "skirt rebuilt")
	if _t == 200:
		_snap["skirt"] = _positions(_skirt)
		_snap["cape"] = _positions(_cape)
	if _t == 230:
		for label in ["skirt", "cape"]:
			var cloth := _skirt if label == "skirt" else _cape
			var now := _positions(cloth)
			_check(not now.is_empty() and now != _snap[label], "%s still simulates after the rebuilds (positions change)" % label)
		print("[cloth_rebuild] ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
