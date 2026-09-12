shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add, shadows_disabled;

// Real volumetric raymarched fire: a box mesh is rendered from its BACK
// faces (cull_front) so every visible fragment is a point on the far side
// of the box as seen from the camera; from there we raymarch backward
// through the box in LOCAL space, sampling a 3D noise texture (baked from
// FastNoiseLite via NoiseTexture3D -- GLSL has no built-in noise, so the
// texture IS the "FastNoiseLite in a shader" bridge) at each step to shape
// density and color. Reads as genuinely 3D fire from any angle, unlike a
// camera-facing flat billboard (fire_billboard.gdshader), at the cost of
// real per-pixel raymarching cost.

uniform sampler3D noise_tex;
uniform float noise_scale : hint_range(0.2, 6.0) = 1.6;
uniform float scroll_speed : hint_range(0.0, 3.0) = 0.6;
uniform vec3 box_half_extents = vec3(0.5, 0.8, 0.5);
uniform int raymarch_steps : hint_range(8, 64) = 32;
uniform float density_mult : hint_range(0.5, 10.0) = 4.0;
uniform float emission_strength : hint_range(0.5, 8.0) = 3.0;
uniform vec4 color_core : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 color_outer : source_color = vec4(0.35, 0.05, 0.0, 1.0);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX; // default (object) space -- exactly what the box intersection test below needs
}

// Ray/AABB slab test, box centred at the origin in the mesh's own local
// space with half-extents box_half_extents.
bool intersect_box(vec3 ro, vec3 rd, out float t_near, out float t_far) {
	vec3 inv_rd = 1.0 / rd;
	vec3 t0 = (-box_half_extents - ro) * inv_rd;
	vec3 t1 = (box_half_extents - ro) * inv_rd;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	t_near = max(max(tmin.x, tmin.y), tmin.z);
	t_far = min(min(tmax.x, tmax.y), tmax.z);
	return t_far > max(t_near, 0.0);
}

void fragment() {
	vec3 cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 rd = normalize(local_pos - cam_local);

	float t_near, t_far;
	if (!intersect_box(cam_local, rd, t_near, t_far)) {
		discard;
	}
	t_near = max(t_near, 0.0);

	float step_size = (t_far - t_near) / float(raymarch_steps);
	vec3 pos = cam_local + rd * t_near;

	vec3 accum_col = vec3(0.0);
	float accum_alpha = 0.0;
	float t_scroll = TIME * scroll_speed;

	for (int i = 0; i < raymarch_steps; i++) {
		if (accum_alpha > 0.98) {
			break;
		}
		// Noise scrolls DOWN in the sample space so the fire's turbulent
		// structure appears to rise, matching real flame motion.
		// Subtract, not add: adding t_scroll samples progressively HIGHER
		// into the noise texture over time at a fixed world point, which
		// reads as the pattern moving DOWN past it (the classic UV-scroll
		// sign inversion) -- confirmed on the running scene ("fire is
		// moving down instead of up").
		vec3 uvw = pos * noise_scale - vec3(0.0, t_scroll, 0.0) + vec3(0.5);
		float n = texture(noise_tex, fract(uvw)).r;

		// Taper: full density near the base (local y = -half.y), thinning
		// to nothing at the tip (+half.y), pulled in toward the vertical
		// axis by a radial falloff -- a cone-ish flame silhouette instead
		// of a solid filled box.
		float height01 = clamp((pos.y + box_half_extents.y) / (2.0 * box_half_extents.y), 0.0, 1.0);
		float radial = length(pos.xz) / box_half_extents.x;
		float shape = (1.0 - height01) * clamp(1.0 - radial, 0.0, 1.0);
		float density = max(0.0, n - (0.3 + height01 * 0.45)) * shape * density_mult;

		if (density > 0.001) {
			float heat = clamp(1.0 - height01 * 1.3 + (n - 0.5) * 0.4, 0.0, 1.0);
			vec3 col = mix(color_outer.rgb, color_mid.rgb, smoothstep(0.0, 0.5, heat));
			col = mix(col, color_core.rgb, smoothstep(0.5, 1.0, heat));
			// Exponential extinction (Beer-Lambert) -- the standard way to
			// accumulate density along a ray so thicker regions read as
			// more opaque without ever fully clipping at density=1.
			float alpha_step = 1.0 - exp(-density * step_size * 20.0);
			accum_col += (1.0 - accum_alpha) * alpha_step * col * emission_strength;
			accum_alpha += (1.0 - accum_alpha) * alpha_step;
		}
		pos += rd * step_size;
	}

	if (accum_alpha < 0.01) {
		discard;
	}
	ALBEDO = accum_col;
	EMISSION = accum_col;
	ALPHA = clamp(accum_alpha, 0.0, 1.0);
}
