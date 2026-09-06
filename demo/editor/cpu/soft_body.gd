extends Node3D

# Node-authored SoftBody3D demo on the PhysX backend. Every blob is a stock
# SoftBody3D node -- select one to paint pinned vertices with its gizmo and
# tune total_mass / pressure_coefficient / linear_stiffness / simulation_precision
# in the inspector, then press Play.
#
#   SPACE  drop a heavy ball onto the blobs
#   R      reload the scene       ESC  quit

@onready var _hud: Label = $HUD/Label
@onready var _blobs: Array[Node] = [$SphereBlob, $BoxBlob, $PinnedBlob]
var _ball: RigidBody3D

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_drop_ball()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()

func _drop_ball() -> void:
	if _ball != null and is_instance_valid(_ball):
		_ball.queue_free()
	_ball = RigidBody3D.new()
	_ball.mass = 25.0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.6
	cs.shape = sph
	_ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	mi.mesh = sm
	_ball.add_child(mi)
	_ball.position = Vector3(0, 6, 0)
	add_child(_ball)

func _process(_dt: float) -> void:
	var b := PhysicsServer3D.soft_body_get_bounds($SphereBlob.get_physics_rid())
	_hud.text = "SoftBody3D showcase (PhysX backend)   SPACE drop ball   R reset   ESC\nsphere blob height: %.2f m     FPS: %d" % [
		b.size.y, Engine.get_frames_per_second()]
