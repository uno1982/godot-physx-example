extends Node3D
# Root script for engine_drive.tscn: PhysX's engine drive (torque curve, clutch,
# gearbox, autobox) on a muscle car (PhysXVehicle3D, rear-wheel drive) and a
# drag bike (PhysXMotorcycle3D), on a drag strip: a start line, a light tree,
# the eighth and quarter mile marked, a marker every 100 m.
#
#   W/S    throttle / brake, then reverse     A/D  steer     Space  brake
#   E / Q  shift up / down (manual)           Shift  clutch
#   M      manual / manual without clutch assist (hold Shift to change gear)
#          / automatic                        R    back to the start
#   Tab    swap between the car and the bike
#   Enter  line up for a quarter-mile run: the tree counts down three ambers,
#          the clock starts on green, and the run reads out like a timeslip
#          (reaction, 60 ft, eighth mile, quarter mile, trap speeds). Moving
#          before green is a red light.
# Both start in manual, first gear.

@export var vehicle_paths: Array[NodePath] = []
@export var gauge_path: NodePath
@export var hint_path: NodePath
@export var camera_path: NodePath
@export var race_label_path: NodePath
@export var tree_path: NodePath # Amber1..3, Green, Red lamps (MeshInstance3D)
@export var hud_lamps_path: NodePath # the same five, as ColorRects

const HINTS := [
	"PhysXVehicle3D muscle car, drivetrain = Engine",
	"PhysXMotorcycle3D drag bike, drivetrain = Engine",
]
const KEYS := "W/S throttle-brake-reverse, A/D steer, Space brake, E/Q shift up/down, Shift clutch, M manual / manual without clutch assist / automatic, Enter run the quarter mile, R reset, Tab swap vehicle"

# Distances along the strip from the start line, in meters.
const SIXTY_FEET := 18.288
const EIGHTH_MILE := 201.168
const QUARTER_MILE := 402.336
# A sportsman tree: after staging, the three ambers half a second apart, green half a second after the last.
const STAGE_DELAY := 1.0
const AMBER_STEP := 0.5
const LEFT_START := 0.3 # m: moved this far, the vehicle has left the line
const LAMPS := ["Amber1", "Amber2", "Amber3", "Green", "Red"]
const LAMP_COLORS := [Color(1.0, 0.7, 0.05), Color(1.0, 0.7, 0.05), Color(1.0, 0.7, 0.05), Color(0.1, 1.0, 0.2), Color(1.0, 0.08, 0.05)]

enum Race { IDLE, COUNTDOWN, RUNNING, DONE, FOUL }

var _vehicles: Array[Node3D] = []
var _starts: Array[Transform3D] = []
var _active := 0
var _gauge: Label
var _hint: Label
var _camera: Node3D
var _race_label: Label
var _tree: Node3D
var _hud_lamps: Node

var _race := Race.IDLE
var _racer := 0
var _clock := 0.0 # s since staging, then since green
var _last_distance := 0.0
var _last_speed := 0.0
var _reaction := -1.0
var _splits := {} # distance -> [time since green, speed m/s]
var _best := {} # vehicle index -> quarter-mile time


func _ready() -> void:
	for path in vehicle_paths:
		var v: Node3D = get_node(path)
		_vehicles.append(v)
		_starts.append(v.global_transform)
	_gauge = get_node(gauge_path)
	_hint = get_node(hint_path)
	_camera = get_node(camera_path)
	_race_label = get_node(race_label_path)
	_tree = get_node(tree_path)
	_hud_lamps = get_node(hud_lamps_path)
	_set_lamps(0, false, false)
	_apply_active()


func _apply_active() -> void:
	for i in _vehicles.size():
		_vehicles[i].active = i == _active
	_camera.set_target(_vehicles[_active])
	_hint.text = "%s  |  %s" % [HINTS[_active], KEYS]


# ambers: how many are lit (0..3).
func _set_lamps(ambers: int, green: bool, red: bool) -> void:
	var lit := [ambers >= 1, ambers >= 2, ambers >= 3, green, red]
	for i in LAMPS.size():
		var color: Color = LAMP_COLORS[i]
		var lamp: MeshInstance3D = _tree.get_node(LAMPS[i])
		var mat: StandardMaterial3D = lamp.material_override
		mat.albedo_color = color if lit[i] else color.darkened(0.85)
		mat.emission_enabled = lit[i]
		mat.emission = color
		mat.emission_energy_multiplier = 4.0
		var rect: ColorRect = _hud_lamps.get_node(LAMPS[i])
		rect.color = color if lit[i] else color.darkened(0.8)


