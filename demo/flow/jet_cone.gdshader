shader_type spatial;
// The sharp core of a torch or jet flame, which a fluid grid can't resolve:
// put it on a CylinderMesh (no caps, top radius = bottom radius) whose bottom
// sits at the nozzle; the shader shapes it into the flame. Additive and
// unshaded, so it reads as glow; the silhouette is the mesh's own edge. A
// PhysXFlowEmitter3D at its tip can carry the flame on.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// Color from the nozzle (0) to the tip (1).
uniform vec4 base_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.15, 0.5, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.45, 0.12, 0.9, 1.0);
uniform float intensity = 4.0;
// How fast brightness drops toward the tip.
uniform float falloff = 1.5;
// How much the middle outshines the silhouette (higher: softer edge).
uniform float core_weight = 1.0;
// Shape: 1 = a straight cone to a point, lower = rounder tip; bulge swells
// the flame between nozzle and tip.
uniform float taper = 1.0;
uniform float bulge = 0.0;
// A ripple running down the flame, as a fraction of its radius.
uniform float flicker = 0.06;
uniform float flicker_speed = 40.0;
// The mesh's height, to measure the way along the flame.
uniform float height = 0.5;

varying float along;

void vertex() {
	along = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	float ripple = sin(TIME * flicker_speed - along * 25.0) * 0.5 + sin(TIME * flicker_speed * 1.7 - along * 41.0) * 0.5;
	float profile = pow(1.0 - along, taper) * (1.0 + bulge * sin(PI * along));
	VERTEX.xz *= profile * (1.0 + flicker * ripple * along);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = mix(1.0, facing, clamp(core_weight, 0.0, 1.0));
	vec3 color = along < 0.5 ? mix(base_color.rgb, mid_color.rgb, along * 2.0) : mix(mid_color.rgb, tip_color.rgb, along * 2.0 - 1.0);
	ALBEDO = color * body * pow(1.0 - along, falloff) * intensity;
}
