// 이펙트 공용 셰이더 조각 (fx_mix / fx_add 가 #include 한다). 2026-10-19 이펙트 리뉴얼 F1.
// 1) 팔레트 바꾸기(그라데이션 맵): 그림의 밝기를 어두운색 → 가운데색 → 밝은색 세 색으로 다시 칠한다.
//    파란·흰 그림을 민트·금빛·초록·붉은·보랏빛으로 바꿔 쓰는 데 쓴다. pal_keep 만큼 원래 색을 남긴다.
// 2) 호 닦아 드러내기(wipe): 그림 안의 한 점(wipe_center, UV)을 중심으로 각도 wipe_a0 에서 wipe_span 만큼
//    머리(wipe_head 0→1)가 지나간 곳만 보인다. wipe_tail 이 1 보다 작으면 머리 뒤 그만큼만 남고 앞쪽부터 사라진다.
//    칼이 지나간 길을 따라 칼자국이 그려지는 데 쓴다. 머리 근처는 조금 더 밝게(wipe_glow).
// 색(modulate)은 그림 색에 곱한다 (1 보다 크면 HDR 글로우로 번진다).
// 주의: 방의 글로우가 '스크린' 섞기라 화면 값이 1 을 크게 넘으면(더하기 이펙트가 여러 겹 + 밝기 배수) 오히려 회색으로 죽는다.
//       큰 그림은 섞기(mix)로, 더하기(add)는 작은 반짝임에만, 밝기 배수는 1.2 안쪽으로 쓴다.

uniform bool palette_on = false;
uniform vec4 pal_dark : source_color = vec4(0.05, 0.12, 0.30, 1.0);
uniform vec4 pal_mid : source_color = vec4(0.40, 0.62, 0.95, 1.0);
uniform vec4 pal_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float pal_keep : hint_range(0.0, 1.0) = 0.0;

uniform bool wipe_on = false;
uniform vec2 wipe_center = vec2(0.5, 0.5);
uniform vec2 wipe_aspect = vec2(1.0, 1.0);
uniform float wipe_a0 = 0.0;
uniform float wipe_span = 3.1416;
uniform float wipe_head = 1.0;
uniform float wipe_tail = 4.0;
uniform float wipe_soft = 0.12;
uniform float wipe_glow = 0.6;
uniform float wipe_gap_hide = 0.0;   // 1 이면 호 범위 밖(초승달 안쪽 꽃잎 등)은 그리지 않는다
// 3) 둥근 테(round): 그림 가운데(UV 0.5)에서 round_r0 ~ round_r1 사이에서 서서히 지운다 — 그림 가장자리가 잘려 있는(알파가 0 이 아닌)
//    그림을 크게 키워 돌려도 곧은 테두리(마름모·사각)가 보이지 않게 (포자 구름 — 2026-10-20 검수). 기본은 꺼짐.
uniform bool round_on = false;
uniform float round_r0 = 0.3;
uniform float round_r1 = 0.5;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = tex.rgb;
	float a = tex.a;
	if (palette_on) {
		float l = clamp(dot(rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
		vec3 m = l < 0.5 ? mix(pal_dark.rgb, pal_mid.rgb, l * 2.0) : mix(pal_mid.rgb, pal_light.rgb, (l - 0.5) * 2.0);
		rgb = mix(m, rgb, pal_keep);
	}
	if (wipe_on) {
		vec2 d = (UV - wipe_center) * wipe_aspect;
		float ang = atan(d.y, d.x);
		float mid = wipe_a0 + wipe_span * 0.5;
		float rel = mod(ang - mid + 3.14159265, 6.2831853) - 3.14159265;   // -π..π (호 가운데 기준)
		float t = rel * sign(wipe_span) / max(abs(wipe_span), 0.001) + 0.5;  // 0 = 시작, 1 = 끝
		float gap = (1.0 - smoothstep(-0.07, -0.01, t)) + smoothstep(1.01, 1.07, t);   // 호 범위 밖이면 1
		float vis = 1.0 - smoothstep(wipe_head - wipe_soft, wipe_head, t);
		vis *= 1.0 - wipe_gap_hide * clamp(gap, 0.0, 1.0);
		vis *= smoothstep(wipe_head - wipe_tail - wipe_soft, wipe_head - wipe_tail, t);
		a *= vis;
		rgb += vec3(wipe_glow) * (1.0 - smoothstep(0.0, wipe_soft * 1.6, abs(t - wipe_head + wipe_soft * 0.5))) * step(wipe_head, 1.0);
	}
	if (round_on) {
		a *= 1.0 - smoothstep(round_r0, round_r1, length(UV - vec2(0.5)));
	}
	COLOR = vec4(rgb, a) * v_mod;
}
