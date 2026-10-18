extends Node
## 효과음 재생. audio/sfx/<이름>.wav 를 이름으로 튼다. 음량은 설정을 따른다.

const DIR := "res://audio/sfx/"
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	var dir := DirAccess.open(DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".wav") or f.ends_with(".wav.import"):
				var name := f.get_basename().get_basename() if f.ends_with(".import") else f.get_basename()
				if not _streams.has(name):
					var st := load(DIR + name + ".wav")
					if st:
						_streams[name] = st
	Settings.changed.connect(_apply_volume)
	_apply_volume()


func _apply_volume() -> void:
	var v := float(Settings.get_value("sfx_volume")) / 10.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)


func play(name: String, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	var st: AudioStream = _streams.get(name)
	if st == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
