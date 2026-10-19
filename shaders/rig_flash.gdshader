shader_type canvas_item;
// 부위 뼈대(PartRig) 공용 재질. 부위 그림 전체가 이 재질 하나를 함께 쓴다 (PartRig 가 노드 하나에 걸고 부위는 부모 재질을 쓴다).
//  - flash: 0~1 만큼 flash_color 로 섞는다 (곱하기가 아니라 섞기라 어두운 부위도 밝게 번쩍인다). 1 을 넘는 색은 글로우로 번진다.
//  - dissolve: 0~1. 화면 픽셀 기준 얼룩 무늬가 dissolve 보다 낮은 곳부터 사라진다 (쓰러짐: 잿빛 재 / 정화·구원: 빛).
//    투명도(alpha)로 흐리면 부위가 겹친 자리가 비쳐 보이므로(뒷팔이 몸통 너머로 보임) 픽셀을 통째로 지운다.
//    사라지는 가장자리는 dissolve_edge 색으로 잠깐 빛난다.
// 색·투명도는 노드 modulate(COLOR)로.
uniform float flash = 0.0;
uniform vec4 flash_color = vec4(1.6, 1.6, 1.6, 1.0);
uniform float dissolve = 0.0;
uniform vec4 dissolve_edge = vec4(1.4, 0.9, 0.5, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Godot 4: fragment 의 COLOR 는 이미 '텍스처 색 × modulate' 다 (HDR 2D 의 색 공간 변환 포함). 텍스처를 또 곱하면 어둡고 진해진다.
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	if (dissolve > 0.0) {
		float n = vnoise(FRAGCOORD.xy / 7.0) * 0.75 + hash(floor(FRAGCOORD.xy / 2.0)) * 0.25;
		float d = dissolve * 1.08;
		if (n < d) {
			discard;
		}
		float edge = 1.0 - smoothstep(d, d + 0.07, n);
		c.rgb = mix(c.rgb, dissolve_edge.rgb, edge);
	}
	COLOR = c;
}
