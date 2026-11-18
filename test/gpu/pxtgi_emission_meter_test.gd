extends SceneTree

# PXTGIEmissionMeter: how brightly a material glows, measured by drawing it (PXTGI can't read a ShaderMaterial's glow;
# the editor's emissive material tool tags them from this). Materials whose glow is known exactly:
#   1. a constant 250, a hidden multiplier (0.01 x 30000 = 300, as converted materials have), a gradient texture
#      averaging 0.5 x 100 = 50, a StandardMaterial3D at energy 3: each measured within 3%;
#   2. far above white (2,000,000): measured within 3% (no half-float overflow);
#   3. no emission: 0;
#   4. a glow animated by TIME is flagged as changing, the constant ones aren't;
#   5. find_untagged lists only the ShaderMaterials with no pxtgi_emission on the material or its mesh;
#   6. emission_tag encodes a glow as PXTGI reads it (srgb_to_linear gives it back);
#   7. albedo (the share of white light a surface bounces: diffuse under an even ambient light, plus what a metal
#      reflects of a white sky): a StandardMaterial3D's sRGB gray, a two-color albedo texture averaged, that texture
#      tinted, a ShaderMaterial's ALBEDO with and without a glow, AO taken in: each within 0.01; a glossy dielectric
#      (its albedo and a little more) and a glossy metal (about its color) within 0.03; rough metals a share of their
#      color (Godot draws a rough metal's reflection dimmer: about half at roughness 1);
#   8. find_untagged_albedo lists ShaderMaterials and textured BaseMaterial3Ds with no pxtgi_albedo, not a plain
#      StandardMaterial3D (PXTGI reads its color); albedo_tag encodes an albedo as PXTGI reads it.
# Needs a window (the measuring draws):
#   godot --path . --script res://test/gpu/pxtgi_emission_meter_test.gd

var _ok := true


