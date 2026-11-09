shader_type spatial;
// The desert scrub's grass (desert_scrub.gd): blades bending in the wind, more toward the tips, each plant in its own
// part of the gusts; near the tornado (vortex_center, set each frame) dragged around it, the way it spins, and in
// toward it, fluttering. Color from each instance (MultiMesh colors). desert_scrub.gd sets the uniforms from its own
// exports.
render_mode cull_disabled;

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.3);
// How far a tip moves in the breeze (meters per meter of blade, squared), and how fast the gusts come.
uniform float sway = 0.06;
uniform float sway_speed = 1.6;
uniform vec3 vortex_center = vec3(0.0);
// How far from the tornado the grass feels it (meters), and how hard it's pulled there.
uniform float vortex_reach = 22.0;
uniform float vortex_strength = 1.0;

void vertex() {
	// A blade bends from its root: nothing at the ground, most at the tip.
	float h = max(VERTEX.y, 0.0);
	float bend = h * h;
	vec3 root = MODEL_MATRIX[3].xyz;
	float gust = 0.4 + 0.6 * sin(TIME * sway_speed + root.x * 0.35 + root.z * 0.25) + 0.25 * sin(TIME * sway_speed * 2.3 + root.x * 1.3);
	vec3 offset = normalize(wind_dir) * gust * sway * bend * 4.0;

	vec3 to_center = vortex_center - root;
	to_center.y = 0.0;
	float d = length(to_center);
	if (d < vortex_reach) {
		float k = 1.0 - d / vortex_reach;
		vec3 inward = to_center / max(d, 0.01);
		// The tornado's spin (tornado.gd: around = up x outward).
		vec3 around = cross(vec3(0.0, 1.0, 0.0), -inward);
		float flutter = 0.8 + 0.2 * sin(TIME * 9.0 + root.x * 2.1 + root.z * 1.7);
		offset += (around * 0.8 + inward * 0.5) * vortex_strength * k * bend * 4.0 * flutter;
	}
	// The offset is in world space; the instance's own turn and size taken out. A blade bends rather than stretches:
	// its tip goes no further sideways than about its height, and drops as it goes (hard pulled, it lies flat).
	vec3 sideways = inverse(mat3(MODEL_MATRIX)) * offset;
	sideways.y = 0.0;
	float far = length(sideways);
	float most = h * 1.3;
	if (far > most) {
		sideways *= most / far;
		far = most;
	}
	VERTEX.xz += sideways.xz;
	float r = h > 1e-4 ? far / (h * 1.4) : 0.0;
	VERTEX.y = h * sqrt(max(1.0 - r * r, 0.2));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
