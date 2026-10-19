shader_type canvas_item;
render_mode unshaded;
// 앞 지형의 뒤 그림자 (앞뒤 가르기 — TERRAIN.md 5장). 지형 조각(atlas)을 한 번 더, 지형 묶음 맨 아래 겹에 그린다:
// 흐린 밉맵 단계(lod)의 알파로 실루엣보다 조금 넓고 부드러운 어두운 테가 생겨, 같은 화풍의 배경 그림 위에서 발판 가장자리가 갈라져 보인다.
// 그림자는 잿빛 표를 거치지 않는다(어두운 색 하나). 진하기·색은 정화 전·후 두 값 — 번지는 연출 중에는 ash_purify 와 같은 자리에서 섞인다.
// Purity 가 purity·center·radius·softness 를 함께 넣고, apply_depth 가 나머지를 방의 그림 옷 데이터("depth")로 넣는다.

uniform float purity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float softness = 0.3;
uniform float lod = 3.5;                                  // 흐림 (밉맵 단계 — 1 늘 때마다 두 배 넓게)
uniform vec2 strength = vec2(0.0, 0.0);                   // 진하기 (정화 전, 정화 후)
uniform vec3 color_ash : source_color = vec3(0.04, 0.04, 0.06);
uniform vec3 color_alive : source_color = vec3(0.05, 0.03, 0.02);
uniform vec2 offset = vec2(0.0, 4.0);                     // 그림자를 옮기는 거리 (px — 조금 아래로 두면 떠 있는 발판이 앞으로 나와 보인다)

void vertex() {
	VERTEX += offset;
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float d = distance(SCREEN_UV * aspect, center * aspect);
	float spread = 1.0 - smoothstep(radius - softness, radius + softness, d);
	float k = clamp(max(purity, spread), 0.0, 1.0);
	float a = textureLod(TEXTURE, UV, lod).a;
	COLOR = vec4(mix(color_ash, color_alive, k), a * mix(strength.x, strength.y, k) * COLOR.a);
}
