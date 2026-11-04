extends SceneTree

# MPM fluid vs a baked distance field (GPUParticlesCollisionSDF3D). The field holds a
# box off the node's center, and the node is moved, turned and scaled, so all of that
# has to be right for the fluid to pool on the box. Windowed: MPM needs the main device.
#
# After "--":
#   shell    the field is only negative just behind the surface, as a real bake is
#   thin     a finer field, so that skin is much thinner than a grid cell
#   gaps     holes in that skin, as a real bake has on curved surfaces: still solid
#   fast     a fast stream instead of a pour
#   control  the node isn't listed: the fluid must pour through (the test can fail)

const NODE_SIZE := Vector3(2.0, 1.6, 2.0)
const BOX_CENTER := Vector3(0.2, 0.0, 0.0)
const BOX_HALF := Vector3(0.5, 0.3, 0.5)

var _fluid: PhysXParticleFluid3D
var _baked: GPUParticlesCollisionSDF3D
var _tick := 0
var _control := false
var _exit_code := 1
var _res := 40


func _box_distance(p: Vector3) -> float:
	var d := (p - BOX_CENTER).abs() - BOX_HALF
	return d.max(Vector3.ZERO).length() + minf(maxf(d.x, maxf(d.y, d.z)), 0.0)


func _make_field(shell: bool, gaps: bool) -> ImageTexture3D:
	var voxel := NODE_SIZE.x / _res
	var size := Vector3i(_res, int(NODE_SIZE.y / voxel), _res)
	var images: Array[Image] = []
	for z in size.z:
		var bytes := PackedFloat32Array()
		bytes.resize(size.x * size.y)
		for y in size.y:
			for x in size.x:
				var p := -NODE_SIZE * 0.5 + (Vector3(x, y, z) + Vector3.ONE * 0.5) * voxel
				var d := _box_distance(p)
				if shell and d < -voxel:
					d = -(d + voxel) # past the skin: positive again
				elif gaps and d < 0.0 and (x * 7 + y * 13 + z * 17) % 11 == 0:
					d = voxel * 0.2 # just outside the nearest triangle
				bytes[x + y * size.x] = d
		images.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, bytes.to_byte_array()))
	var texture := ImageTexture3D.new()
	texture.create(Image.FORMAT_RF, size.x, size.y, size.z, false, images)
	return texture


func _initialize() -> void:
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[mpm-baked] not registered -> SKIP")
		quit(0)
		return
	var args := OS.get_cmdline_user_args()
	_control = args.has("control")
	if args.has("thin"):
		_res = 128

	var root := Node3D.new()
	get_root().add_child(root)

	_baked = GPUParticlesCollisionSDF3D.new()
	_baked.size = NODE_SIZE
	_baked.texture = _make_field(args.has("shell"), args.has("gaps"))
	_baked.position = Vector3(0.4, 1.5, -0.3)
	_baked.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
	_baked.scale = Vector3.ONE * 1.25
	root.add_child(_baked)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.solver = PhysXParticleFluid3D.SOLVER_MPM
	_fluid.particle_count = 14000
	_fluid.particle_size = 0.05
	_fluid.mpm_domain_size = Vector3(4.0, 6.0, 4.0)
	_fluid.mpm_substeps = 5
	_fluid.spawn_on_ready = false
	_fluid.emitting = true
	_fluid.emission_rate = 5000.0
	_fluid.emission_radius = 0.1
	_fluid.emission_velocity = Vector3(0, -10.0 if args.has("fast") else -2.2, 0)
	_fluid.position = _baked.transform * BOX_CENTER + Vector3(0, 1.5, 0)
	root.add_child(_fluid)
	if not _control:
		_fluid.mpm_colliders = [_fluid.get_path_to(_baked)]


func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		if _tick >= 364:
			quit(_exit_code)
			return true
		return false
	if _tick == 90 and _fluid.get_live_particle_count() == 0:
		print("[mpm-baked] no particles -> SKIP (needs a window)")
		quit(0)
		return true

	var pts := _fluid.get_particle_positions()
	var to_local := _baked.global_transform.affine_inverse()
	var inside := 0
	var on_top := 0
	var below := 0
	for world in pts:
		var p: Vector3 = (to_local * world) - BOX_CENTER
		var over := absf(p.x) < BOX_HALF.x and absf(p.z) < BOX_HALF.z
		if p.abs().x < BOX_HALF.x - 0.06 and p.abs().y < BOX_HALF.y - 0.06 and p.abs().z < BOX_HALF.z - 0.06:
			inside += 1
		elif over and p.y >= BOX_HALF.y - 0.06 and p.y < BOX_HALF.y + 0.5:
			on_top += 1
		elif over and p.y < -BOX_HALF.y:
			below += 1

	if _tick % 60 == 0:
		print("[mpm-baked] tick %3d  live=%d  inside=%d  on_top=%d  below=%d" % [_tick, pts.size(), inside, on_top, below])

	if _tick == 300:
		var ok := pts.size() > 1000 and inside < pts.size() * 0.005 and on_top > 200 and below < pts.size() * 0.1
		if _control:
			ok = inside > pts.size() * 0.01 # nothing to stop it: the check above has to fail
		print("[mpm-baked] inside=%d on_top=%d below=%d of %d -> %s" % [inside, on_top, below, pts.size(), "PASS" if ok else "FAIL"])
		_exit_code = 0 if ok else 1
		_baked.get_parent().free()
		_fluid = null
	return false
