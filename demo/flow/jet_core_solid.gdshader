shader_type spatial;
// The sharp, white-hot core of a jet flame as a solid glowing surface, for
// inside a PhysXFlow3D plume. Opaque, so it writes depth: Flow's gas behind
// it is hidden and the gas in front still draws over it -- a hot core seen
// through the plume, with Flow drawn after transparent geometry as usual.
// Put it on a CylinderMesh (no caps, top radius = bottom radius) whose bottom
// sits at the nozzle; the shader shapes it. Being opaque it can't fade out,
// so its color runs into the plume's own color toward the tip and the edges.
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// Hottest (nozzle, middle) to coolest (tip, silhouette).
uniform vec4 hot_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform vec4 cool_color : source_color = vec4(0.04, 0.25, 1.0, 1.0);
uniform float intensity = 2.5;
// Where along the flame the color reaches cool_color (0..1).
uniform float cool_at = 0.85;
// How much the silhouette cools toward cool_color.
uniform float edge_cooling = 0.7;
// Shape: 1 = a straight cone to a point, lower = rounder tip; bulge swells
// the flame between nozzle and tip.
uniform float taper = 1.0;
uniform float bulge = 0.0;
// A ripple running down the flame, as a fraction of its radius.
uniform float flicker = 0.03;
uniform float flicker_speed = 40.0;
// The mesh's height, to measure the way along the flame.
uniform float height = 1.0;

varying float along;

void vertex() {
	along = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	float ripple = sin(TIME * flicker_speed - along * 25.0) * 0.5 + sin(TIME * flicker_speed * 1.7 - along * 41.0) * 0.5;
	float profile = pow(1.0 - along, taper) * (1.0 + bulge * sin(PI * along));
	VERTEX.xz *= profile * (1.0 + flicker * ripple * along);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float heat = 1.0 - clamp(along / cool_at, 0.0, 1.0);
	heat *= mix(1.0, facing, edge_cooling);
	vec3 color = heat > 0.5 ? mix(mid_color.rgb, hot_color.rgb, heat * 2.0 - 1.0) : mix(cool_color.rgb, mid_color.rgb, heat * 2.0);
	ALBEDO = color * intensity * mix(0.6, 1.0, heat);
}
