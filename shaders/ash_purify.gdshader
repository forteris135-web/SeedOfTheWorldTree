shader_type canvas_item;
// 잿빛 → 색 복원 (팔레트 바꾸기). 정화 전에는 원래 색을 지역의 '잿빛 팔레트'로 바꿔 그리고,
// 정화 순간 화면의 한 점에서 원래 색이 번져 돌아온다.
// 화면 좌표(SCREEN_UV) 기준이라 배경·안개·잎·지형 등 어떤 겹에 붙여도 같은 자리에서 함께 번진다.
//
// 팔레트 바꾸기 (2026-10-19): ash_lut 은 64×8 그림 (Purity 가 data/terrain/<지역>.json 의 "ash" 로 만든다).
//   0번 줄 = 무채색 줄(밝기 → 잿빛 색), 1~6번 줄 = 색상 띠(빨강·노랑·초록·청록·파랑·자홍)마다 밝기 → 잿빛 색.
//   원래 색의 밝기·색상으로 표를 찾아 바꾼다 (채도가 낮으면 무채색 줄). 밝기 순서가 지켜져 그림이 뭉개지지 않고,
//   잎·나무껍질·꽃이 서로 다른 잿빛으로 남는다. 1 넘는 빛(발광)은 밝기를 그대로 지킨다.

uniform float purity : hint_range(0.0, 1.0) = 0.0;   // 전체 정화 정도 (0 잿빛, 1 원래 색)
uniform vec2 center = vec2(0.5, 0.5);                  // 색이 번져 나오는 중심 (화면 비율 좌표)
uniform float radius = 0.0;                            // 번진 반지름 (화면 높이 = 1)
uniform float softness = 0.3;                          // 경계의 부드러움
uniform sampler2D ash_lut : filter_linear, repeat_disable;
// 앞뒤 가르기 (TERRAIN.md 5장): 같은 셰이더를 재질 세 벌이 쓴다 — ash_purify(가운데 겹: 안개·잎·기록물 등, 아래 값은 기본 = 아무것도 안 함),
//   ash_purify_far(배경 그림: 아지랑이 색으로 옅게·대비 낮게), ash_purify_fore(앞 지형: 조금 진하고 또렷하게).
//   Purity.apply_depth 가 방의 그림 옷 데이터("depth")로 값을 넣는다. vec2 는 (정화 전, 정화 후) — 번지는 연출 중에는 화면 자리마다 섞인다.
uniform vec2 haze = vec2(0.0, 0.0);                     // 아지랑이 색으로 섞는 양 (0~1)
uniform vec3 haze_color_ash : source_color = vec3(0.8, 0.8, 0.8);
uniform vec3 haze_color_alive : source_color = vec3(0.8, 0.8, 0.8);
uniform vec2 contrast = vec2(1.0, 1.0);                 // 대비 배수 (밝기 0.5 를 기준으로; 배경은 1 보다 작게, 앞 지형은 크게)
uniform vec2 value = vec2(1.0, 1.0);                    // 밝기 배수
uniform vec2 sat = vec2(1.0, 1.0);                      // 채도 배수
// 옛 값 (지금은 쓰지 않지만 다른 곳에서 넣어도 오류가 나지 않게 남겨 둔다)
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

// 앞뒤 가르기: 채도 → 대비(0.5 기준) → 밝기 → 아지랑이. 1 넘는 빛(발광)은 넘는 만큼 그대로 지킨다.
vec3 depth_of(vec3 col, float k) {
	vec2 w = vec2(1.0 - k, k);
	float st = dot(sat, w);
	float ct = dot(contrast, w);
	float va = dot(value, w);
	float hz = dot(haze, w);
	vec3 over = max(col - 1.0, vec3(0.0));
	vec3 c = min(col, vec3(1.0));
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, st);
	c = clamp((c - 0.5) * ct + 0.5, 0.0, 1.0) * va;
	c = mix(c, mix(haze_color_ash, haze_color_alive, k), hz);
	return c + over;
}

void fragment() {
	vec4 c = COLOR;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float d = distance(SCREEN_UV * aspect, center * aspect);
	// 번지는 가장자리에 따뜻한 빛의 테두리
	float edge = 1.0 - smoothstep(0.0, softness, abs(d - radius));
	float spread = 1.0 - smoothstep(radius - softness, radius + softness, d);
	float k = clamp(max(purity, spread), 0.0, 1.0);
	vec3 col = c.rgb;
	if (k < 0.999) {
		col = mix(ash_of(c.rgb), c.rgb, k);   // 정화된 곳은 표를 찾지 않는다 (가벼움)
	}
	col = depth_of(col, k);
	col += vec3(1.0, 0.85, 0.5) * edge * 0.25 * float(radius > 0.001 && radius < 3.0);
	COLOR = vec4(col, c.a);
}
