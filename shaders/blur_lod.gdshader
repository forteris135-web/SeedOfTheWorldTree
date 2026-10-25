shader_type canvas_item;
// 밉맵 단계로 흐리게 그린다 (v1.1.0 — 뿌리지기 방 배경의 흐린 물레방아, scripts/world/blur_wheel.gd).
// 텍스처에 밉맵이 있어야 한다 (.import 의 mipmaps/generate=true, 노드의 texture_filter = LINEAR_WITH_MIPMAPS).
// blur = 밉맵 단계 (0 = 또렷, 1 = 절반 해상도, 2.5 = 약 1/6 해상도). 계산 한 번이라 가볍다.
// ash = 잿빛 정도 (0 = 원래 색, 1 = 무채색을 ash_color 쪽으로 — 잿빛 방에서 혼자 갈색으로 튀지 않게, v1.1.0 검수).
// bright = 밝기 배수 (정화된 어두운 방에서 바퀴 모양이 묻히지 않게).
uniform float blur : hint_range(0.0, 8.0) = 2.5;
uniform float ash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ash_color = vec3(0.5, 0.5, 0.54);
uniform float ash_mix : hint_range(0.0, 1.0) = 0.35;
uniform float bright = 1.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;   // 정점 색 × modulate (fragment 의 COLOR 는 이미 텍스처가 곱해져 있어 따로 받아 둔다)
}

void fragment() {
	vec4 c = textureLod(TEXTURE, UV, blur) * tint;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 grey = mix(vec3(lum), ash_color, ash_mix);
	c.rgb = mix(c.rgb * bright, grey, ash);
	COLOR = c;
}
