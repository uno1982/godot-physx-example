extends SceneTree

# PhysXSkinnedCloth3D.wind (uno1982/godot#24). Strips hang from a pinned top edge in the XY plane, facing +Z.
# - Wind into the face blows them that way; edge-on wind barely moves them. (extra_acceleration can't do that.)
# - Off, or no wind: they hang as without any.
# - A wind_area drives them; turbulence keeps them moving; a gale stays finite; self collision can be on too.
# - Running at a steady speed adds no wind of its own, and the air settles the swing.
# - drag and lift scale the force, and a denser mesh blows the same.
# Needs a window (the cloth solver is a compute shader).

const SETTLE := 240
const SPACING := 5.0

var _rigs := {}
var _t := 0
var _ok := true
var _turb_lo := INF
var _turb_hi := -INF
var _steady_lo := INF
var _steady_hi := -INF
var _run_sum := 0.0
var _stand_sum := 0.0
var _samples := 0


func _check(cond: bool, msg: String) -> void:
	print("[cloth_wind] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _rig(key: String, setup: Callable, rows := 13, cols := 5) -> Node3D:
	var slot := _rigs.size()
	var root := Node3D.new()
	root.position = Vector3(slot * SPACING, 0, 0)
	get_root().add_child(root)
	var sk := Skeleton3D.new()
	sk.add_bone("root")
	root.add_child(sk)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var dist := PackedFloat32Array()
	for r in rows:
		for c in cols:
			verts.append(Vector3(float(c) / (cols - 1), 1.0 + float(r) / (rows - 1), 0))
			normals.append(Vector3(0, 0, 1))
			bones.append_array([0, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
			dist.append(0.0 if r == rows - 1 else 3.0)
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			idx.append_array([a, a + cols, a + 1, a + 1, a + cols, a + cols + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var skin := Skin.new()
	skin.add_bind(0, Transform3D())
	var mi := MeshInstance3D.new()
	mi.name = "Strip"
	mi.mesh = mesh
	mi.skin = skin
	sk.add_child(mi)
	mi.skeleton = mi.get_path_to(sk)

	var cloth: Node3D = ClassDB.instantiate("PhysXSkinnedCloth3D")
	cloth.set("max_distances", dist)
	cloth.set("wind_turbulence", 0.0)
	sk.add_child(cloth)
	cloth.set("mesh_instance_path", cloth.get_path_to(mi))
	setup.call(cloth)
	_rigs[key] = {"cloth": cloth, "root": root, "rows": rows, "cols": cols}
	return cloth


# Particle positions in the strip mesh's local space.
func _positions(cloth: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in cloth.get_parent().get_children(true):
		if n is MeshInstance3D and n.name != "Strip":
			var mat: ShaderMaterial = (n as MeshInstance3D).get_surface_override_material(0)
			var tex: Texture2DRD = mat.get_shader_parameter("cloth_positions") if mat else null
			if tex == null:
				continue
			var f := RenderingServer.get_rendering_device().texture_get_data(tex.texture_rd_rid, 0).to_float32_array()
			for i in int(cloth.call("get_particle_count")):
				out.append(Vector3(f[i * 4], f[i * 4 + 1], f[i * 4 + 2]))
	return out


# The mean offset of the bottom row from where it hangs at rest.
func _tip(key: String) -> Vector3:
	var rig: Dictionary = _rigs[key]
	var p := _positions(rig.cloth)
	if p.is_empty():
		return Vector3(NAN, NAN, NAN)
	# Find the bottom row by height, whichever way the particles were ordered.
	var ys := []
	for q in p:
		ys.append(q.y)
	ys.sort()
	var cutoff: float = ys[int(rig.cols) - 1] + 1e-4
	var sum := Vector3.ZERO
	var n := 0
	for q in p:
		if q.y <= cutoff:
			sum += q
			n += 1
	return sum / n - Vector3(0.5, 1.0, 0)


func _all_finite(key: String) -> bool:
	for q in _positions(_rigs[key].cloth):
		if not q.is_finite():
			return false
	return true


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXSkinnedCloth3D"):
		print("[cloth_wind] SKIP: no PhysXSkinnedCloth3D")
		quit(0)
		return
	# One step per tick: a rig moving in uneven steps sways by itself, with or without wind.
	Engine.max_fps = 60
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(30, 2, 60), Vector3(30, 1.5, 0))

	_rig("calm", func(_c): pass)
	_rig("into", func(c): c.set("wind", Vector3(0, 0, 5)))
	_rig("back", func(c): c.set("wind", Vector3(0, 0, -5)); c.set("backstop", -1.0))
	_rig("backstop", func(c): c.set("wind", Vector3(0, 0, -5)))
	_rig("edge", func(c): c.set("wind", Vector3(5, 0, 0)); c.set("lift", 0.0))
	_rig("off", func(c): c.set("wind", Vector3(0, 0, 5)); c.set("wind_enabled", false))
	_rig("double", func(c): c.set("wind", Vector3(0, 0, 5)); c.set("drag", 2.0))
	_rig("dense", func(c): c.set("wind", Vector3(0, 0, 5)), 25, 9)
	_rig("gusty", func(c): c.set("wind", Vector3(0, 0, 5)); c.set("wind_turbulence", 1.0))
	_rig("gale", func(c): c.set("wind", Vector3(0, 0, 200)); c.set("lift", 2.0); c.set("wind_turbulence", 2.0))
	_rig("selfcol", func(c): c.set("wind", Vector3(0, 0, 5)); c.set("self_collision", true))
	_rig("running", func(c): c.set("wind", Vector3(0, 0, 5)))

	# An Area3D blowing +Z, its wind source behind the strip.
	var area := Area3D.new()
	area.wind_force_magnitude = 5.0
	area.wind_attenuation_factor = 0.0
	var source := Node3D.new()
	source.name = "Source"
	area.add_child(source)
	source.rotation_degrees = Vector3(0, 180, 0) # its -Z points along +Z
	get_root().add_child(area)
	area.position = Vector3(_rigs.size() * SPACING, 1, -3)
	area.wind_source_path = area.get_path_to(source)
	_rig("area", func(c): c.set("wind_area", c.get_path_to(area)))
	physics_frame.connect(_tick)


func _tick() -> void:
	_t += 1
	if _t > 60:
		# At a steady speed along +Z, into the face: its own speed must not count as wind.
		_rigs["running"].root.position.z += 8.0 / Engine.physics_ticks_per_second
	if _t > SETTLE:
		var g: float = _tip("gusty").z
		_turb_lo = minf(_turb_lo, g)
		_turb_hi = maxf(_turb_hi, g)
		var s: float = _tip("into").z
		_steady_lo = minf(_steady_lo, s)
		_steady_hi = maxf(_steady_hi, s)
		_run_sum += _tip("running").z
		_stand_sum += s
		_samples += 1
	if _t == SETTLE + 180:
		_finish()


func _finish() -> void:
	var calm := _tip("calm")
	var into := _tip("into")
	var back := _tip("back")
	var edge := _tip("edge")
	var off := _tip("off")
	_check(_positions(_rigs["calm"].cloth).size() > 0, "strips to read")
	_check(absf(calm.z) < 0.01, "no wind hangs straight: tip z %.3f" % calm.z)
	_check(into.z > 0.2, "wind into the face blows it along: tip z %.3f" % into.z)
	_check(absf(back.z + into.z) < 0.03, "and the other way, backstop off: %.3f against %.3f" % [back.z, into.z])
	var stopped := _tip("backstop")
	_check(stopped.z > -0.03, "the backstop keeps it from blowing inward: %.3f" % stopped.z)
	_check(edge.length() < into.z * 0.25, "edge-on barely moves it: %.3f m against %.3f m" % [edge.length(), into.z])
	_check(off.distance_to(calm) < 0.005, "wind_enabled off: as with no wind, %.4f m apart" % off.distance_to(calm))
	var double := _tip("double")
	_check(double.z > into.z * 1.15, "drag scales it: %.3f at 2, %.3f at 1" % [double.z, into.z])
	var dense := _tip("dense")
	_check(absf(dense.z - into.z) < into.z * 0.25, "a denser mesh blows the same: %.3f at 4x the triangles, %.3f" % [dense.z, into.z])
	var area := _tip("area")
	_check(absf(area.z - into.z) < 0.03, "a wind_area drives it: %.3f against %.3f" % [area.z, into.z])
	_check(_rigs["area"].cloth.call("get_effective_wind").is_equal_approx(Vector3(0, 0, 5)), "get_effective_wind reports it: %s" % _rigs["area"].cloth.call("get_effective_wind"))
	_check(_turb_hi - _turb_lo > (_steady_hi - _steady_lo) + 0.05, "turbulence keeps it moving: %.3f m of swing, %.3f m steady" % [_turb_hi - _turb_lo, _steady_hi - _steady_lo])
	_check(_all_finite("gale"), "a gale stays finite")
	var selfcol := _tip("selfcol")
	_check(selfcol.z > into.z * 0.7, "self collision on too: tip z %.3f" % selfcol.z)
	var run_mean := _run_sum / _samples
	var stand_mean := _stand_sum / _samples
	_check(absf(run_mean - stand_mean) < 0.05, "running at 8 m/s adds no wind of its own: mean tip z %.3f, standing %.3f" % [run_mean, stand_mean])
	_check(_steady_hi - _steady_lo < 0.1, "steady wind settles: %.3f m of swing" % (_steady_hi - _steady_lo))
	print("[cloth_wind] %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
