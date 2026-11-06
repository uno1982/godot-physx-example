extends Node3D
# Character cloth showcase: the Quaternius mannequin in a long skirt and a cape,
# each a PhysXSkinnedCloth3D (compute shaders, any GPU), running the Universal
# Animation Library around a circle so the cloth reacts to real movement and
# turning, not just the animation in place.
#
#   1-7   idle / walk / jog / sprint / roll / spell / dance
#   C     cloth on/off (off = the plain skinned garments, for comparison)
#   M     move around the circle / stay in place
#   F     follow camera / free fly (WASD + hold RMB)
#   R     reset the cloth onto the animated pose
#   B     legs / feet colliders: capsules or boxes (live, no rebuild)
#   V     show the colliders (capsules green, boxes yellow)
#   N     wind on/off (a gusty breeze across the circle; a wind vector, no rebuild)
#   T     the garments' look: the built-in one, or your own material (render_material, one ShaderMaterial shared by
#         both: cloth_own_material.gdshader; swapped live, no rebuild)

const ANIMS := [
	["Idle", 0.0],
	["Walk", 1.4],
	["Jog_Fwd", 3.2],
	["Sprint", 5.6],
	["Roll", 3.0],
	["Spell_Simple_Shoot", 0.0],
	["Dance", 0.0],
]

@export var circle_radius := 5.0
@export var start_animation := 2
## The character: an imported glTF with its own AnimationPlayer, and
## PhysXSkinnedCloth3D children for its garments.
@export var character: Node3D

@onready var _cam: Camera3D = $Camera3D
@onready var _hud: Label = $HUD/Label

var _ap: AnimationPlayer
var _cloths: Array[PhysXSkinnedCloth3D] = []
var _wind_on := false
const WIND := Vector3(5.0, 0.0, 3.0)
var _fly: FlyCamera
var _anim := 0
var _moving := true
var _follow := true
var _angle := 0.0
var _viewport_rid: RID
# Leg / foot physical bones: each capsule gets a box twin of the same size; B
# switches which of the two is enabled (the cloth reads them live).
const BOX_BONES := ["LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]
var _leg_pairs: Array = [] # [capsule CollisionShape3D, box CollisionShape3D]
var _boxes := false
var _skel: Skeleton3D
var _gizmos: Array = [] # [MeshInstance3D, PhysicalBone3D, CollisionShape3D, bone]
var _show_colliders := false
var _own_material: ShaderMaterial # null = the built-in look

func _ready() -> void:
	_ap = character.find_children("*", "AnimationPlayer", true, false)[0]
	# The garments' cloth nodes are in the scene so their max distances can be
	# painted in the editor (select one, then Paint Cloth in the 3D toolbar).
	for c in character.find_children("*", "PhysXSkinnedCloth3D", false, false):
		_cloths.append(c)
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_fly = FlyCamera.new(_cam)
	_setup_colliders()
	_play(start_animation)

func _setup_colliders() -> void:
	_skel = character.find_children("*", "Skeleton3D", true, false)[0]
	for pb: PhysicalBone3D in character.find_children("*", "PhysicalBone3D", true, false):
		for cs in pb.get_children():
			if not (cs is CollisionShape3D) or not ((cs as CollisionShape3D).shape is CapsuleShape3D):
				continue
			var cap := (cs as CollisionShape3D).shape as CapsuleShape3D
			var twin: CollisionShape3D = null
			if pb.bone_name in BOX_BONES:
				twin = CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0)
				twin.shape = box
				twin.transform = (cs as CollisionShape3D).transform
				twin.disabled = true
				pb.add_child(twin)
				_leg_pairs.append([cs, twin])
			_add_gizmo(pb, cs)
			if twin != null:
				_add_gizmo(pb, twin)

func _add_gizmo(pb: PhysicalBone3D, cs: CollisionShape3D) -> void:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if cs.shape is BoxShape3D:
		var bm := BoxMesh.new()
		bm.size = (cs.shape as BoxShape3D).size
		mi.mesh = bm
		m.albedo_color = Color(1.0, 0.8, 0.2, 0.45)
	else:
		var cm := CapsuleMesh.new()
		cm.radius = (cs.shape as CapsuleShape3D).radius
		cm.height = (cs.shape as CapsuleShape3D).height
		mi.mesh = cm
		m.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	_gizmos.append([mi, pb, cs, _skel.find_bone(pb.bone_name)])

