extends SceneTree

# Loads the SoftBody3D marble-run demo and checks the wave flows the whole
# course -- hopper, chutes, stair section -- into the catch basin without any
# blob punching through the track (soft-vs-rigid penetration + friction/flow
# regression).

var _t := 0
var _root: Node

func _initialize() -> void:
	_root = load("res://demo/cpu/physx_soft_body.tscn").instantiate()
	get_root().add_child(_root)
	print("[sbcascade] engine = ", ProjectSettings.get_setting("physics/3d/physics_engine", "?"))

func _physics_process(_d: float) -> bool:
	_t += 1

	# No blob may drop far below the track anywhere on the course (tunnelling).
	var stage := _root.get_node("Stage")
	for sb in stage.get_children():
		var b := PhysicsServer3D.soft_body_get_bounds(sb.get_physics_rid())
		if b.position.y < -10.0:
			print("[sbcascade] FAIL: blob punched through the track (bottom y = %.1f at tick %d)" % [b.position.y, _t])
			quit(1)
			return true

	if _t >= 800:
		var reached := 0
		var n := stage.get_child_count()
		for sb in stage.get_children():
			var c: Vector3 = PhysicsServer3D.soft_body_get_bounds(sb.get_physics_rid()).get_center()
			if c.z < -30.0: # made it down the whole course into the basin
				reached += 1
		if reached < (n * 2) / 3:
			print("[sbcascade] FAIL: only %d/%d blobs flowed down into the basin" % [reached, n])
			quit(1)
		else:
			print("[sbcascade] PASS  (%d/%d blobs completed the run, none through the track)" % [reached, n])
			quit(0)
		return true
	return false
