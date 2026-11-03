extends SceneTree

# uno1982/godot#25: what PhysXSkinnedCloth3D collides with. A strip hangs from its pinned top edge; the skeleton has
# physical bones (a capsule shape on "tip", a box on "root", well away from the strip):
#   1. set_body_capsules(): a script capsule, moved into the strip's plane a little every frame, moves the particles in
#      its path out of its way -- none is left inside it -- even with collide_with_body off (then it's the only
#      collider);
#   2. with collide_with_body on, the physical bones' shapes are used too, and collision_radius_scale reaches them
#      (capsule radius, box size);
#   3. physical_bone_skip leaves a bone's shapes out, and use_physical_bones off uses none of them -- both live, no
#      rebuild.
# Needs a window (the cloth solver is a compute shader):
#   godot --path . --script res://test/gpu/skinned_cloth_colliders_test.gd

const RADIUS := 0.12
const Y := 1.45 # the script capsule's height, across the strip

var _mi: MeshInstance3D
var _cloth: Node3D
var _t := 0
var _ok := true
var _copy: MeshInstance3D
var _hang := PackedVector3Array()


func _check(cond: bool, msg: String) -> void:
	print("[cloth_colliders] %s %s" % ["ok  " if cond else "FAIL", msg])
	_ok = _ok and cond


func _strip(rows: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for r in rows:
		for c in 2:
			verts.append(Vector3(lerpf(-0.15, 0.15, c), 1.0 + float(r) / (rows - 1), 0))
			normals.append(Vector3(0, 0, 1))
			uvs.append(Vector2(c, float(r) / (rows - 1)))
			bones.append_array([0, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
	for r in rows - 1:
		var a := r * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _physical_bone(sim: Node, bone: String, shape: Shape3D, at: Vector3) -> void:
	var pb := PhysicalBone3D.new()
	pb.name = "Physical Bone " + bone
	pb.bone_name = bone
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	pb.add_child(cs)
	sim.add_child(pb)


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXSkinnedCloth3D"):
		print("[cloth_colliders] SKIP: no PhysXSkinnedCloth3D")
		quit(0)
		return
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(1.5, 2.2, 2.0), Vector3(0, 1.5, 0))
	var sk := Skeleton3D.new()
	sk.add_bone("root")
	sk.add_bone("tip")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 1, 0)))
	sk.reset_bone_poses()
	get_root().add_child(sk)
	var sim := PhysicalBoneSimulator3D.new()
	sk.add_child(sim)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.05
	cap.height = 0.3
	_physical_bone(sim, "tip", cap, Vector3(1.5, 0, 0))
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	_physical_bone(sim, "root", box, Vector3(1.5, 0, 0))

	var skin := Skin.new()
	skin.add_bind(1, Transform3D(Basis(), Vector3(0, -1, 0)))
	_mi = MeshInstance3D.new()
	_mi.mesh = _strip(13)
	_mi.skin = skin
	sk.add_child(_mi)
	_mi.skeleton = _mi.get_path_to(sk)
	_cloth = ClassDB.instantiate("PhysXSkinnedCloth3D")
	var dist := PackedFloat32Array()
	for r in 13:
		for c in 2:
			dist.append(0.0 if r == 12 else 2.0)
	_cloth.set("max_distances", dist)
	# The script capsule first, with the body's colliders off: it collides regardless.
	_cloth.set("collide_with_body", false)
	sk.add_child(_cloth)
	_cloth.set("mesh_instance_path", _cloth.get_path_to(_mi))
	physics_frame.connect(_tick)


# The script capsule: across the strip (along X) at height Y, at depth z.
func _script_capsule(z: float) -> void:
	_cloth.call("set_body_capsules", [{"a": Vector3(-0.5, Y, z), "b": Vector3(0.5, Y, z), "radius": RADIUS}])


# The simulated positions, read back from the cloth's position texture.
func _positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	var copy: MeshInstance3D = _cloth.get_render_instance()
	var mat := copy.get_surface_override_material(0) as ShaderMaterial if copy else null
	var tex: Texture2D = mat.get_shader_parameter("cloth_positions") if mat else null
	var img := tex.get_image() if tex else null
	if img == null:
		return out
	var n: int = _cloth.get_particle_count()
	for i in n:
		var c := img.get_pixel(i % img.get_width(), i / img.get_width())
		out.append(Vector3(c.r, c.g, c.b))
	return out


