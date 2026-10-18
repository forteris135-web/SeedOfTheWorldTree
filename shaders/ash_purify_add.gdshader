shader_type canvas_item;
render_mode blend_add;
// ash_purify 와 같지만 더하기 혼합(빛 입자, 빛줄기, 발광용).

uniform float purity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float softness = 0.3;
uniform vec3 ash_tint : source_color = vec3(0.66, 0.70, 0.78);
uniform float ash_contrast = 0.7;
uniform float ash_brightness = 0.82;

void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	lum = (lum - 0.5) * ash_contrast + 0.5;
	vec3 ash = lum * ash_tint * ash_brightness;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float d = distance(SCREEN_UV * aspect, center * aspect);
	float spread = 1.0 - smoothstep(radius - softness, radius + softness, d);
	float k = clamp(max(purity, spread), 0.0, 1.0);
	COLOR = vec4(mix(ash, c.rgb, k), c.a);
}
