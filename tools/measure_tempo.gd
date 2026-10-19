extends SceneTree
## 곡의 템포와 첫 강박을 잰다 (수액의 여왕처럼 박자에 맞춰 움직이는 보스의 상수를 정할 때).
## 사용: <godot> --headless --path . -s res://tools/measure_tempo.gd -- <wav 경로> [최저 bpm] [최고 bpm] [예상 bpm]
##   예) .../godot --headless --path . -s res://tools/measure_tempo.gd -- res://audio/music/boss_sap_queen.wav 60 220
## 방법: 10ms 단위로 에너지(전체·낮은 음역·높은 음역) → 로그 에너지가 늘어나는 정도(시작점 곡선) → 자기상관으로 대략의 박 →
##   박 길이 후보마다 곡 전체를 접어(fold) 가장 뾰족한 박 길이·위상 → 박 자리 둘레 무게중심으로 위상 다듬기 →
##   네 구간별 어긋남(템포가 흔들리는지) → 낮은 음 시작점을 박 번호 mod 3 / 4 / 2 로 모아 강박(마디 첫 박) 찾기.
## 16비트 스테레오 PCM WAV 만 읽는다 (기획자의 원본 형식). 결과는 [tempo] 줄로 찍는다.
## 2026-10-19 잰 값: boss_sap_queen 137.99bpm · 3/4 · 첫 강박 0.123초 / boss_iron_pump 124.48bpm · 4/4 · 첫 박 0.36초
##   / boss_bird 75bpm / boss_knight 60bpm.
const HOP := 480   # 48kHz 에서 10ms

