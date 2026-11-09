extends Node3D

## A dust tornado in Flow: no vortex physics of its own, a choreography of emitters around one axis (this node's).
## - A ring of dust sources at the ground, blowing in toward the axis, around it and up, and a wider skirt of dust
##   spinning in along the ground.
## - Rings of wind up the funnel (narrow at the ground, wide at the top), each emitter pushing around the axis, a little
##   in toward it and up. They don't grow the grid (PhysXFlowEmitter3D.allocate off): they only spin and lift the dust
##   that's already there, and cost nothing in the empty air around the column. Near the top they blow out instead:
##   the cloud flares.
## - An updraft up the axis, for the core the rings' boxes don't reach.
## Flow's pressure turns the inflow into lift and its vorticity confinement twists the dust into ropes and sheets.
## The tornado wanders slowly, leaving dust behind.

## The funnel: its height, and its radius at the ground and at the top (meters).
@export var height := 26.0
@export var radius_bottom := 0.8
@export var radius_top := 9.0
## How sharply the funnel widens with height (1: a straight cone; higher: narrow most of the way, flaring at the top).
@export var flare := 2.2
## The wind around the axis, toward it and up (m/s).
@export var spin := 20.0
@export var inflow := 2.5
## How much harder the wind pulls in near the ground (on top of inflow; gone by half the height).
@export var ground_pull := 3.0
@export var rise := 12.0
## Wind rings up the funnel, and emitters per ring.
@export var rings := 9
@export var per_ring := 8
## How strongly the wind takes hold of the dust (per second).
@export var wind_grip := 1.2
## Dust put in at the base, and in the skirt around it (a wide, low ring spinning in along the ground).
@export var dust := 6.0
@export var skirt_dust := 2.0
@export var skirt_radius := 4.5
## The top part of the funnel (this share of its height) blows out instead of in: the cloud flares there.
@export var outflow_top := 0.25
## How far and how fast the tornado wanders (meters, rad/s).
@export var wander_radius := 6.0
@export var wander_speed := 0.12

var _time := 0.0
var _home := Vector3()


func _ready() -> void:
	_home = position
	# Dust at the base: a ring blowing in, around and up.
	for j in per_ring:
		_ring_emitter(j, per_ring, radius_bottom * 1.5, 0.35, Vector3(1.2, 0.7, 1.2), spin * 0.7, inflow * 2.5, rise * 0.8, true, dust, 0.4, 2.0)
	# The skirt: dust low and wide, spinning in along the ground; cold, so it hugs the ground rather than billowing up.
	for j in per_ring * 2:
		_ring_emitter(j, per_ring * 2, skirt_radius, 0.3, Vector3(2.0, 0.5, 1.5), spin * 0.5, inflow * 2.5, 0.0, true, skirt_dust, 0.0, 2.0)
	# The core's updraft: one tall box up the axis, lifting what the rings around it don't reach.
	var core: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
	core.shape = 1
	core.size = Vector3(radius_bottom * 2.5, height, radius_bottom * 2.5)
	core.velocity = Vector3(0.0, rise, 0.0)
	core.temperature = 0.35
	core.smoke = 0.0
	core.couple_rate = wind_grip
	core.allocate = false
	add_child(core)
	core.position = Vector3(0.0, height * 0.5, 0.0)
	# Wind up the funnel.
	for i in rings:
		var t := (i + 0.5) / rings
		var h := t * height
		var r: float = lerpf(radius_bottom, radius_top, pow(t, flare))
		# Each emitter a box spanning its share of the ring, its ring's height, and the funnel wall's depth.
		var arc := TAU * r / per_ring
		var size := Vector3(arc * 1.1, height / rings * 1.1, maxf(r * 1.6, 1.5))
		# In toward the axis below, hardest at the ground (the base is drawn into the core rather than flung out by its
		# spin), and out from it at the top.
		var pull := inflow * (1.0 + ground_pull * pow(maxf(1.0 - 2.0 * t, 0.0), 2.0)) if t < 1.0 - outflow_top else -inflow * 2.0
		for j in per_ring:
			_ring_emitter(j, per_ring, r, h, size, spin * lerpf(1.0, 0.6, t), pull, rise, false, 0.0, 0.35, wind_grip)


# An emitter at angle j / count around the axis, radius p_radius, height p_height: its local x around the axis, z out
# from it, so its velocity (around, up, in) holds wherever the ring is.
func _ring_emitter(j: int, count: int, p_radius: float, p_height: float, p_size: Vector3, p_around: float, p_in: float, p_up: float, p_dust: bool, p_smoke: float, p_heat: float, p_grip: float) -> void:
	var angle := TAU * j / count
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var around := Vector3.UP.cross(out)
	var e: Node3D = ClassDB.instantiate("PhysXFlowEmitter3D")
	e.shape = 1 # box
	e.size = p_size
	e.velocity = Vector3(p_around, p_up, -p_in)
	e.temperature = p_heat
	e.smoke = p_smoke
	e.couple_rate = p_grip
	e.allocate = p_dust
	add_child(e)
	e.transform = Transform3D(Basis(around, Vector3.UP, out), out * p_radius + Vector3.UP * p_height)


func _process(delta: float) -> void:
	_time += delta
	# A slow, uneven loop.
	var a := _time * wander_speed
	position = _home + Vector3(sin(a) * wander_radius, 0.0, sin(a * 1.7 + 0.6) * wander_radius * 0.6)
