shader_type canvas_item;
render_mode blend_add;
// ash_purify 와 같지만 더하기 혼합(빛 입자, 빛줄기, 발광용). 팔레트 바꾸기도 같다.

uniform float purity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float softness = 0.3;
uniform sampler2D ash_lut : filter_linear, repeat_disable;
uniform vec3 ash_tint : source_color = vec3(0.66, 0.70, 0.78);
uniform float ash_contrast = 0.7;
uniform float ash_brightness = 0.82;

const float ROWS = 8.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 ash_of(vec3 rgb) {
	float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	float l = clamp(lum, 0.0, 1.0) * (63.0 / 64.0) + 0.5 / 64.0;
	vec3 neutral = texture(ash_lut, vec2(l, 0.5 / ROWS)).rgb;
	vec3 hsv = rgb2hsv(clamp(rgb, 0.0, 1.0));
	float hb = hsv.x * 6.0;
	float i0 = mod(floor(hb), 6.0);
	float f = hb - floor(hb);
	float i1 = mod(i0 + 1.0, 6.0);
	vec3 c0 = texture(ash_lut, vec2(l, (1.5 + i0) / ROWS)).rgb;
	vec3 c1 = texture(ash_lut, vec2(l, (1.5 + i1) / ROWS)).rgb;
	vec3 a = mix(neutral, mix(c0, c1, f), smoothstep(0.06, 0.35, hsv.y));
	return a * max(lum, 1.0);
}

void fragment() {
	vec4 c = COLOR;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float d = distance(SCREEN_UV * aspect, center * aspect);
	float spread = 1.0 - smoothstep(radius - softness, radius + softness, d);
	float k = clamp(max(purity, spread), 0.0, 1.0);
	vec3 col = c.rgb;
	if (k < 0.999) {
		col = mix(ash_of(c.rgb), c.rgb, k);   // 정화된 곳은 표를 찾지 않는다 (가벼움)
	}
	COLOR = vec4(col, c.a);
}
