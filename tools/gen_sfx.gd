extends SceneTree
## 임시 효과음을 코드로 합성해 audio/sfx/*.wav 로 저장한다. (나중에 무료 에셋으로 바꿔도 이름만 같으면 된다)
## 사용: Godot --headless --path . --script tools/gen_sfx.gd

const RATE := 22050


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://audio/sfx"))
	_save("jump", _tone_sweep(0.14, 320.0, 640.0, 0.6, 2.0))
	_save("land", _noise(0.09, 0.5, 14.0, 900.0))
	_save("step", _noise(0.04, 0.18, 30.0, 1400.0))
	_save("roll", _noise(0.2, 0.35, 8.0, 500.0))
	_save("swing", _noise(0.13, 0.4, 10.0, 2500.0))
	_save("hit", _mix([_noise(0.1, 0.6, 18.0, 1800.0), _tone_sweep(0.12, 180.0, 90.0, 0.7, 10.0)]))
	_save("heavy_hit", _mix([_noise(0.16, 0.7, 12.0, 1200.0), _tone_sweep(0.2, 140.0, 60.0, 0.9, 7.0)]))
	# 일반 가드: 잘 들리는 나무 방패 막는 소리 (둔탁음 + 중음 짧은 감쇠 + 노이즈 버스트). 2026-10-18 전엔 0.08초짜리라 안 들렸다.
	# 둔탁음은 180Hz 가 아니라 280Hz: 폰 스피커는 400Hz 아래를 거의 못 내는데 180Hz 가 피크를 차지해 들리는 대역이 깎였다 (검토).
	_save("guard", _mix([_tone(0.16, 280.0, 0.5, 14.0), _tone(0.12, 820.0, 0.6, 26.0), _noise(0.08, 0.7, 28.0, 2200.0)]))
	# 씨앗 베기: 길고 무거운, 바람을 가르는 소리 (부풀었다 잦아드는 휘파람 노이즈 + 낮은 울림)
	_save("slash_wide", _mix([_whoosh(0.5, 0.7, 600.0, 2600.0, 0.3), _tone_sweep(0.4, 140.0, 70.0, 0.35, 5.0)]))
	# 낙하 공격: 떨어지는 휘파람 (높은 데서 낮은 데로) + 바람
	_save("plunge", _mix([_tone_sweep(0.32, 1100.0, 320.0, 0.3, 3.0), _whoosh(0.3, 0.45, 2400.0, 900.0, 0.5)]))
	_save("just_guard", _mix([_tone(0.5, 1320.0, 0.55, 5.0), _tone(0.45, 1980.0, 0.35, 6.0), _tone(0.35, 2640.0, 0.25, 8.0), _noise(0.04, 0.5, 40.0, 4000.0)]))
	_save("guard_break", _mix([_noise(0.3, 0.6, 6.0, 700.0), _tone_sweep(0.3, 300.0, 80.0, 0.6, 5.0)]))
	_save("hurt", _tone_sweep(0.22, 240.0, 110.0, 0.6, 6.0, true))
	_save("heal", _arp([523.25, 659.25, 783.99, 1046.5], 0.14, 0.4))
	_save("purify", _mix([_arp([392.0, 523.25, 659.25, 783.99, 1046.5, 1318.5], 0.16, 0.35), _tone(1.2, 196.0, 0.25, 1.5)]))
	_save("soul", _mix([_tone(0.9, 880.0, 0.3, 2.5), _tone(0.9, 1108.7, 0.25, 2.5), _tone(0.9, 1318.5, 0.2, 2.5)]))
	_save("select", _tone(0.07, 880.0, 0.35, 25.0))
	_save("blip", _tone(0.03, 1100.0, 0.25, 40.0))
	_save("broke", _mix([_tone_sweep(0.35, 500.0, 200.0, 0.5, 5.0), _noise(0.12, 0.4, 14.0, 900.0)]))
	_save("boss_fall", _mix([_noise(0.6, 0.6, 4.0, 400.0), _tone_sweep(0.7, 90.0, 40.0, 0.9, 3.0)]))
	_save("bloom", _arp([659.25, 783.99, 987.77, 1318.5], 0.22, 0.3))
	_save("gust", _noise(0.25, 0.4, 6.0, 1600.0))
	_save("thorn", _mix([_noise(0.08, 0.5, 20.0, 2200.0), _tone_sweep(0.15, 300.0, 120.0, 0.5, 8.0)]))
	# ---- 등불 기사 (2026-10-19) ----
	# 창 휘두르기: 무겁고 긴 바람 가르는 소리 (낮게 부풀었다 잦아듦)
	_save("spear_whoosh", _mix([_whoosh(0.42, 0.7, 400.0, 1900.0, 0.35), _tone_sweep(0.3, 110.0, 60.0, 0.3, 6.0)]))
	# 검기: 밝은 베기(높은 휘파람) + 금속 울림 + 빛의 떨림
	_save("sword_wave", _mix([_whoosh(0.36, 0.6, 1800.0, 5200.0, 0.2), _tone(0.5, 1760.0, 0.3, 6.0), _tone(0.45, 2637.0, 0.2, 7.0), _tone_sweep(0.25, 420.0, 180.0, 0.35, 8.0)]))
	# 돌진: 발 끌림 노이즈 + 낮은 울림이 치솟음
	_save("charge_dash", _mix([_whoosh(0.6, 0.6, 300.0, 1400.0, 0.5), _tone_sweep(0.5, 70.0, 160.0, 0.4, 3.0)]))
	# 창이 벽에 박힘: 둔탁한 충격 + 금속 쇳소리 + 돌가루
	_save("spear_stuck", _mix([_tone_sweep(0.3, 220.0, 70.0, 0.8, 7.0), _tone(0.35, 1480.0, 0.35, 12.0), _tone(0.25, 2210.0, 0.2, 16.0), _noise(0.18, 0.6, 12.0, 1500.0)]))
	print("효과음 생성 완료")
	quit()


