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
	_save("guard", _mix([_tone(0.08, 420.0, 0.5, 20.0), _noise(0.05, 0.3, 30.0, 1000.0)]))
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
