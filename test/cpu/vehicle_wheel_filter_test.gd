extends SceneTree

# U27 regression (godot-physx-example#1): PhysXVehicle3D wheel raycasts were
# unfiltered -- the wheels rode on Area3D triggers and on bodies outside the
# vehicle's collision_mask. Like a Godot raycast, a wheel now hits only
# non-trigger shapes on a layer in the vehicle's mask.
#
# Three cars side by side, each parked over a 1 m high box, floor top at y=0:
#   A: box is an Area3D                      -> must settle on the floor
#   B: box is a StaticBody3D on layer 2       -> must settle on the floor
#      (the car's mask is 1; the box's mask is 0 so the chassis ignores it too)
#   C: box is a StaticBody3D on layer 1       -> must ride on the box (control)

const BOX_H := 1.0
var _cars := {}
var _t := 0

func _box_shape() -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4, BOX_H, 6)
	cs.shape = b
	return cs

func _make_car(x: float) -> PhysXVehicle3D:
	var car := PhysXVehicle3D.new()
	car.position = Vector3(x, BOX_H + 0.6, 0)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 0.8, 3.7)
	cs.shape = shape
	cs.position = Vector3(0, 0.4, 0)
	car.add_child(cs)
	for p in [Vector3(-0.75, 0.05, 1.35), Vector3(0.75, 0.05, 1.35), Vector3(-0.75, 0.05, -1.35), Vector3(0.75, 0.05, -1.35)]:
		var w := PhysXVehicleWheel3D.new()
		w.position = p
		w.use_as_steering = p.z > 0.0
		car.add_child(w)
	return car

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var floor_body := StaticBody3D.new()
	var floor_cs := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(200, 1, 200)
	floor_cs.shape = floor_shape
	floor_body.add_child(floor_cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var area := Area3D.new()
	area.add_child(_box_shape())
	area.position = Vector3(-10, BOX_H * 0.5, 0)
	root.add_child(area)

	var off_mask := StaticBody3D.new()
	off_mask.collision_layer = 2
	off_mask.collision_mask = 0
	off_mask.add_child(_box_shape())
	off_mask.position = Vector3(0, BOX_H * 0.5, 0)
	root.add_child(off_mask)

	var on_mask := StaticBody3D.new()
	on_mask.add_child(_box_shape())
	on_mask.position = Vector3(10, BOX_H * 0.5, 0)
	root.add_child(on_mask)

	_cars = {"A_area": _make_car(-10), "B_off_mask": _make_car(0), "C_on_mask": _make_car(10)}
	for k in _cars:
		root.add_child(_cars[k])
	await process_frame
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1
	if _t < 180:
		return
	var ya: float = _cars.A_area.global_position.y
	var yb: float = _cars.B_off_mask.global_position.y
	var yc: float = _cars.C_on_mask.global_position.y
	print("[wheel_filter] settled y: area=%.3f off_mask=%.3f on_mask=%.3f" % [ya, yb, yc])
	var ok := true
	if ya > 0.6:
		print("[wheel_filter] FAIL: car A rides on an Area3D trigger")
		ok = false
	if yb > 0.6:
		print("[wheel_filter] FAIL: car B rides on a body outside its collision_mask")
		ok = false
	if yc < BOX_H + 0.1:
		print("[wheel_filter] FAIL: car C fell through a box on its own layer (control)")
		ok = false
	if ok:
		print("[wheel_filter] PASS -- wheels skip triggers and off-mask bodies, still ride on-mask ones")
	quit(0 if ok else 1)