func _toggle_boxes() -> void:
	_boxes = not _boxes
	for pair in _leg_pairs:
		(pair[0] as CollisionShape3D).disabled = _boxes
		(pair[1] as CollisionShape3D).disabled = not _boxes

func _play(i: int) -> void:
	_anim = clampi(i, 0, ANIMS.size() - 1)
	_ap.play(ANIMS[_anim][0], 0.25)

func _process(delta: float) -> void:
	var speed: float = ANIMS[_anim][1] if _moving else 0.0
	if speed > 0.0:
		_angle += speed * delta / circle_radius
	var pos := Vector3(cos(_angle), 0.0, sin(_angle)) * circle_radius
	var forward := Vector3(-sin(_angle), 0.0, cos(_angle)) # direction of travel (counter-clockwise from above)
	if _moving:
		character.global_position = pos
		# glTF characters face +Z.
		character.global_basis = Basis.looking_at(-forward, Vector3.UP)

	if _follow:
		var side := character.global_basis.x
		var target := character.global_position + Vector3(0, 1.0, 0)
		var eye := target - character.global_basis.z * 2.2 + side * 2.0 + Vector3(0, 0.6, 0)
		_cam.global_position = _cam.global_position.lerp(eye, clampf(delta * 4.0, 0.0, 1.0))
		_cam.look_at(target)
		_fly.yaw = _cam.rotation.y
		_fly.pitch = _cam.rotation.x
	else:
		_fly.process(delta)

	for g in _gizmos:
		var mi: MeshInstance3D = g[0]
		mi.visible = _show_colliders and not (g[2] as CollisionShape3D).disabled
		if mi.visible:
			# Where the PhysicalBone3D puts its shape: bone pose * body offset * shape.
			mi.global_transform = _skel.global_transform * _skel.get_bone_global_pose(g[3]) * (g[1] as PhysicalBone3D).body_offset * (g[2] as CollisionShape3D).transform

	var particles := 0
	for c in _cloths:
		particles += c.get_particle_count()
	var timing := "\nprocess %.2f ms   physics %.2f ms   %s" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderTime.cpu_gpu(_viewport_rid)]
	_hud.text = "Character cloth -- PhysXSkinnedCloth3D (compute shaders, any GPU)\n1-7 animation   C cloth on/off   M move/stay   F follow/fly (WASD + RMB)   R reset   B leg boxes   V colliders   T look   N wind\n%s   cloth %s   wind %s   legs: %s   look: %s   %d particles   FPS %d%s" % [
		ANIMS[_anim][0], "ON" if _cloth_on() else "OFF", "ON" if _wind_on else "OFF", "boxes" if _boxes else "capsules", "own material" if _own_material else "built-in", particles, Engine.get_frames_per_second(), timing]

func _cloth_on() -> bool:
	return not _cloths.is_empty() and _cloths[0].is_inside_tree()

func _unhandled_input(event: InputEvent) -> void:
	if not _follow and _fly.handle_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_7:
			_play(k - KEY_1)
		elif k == KEY_C:
			_toggle_cloth()
		elif k == KEY_M:
			_moving = not _moving
		elif k == KEY_F:
			_follow = not _follow
		elif k == KEY_B:
			_toggle_boxes()
		elif k == KEY_V:
			_show_colliders = not _show_colliders
		elif k == KEY_T:
			_toggle_material()
		elif k == KEY_N:
			_toggle_wind()
		elif k == KEY_R:
			for c in _cloths:
				c.reset()

func _toggle_wind() -> void:
	_wind_on = not _wind_on
	for c in _cloths:
		c.wind = WIND if _wind_on else Vector3.ZERO
		c.wind_turbulence = 0.6

func _toggle_material() -> void:
	if _own_material:
		_own_material = null
	else:
		_own_material = ShaderMaterial.new()
		_own_material.shader = preload("res://demo/editor/cloth/cloth_own_material.gdshader")
	for c in _cloths:
		c.render_material = _own_material

func _toggle_cloth() -> void:
	# Off: take the cloth nodes out (the skinned garments show again); on: put
	# them back, which rebuilds them on the animated pose.
	var on := _cloth_on()
	for c in _cloths:
		if on:
			character.remove_child(c)
		else:
			character.add_child(c)
