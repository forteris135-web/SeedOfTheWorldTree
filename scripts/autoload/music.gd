extends Node
## 음악 재생. 두 플레이어를 번갈아 써서 부드럽게 바꾼다(크로스페이드). 반복 곡은 끊김 없이 돈다.
## 지금 곡들은 Claude Code가 합성한 임시곡(tools/gen_music.swift). 기획자의 주제곡이 오면 같은 이름으로 바꿔 끼운다.
## 이름: theme_a / theme_ab / theme_full / theme_ending / theme_battle / ambient_<지역> / boss_bird / boss_knight / boss_root

const DIR := "res://audio/music/"
const LOOPING := ["theme_a", "theme_ab", "theme_full", "theme_battle", "ambient_canopy", "ambient_village", "ambient_mine", "ambient_abyss", "boss_bird", "boss_knight", "boss_root"]

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	Settings.changed.connect(_apply_volume)


func current() -> String:
	return _current


func _target_db() -> float:
	var v := float(Settings.get_value("music_volume")) / 10.0
	return linear_to_db(maxf(v, 0.0001)) - 6.0 if v > 0.0 else -80.0


func _apply_volume() -> void:
	if _tween and _tween.is_running():
		return
	_players[_active].volume_db = _target_db() if _current != "" else -80.0


## 곡을 튼다. 같은 곡이면 그대로 둔다. fade 는 초.
func play(name: String, fade := 1.5, from_start := false) -> void:
	if name == _current and not from_start:
		return
	var stream: AudioStream = load(DIR + name + ".wav") if name != "" else null
	if name != "" and stream == null:
		return
	if stream is AudioStreamWAV and name in LOOPING:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2   # 16비트 모노
	var old := _players[_active]
	_active = 1 - _active
	var nw := _players[_active]
	_current = name
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(old, "volume_db", -80.0, fade).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(old.stop).set_delay(fade)
	if stream:
		nw.stream = stream
		nw.volume_db = -80.0
		nw.play()
		_tween.tween_property(nw, "volume_db", _target_db(), fade).set_trans(Tween.TRANS_SINE)


func stop(fade := 1.0) -> void:
	play("", fade)


## 지역 배경음악
func play_region(region: String) -> void:
	var name := "ambient_" + region
	if not ResourceLoader.exists(DIR + name + ".wav"):
		# 확장 지역의 곡이 아직 없으면 가까운 지역곡으로 (수액의 호수 → 심연, 잠긴 채굴장 → 채굴장)
		name = "ambient_" + {"sap_lake": "abyss", "flooded_mine": "mine"}.get(region, "canopy")
	play(name, 2.0)
