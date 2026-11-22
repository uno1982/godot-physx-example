extends Node3D

# A flat mirror drawn by a scene capture, as Unreal's SceneCaptureComponent2D does one: a second camera renders the
# world into a texture, and the mirror's surface shows that texture. Godot's equivalent of the capture is a
# SubViewport with its own Camera3D, sampled through a ViewportTexture.
#
# The node is the mirror's glass: a rectangle of size in its local XY plane, facing its local +Z. Every frame the
# capture camera sits at the viewing camera's eye mirrored through that plane, looking back through the glass, in
# frustum mode with its near plane exactly on the rectangle (Godot's cameras have no clip plane and no custom
# projection; for a rectangle this off-axis frustum is the exact mirror view, and it clips at the glass, so nothing
# behind the mirror draws). The capture renders linear HDR (its environment's tone mapping off) and the glass shows it
# unshaded, flipped left to right; the viewing camera tone maps it with the rest of the frame. The glass is on its
# own render layer, which the capture leaves out (it would see itself).

## The glass's width and height, meters.
@export var size := Vector2(2.4, 2.2)
## The capture's height in pixels (its width follows the glass's shape).
@export var resolution := 1024
## The camera whose view the mirror shows (the viewport's current camera when empty).
@export var viewer: Camera3D
## The render layer of the glass: the capture leaves it out.
@export_flags_3d_render var glass_layer := 1 << 19
## The capture lit with PXTGI's GI as the room is (off: direct light only).
@export var gi := true

var _viewport: SubViewport
var _camera: Camera3D
var _glass: MeshInstance3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.use_hdr_2d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.cull_mask = 0xFFFFF & ~glass_layer
	_viewport.add_child(_camera)
	_glass = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	_glass.mesh = quad
	_glass.layers = glass_layer
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glass.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D capture : filter_linear, repeat_disable;
void fragment() {
	// The capture looks back through the glass: its left is the mirror's right.
	ALBEDO = texture(capture, vec2(1.0 - UV.x, UV.y)).rgb;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("capture", _viewport.get_texture())
	_glass.material_override = material
	add_child(_glass)
	set_resolution(resolution)


func set_resolution(p_height: int) -> void:
	resolution = p_height
	if _viewport:
		_viewport.size = Vector2i(maxi(int(p_height * size.x / size.y), 1), maxi(p_height, 1))


# The capture's own environment: the viewer's, with tone mapping off (the viewer tone maps the mirror with the rest
# of its frame).
func _environment() -> Environment:
	var source: Environment = viewer.environment if viewer and viewer.environment else null
	if source == null and get_world_3d():
		source = get_world_3d().environment
	if source == null:
		return null
	var env := source.duplicate() as Environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	# PXTGI runs on every viewport of the world, the capture's too; it hands surfaces its light through SDFGI's
	# switch (the viewer's environment gets it from PXTGI3D; this copy needs it set).
	if gi:
		env.sdfgi_enabled = true
		env.sdfgi_cascades = 1
	return env


func _process(_delta: float) -> void:
	var eye_camera := viewer if viewer else get_viewport().get_camera_3d()
	if eye_camera == null:
		return
	if _camera.environment == null:
		_camera.environment = _environment()
		_camera.attributes = eye_camera.attributes
	var to_local := global_transform.affine_inverse()
	var eye := to_local * eye_camera.global_position
	# Behind the glass the mirror shows nothing (and the capture would look the wrong way).
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if eye.z > 0.01 and _glass.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if eye.z <= 0.01:
		return
	# The eye mirrored through the glass (local z -> -z), looking along -z... back through the glass toward +z: the
	# capture camera's own -z is the glass's +z.
	var mirrored := Vector3(eye.x, eye.y, -eye.z)
	var basis := global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI)
	_camera.global_transform = Transform3D(basis, global_transform * mirrored)
	# The near plane on the glass, its middle offset from the camera's axis. The camera's right is the glass's -x.
	var near := eye.z
	_camera.set_frustum(size.y, Vector2(eye.x, -eye.y), near, eye_camera.far)
