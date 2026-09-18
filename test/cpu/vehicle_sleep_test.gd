extends SceneTree

# Regression: an idle PhysXVehicle3D sleeps by default, then stays awake when
# can_sleep is disabled.

var _car: PhysXVehicle3D
var _tick := 0
var _sleep_verified := false

func _initialize() -> void:
	print("[vehicle-sleep] engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var root := Node3D.new()

	var floor_body := StaticBody3D.new()
	var floor_cs := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 1, 20)
	floor_cs.shape = floor_shape
	floor_body.add_child(floor_cs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	_car = PhysXVehicle3D.new()
	_car.position = Vector3(0, 0.6, 0)
	root.add_child(_car)

	var chassis_cs := CollisionShape3D.new()
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = Vector3(1.9, 0.8, 3.7)
	chassis_cs.shape = chassis_shape
	chassis_cs.position = Vector3(0, 0.4, 0)
	_car.add_child(chassis_cs)

	var wheel_positions := {
		"FL": Vector3(-0.75, 0.05, 1.35),
		"FR": Vector3(0.75, 0.05, 1.35),
		"RL": Vector3(-0.75, 0.05, -1.35),
		"RR": Vector3(0.75, 0.05, -1.35),
	}
	for key in wheel_positions:
		var wheel := PhysXVehicleWheel3D.new()
		wheel.position = wheel_positions[key]
		wheel.use_as_steering = key.begins_with("F")
		_car.add_child(wheel)

	get_root().add_child(root)
	await process_frame
	print("[vehicle-sleep] can_sleep=%s" % _car.is_able_to_sleep())
	physics_frame.connect(_tick_physics)

func _tick_physics() -> void:
	_tick += 1
	if not _sleep_verified and _tick >= 120:
		if not _car.is_able_to_sleep() or not _car.is_sleeping():
			print("[vehicle-sleep] FAIL -- default can_sleep did not reach sleeping state: can_sleep=%s sleeping=%s" % [
				_car.is_able_to_sleep(), _car.is_sleeping()])
			_car.free()
			quit(1)
			return
		_sleep_verified = true
		print("[vehicle-sleep] PASS -- default can_sleep reached sleeping state")
		_car.can_sleep = false
		print("[vehicle-sleep] disabled can_sleep=%s sleeping=%s" % [
			_car.is_able_to_sleep(), _car.is_sleeping()])

	if _tick % 30 == 0:
		print("[vehicle-sleep] tick=%d sleeping=%s pos=%s" % [
			_tick, _car.is_sleeping(), _car.global_position])
	if _tick >= 240:
		var passed := not _car.is_able_to_sleep() and not _car.is_sleeping()
		if passed:
			print("[vehicle-sleep] PASS -- can_sleep=false kept vehicle awake")
		else:
			print("[vehicle-sleep] FAIL -- can_sleep=%s sleeping=%s" % [
				_car.is_able_to_sleep(), _car.is_sleeping()])
		_car.free()
		quit(0 if passed else 1)
