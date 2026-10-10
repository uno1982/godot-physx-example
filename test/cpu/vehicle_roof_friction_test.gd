extends SceneTree

# A flipped PhysXVehicle3D must not slide on its roof. The chassis material
# had friction 0, harmless while PhysX averaged frictions (0 vs a 1.0 ground
# = 0.5) but frictionless once bodies combine by MIN (Godot's rule): a car
# upside down on a 15 deg slope slid 22 m in 3 s. With the chassis at 0.5
# (> tan 15 deg = 0.27) it holds.

var _car: PhysXVehicle3D
var _start: Vector3
var _t := 0

func _initialize() -> void:
	var slope := StaticBody3D.new()
	var scs := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(8, 1, 60)
	scs.shape = sbox
	slope.add_child(scs)
	slope.rotation_degrees = Vector3(15, 0, 0)
	get_root().add_child(slope)

	_car = PhysXVehicle3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 0.8, 3.7)
	cs.shape = shape
	cs.position = Vector3(0, 0.4, 0)
	_car.add_child(cs)
	for p in [Vector3(-0.75, 0.05, 1.35), Vector3(0.75, 0.05, 1.35), Vector3(-0.75, 0.05, -1.35), Vector3(0.75, 0.05, -1.35)]:
		var w := PhysXVehicleWheel3D.new()
		w.position = p
		w.use_as_steering = p.z > 0.0
		_car.add_child(w)
	_car.position = Vector3(0, 3.0, 0)
	_car.rotation_degrees = Vector3(15, 0, 180) # upside down, roof on the slope
	get_root().add_child(_car)
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1
	if _t == 90: # landed
		_start = _car.global_position
	if _t < 270:
		return
	var slid := _car.global_position.distance_to(_start)
	var up_y := _car.global_transform.basis.y.y
	print("[roof_friction] slid %.2f m in 3 s, up.y=%.2f" % [slid, up_y])
	if up_y > -0.5:
		print("[roof_friction] FAIL: the car did not land on its roof (test setup)")
		quit(1)
	elif slid > 0.5:
		print("[roof_friction] FAIL: a flipped car slides on its roof")
		quit(1)
	else:
		print("[roof_friction] PASS -- a flipped car stays put on a 15 deg slope")
		quit(0)
