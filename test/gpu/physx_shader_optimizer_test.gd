extends SceneTree

# PhysXShaderOptimizer (Project > Tools > Optimize Shaders): shaders and materials written to user://, then
#   1. code_without_defaults drops "= value" from uniforms (hints kept), keeps instance and global uniforms whole;
#   2. find_groups: same code (A, A2) and code differing only in a default (B) are one group, kept = the most used;
#      a structural difference (C) and a differing instance-uniform default (I1, I2) aren't grouped;
#   3. the materials' values: one relying on B's default gets it set; one setting it itself, and A2's, get nothing;
#   4. default textures (a VisualShader's texture nodes) must match: a material can't be given its own (Godot hides
#      those parameters from it, and doesn't save one set), so only shaders with the same default textures are grouped;
#   5. merge_group moves the materials, and saved and read back they keep the kept shader and their values.
# Needs a rendering device (shaders report no parameters headless):
#   godot --path . --script res://test/gpu/physx_shader_optimizer_test.gd

const DIR := "user://shader_optimizer_test"
var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[shader-opt] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _shader(name: String, code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	ResourceSaver.save(s, DIR.path_join(name + ".tres"))
	return load(DIR.path_join(name + ".tres"))


# Written as text with only the values given: Godot's own saver writes every parameter (defaults too), so a material
# relying on its shader's default is one written by hand or another tool.
func _material(name: String, shader: Shader, params := {}) -> ShaderMaterial:
	var text := "[gd_resource type=\"ShaderMaterial\" format=3]

[ext_resource type=\"Shader\" path=\"%s\" id=\"1\"]

[resource]
shader = ExtResource(\"1\")
" % shader.resource_path
	for k in params:
		text += "shader_parameter/%s = %s
" % [k, var_to_str(params[k])]
	var f := FileAccess.open(DIR.path_join(name + ".tres"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return load(DIR.path_join(name + ".tres"))


func _group_of(groups: Array, shader: Shader) -> Dictionary:
	for g in groups:
		if g.shaders.has(shader):
			return g
	return {}


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXShaderOptimizer"):
		print("[shader-opt] SKIP: no PhysXShaderOptimizer")
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		print("[shader-opt] SKIP: needs a rendering device (run without --headless)")
		quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))

	# 1.
	var stripped: String = PhysXShaderOptimizer.code_without_defaults("uniform float a : hint_range(0.0, 1.0) = 0.5;\nuniform vec4 b = vec4(1.0, 2.0, 3.0, 4.0);\nuniform sampler2D t : source_color;\ninstance uniform float c = 2.0;\nglobal uniform vec4 g;")
	_check(stripped == "uniform float a : hint_range(0.0, 1.0);\nuniform vec4 b;\nuniform sampler2D t : source_color;\ninstance uniform float c = 2.0;\nglobal uniform vec4 g;", "code_without_defaults: values dropped, hints kept, instance uniforms whole (got %s)" % stripped.c_escape())

	const BODY := "\nvoid fragment() { ALBEDO = tint.rgb * k; }\n"
	var a := _shader("sh_a", "shader_type spatial;\nuniform vec4 tint = vec4(1.0, 0.0, 0.0, 1.0);\nuniform float k = 1.0;" + BODY)
	var a2 := _shader("sh_a2", "shader_type spatial;\nuniform vec4 tint = vec4(1.0, 0.0, 0.0, 1.0);\nuniform float k = 1.0;" + BODY)
	var b := _shader("sh_b", "shader_type spatial;\nuniform vec4 tint = vec4(0.0, 1.0, 0.0, 1.0);\nuniform float k = 1.0;" + BODY)
	var c := _shader("sh_c", "shader_type spatial;\nuniform vec4 tint = vec4(1.0, 0.0, 0.0, 1.0);\nuniform float k = 1.0;\nvoid fragment() { ALBEDO = tint.rgb + k; }\n")
	var i1 := _shader("sh_i1", "shader_type spatial;\ninstance uniform float w = 1.0;\nvoid fragment() { ALBEDO = vec3(w); }\n")
	var i2 := _shader("sh_i2", "shader_type spatial;\ninstance uniform float w = 2.0;\nvoid fragment() { ALBEDO = vec3(w); }\n")
	const TEX := "shader_type spatial;\nuniform sampler2D tex;\nvoid fragment() { ALBEDO = texture(tex, UV).rgb; }\n"
	# A default texture (set from code, as the VisualShader editor does): kept in memory under its file's path, as a text
	# shader's file doesn't hold one.
	var t1 := _shader("sh_t1", TEX)
	var gradient := GradientTexture2D.new()
	t1.set_default_texture_parameter("tex", gradient)
	var t2 := _shader("sh_t2", TEX)
	var t3 := _shader("sh_t3", TEX)
	t3.set_default_texture_parameter("tex", gradient)
	var t4 := _shader("sh_t4", TEX)
	t4.set_default_texture_parameter("tex", GradientTexture2D.new())

	var m_a1 := _material("m_a1", a)
	var _m_a1b := _material("m_a1b", a)
	var m_a2 := _material("m_a2", a2)
	var m_b1 := _material("m_b1", b)
	var m_b2 := _material("m_b2", b, {"tint": Vector4(0.2, 0.3, 0.4, 1.0)})
	var _m_c := _material("m_c", c)
	var _m_i1 := _material("m_i1", i1)
	var _m_i2 := _material("m_i2", i2)
	var _m_t1 := _material("m_t1", t1)
	var _m_t1b := _material("m_t1b", t1)
	var _m_t2 := _material("m_t2", t2)
	var _m_t3 := _material("m_t3", t3)
	var _m_t4 := _material("m_t4", t4)

	# 2.
	var materials: Array = PhysXShaderOptimizer.find_materials(DIR)
	_check(materials.size() == 13, "find_materials: the 13 material files, not the shaders (%d)" % materials.size())
	var groups: Array = PhysXShaderOptimizer.find_groups(materials)
	var g: Dictionary = _group_of(groups, a)
	_check(not g.is_empty() and g.shader == a and g.shaders.size() == 3 and g.shaders.has(a2) and g.shaders.has(b), "A, A2 and B (a default differs) are one group, A kept (used most)")
	_check(not g.is_empty() and not g.identical, "that group isn't identical (B's default differs)")
	_check(_group_of(groups, c).is_empty(), "C (different code) isn't grouped")
	_check(_group_of(groups, i1).is_empty() and _group_of(groups, i2).is_empty(), "a differing instance-uniform default isn't merged")

	# 3.
	var set_for := {}
	for i in g.materials.size():
		set_for[g.materials[i]] = g.parameters[i]
	_check(set_for.size() == 3 and not set_for.has(m_a1), "the materials moved: A2's and B's, not A's own")
	_check(set_for.get(m_b1, {}).get("tint") == Vector4(0, 1, 0, 1), "a material relying on B's default gets it set (%s)" % [set_for.get(m_b1)])
	_check(set_for.get(m_b2, {"x": 1}).is_empty(), "a material setting it itself gets nothing")
	_check(set_for.get(m_a2, {"x": 1}).is_empty(), "A2's material (same code, same defaults) gets nothing")

	# 4.
	var gt: Dictionary = _group_of(groups, t1)
	_check(not gt.is_empty() and gt.shader == t1 and gt.shaders.size() == 2 and gt.shaders.has(t3), "the same default texture: grouped (T1, T3)")
	_check(_group_of(groups, t2).is_empty(), "no default texture where the others have one: not grouped (T2)")
	_check(_group_of(groups, t4).is_empty(), "a different default texture: not grouped (T4; a material can't be given it)")

	# 5.
	PhysXShaderOptimizer.merge_group(g)
	for m in g.materials:
		ResourceSaver.save(m)
	var back: ShaderMaterial = ResourceLoader.load(DIR.path_join("m_b1.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(back.shader.resource_path == a.resource_path and back.get_shader_parameter("tint") == Vector4(0, 1, 0, 1), "merged and saved: read back, on A with B's default as its own value")
	var back2: ShaderMaterial = ResourceLoader.load(DIR.path_join("m_b2.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(back2.shader.resource_path == a.resource_path and back2.get_shader_parameter("tint") == Vector4(0.2, 0.3, 0.4, 1.0), "and the one with its own value keeps it")
	var regroup: Array = PhysXShaderOptimizer.find_groups(PhysXShaderOptimizer.find_materials(DIR))
	_check(_group_of(regroup, a).is_empty(), "after merging, A's group is gone (nothing left to merge)")

	print("[shader-opt] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