func _stage() -> void:
	_racer = _active
	var v: Node3D = _vehicles[_racer]
	v.teleport(_starts[_racer])
	if not v.automatic_transmission:
		v.gear = 1
	_race = Race.COUNTDOWN
	_clock = 0.0
	_last_distance = 0.0
	_last_speed = 0.0
	_reaction = -1.0
	_splits.clear()
	_set_lamps(0, false, false)


func _abort() -> void:
	_race = Race.IDLE
	_set_lamps(0, false, false)


func _physics_process(delta: float) -> void:
	if _race != Race.COUNTDOWN and _race != Race.RUNNING:
		return
	var v: Node3D = _vehicles[_racer]
	var start := _starts[_racer]
	var distance := (v.global_position - start.origin).dot(start.basis.z)
	var speed: float = v.get_forward_speed()
	_clock += delta
	if _race == Race.COUNTDOWN:
		if distance > LEFT_START:
			_race = Race.FOUL
			_set_lamps(0, false, true)
		elif _clock >= STAGE_DELAY + 3 * AMBER_STEP:
			_race = Race.RUNNING
			_clock = 0.0
			_set_lamps(0, true, false)
		elif _clock >= STAGE_DELAY:
			_set_lamps(mini(int((_clock - STAGE_DELAY) / AMBER_STEP) + 1, 3), false, false)
	else:
		# Each mark is timed where the vehicle crossed it between two ticks, not at the tick after.
		var previous := _clock - delta
		if _reaction < 0.0 and distance >= LEFT_START:
			_reaction = _cross(previous, LEFT_START, distance)
		for mark: float in [SIXTY_FEET, EIGHTH_MILE, QUARTER_MILE]:
			if not _splits.has(mark) and distance >= mark:
				var f := (mark - _last_distance) / maxf(distance - _last_distance, 0.0001)
				_splits[mark] = [previous + delta * f, lerpf(_last_speed, speed, f)]
		if _splits.has(QUARTER_MILE):
			_race = Race.DONE
			var time: float = _splits[QUARTER_MILE][0]
			if not _best.has(_racer) or time < _best[_racer]:
				_best[_racer] = time
	_last_distance = distance
	_last_speed = speed


func _cross(previous: float, mark: float, distance: float) -> float:
	var f := (mark - _last_distance) / maxf(distance - _last_distance, 0.0001)
	return previous + get_physics_process_delta_time() * f


func _process(_delta: float) -> void:
	var v: Node3D = _vehicles[_active]
	var gear_text := _gear_name(v.get_target_gear())
	if v.get_current_gear() != v.get_target_gear():
		gear_text = "%s > %s" % [_gear_name(v.get_current_gear()), gear_text] # shifting
	_gauge.text = "%s   gear %s   %5.0f RPM   %3.0f km/h%s" % [
		"Automatic" if v.automatic_transmission else ("Manual" if v.clutch_assist else "Manual, no clutch assist"),
		gear_text,
		v.get_engine_rpm(),
		absf(v.get_forward_speed()) * 3.6,
		"   clutch" if v.clutch > 0.0 else ""]
	_race_label.text = _race_text()


func _race_text() -> String:
	match _race:
		Race.COUNTDOWN:
			return "Staged: wait for the green"
		Race.FOUL:
			return "RED LIGHT: left before the green  |  Enter: try again"
		Race.RUNNING:
			return "%6.2f s   %4.0f m%s" % [_clock, _last_distance, _slip()]
		Race.DONE:
			return "%s\nbest %.3f s  |  Enter: run again" % [_slip().strip_edges(), _best[_racer]]
	return "Enter: line up for a quarter-mile run" + ("   (best %.3f s)" % _best[_active] if _best.has(_active) else "")


# The timeslip so far.
func _slip() -> String:
	var parts: PackedStringArray = []
	if _reaction >= 0.0:
		parts.append("R/T %.3f" % _reaction)
	if _splits.has(SIXTY_FEET):
		parts.append("60 ft %.3f" % _splits[SIXTY_FEET][0])
	for mark: float in [EIGHTH_MILE, QUARTER_MILE]:
		if _splits.has(mark):
			var speed: float = _splits[mark][1]
			parts.append("%s %.3f @ %.1f mph (%.0f km/h)" % ["1/8" if mark == EIGHTH_MILE else "1/4", _splits[mark][0], speed * 2.23694, speed * 3.6])
	return ("   " + "   ".join(parts)) if not parts.is_empty() else ""


func _gear_name(g: int) -> String:
	return "R" if g < 0 else ("N" if g == 0 else str(g))


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_stage()
	elif event.keycode == KEY_R:
		_abort()
		_vehicles[_active].teleport(_starts[_active])
	elif event.keycode == KEY_TAB:
		_abort()
		_active = (_active + 1) % _vehicles.size()
		_apply_active()
