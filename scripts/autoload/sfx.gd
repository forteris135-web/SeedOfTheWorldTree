extends Node
## 효과음 재생. audio/sfx/<이름>.wav 를 이름으로 튼다. 소리는 'SFX' 버스로 흐르고, 설정의 효과음 음량은 그 버스만 바꾼다
## (Settings → AudioBuses.apply). 효과음을 따로 트는 다른 플레이어도 bus = Sfx.BUS 로 둔다.

const DIR := "res://audio/sfx/"
## 효과음 버스 이름 (AudioBuses.SFX 와 같음)
const BUS := "SFX"
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
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
