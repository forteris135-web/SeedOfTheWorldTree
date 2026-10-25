shader_type canvas_item;
// 밉맵 단계로 흐리게 그린다 (v1.1.0 — 뿌리지기 방 배경의 흐린 물레방아, scripts/world/blur_wheel.gd).
// 텍스처에 밉맵이 있어야 한다 (.import 의 mipmaps/generate=true, 노드의 texture_filter = LINEAR_WITH_MIPMAPS).
// blur = 밉맵 단계 (0 = 또렷, 1 = 절반 해상도, 2.5 = 약 1/6 해상도). 계산 한 번이라 가볍다.
uniform float blur : hint_range(0.0, 8.0) = 2.5;
varying vec4 tint;

void vertex() {
	tint = COLOR;   // 정점 색 × modulate (fragment 의 COLOR 는 이미 텍스처가 곱해져 있어 따로 받아 둔다)
}

void fragment() {
	COLOR = textureLod(TEXTURE, UV, blur) * tint;
}
