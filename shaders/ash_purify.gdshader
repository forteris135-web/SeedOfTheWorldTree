shader_type canvas_item;
// 잿빛 → 색 복원. 정화 전에는 잿빛으로 바래 보이고, 정화 순간 화면의 한 점에서 색이 번져 돌아온다.
// 화면 좌표(SCREEN_UV) 기준이라 배경·안개·잎 등 어떤 겹에 붙여도 같은 자리에서 함께 번진다.

uniform float purity : hint_range(0.0, 1.0) = 0.0;   // 전체 정화 정도 (0 잿빛, 1 원래 색)
uniform vec2 center = vec2(0.5, 0.5);                  // 색이 번져 나오는 중심 (화면 비율 좌표)
uniform float radius = 0.0;                            // 번진 반지름 (화면 높이 = 1)
uniform float softness = 0.3;                          // 경계의 부드러움
uniform vec3 ash_tint : source_color = vec3(0.66, 0.70, 0.78);  // 잿빛의 색조 (살짝 차가운 회색)
uniform float ash_contrast = 0.7;
uniform float ash_brightness = 0.82;

void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	lum = (lum - 0.5) * ash_contrast + 0.5;
	vec3 ash = lum * ash_tint * ash_brightness;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float d = distance(SCREEN_UV * aspect, center * aspect);
	// 번지는 가장자리에 따뜻한 빛의 테두리
	float edge = 1.0 - smoothstep(0.0, softness, abs(d - radius));
	float spread = 1.0 - smoothstep(radius - softness, radius + softness, d);
	float k = clamp(max(purity, spread), 0.0, 1.0);
	vec3 col = mix(ash, c.rgb, k);
	col += vec3(1.0, 0.85, 0.5) * edge * 0.25 * float(radius > 0.001 && radius < 3.0);
	COLOR = vec4(col, c.a);
}
