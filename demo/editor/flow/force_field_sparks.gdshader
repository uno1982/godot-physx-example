shader_type particles;
// The sparks off the force field (force_field.gd places the emitter at the hit point, its +Y the shield's normal there):
// each starts on the shield a little way from the hit and leaves sliding along its surface, away from the hit in any
// direction, and while near the shield is pulled toward it about as much as it takes to follow its curve, so its path
// bends around the sphere; the shield's surface keeps it out. The air slowly takes it over, so once clear of the
// shield it trails off on the wind with the smoke. Cooling color and shrinking size over its life.

uniform vec3 shield_center = vec3(0.0);
uniform float shield_radius = 1.6;
// How near the shield (beyond its surface) the pull reaches, and how much of the pull that would keep a spark on the
// surface (its speed along it squared over the radius: what bends its path around the sphere) it gets there. Below 1
// they peel off as they go, above it they ride the surface; a slow spark gets almost none either way, so the wind
// carries it off rather than holding it.
uniform float hug_reach = 0.7;
uniform float hug = 0.7;
uniform vec3 wind = vec3(4.6, 0.0, 0.0);
// How quickly a spark takes on the wind's velocity (per second).
uniform float drag = 1.5;
uniform float gravity = 1.5;
uniform float speed_min = 5.0;
uniform float speed_max = 8.0;
// How far off the surface a spark leaves (0: along it).
uniform float lift = 0.1;
// Where on the shield a spark starts: this far from the hit (meters, across the surface), heading away from it.
uniform float spawn_min = 0.5;
uniform float spawn_max = 1.5;
uniform float floor_height = 0.0;
uniform sampler2D color_ramp : repeat_disable;
uniform float size_min = 0.9;
uniform float size_max = 1.1;

float rand(inout uint seed) {
	seed = seed * 747796405u + 2891336453u;
	uint w = ((seed >> ((seed >> 28u) + 4u)) ^ seed) * 277803737u;
	return float((w >> 22u) ^ w) / 4294967295.0;
}

void start() {
	uint seed = NUMBER * 9781u + RANDOM_SEED * 6271u + 17u;
	float angle = rand(seed) * TAU;
	vec3 normal = normalize(EMISSION_TRANSFORM[1].xyz);
	vec3 side = normalize(EMISSION_TRANSFORM[0].xyz);
	vec3 other = normalize(EMISSION_TRANSFORM[2].xyz);
	vec3 along = cos(angle) * side + sin(angle) * other;
	// A start on the shield's surface, spawn_min to spawn_max from the hit, and the way away from the hit there.
	vec3 offset = EMISSION_TRANSFORM[3].xyz + along * mix(spawn_min, spawn_max, rand(seed)) - shield_center;
	vec3 out_n = normalize(offset);
	vec3 start_at = shield_center + out_n * (shield_radius + 0.03);
	vec3 away = normalize(along - out_n * dot(along, out_n));
	if (RESTART_POSITION) {
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = start_at;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = normalize(away + out_n * lift) * mix(speed_min, speed_max, rand(seed));
	}
	CUSTOM = vec4(mix(size_min, size_max, rand(seed)), 0.0, 0.0, 0.0);
}

void process() {
	CUSTOM.y += DELTA;
	float age = clamp(CUSTOM.y / LIFETIME, 0.0, 1.0);

	vec3 v = VELOCITY;
	v.y -= gravity * DELTA;
	v += (wind - v) * (1.0 - exp(-drag * DELTA));

	// Near the shield: pulled toward it, so the path bends around it; at its surface, kept out (what goes in is lost).
	vec3 p = TRANSFORM[3].xyz;
	vec3 d = p - shield_center;
	float dist = max(length(d), 1e-4);
	vec3 n = d / dist;
	float gap = dist - shield_radius;
	if (gap < hug_reach) {
		vec3 across = v - n * dot(v, n);
		float follow = dot(across, across) / dist;
		v -= n * follow * hug * (1.0 - max(gap, 0.0) / hug_reach) * DELTA;
	}
	if (gap < 0.02) {
		TRANSFORM[3].xyz = shield_center + n * (shield_radius + 0.02);
		v -= n * min(dot(v, n), 0.0);
	}
	// The floor: they land and skate along it.
	if (TRANSFORM[3].y < floor_height + 0.01) {
		TRANSFORM[3].y = floor_height + 0.01;
		v.y = max(v.y, 0.0);
		v.xz *= 1.0 - min(4.0 * DELTA, 1.0);
	}
	VELOCITY = v;

	COLOR = texture(color_ramp, vec2(age, 0.5));
	float s = CUSTOM.x * mix(1.0, 0.3, age);
	TRANSFORM[0].xyz = vec3(s, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, s, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, s);
}