func _colliders(key: String) -> int:
	var n := 0
	for d in _cloth.call("get_body_capsules"):
		n += 1 if d.get(key, false) else 0
	return n


func _find(key: String, value) -> Dictionary:
	for d in _cloth.call("get_body_capsules"):
		if d.get(key) == value:
			return d
	return {}


func _tick() -> void:
	_t += 1
	if _t >= 20 and _t <= 100:
		# Moved in from in front of the strip to its plane, a little every frame (read live).
		_script_capsule(lerpf(0.6, 0.0, (_t - 20) / 80.0))
	if _t == 19:
		var hang := _positions()
		_hang = hang
		var flat := hang.size() > 0
		for p in hang:
			flat = flat and absf(p.z) < 0.05
		_check(flat, "the strip hangs flat in its plane before the capsule arrives")
	if _t == 160:
		var pos := _positions()
		var inside := 0
		var deepest := 0.0
		var moved := 0.0
		for i in pos.size():
			var p := pos[i]
			var d := Vector2(p.y - Y, p.z).length() # distance from the capsule's axis (along X)
			if d < RADIUS * 0.85:
				inside += 1
			deepest = maxf(deepest, RADIUS - d)
			# Where it hung, if that's now inside the capsule: it had to get out of the way.
			if i < _hang.size() and Vector2(_hang[i].y - Y, _hang[i].z).length() < RADIUS:
				moved = maxf(moved, p.distance_to(_hang[i]))
		_check(pos.size() > 0 and inside == 0, "set_body_capsules, with collide_with_body off: no particle inside the script capsule (deepest %.3f m into it)" % deepest)
		# The capsule ends in the strip's plane: the particles where it now is were moved out of its way (the strip parts
		# around it, sliding along its surface).
		_check(moved > 0.08, "the particles in its path were moved out of the way (up to %.2f m)" % moved)
		_check(_colliders("from_script") == 1 and _colliders("from_physical_bone") == 0, "collide_with_body off: only the script capsule is used (%d script, %d physical-bone)" % [_colliders("from_script"), _colliders("from_physical_bone")])
		_copy = _cloth.get_render_instance()
		_cloth.set("collide_with_body", true)
	if _t == 162:
		_check(_colliders("from_script") == 1 and _colliders("from_physical_bone") == 2, "collide_with_body on: the physical bones' shapes too (%d script, %d physical-bone)" % [_colliders("from_script"), _colliders("from_physical_bone")])
		_cloth.set("collision_radius_scale", 2.0)
	if _t == 164:
		var c := _find("bone_a", "tip")
		var b := _find("bone_a", "root")
		_check(not c.is_empty() and is_equal_approx(c.radius_a, 0.1), "collision_radius_scale reaches the physical bone's capsule (radius %s)" % c.get("radius_a"))
		_check(not b.is_empty() and b.get("size", Vector3()).is_equal_approx(Vector3(0.2, 0.2, 0.2)), "...and its box (size %s)" % b.get("size"))
		_cloth.set("collision_radius_scale", 1.0)
		_cloth.set("physical_bone_skip", PackedStringArray(["root"]))
	if _t == 166:
		_check(_colliders("from_physical_bone") == 1 and not _find("bone_a", "tip").is_empty() and _find("bone_a", "root").is_empty(), "physical_bone_skip leaves out the root bone's box")
		_check(_cloth.get_render_instance() == _copy, "...live, without a rebuild")
		_cloth.set("physical_bone_skip", PackedStringArray())
		_cloth.set("use_physical_bones", false)
	if _t == 168:
		_check(_colliders("from_physical_bone") == 0, "use_physical_bones off: none of the physical bones' shapes")
		_cloth.set("use_physical_bones", true)
	if _t == 170:
		_check(_colliders("from_physical_bone") == 2 and _cloth.get_render_instance() == _copy, "use_physical_bones on again: the physical bones' shapes, same render copy")
		print("[cloth_colliders] ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
