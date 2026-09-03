extends SceneTree

# Drives a fast PhysXParticleFluid3D stream into a floor with foam enabled and
# checks that the solver spawns diffuse (foam/spray) particles once the fluid is
# splashing, then that the count falls back down as foam expires.

const CAP := 40000
const FOAM_CAP := 20000

var _fluid: PhysXParticleFluid3D
var _tick := 0
var _peak_foam := 0

func _initialize() -> void:
	print("[foam] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	if not ClassDB.class_exists("PhysXParticleFluid3D"):
		print("[foam] node not registered -> SKIP")
		quit(0)
		return
	var root := Node3D.new()
	get_root().add_child(root)

	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(8, 1, 8)
	fc.shape = fs
	fb.add_child(fc)
	fb.position = Vector3(0, -0.5, 0)
	root.add_child(fb)

	_fluid = PhysXParticleFluid3D.new()
	_fluid.spawn_on_ready = false
	_fluid.particle_count = CAP
	_fluid.particle_size = 0.06
	_fluid.emitting = true
	_fluid.emission_rate = 12000.0
	_fluid.emission_radius = 0.1
	_fluid.emission_velocity = Vector3(0, -7, 0)
	_fluid.position = Vector3(0, 3.5, 0)
	_fluid.foam_enabled = true
	_fluid.foam_particle_count = FOAM_CAP
	_fluid.foam_lifetime = 1.0
	_fluid.foam_threshold = 200.0
	root.add_child(_fluid)

func _physics_process(_d: float) -> bool:
	_tick += 1
	if _fluid == null:
		return true
	var live := _fluid.get_live_particle_count()
	var foam := _fluid.get_live_foam_count()
	_peak_foam = maxi(_peak_foam, foam)
	if _tick == 10 and live == 0:
		print("[foam] 0 particles after emitting (no CUDA / CPU build) -> SKIP")
		quit(0)
		return true
	if _tick % 60 == 0:
		print("[foam] tick %3d  fluid=%d  foam=%d" % [_tick, live, foam])
	if _tick == 240:
		# Stop the faucet; the pool keeps churning but foam output should ebb.
		_fluid.emitting = false
	if _tick == 900:
		var foam_now := _fluid.get_live_foam_count()
		var spawned: bool = _peak_foam > 500
		var bounded: bool = _peak_foam <= FOAM_CAP
		var ebbed: bool = foam_now < _peak_foam * 0.8
		var ok: bool = spawned and bounded and ebbed
		print("[foam] peak=%d  after_settle=%d -> %s" %
				[_peak_foam, foam_now, "PASS" if ok else "FAIL"])
		quit(0 if ok else 1)
	return false
