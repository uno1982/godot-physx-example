// A PhysXSkinnedCloth3D drawn with your own material (its render_material): the vertex() places the vertices from
// the simulation, from the inputs the cloth sets on the material (see the class reference); the look is up to you.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D cloth_positions : filter_nearest, repeat_disable;
uniform sampler2D cloth_normals : filter_nearest, repeat_disable;
uniform int texture_width = 1;
uniform float normal_sign = 1.0;

// The look: woven stripes and a velvet-like sheen at grazing angles.
uniform vec4 base_color : source_color = vec4(0.1, 0.18, 0.42, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.86, 0.68, 0.2, 1.0);
uniform float stripes = 18.0;

void vertex() {
	int i = int(CUSTOM0.x + 0.5);
	ivec2 px = ivec2(i % texture_width, i / texture_width);
	float handedness = dot(cross(NORMAL, TANGENT), BINORMAL) < 0.0 ? -1.0 : 1.0;
	VERTEX = texelFetch(cloth_positions, px, 0).xyz;
	NORMAL = normalize(texelFetch(cloth_normals, px, 0).xyz * normal_sign);
	// Keep the tangent frame with the new normal, for a normal map.
	vec3 tangent = TANGENT - NORMAL * dot(NORMAL, TANGENT);
	if (dot(tangent, tangent) > 1e-8) {
		TANGENT = normalize(tangent);
		BINORMAL = cross(NORMAL, TANGENT) * handedness;
	}
}

void fragment() {
	float stripe = smoothstep(0.38, 0.46, abs(fract(UV.x * stripes) - 0.5));
	ALBEDO = mix(base_color.rgb, stripe_color.rgb, stripe);
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	RIM = 0.7;
	RIM_TINT = 0.4;
	// Single-layer cloth: light the back faces from their own side.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
