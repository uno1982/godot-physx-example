extends Node3D

## A flamethrower against a force field: Flow's fire (PhysXFlow3D, PhysXFlowEmitter3D "Nozzle") hits a sphere collider
## (the Shield's SphereShape3D, collide_with_bodies), wraps around it and rolls off as smoke. The shield's shader glows
## where the fire hits (the jet's line through the sphere), and the fire lights the scene from there. Sparks fan out
## from the hit along the shield's surface, curve around it and trail off on the wind (force_field_sparks.gdshader).
##   Space: jet on / off

@export var nozzle: Node3D
@export var shield: Node3D
@export var shield_mesh: MeshInstance3D
@export var fire_light: OmniLight3D
@export var sparks: GPUParticles3D
## How long the fire takes to reach the shield once the jet is on, and how long it burns on it once the jet is off
## (seconds): the sparks and the shield's glow follow it. (Reading the gas back with sample_temperature would know for
## sure, but cpu_readback stutters the frame.)
@export var fire_arrival := 0.75
@export var fire_linger := 0.6
@export var shield_radius := 1.6

var _strength := 0.0
var _time := 0.0
# How long the jet has been on, or off.
var _on_for := 0.0
var _off_for := 99.0

@onready var _help: Label = $HUD/Help


func _ready() -> void:
	_show_help()


func _show_help() -> void:
	_help.text = "Space: jet %s" % ("on" if nozzle.enabled else "off")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		nozzle.enabled = not nozzle.enabled
		_show_help()


# Where the jet's line (the nozzle's velocity, from its position) enters the shield's sphere; null when it misses.
func _impact() -> Variant:
	var from := nozzle.global_position
	var dir: Vector3 = (nozzle.global_basis * nozzle.velocity).normalized()
	var to_center := shield.global_position - from
	var along := to_center.dot(dir)
	var miss2 := to_center.length_squared() - along * along
	var r2 := shield_radius * shield_radius
	if along < 0.0 or miss2 > r2:
		return null
	return from + dir * (along - sqrt(r2 - miss2))


func _process(delta: float) -> void:
	_time += delta
	var hit: Variant = _impact()
	# The fire is at the shield once it's had time to get there, and until it's burned off.
	if nozzle.enabled:
		_on_for += delta
		_off_for = 0.0
	else:
		_off_for += delta
		_on_for = 0.0
	var fire_here: bool = hit != null and ((nozzle.enabled and _on_for > fire_arrival) or (not nozzle.enabled and _off_for < fire_linger))
	# The glow follows the fire: up as it reaches the shield, down slowly as the last of it burns off.
	var target := 1.0 if fire_here else 0.0
	_strength = move_toward(_strength, target, delta * (2.0 if target > _strength else 0.6))
	var mat := shield_mesh.get_surface_override_material(0) as ShaderMaterial
	if hit != null:
		mat.set_shader_parameter("impact_point", hit)
		var back: Vector3 = (nozzle.global_position - hit).normalized()
		fire_light.global_position = hit + back * 0.4
		# The sparks leave the hit point along the shield's surface (force_field_sparks.gdshader): the emitter at the
		# hit, its +Y the shield's normal there.
		var normal: Vector3 = (hit - shield.global_position).normalized()
		var side := normal.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = Vector3.RIGHT
		side = side.normalized()
		sparks.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), hit + normal * 0.03)
	var spark_mat := sparks.process_material as ShaderMaterial
	spark_mat.set_shader_parameter("shield_center", shield.global_position)
	spark_mat.set_shader_parameter("shield_radius", shield_radius)
	sparks.emitting = fire_here
	mat.set_shader_parameter("impact_strength", _strength)
	# A fire's flicker.
	var flicker := 0.8 + 0.12 * sin(_time * 23.0) + 0.08 * sin(_time * 41.0 + 1.3)
	fire_light.light_energy = 6.0 * _strength * flicker
