extends Node3D

# GPU cloth showcase for PhysXCloth3D. Every cloth is a real scene node -- select
# one to drag its grid handles, move its pins and tune the inspector. On an
# NVIDIA machine these run on a PhysX deformable surface (high resolution,
# proper draping and self-collision); elsewhere they fall back to the CPU
# solver, same scene.
#
#   SPACE  drop a ball onto the sheet     R  reset     ESC  quit

@onready var _sheet: PhysXCloth3D = $Sheet
@onready var _flag: PhysXCloth3D = $Flag
@onready var _wind: Area3D = $Wind
@onready var _hud: Label = $HUD/Label
var _balls: Array[RigidBody3D] = []
var _t := 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				var rb := RigidBody3D.new()
				rb.mass = 2.0
				var cs := CollisionShape3D.new()
				var sh := SphereShape3D.new()
				sh.radius = 0.25
				cs.shape = sh
				rb.add_child(cs)
				var mi := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.25
				sm.height = 0.5
				mi.mesh = sm
				rb.add_child(mi)
				rb.position = Vector3(randf_range(-0.5, 0.5), 4.5, randf_range(-0.5, 0.5))
				add_child(rb)
				_balls.append(rb)
			KEY_R:
				for b in _balls:
					if is_instance_valid(b):
						b.queue_free()
				_balls.clear()
				_sheet.reset()
				_flag.reset()
			KEY_ESCAPE:
				get_tree().quit()

func _physics_process(delta: float) -> void:
	_t += delta
	_wind.wind_force_magnitude = 9.0 * (0.6 + 0.4 * sin(_t * 0.8))

func _process(_dt: float) -> void:
	_hud.text = "PhysXCloth3D GPU showcase   SPACE drop ball   R reset   ESC\nsheet verts: %d   gpu: %s   FPS: %d" % [
		_sheet.get_vertex_count(), str(_sheet.is_gpu_accelerated()), Engine.get_frames_per_second()]
