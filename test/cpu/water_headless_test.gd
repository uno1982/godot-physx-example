extends SceneTree

# U28 regression (godot-physx-example#1): PhysXWaterSurface3D (+ a
# PhysXWaterWake3D) entering the tree without a RenderingDevice -- this runner
# is headless -- crashed the engine. Now: a warning, flat water, no crash,
# including a runtime reconfigure.

func _initialize() -> void:
	var water = ClassDB.instantiate("PhysXWaterSurface3D")
	if water == null:
		print("SKIP: no PhysXWaterSurface3D in this build")
		quit(0)
		return
	get_root().add_child(water)
	water.add_child(ClassDB.instantiate("PhysXWaterWake3D"))
	for i in 10:
		await physics_frame
	water.set("wave_amplitude", 0.7) # reconfigures the solver
	await physics_frame
	var h: float = water.call("sample_height", Vector3(3, 0, -2))
	if not is_equal_approx(h, float(water.get("water_level"))):
		print("[water_headless] FAIL: expected flat water at the rest level, got %f" % h)
		quit(1)
		return
	print("[water_headless] PASS -- no crash headless, flat water (h=%.3f)" % h)
	quit(0)
