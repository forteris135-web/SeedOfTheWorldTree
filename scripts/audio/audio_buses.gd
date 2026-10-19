class_name AudioBuses
## 소리 버스: Master ← Music(음악) / SFX(효과음). 배치는 res://default_bus_layout.tres 에 있고, 없으면 ensure() 가 만든다.
## 설정의 음량(0~10)은 각 버스의 음량만 바꾼다 — 음악 음량은 음악만, 효과음 음량은 효과음만, 전체 음량은 둘 다.
## (2026-10-19 전엔 효과음 음량이 Master 버스를 바꿔 음악까지 작아졌다.)

const MASTER := "Master"
const MUSIC := "Music"
const SFX := "SFX"
## 설정 키 → 버스
const SETTING_BUS := {"master_volume": MASTER, "music_volume": MUSIC, "sfx_volume": SFX}


## Music·SFX 버스가 없으면 만든다 (Master 로 보냄).
static func ensure() -> void:
	for n in [MUSIC, SFX]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, MASTER)


## 설정 값(0~10) → 버스 음량(dB). 진폭이 값에 비례한다 (10 = 0dB, 5 = -6dB, 1 = -20dB). 0 은 끔.
static func slider_db(v: int) -> float:
	if v <= 0:
		return -80.0
	return linear_to_db(clampf(v / 10.0, 0.0, 1.0))


## 설정 사전(Settings.data)의 음량을 버스에 반영한다. 없는 키는 그 버스를 0dB 로 둔다.
static func apply(settings: Dictionary) -> void:
	ensure()
	for key in SETTING_BUS:
		var idx := AudioServer.get_bus_index(SETTING_BUS[key])
		if idx < 0:
			continue
		var v := int(settings.get(key, 10))
		AudioServer.set_bus_volume_db(idx, slider_db(v))
		AudioServer.set_bus_mute(idx, v <= 0)


## 버스 음량 (dB, 시험용). 꺼져 있으면 -80.
static func bus_db(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	return -80.0 if AudioServer.is_bus_mute(idx) else AudioServer.get_bus_volume_db(idx)
