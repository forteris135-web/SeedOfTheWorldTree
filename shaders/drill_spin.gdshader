shader_type canvas_item;
render_mode blend_add;
// 드릴이 도는 빛: 드릴 그림을 한 장 더 겹쳐 그리며, 그림의 축(밑동 → 끝)을 따라 비스듬한 빛 줄(나선)이 끝 쪽으로 흘러간다.
// 그림의 불투명한 곳에만 빛이 올라간다 (드릴 밖으로 새지 않는다). 더하기 혼합이라 어두운 곳은 그대로다.
// axis_a / axis_b: 텍스처 px 의 밑동·끝 자리, phase: 0→1 반복(빠르기는 그림 쪽이 정한다), strength: 0~1.

uniform vec2 tex_size = vec2(128.0, 128.0);
uniform vec2 axis_a = vec2(0.0, 0.0);
uniform vec2 axis_b = vec2(0.0, 128.0);
uniform float phase = 0.0;
uniform float strength = 0.0;
uniform float bands = 5.0;
uniform float skew = 0.9;
uniform vec4 band_color : source_color = vec4(1.0, 0.82, 0.5, 1.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec2 p = UV * tex_size;
	vec2 ab = axis_b - axis_a;
	float l2 = max(dot(ab, ab), 1.0);
	float u = dot(p - axis_a, ab) / l2;                       // 축을 따라 0(밑동) → 1(끝)
	float v = (ab.x * (p.y - axis_a.y) - ab.y * (p.x - axis_a.x)) / l2;   // 축에서 옆으로 (나선의 기울기)
	float w = fract(u * bands + v * skew * bands - phase);
	float band = smoothstep(0.0, 0.18, w) * (1.0 - smoothstep(0.18, 0.45, w));
	float ends = smoothstep(0.02, 0.12, u) * (1.0 - smoothstep(0.88, 1.0, u));
	float k = band * ends * strength * t.a;
	COLOR = vec4(band_color.rgb * 1.4, k);
}
