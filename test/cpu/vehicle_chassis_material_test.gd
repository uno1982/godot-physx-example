extends SceneTree

# PhysXVehicle3D.physics_material_override sets the chassis contact material.
# Three cars upside down on 15 deg slopes (tan 15 deg = 0.27):
#   A: no override (friction 0.5)                   -> holds
#   B: override friction 0.05 from the start         -> slides
#   C: no override, then friction 0.05 after landing -> starts sliding (live edit, no rebuild)

var _cars := {}
var _start := {}
var _t := 0
var _slippery := PhysicsMaterial.new()

func _slope(x: float) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(8, 1, 80)
	cs.shape = s
	b.add_child(cs)
	b.position = Vector3(x, 0, 0)
	b.rotation_degrees = Vector3(15, 0, 0)
	get_root().add_child(b)

func _car(x: float) -> PhysXVehicle3D:
	var car := PhysXVehicle3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 0.8, 3.7)
	cs.shape = sh
	cs.position = Vector3(0, 0.4, 0)
	car.add_child(cs)
	for p in [Vector3(-0.75, 0.05, 1.35), Vector3(0.75, 0.05, 1.35), Vector3(-0.75, 0.05, -1.35), Vector3(0.75, 0.05, -1.35)]:
		var w := PhysXVehicleWheel3D.new()
		w.position = p
		w.use_as_steering = p.z > 0.0
		car.add_child(w)
	car.position = Vector3(x, 3.0, 0)
	car.rotation_degrees = Vector3(15, 0, 180)
	return car

func _initialize() -> void:
	_slippery.friction = 0.05
	for x in [-12.0, 0.0, 12.0]:
		_slope(x)
	_cars = {"A_default": _car(-12), "B_override": _car(0), "C_live": _car(12)}
	_cars.B_override.physics_material_override = _slippery
	for k in _cars:
		get_root().add_child(_cars[k])
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1
	if _t == 90: # all landed on their roofs
		for k in _cars:
			_start[k] = _cars[k].global_position
		_cars.C_live.physics_material_override = _slippery
	if _t < 210:
		return
	var slid := {}
	for k in _cars:
		slid[k] = _cars[k].global_position.distance_to(_start[k])
	print("[chassis_material] slid in 2 s: default=%.2f override=%.2f live=%.2f" % [slid.A_default, slid.B_override, slid.C_live])
	var ok := true
	for k in _cars:
		if _cars[k].global_transform.basis.y.y > -0.5:
			print("[chassis_material] FAIL: %s did not land on its roof (test setup)" % k)
			ok = false
	if slid.A_default > 0.5:
		print("[chassis_material] FAIL: the default chassis slides on its roof")
		ok = false
	if slid.B_override < 2.0:
		print("[chassis_material] FAIL: a low-friction override did not make the roof slide")
		ok = false
	if slid.C_live < 2.0:
		print("[chassis_material] FAIL: an override set on a live vehicle did not take effect")
		ok = false
	if ok:
		print("[chassis_material] PASS -- default holds, override slides, live override applies")
	quit(0 if ok else 1)
