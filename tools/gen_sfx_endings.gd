extends SceneTree
## 엔딩 장면용 효과음 합성기 (ENDINGS.md: 허밍이 시작되기 전의 장면은 음악 없이 "뿌리의 낮은 울림과 잎 소리",
## "등불이 꺼지는 작은 소리와 땅의 울림", "영혼들이 나타나는 소리와 펌프의 낮은 울림"만).
## 결과: audio/sfx/end_rumble.wav · end_leaves.wav · lamp_out.wav · pump_creak.wav · pump_clunk.wav (Sfx 가 이름으로 튼다)
## 사용: <godot> --headless --path . --script tools/gen_sfx_endings.gd   (임시 소리 — 나중에 같은 이름의 진짜 소리로 바꿔도 된다)
## 폰 스피커는 400Hz 아래를 거의 못 내므로, 낮은 울림에도 중음 배음을 섞어 둔다 (tools/gen_sfx.gd 의 가드 소리 메모 참고).

const RATE := 22050


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://audio/sfx"))
	# 뿌리의 낮은 울림: 천천히 부풀었다 잦아드는 낮은 소리 + 흙이 스치는 중음 노이즈 (3.2초)
	_save("end_rumble", _mix([_swell_tone(3.2, 55.0, 0.55, 0.45), _swell_tone(3.2, 110.0, 0.35, 0.4), _swell_tone(3.2, 330.0, 0.08, 0.5),
		_swell_noise(3.2, 0.45, 420.0, 0.45), _swell_noise(3.2, 0.12, 1400.0, 0.55)]))
	# 잎 소리: 짧은 사각거림 알갱이 여럿 (1.8초)
	_save("end_leaves", _leaves(1.8, 14))
	# 등불이 꺼지는 작은 소리: 훅 하는 숨 + 아주 작은 유리 울림 (0.5초)
	_save("lamp_out", _mix([_swell_noise(0.32, 0.5, 1100.0, 0.25), _tone(0.5, 2350.0, 0.07, 9.0), _tone(0.4, 3520.0, 0.04, 12.0)]))
	# 펌프의 삐걱임: 낮은 톱니파가 끌리듯 내려가고 마지막에 쿵 (1.4초)
	_save("pump_creak", _mix([_creak(1.1, 150.0, 105.0, 0.32), _offset(_clunk(0.4, 0.8), 1.0)]))
	# 펌프의 고른 쿵: 박자에 맞춰 울릴 짧은 금속성 쿵 (0.35초)
	_save("pump_clunk", _clunk(0.35, 0.75))
	print("엔딩 효과음 5개 생성 완료")
	quit()


## 천천히 부풀었다(앞 peak 비율) 잦아드는 봉투
func _swell(u: float, peak: float) -> float:
	if u < peak:
		return sin(u / maxf(peak, 0.001) * PI * 0.5)
	return pow(maxf(1.0 - (u - peak) / maxf(1.0 - peak, 0.001), 0.0), 1.6)


func _swell_tone(dur: float, freq: float, vol: float, peak: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# 아주 느린 떨림 (살아 있는 나무의 울림)
		var wob := 1.0 + 0.08 * sin(TAU * 0.7 * t)
		out[i] = sin(TAU * freq * t) * vol * wob * _swell(t / dur, peak)
	return out


func _swell_noise(dur: float, vol: float, cutoff: float, peak: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff) * 7 + n
	var y := 0.0
	var k := clampf(cutoff / (RATE * 0.5), 0.01, 1.0)
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * k
		out[i] = y * vol * 2.5 * _swell(t / dur, peak)
	return out


func _leaves(dur: float, grains: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for g in grains:
		var start := int(rng.randf_range(0.0, dur - 0.25) * RATE)
		var glen := int(rng.randf_range(0.06, 0.2) * RATE)
		var cutoff := rng.randf_range(2200.0, 5200.0)
		var k := clampf(cutoff / (RATE * 0.5), 0.01, 1.0)
		var vol := rng.randf_range(0.15, 0.4)
		var y := 0.0
		var prev := 0.0
		for i in glen:
			var idx := start + i
			if idx >= n:
				break
			y += (rng.randf_range(-1.0, 1.0) - y) * k
			var hp := y - prev   # 높은 음역만 (사각사각)
			prev = y
			var u := float(i) / glen
			out[idx] += hp * vol * 6.0 * sin(u * PI)
	return out


func _creak(dur: float, f0: float, f1: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var f := lerpf(f0, f1, u) * (1.0 + 0.05 * sin(TAU * 11.0 * t))
		phase += TAU * f / RATE
		var saw := 2.0 * fmod(phase / TAU, 1.0) - 1.0
		# 마찰음처럼 끊기는 떨림
		var grit := 0.6 + 0.4 * absf(sin(TAU * 23.0 * t))
		out[i] = saw * vol * grit * _swell(u, 0.2)
	return out


func _clunk(dur: float, vol: float) -> PackedFloat32Array:
	return _mix([_tone_sweep(dur, 200.0, 85.0, vol, 9.0), _tone(dur * 0.6, 760.0, vol * 0.35, 22.0), _tone(dur * 0.5, 1180.0, vol * 0.18, 28.0), _noise(0.08, vol * 0.5, 30.0, 1600.0)])


func _offset(p: PackedFloat32Array, sec: float) -> PackedFloat32Array:
	var pad := int(sec * RATE)
	var out := PackedFloat32Array()
	out.resize(pad + p.size())
	for i in p.size():
		out[pad + i] = p[i]
	return out


func _tone(dur: float, freq: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * vol * exp(-decay * t) * minf(t / 0.003, 1.0)
	return out


func _tone_sweep(dur: float, f0: float, f1: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / dur) / RATE
		out[i] = sin(phase) * vol * exp(-decay * t) * minf(t / 0.003, 1.0)
	return out


func _noise(dur: float, vol: float, decay: float, cutoff: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff) + n
	var y := 0.0
	var k := clampf(cutoff / (RATE * 0.5), 0.01, 1.0)
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * k
		out[i] = y * vol * exp(-decay * t) * 2.5
	return out


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out


func _save(name: String, samples: PackedFloat32Array) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var gain := minf(0.9 / peak, 1.0)
	# 끝 10ms 를 부드럽게 줄여 '틱' 소리를 막는다
	var tail := mini(int(0.01 * RATE), samples.size())
	for i in samples.size():
		var g := gain
		var left := samples.size() - i
		if left < tail:
			g *= float(left) / tail
		bytes.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 32767.0))
	wav.data = bytes
	wav.save_to_wav(ProjectSettings.globalize_path("res://audio/sfx/%s.wav" % name))
	print("  audio/sfx/%s.wav  %.2f초" % [name, samples.size() / float(RATE)])