static func read_wav(path: String) -> PackedInt32Array:
	var fa := FileAccess.open(path, FileAccess.READ)
	fa.seek(12)
	while fa.get_position() < fa.get_length():
		var id := fa.get_buffer(4).get_string_from_ascii()
		var sz := fa.get_32()
		if id == "data":
			return fa.get_buffer(sz).to_int32_array()
		fa.seek(fa.get_position() + sz + (sz & 1))
	return PackedInt32Array()

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("[tempo] 사용: -- <wav 경로> [최저 bpm] [최고 bpm] [예상 bpm]")
		quit(1)
		return
	var path: String = args[0]
	if path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	var bpm_lo := float(args[1]) if args.size() > 1 else 60.0
	var bpm_hi := float(args[2]) if args.size() > 2 else 200.0
	var ints := read_wav(path)
	var n := ints.size()
	var hops := n / HOP
	var e_full := PackedFloat32Array(); e_full.resize(hops)
	var e_low := PackedFloat32Array(); e_low.resize(hops)
	var e_hi := PackedFloat32Array(); e_hi.resize(hops)
	var lp := 0.0
	var a_lp := 1.0 - exp(-TAU * 180.0 / 48000.0)
	var prev := 0.0
	for h in hops:
		var sf := 0.0; var sl := 0.0; var sh := 0.0
		var base := h * HOP
		for i in HOP:
			var v := ints[base + i]
			var m := float(((v << 48) >> 48) + (v >> 16)) * 0.5
			lp += a_lp * (m - lp)
			var d := m - prev
			prev = m
			sf += m * m; sl += lp * lp; sh += d * d
		e_full[h] = sf; e_low[h] = sl; e_hi[h] = sh
	# 시작점 곡선: 로그 에너지 증가분 (반파 정류)
	var onset := PackedFloat32Array(); onset.resize(hops)
	var onset_low := PackedFloat32Array(); onset_low.resize(hops)
	for h in range(1, hops):
		var o := 0.0
		o += maxf(0.0, log(e_full[h] + 1.0) - log(e_full[h - 1] + 1.0))
		o += maxf(0.0, log(e_hi[h] + 1.0) - log(e_hi[h - 1] + 1.0))
		var ol := maxf(0.0, log(e_low[h] + 1.0) - log(e_low[h - 1] + 1.0))
		onset[h] = o + ol
		onset_low[h] = ol
	# 평균 빼기
	var mean := 0.0
	for h in hops: mean += onset[h]
	mean /= hops
	var oc := PackedFloat32Array(); oc.resize(hops)
	for h in hops: oc[h] = onset[h] - mean
	# 자기상관 (박 후보)
	var lag_lo := int(floor(6000.0 / bpm_hi)); var lag_hi := int(ceil(6000.0 / bpm_lo))
	var ac := []
	for lag in range(lag_lo, lag_hi + 1):
		var s := 0.0
		for h in range(0, hops - lag):
			s += oc[h] * oc[h + lag]
		ac.append([s, lag])
	ac.sort_custom(func(a, b): return a[0] > b[0])
	var tops := []
	for k in 6: tops.append("%d(%.0fbpm %.1f)" % [ac[k][1], 6000.0 / ac[k][1], ac[k][0]])
	print("[tempo] %s  %.2fs  자기상관 상위: %s" % [path.get_file(), n / 48000.0, tops])
	# 정밀: 접기 히스토그램
	var best := [-1.0, 0.0, 0.0]
	var p0: float = ac[0][1]
	if args.size() > 3:
		p0 = 6000.0 / float(args[3])
	var BINS := 96
	var p := p0 - 1.5
	while p <= p0 + 1.5:
		var hist := PackedFloat32Array(); hist.resize(BINS)
		for h in hops:
			var ph := fmod(float(h), p) / p
			hist[int(ph * BINS) % BINS] += onset[h]
		# 둥근 평활 (3칸)
		var bmax := -1.0; var bi := 0
		for b in BINS:
			var s := hist[(b - 1 + BINS) % BINS] * 0.5 + hist[b] + hist[(b + 1) % BINS] * 0.5
			if s > bmax: bmax = s; bi = b
		# 날카로움: 최대 / 평균
		var tot := 0.0
		for b in BINS: tot += hist[b]
		var sharp := bmax / (tot / BINS * 2.0)
		if sharp > best[0]:
			best = [sharp, p, (bi + 0.5) / BINS * p]
		p += 0.002
	var P: float = best[1]
	var phase: float = best[2]
	print("[tempo] 박 길이 %.4f hop = %.5f초 = %.3f bpm, 위상 %.3f초, 날카로움 %.2f" % [P, P * 0.01, 6000.0 / P, phase * 0.01, best[0]])
	# 위상 미세 조정: 박 자리 ±4 hop 안의 시작점 무게중심
	var sum_w := 0.0; var sum_d := 0.0
	var k := 0
	while phase + k * P < hops - 5:
		var c := phase + k * P
		for dh in range(-4, 5):
			var hh := int(round(c)) + dh
			if hh >= 0 and hh < hops:
				sum_w += onset[hh]; sum_d += onset[hh] * (hh - c)
		k += 1
	phase += sum_d / maxf(sum_w, 0.0001)
	print("[tempo] 위상(무게중심 보정) %.3f초, 박 수 %d" % [phase * 0.01, k])
	# 구간별 위상 (흔들림 확인): 4 구간
	for seg in 4:
		var a := hops * seg / 4; var b := hops * (seg + 1) / 4
		var sw := 0.0; var sd := 0.0
		var kk := int(ceil((a - phase) / P))
		while phase + kk * P < b - 5:
			var c := phase + kk * P
			for dh in range(-8, 9):
				var hh := int(round(c)) + dh
				if hh >= 0 and hh < hops:
					sw += onset[hh]; sd += onset[hh] * (hh - c)
			kk += 1
		print("[tempo]   구간 %d (%.0f~%.0f초): 박 자리 어긋남 평균 %+.1f ms" % [seg, a * 0.01, b * 0.01, sd / maxf(sw, 0.0001) * 10.0])
	# 강박 찾기: 낮은 음역 시작점 + 전체 시작점을 박 번호 mod 3, mod 4 로
	for meter in [3, 4, 2]:
		var acc_l := []; var acc_f := []
		for r in meter: acc_l.append(0.0); acc_f.append(0.0)
		var kb := 0
		while phase + kb * P < hops - 5:
			var c := int(round(phase + kb * P))
			var sl2 := 0.0; var sf2 := 0.0
			for dh in range(-3, 4):
				var hh := c + dh
				if hh >= 0 and hh < hops:
					sl2 += onset_low[hh]; sf2 += onset[hh]
			acc_l[kb % meter] += sl2; acc_f[kb % meter] += sf2
			kb += 1
		var sl_txt := []; var sf_txt := []
		for r in meter:
			sl_txt.append("%.1f" % acc_l[r]); sf_txt.append("%.1f" % acc_f[r])
		print("[tempo]   %d박 묶음: 낮은음 시작점 %s / 전체 %s (박 번호 0 = %.3f초)" % [meter, sl_txt, sf_txt, phase * 0.01])
	# 구간별 3박 묶음 (곡 중간에 마디가 밀리지 않았는지: 모든 구간에서 같은 자리가 가장 세야 한다)
	for seg in 6:
		var a := hops * seg / 6; var b := hops * (seg + 1) / 6
		var acc := [0.0, 0.0, 0.0]
		var kb := int(ceil((a - phase) / P))
		while phase + kb * P < b - 5:
			var c := int(round(phase + kb * P))
			for dh in range(-3, 4):
				var hh := c + dh
				if hh >= 0 and hh < hops:
					acc[kb % 3] += onset_low[hh]
			kb += 1
		print("[tempo]   구간 %d (%.0f~%.0f초) 3박 묶음 낮은음: %.1f / %.1f / %.1f" % [seg, a * 0.01, b * 0.01, acc[0], acc[1], acc[2]])
	# 앞 20박의 시작점 세기 (눈으로 보기)
	var line := []
	for kb in 24:
		var c := int(round(phase + kb * P))
		var s := 0.0; var sl3 := 0.0
		for dh in range(-3, 4):
			var hh := c + dh
			if hh >= 0 and hh < hops: s += onset[hh]; sl3 += onset_low[hh]
		line.append("%d:%.1f/%.1f" % [kb, s, sl3])
	print("[tempo]   앞 24박 (전체/낮은음): %s" % [line])
	quit()
