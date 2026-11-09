shader_type spatial;
// The force field: an additive glow on a sphere. A rim where the view grazes it, a faint hexagon grid, and where the
// fire hits it (impact_point, impact_strength from force_field.gd) a hot spot and rings running out from it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 shield_color : source_color = vec3(0.25, 0.65, 1.0);
uniform vec3 hot_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float rim_power = 2.5;
uniform float rim_strength = 1.4;
uniform float grid_strength = 0.12;
uniform float grid_scale = 18.0;
uniform vec3 impact_point = vec3(0.0);
uniform float impact_strength = 0.0;
uniform float impact_radius = 0.45;
uniform float ripple_speed = 6.0;
uniform float ripple_spacing = 0.18;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Distance to the nearest hexagon edge, 0 on an edge (a hexagon grid of unit cell size).
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - c.xy * s, p - (c.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, rim_power) * rim_strength;

	float grid = 1.0 - smoothstep(0.0, 0.06, hex_edge(UV * vec2(grid_scale * 2.0, grid_scale)));
	// The grid shimmers: a slow band running down the shield.
	float band = 0.5 + 0.5 * sin(UV.y * 12.0 - TIME * 1.5);
	grid *= grid_strength * (0.4 + 0.6 * band);

	// Where the fire hits: a hot spot, rings running out from it, and the grid lit up around it.
	float d = distance(v_world, impact_point);
	float hot = exp(-(d * d) / (impact_radius * impact_radius)) * impact_strength;
	float rings = max(0.0, sin((d / ripple_spacing - TIME * ripple_speed))) * exp(-d * 1.6) * impact_strength;
	float lit_grid = grid * (1.0 + 6.0 * exp(-d * 2.0) * impact_strength);

	vec3 col = shield_color * (rim + lit_grid + rings * 0.6) + hot_color * (hot * 1.6 + rings * 0.5);
	ALBEDO = col;
}
