extends Node3D

# Node-authored rope bridge -- every plank and every joint is a real scene node.
#
# The deck is a row of RigidBody3D planks. Each junction (the two ends pin to the
# static blocks) is a Generic6DOFJoint3D set up the same way:
#
#   * linear X / Y / Z limits enabled at 0..0   -> translation locked (rigid link)
#   * angular X / Y limits enabled at 0..0       -> no twist, no yaw
#   * angular Z spring enabled                    -> the deck hinges to sag, and
#                                                   the spring pulls it back flat
#
# Select any "Deck/J*" joint in the editor to see that in the inspector (and its
# limit gizmo in the viewport), or a "Deck/Plank*" body to change its mass. Press
# Play: the deck settles under the crates and holds -- the angular spring is what
# stops a plain PGS joint chain from slowly drifting apart under the load.
#
#   C  drop a crate pile      R  reset      ESC  quit

@onready var _hud: Label = $HUD/Label
@onready var _mid: RigidBody3D = $Deck/Plank2
var _rest_y := 0.0

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_rest_y = _mid.global_position.y

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_drop_crates()
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				get_tree().quit()

func _drop_crates() -> void:
	for i in 8:
		var rb := RigidBody3D.new()
		var s := randf_range(0.4, 0.6)
		rb.mass = s * s * s * 10.0
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(s, s, s)
		cs.shape = b
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(randf(), 0.4, 0.9)
		mi.material_override = m
		rb.add_child(mi)
		rb.position = Vector3(randf_range(-1.5, 1.5), 5.0 + i * 0.6, randf_range(-0.7, 0.7))
		$Crates.add_child(rb)

func _process(_dt: float) -> void:
	var defl: float = _rest_y - _mid.global_position.y if _rest_y != 0.0 else 0.0
	_hud.text = "Generic6DOFJoint3D bridge (node-based)   C drop crates   R reset   ESC\nmid-span deflection: %+.2f m     FPS: %d" % [
		defl, Engine.get_frames_per_second()]

	# There's no floor under the bridge -- anything that gets knocked off the
	# deck would otherwise free-fall forever, never sleeping, getting more
	# expensive to simulate the faster it falls. Cull it instead.
	for c in $Crates.get_children():
		if c is RigidBody3D and c.global_position.y < -30.0:
			c.queue_free()
