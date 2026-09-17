extends PhysXVehicle3D
# Same arcade drive controls as vehicle_rig.gd (W/S throttle, A/D steer,
# Space brake), mapped onto PhysXVehicle3D's own throttle/brake/steer inputs
# (PxVehicleCommandState's [0,1]/[0,1]/[-1,1] convention) instead of
# VehicleBody3D's raw engine_force/steering -- different units, same keys,
# so the two cars feel directly comparable side by side.

# Only the active car reads keyboard input -- see vehicle_rig.gd's own note
# on why the inactive one must relax to neutral instead of coasting.
var active := false

func _physics_process(_delta: float) -> void:
	if not active:
		throttle = 0.0
		brake = 0.0
		steer = 0.0
		return

	var t := 0.0
	if Input.is_key_pressed(KEY_W):
		t += 1.0
	if Input.is_key_pressed(KEY_S):
		t -= 1.0
	# PxVehicleCommandState.throttle has no reverse sense of its own (gear is
	# separate) -- this rig only ever runs in forward gear, so W drives
	# forward and S just brakes/idles rather than reversing. Matches this
	# demo's actual use (drive forward around the same track as the Godot
	# car) without wiring a full gear-shift control just for this comparison.
	throttle = maxf(t, 0.0)
	brake = maxf(-t, 0.0)
	if Input.is_key_pressed(KEY_SPACE):
		brake = 1.0

	var s := 0.0
	if Input.is_key_pressed(KEY_A):
		s += 1.0
	if Input.is_key_pressed(KEY_D):
		s -= 1.0
	steer = s