func _check(cond: bool, msg: String) -> void:
	print("[emission-meter] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _shader(code: String) -> ShaderMaterial:
	var s := Shader.new()
	s.code = "shader_type spatial;\n" + code
	var m := ShaderMaterial.new()
	m.shader = s
	return m


func _near(measured: float, expected: float, tol: float) -> bool:
	return absf(measured - expected) <= tol * maxf(expected, 1e-3)


func _initialize() -> void:
	if not ClassDB.class_exists("PXTGIEmissionMeter"):
		print("[emission-meter] SKIP: no PXTGIEmissionMeter")
		quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	var gradient := GradientTexture2D.new()
	gradient.width = 64
	gradient.height = 64
	gradient.gradient = Gradient.new() # black to white across: averages 0.5
	var textured := _shader("uniform sampler2D tex;\nvoid fragment() { ALBEDO = vec3(0.5); EMISSION = texture(tex, UV).rgb * 100.0; }")
	textured.set_shader_parameter("tex", gradient)
	var standard := StandardMaterial3D.new()
	standard.emission_enabled = true
	standard.emission = Color(1, 1, 1)
	standard.emission_energy_multiplier = 3.0
	var cases := [
		["constant 250", _shader("void fragment() { ALBEDO = vec3(0.8); EMISSION = vec3(250.0); }"), 250.0],
		["hidden x30000", _shader("void fragment() { EMISSION = vec3(0.01) * 30000.0; }"), 300.0],
		["texture avg 0.5 x 100", textured, 50.0],
		["StandardMaterial3D energy 3", standard, 3.0],
		["2,000,000", _shader("void fragment() { EMISSION = vec3(2000000.0); }"), 2000000.0],
		["no emission", _shader("void fragment() { ALBEDO = vec3(1.0); }"), 0.0],
		["animated", _shader("void fragment() { EMISSION = vec3(100.0 + 90.0 * sin(TIME * 3.0)); }"), -1.0],
	]
	var materials: Array[Material] = []
	for c in cases:
		materials.append(c[1])
	var meter: RefCounted = ClassDB.instantiate("PXTGIEmissionMeter")
	var err: int = meter.measure(materials)
	_check(err == OK, "measure() started")
	var results: Array = await meter.finished
	_check(results.size() == cases.size(), "a result for each material (%d)" % results.size())
	for i in mini(results.size(), cases.size()):
		var r: Dictionary = results[i]
		var name: String = cases[i][0]
		var expected: float = cases[i][2]
		_check(r.material == cases[i][1], "%s: result in order" % name)
		if expected < 0.0:
			_check(r.changes, "%s: flagged as changing (%.1f)" % [name, r.luminance])
		elif expected == 0.0:
			_check(r.luminance < 0.01, "%s: 0 (%.4f)" % [name, r.luminance])
			_check(not r.changes, "%s: not flagged as changing" % name)
		else:
			_check(_near(r.luminance, expected, 0.03), "%s: %.1f, expected %.1f" % [name, r.luminance, expected])
			_check(not r.changes, "%s: not flagged as changing" % name)

	# find_untagged: only ShaderMaterials PXTGI can't read a glow from.
	var root := Node3D.new()
	var untagged := _shader("void fragment() { EMISSION = vec3(5.0); }")
	var tagged := _shader("void fragment() { EMISSION = vec3(5.0); }")
	tagged.set_meta("pxtgi_emission", Color(1, 1, 1))
	for m in [untagged, tagged, standard, untagged]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = m
		root.add_child(mi)
	var mesh_tagged := MeshInstance3D.new()
	mesh_tagged.mesh = BoxMesh.new()
	mesh_tagged.material_override = _shader("void fragment() { EMISSION = vec3(5.0); }")
	mesh_tagged.set_meta("pxtgi_emission", Color(1, 1, 1))
	root.add_child(mesh_tagged)
	var found: Dictionary = ClassDB.class_call_static("PXTGIEmissionMeter", "find_untagged", root)
	_check(found.size() == 1 and found.has(untagged), "find_untagged: only the untagged ShaderMaterial (%d found)" % found.size())
	_check(found.has(untagged) and (found[untagged] as Array).size() == 2, "find_untagged: both meshes using it listed")
	root.free()

	# 7. Albedo.
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color(1, 0, 0) if x < 32 else Color(0, 0, 1))
	var two_color := ImageTexture.create_from_image(img)
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.5, 0.5, 0.5)
	var textured_albedo := StandardMaterial3D.new()
	textured_albedo.albedo_texture = two_color
	var tinted := StandardMaterial3D.new()
	tinted.albedo_texture = two_color
	tinted.albedo_color = Color(0.5, 0.5, 0.5)
	var metal := StandardMaterial3D.new()
	metal.metallic = 1.0
	metal.albedo_color = Color(0.5, 0.5, 0.5)
	var gold := StandardMaterial3D.new()
	gold.metallic = 1.0
	gold.roughness = 0.2
	gold.albedo_color = Color(1.0, 0.75, 0.3)
	var glossy := StandardMaterial3D.new()
	glossy.roughness = 0.1
	glossy.albedo_color = Color(0.5, 0.5, 0.5)
	var half := Color(0.5, 0.5, 0.5).srgb_to_linear().r
	var albedo_cases := [
		["StandardMaterial3D sRGB 0.5 gray", gray, Color(half, half, half)],
		["two-color texture", textured_albedo, Color(0.5, 0.0, 0.5)],
		["two-color texture x sRGB 0.5", tinted, Color(0.5 * half, 0.0, 0.5 * half)],
		["metal sRGB 0.5 gray, roughness 1", metal, Color(half, half, half), 0.0, Vector2(0.35, 0.65)],
		["gold metal, roughness 0.2", gold, Color(1.0, 0.75, 0.3).srgb_to_linear(), 0.03],
		["glossy dielectric sRGB 0.5 gray", glossy, Color(half, half, half), 0.03],
		["ShaderMaterial metal 0.4, roughness 0.6", _shader("void fragment() { ALBEDO = vec3(0.4); METALLIC = 1.0; ROUGHNESS = 0.6; }"), Color(0.4, 0.4, 0.4), 0.0, Vector2(0.65, 0.95)],
		["ShaderMaterial ALBEDO 0.3", _shader("void fragment() { ALBEDO = vec3(0.3, 0.2, 0.1); }"), Color(0.3, 0.2, 0.1)],
		["ShaderMaterial ALBEDO 0.3 glowing 250", _shader("void fragment() { ALBEDO = vec3(0.3); EMISSION = vec3(250.0); }"), Color(0.3, 0.3, 0.3)],
		["ShaderMaterial ALBEDO 0.6 AO 0.5", _shader("void fragment() { ALBEDO = vec3(0.6); AO = 0.5; }"), Color(0.3, 0.3, 0.3)],
	]
	var albedo_materials: Array[Material] = []
	for c in albedo_cases:
		albedo_materials.append(c[1])
	meter.measure(albedo_materials)
	var albedo_results: Array = await meter.finished
	for i in mini(albedo_results.size(), albedo_cases.size()):
		var a: Color = albedo_results[i].albedo
		var e: Color = albedo_cases[i][2]
		var tolerance: float = albedo_cases[i][3] if albedo_cases[i].size() > 3 else 0.01
		var close := absf(a.r - e.r) <= tolerance and absf(a.g - e.g) <= tolerance and absf(a.b - e.b) <= tolerance
		var want := "(%.3f, %.3f, %.3f)" % [e.r, e.g, e.b]
		if albedo_cases[i].size() > 4:
			var r: Vector2 = albedo_cases[i][4]
			close = true
			for c in 3:
				close = close and a[c] >= e[c] * r.x and a[c] <= e[c] * r.y
			want = "%.2f-%.2f of %s" % [r.x, r.y, want]
		_check(close, "albedo %s: (%.3f, %.3f, %.3f), expected %s" % [albedo_cases[i][0], a.r, a.g, a.b, want])

	# 8. find_untagged_albedo and albedo_tag.
	var root2 := Node3D.new()
	var shader_untagged := _shader("void fragment() { ALBEDO = vec3(0.3); }")
	var shader_tagged := _shader("void fragment() { ALBEDO = vec3(0.3); }")
	shader_tagged.set_meta("pxtgi_albedo", Color(0.5, 0.5, 0.5))
	for m in [shader_untagged, shader_tagged, gray, textured_albedo]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = m
		root2.add_child(mi)
	var found_albedo: Dictionary = ClassDB.class_call_static("PXTGIEmissionMeter", "find_untagged_albedo", root2)
	_check(found_albedo.size() == 2 and found_albedo.has(shader_untagged) and found_albedo.has(textured_albedo), "find_untagged_albedo: the untagged ShaderMaterial and the textured StandardMaterial3D only (%d found)" % found_albedo.size())
	root2.free()
	var tag_albedo: Color = ClassDB.class_call_static("PXTGIEmissionMeter", "albedo_tag", Color(0.3, 0.2, 0.1))
	var back := tag_albedo.srgb_to_linear()
	_check(absf(back.r - 0.3) < 0.001 and absf(back.g - 0.2) < 0.001 and absf(back.b - 0.1) < 0.001, "albedo_tag reads back as the albedo (%s)" % back)

	# emission_tag: what PXTGI reads back (srgb_to_linear) is the glow.
	for glow in [0.5, 100.0, 1128.0]:
		var tag: Color = ClassDB.class_call_static("PXTGIEmissionMeter", "emission_tag", Color(glow, glow, glow))
		_check(_near(tag.srgb_to_linear().r, glow, 0.001), "emission_tag(%s) reads back as %s" % [glow, tag.srgb_to_linear().r])

	print("[emission-meter] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
