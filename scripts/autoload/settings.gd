extends Node
## 설정. user://settings.json 에 저장. 바뀌면 changed 신호로 알린다.
## 음량 세 가지(전체·음악·효과음, 0~10)는 바뀔 때마다 소리 버스에 바로 반영한다 (AudioBuses: Master / Music / SFX).

signal changed

const PATH := "user://settings.json"

var data := {
	"lenient_guard": false,   # 저스트 가드 판정 넉넉하게
	"sfx_volume": 8,          # 0~10 (SFX 버스)
	"music_volume": 7,        # 0~10 (Music 버스)
	"master_volume": 10,      # 0~10 (Master 버스: 음악과 효과음 모두)
	"touch_scale": 1,         # 0 작게 / 1 보통 / 2 크게
	"debug_hud": false,       # 개발 표시
	"screen_shake": true,
}


func _ready() -> void:
	changed.connect(_apply_audio)
	load_settings()


func _apply_audio() -> void:
	AudioBuses.apply(data)


func get_value(key: String):
	return data.get(key)


func set_value(key: String, value) -> void:
	data[key] = value
	save_settings()
	changed.emit()


func load_settings() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				if data.has(k):
					data[k] = d[k]
	changed.emit()


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func touch_scale_factor() -> float:
	return [0.85, 1.0, 1.2][clampi(int(data.get("touch_scale", 1)), 0, 2)]
