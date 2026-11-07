extends Node3D

# Cloth in wind, all from one gusting Area3D: PhysXCloth3D flags and hanging banners (CPU solver) and the mannequin's
# skirt and cape, each a PhysXSkinnedCloth3D (compute shaders). Every cloth, the wind volume and the character are scene
# nodes, so they can be selected and tweaked; each cloth names the area in its wind_area. A bob on a string reads the
# force, light crates tumble downwind and leaves drift through. Walk into the volume and the gust shoves you too.
#
#   W A S D / arrows  move        SPACE  jump        mouse  look
#   F                 toggle wind        [ / ]  weaker / stronger gusts
#   1-4               the character: idle / walk / jog / dance (in place)
#   G                 dump more leaves
#   R                 reset               ESC   release mouse / quit

const SPEED := 5.0
const JUMP := 6.0
const MOUSE_SENS := 0.0025
const ANIMS := ["Idle", "Walk", "Jog_Fwd", "Dance"]

@onready var _wind: Area3D = $Wind
@onready var _char: CharacterBody3D = $Player
@onready var _cam: Camera3D = $Player/Camera3D
@onready var _hud: Label = $HUD/Label
@onready var _mannequin: Node3D = $Mannequin

var _yaw := -0.9
var _pitch := 0.0
var _gravity := 18.0
var _wind_on := true
var _base_gust := 11.0
var _gust := 0.0
var _t := 0.0
var _anim := 0
var _ap: AnimationPlayer
var _cloths: Array[Node] = []
var _dynamic: Node3D
var _gauge: RigidBody3D
var _gauge_anchor := Vector3(-7, 5.5, -2)
var _leaves: Array[RigidBody3D] = []

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ap = _mannequin.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.play(ANIMS[_anim])
	_cloths = find_children("*", "PhysXCloth3D", true, false) + find_children("*", "PhysXSkinnedCloth3D", true, false)
	_dynamic = Node3D.new()
	add_child(_dynamic)
	_spawn_dynamic()

func _spawn_dynamic() -> void:
	for c in _dynamic.get_children():
		c.queue_free()

	# Wind gauge: a heavy bob on a short string; its lean reads out force.
	var anchor := StaticBody3D.new()
	anchor.position = _gauge_anchor
	_col_box(anchor, Vector3(0.12, 0.12, 0.12))
	_visual_box(anchor, Vector3(0.12, 0.12, 0.12), Color(0.4, 0.4, 0.42))
	_dynamic.add_child(anchor)
	_gauge = _bob(_gauge_anchor - Vector3(0, 2.0, 0), 0.25, 8.0)
	_gauge.linear_damp = 1.0
	var pin := PinJoint3D.new()
	pin.position = _gauge_anchor
	_dynamic.add_child(pin)
	pin.node_a = pin.get_path_to(anchor)
	pin.node_b = pin.get_path_to(_gauge)

	# Light crates that just tumble downwind.
	for i in 10:
		var crate := RigidBody3D.new()
		var s := randf_range(0.4, 0.8)
		_visual_box(crate, Vector3(s, s, s), Color.from_hsv(randf(), 0.3, 0.9))
		_col_box(crate, Vector3(s, s, s))
		crate.mass = s * s * s * 8.0
		crate.position = Vector3(randf_range(12, 22), s * 0.5 + 0.1, randf_range(-10, 10))
		_dynamic.add_child(crate)

	_leaves.clear()
	_spawn_leaves(35)

# Thin leaves that drift downwind and get recycled to the upwind edge once they
# blow out of the play area, so there's always something in the air.
func _spawn_leaves(n: int) -> void:
	for i in n:
		var leaf := RigidBody3D.new()
		var sz := Vector3(randf_range(0.15, 0.35), 0.03, randf_range(0.15, 0.35))
		_visual_box(leaf, sz, Color.from_hsv(randf_range(0.06, 0.13), 0.75, 0.55))
		_col_box(leaf, sz)
		leaf.collision_layer = 2
		leaf.collision_mask = 3 # ground + other leaves only
		leaf.mass = 0.12
		leaf.position = Vector3(randf_range(16, 24), randf_range(1.5, 7), randf_range(-9, 9))
		leaf.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		_dynamic.add_child(leaf)
		_leaves.append(leaf)

func _recycle_leaves() -> void:
	for leaf in _leaves:
		if not is_instance_valid(leaf):
			continue
		var p := leaf.global_position
		if p.x < -40.0 or p.y < -3.0 or absf(p.z) > 24.0:
			leaf.global_position = Vector3(randf_range(20, 26), randf_range(2, 8), randf_range(-9, 9))
			leaf.linear_velocity = Vector3.ZERO
			leaf.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))

func _bob(pos: Vector3, r: float, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	mi.mesh = sm
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	cs.shape = s
	rb.add_child(cs)
	rb.position = pos
	rb.mass = mass
	_dynamic.add_child(rb)
	return rb

func _visual_box(n: Node, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	bm.material = m
	mi.mesh = bm
	n.add_child(mi)

func _col_box(n: Node, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	n.add_child(cs)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.57, 1.57)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k < KEY_1 + ANIMS.size():
			_anim = k - KEY_1
			_ap.play(ANIMS[_anim], 0.25)
		match k:
			KEY_F:
				_wind_on = not _wind_on
			KEY_BRACKETLEFT:
				_base_gust = maxf(0.0, _base_gust - 3.0)
			KEY_BRACKETRIGHT:
				_base_gust = minf(28.0, _base_gust + 3.0)
			KEY_G:
				_spawn_leaves(40)
			KEY_R:
				for c in _cloths:
					c.call("reset")
				_spawn_dynamic()
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()

func _physics_process(delta: float) -> void:
	_char.rotation.y = _yaw
	_cam.rotation.x = _pitch

	_t += delta
	if _wind_on:
		var swell := 0.55 + 0.45 * sin(_t * 0.6)
		var chop := 0.15 * sin(_t * 3.7 + 1.3)
		_gust = _base_gust * clampf(swell + chop, 0.0, 1.4)
	else:
		_gust = lerpf(_gust, 0.0, 0.1)
	_wind.wind_force_magnitude = _gust
	_recycle_leaves()

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	var dir := (_char.transform.basis * input).normalized()

	var v := _char.velocity
	v.x = dir.x * SPEED
	v.z = dir.z * SPEED
	if _char.is_on_floor():
		v.y = JUMP if Input.is_key_pressed(KEY_SPACE) else -0.1
	else:
		v.y -= _gravity * delta
	_char.velocity = v
	_char.move_and_slide()

func _process(_dt: float) -> void:
	var lean := 0.0
	if is_instance_valid(_gauge):
		lean = rad_to_deg((_gauge.global_position - _gauge_anchor).angle_to(Vector3.DOWN))
	_hud.text = "Cloth in wind   F wind %s   [ ] gust %.0f   1-4 %s   G leaves   R reset   ESC\ngust: %4.1f   gauge lean: %4.1f°   leaves: %d   FPS: %d" % [
		("ON" if _wind_on else "OFF"), _base_gust, ANIMS[_anim], _gust, lean, _leaves.size(), Engine.get_frames_per_second()]