func _env(t: float, dur: float, decay: float) -> float:
	var a := minf(t / 0.004, 1.0)
	return a * exp(-decay * t / dur * dur) if dur > 0.3 else a * exp(-decay * t)


func _tone(dur: float, freq: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * vol * exp(-decay * t)
	return out


func _tone_sweep(dur: float, f0: float, f1: float, vol: float, decay: float, saw := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		phase += TAU * f / RATE
		var v := sin(phase)
		if saw:
			v = 2.0 * fmod(phase / TAU, 1.0) - 1.0
		out[i] = v * vol * exp(-decay * t)
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


## 바람 가르는 소리: 필터 컷오프가 f0→f1 로 움직이는 노이즈에, peak(0~1) 지점에서 가장 커지는 부푼 봉투를 씌운다.
func _whoosh(dur: float, vol: float, f0: float, f1: float, peak: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 + f1) + n
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var cutoff := lerpf(f0, f1, u)
		var k := clampf(cutoff / (RATE * 0.5), 0.01, 1.0)
		y += (rng.randf_range(-1.0, 1.0) - y) * k
		var env := 0.0
		if u < peak:
			env = pow(u / maxf(peak, 0.001), 1.4)
		else:
			env = pow(1.0 - (u - peak) / maxf(1.0 - peak, 0.001), 1.8)
		out[i] = y * vol * env * 2.5
	return out


func _arp(freqs: Array, step: float, vol: float) -> PackedFloat32Array:
	var total := step * freqs.size() + 0.5
	var n := int(total * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in freqs.size():
		var start := int(k * step * RATE)
		for i in range(start, n):
			var t := float(i - start) / RATE
			out[i] += sin(TAU * freqs[k] * t) * vol * exp(-3.5 * t)
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
	for i in samples.size():
		var v := int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	wav.save_to_wav(ProjectSettings.globalize_path("res://audio/sfx/%s.wav" % name))
