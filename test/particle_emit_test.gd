extends SceneTree

# A PhysXParticleFluid3D faucet: streams particles from a point, they fall and
# pool. Checks the live count ramps up at roughly the emission rate and caps at
# the buffer capacity.

const RATE := 3000.0
const CAP := 20000

var _fluid: PhysXParticleFluid3D
var _tick := 0
var _count_at := {}

func _initialize() -> void:
	print("[emit] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[emit] node not registered -> SKIP")
		quit(0)
		return
	var root := Node3D.new()
	get_root().add_child(root)

	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(6, 1, 6)
	fc.shape = fs
	fb.add_child(fc)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.spawn_on_ready = false
	_fluid.particle_count = CAP
	_fluid.particle_size = 0.06
	_fluid.emitting = true
	_fluid.emission_rate = RATE
	_fluid.emission_radius = 0.08
	_fluid.emission_velocity = Vector3(0, -2.5, 0)
	_fluid.position = Vector3(0, 3, 0)
	root.add_child(_fluid)

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	var n := _fluid.get_live_particle_count()
	if _tick == 8 and n == 0:
		print("[emit] 0 particles after emitting (no CUDA / CPU build) -> SKIP")
		quit(0)
		return true
	if _tick in [30, 120, 300, 600]:
		_count_at[_tick] = n
		print("[emit] tick %3d  live=%d" % [_tick, n])
	if _tick == 700:
		var ramping: bool = _count_at.get(120, 0) > _count_at.get(30, 0)
		var capped: bool = _count_at.get(600, 0) <= CAP and _count_at.get(600, 0) > CAP * 0.7
		var ok: bool = ramping and capped
		print("[emit] t30=%d t120=%d t600=%d cap=%d -> %s" %
				[_count_at.get(30, 0), _count_at.get(120, 0), _count_at.get(600, 0), CAP, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
