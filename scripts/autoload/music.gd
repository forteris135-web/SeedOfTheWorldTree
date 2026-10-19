extends Node
## 음악 재생. 두 플레이어를 번갈아 써서 부드럽게 바꾼다(크로스페이드). 반복 곡은 끊김 없이 돈다.
## 지금 곡들은 Claude Code가 합성한 임시곡(tools/gen_music.swift). 기획자의 주제곡이 오면 같은 이름으로 바꿔 끼운다.
## 이름: theme_a / theme_ab / theme_full / theme_ending / theme_battle / ambient_<지역> / boss_bird / boss_knight / boss_root

const DIR := "res://audio/music/"
const LOOPING := ["theme_a", "theme_ab", "theme_full", "theme_battle", "ambient_canopy", "ambient_village", "ambient_mine", "ambient_abyss", "boss_bird", "boss_knight", "boss_root", "ambient_flooded_mine", "boss_iron_pump", "boss_iron_pump_2"]

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""
var _tween: Tween
var _latency := -1.0
## 회상 주제곡 붙잡기 (hold): 이 곡이 이 재생 위치(초)에 닿을 때까지는 play_region 이 곡을 바꾸지 않고 기다린다.
## 회상 장면은 27초 남짓이라, 정화한 보스 수에 따라 31 / 43 / 54 / 73.5 / 77초로 늘어나는 주제곡이 그 전에 끊겼다
## (2026-10-19 검수) → 곡은 회상이 끝난 뒤 방에서도 정해진 길이까지 이어지고, 그다음 지역곡으로 넘어간다.
var _hold_name := ""
var _hold_until := 0.0
var _pending_region := ""
var _hold_t0 := 0.0       # 붙잡기 시작한 시각 (Time 초)
var _hold_pos0 := 0.0     # 그때의 재생 위치
const HOLD_FADE := 1.5


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


## 지금 곡이 name 이면 그 곡의 재생 위치(초, 귀에 들리는 소리 기준), 아니면 -1.
## 박자에 맞춰 움직이는 보스(수액의 여왕)가 읽는다 — 히트스톱·일시정지 동안에도 음악은 흐르므로 보스가 음악을 따라간다.
func playback_time(name: String) -> float:
	if name == "" or name != _current:
		return -1.0
	var p := _players[_active]
	if p.stream == null or not p.playing:
		return -1.0
	if _latency < 0.0:
		_latency = AudioServer.get_output_latency()   # 비싸서 한 번만 잰다
	return maxf(p.get_playback_position() + AudioServer.get_time_since_last_mix() - _latency, 0.0)


## 지금 곡의 길이(초). 곡이 없으면 0.
func current_length() -> float:
	var p := _players[_active]
	if _current == "" or p.stream == null:
		return 0.0
	return p.stream.get_length()


func _target_db() -> float:
	var v := float(Settings.get_value("music_volume")) / 10.0
	return linear_to_db(maxf(v, 0.0001)) - 6.0 if v > 0.0 else -80.0


func _apply_volume() -> void:
	if _tween and _tween.is_running():
		return
	_players[_active].volume_db = _target_db() if _current != "" else -80.0


## 지금 곡(name)을 재생 위치 until_sec 까지 붙잡는다. 그사이 play_region 은 미뤄졌다가 끝날 때 이어서 튼다.
## (다른 곡을 play 하거나 stop 하면 붙잡기는 풀린다.)
func hold(name: String, until_sec: float) -> void:
	if name == "" or name != _current:
		return
	var length := current_length()
	_hold_name = name
	_hold_until = minf(until_sec, length) if (until_sec > 0.0 and length > 0.0) else (until_sec if until_sec > 0.0 else length)
	_pending_region = ""
	_hold_t0 = Time.get_ticks_msec() / 1000.0
	_hold_pos0 = maxf(playback_time(name), 0.0)


## 붙잡은 곡이 남았는가 (시험용)
func is_holding() -> bool:
	return _hold_name != ""


func _process(_delta: float) -> void:
	if _hold_name == "":
		return
	if _current != _hold_name:
		_hold_name = ""
		return
	# 재생 위치 (소리 장치가 없는 화면 없는 시험에서는 위치가 멈춰 있을 수 있어 흐른 시간으로도 잰다)
	var t := maxf(playback_time(_hold_name), _hold_pos0 + Time.get_ticks_msec() / 1000.0 - _hold_t0)
	if t >= _hold_until - HOLD_FADE:
		var next := _pending_region
		_hold_name = ""
		_pending_region = ""
		if next != "":
			_play_region_now(next, HOLD_FADE)
		else:
			play("", HOLD_FADE)


## 곡을 튼다. 같은 곡이면 그대로 둔다. fade 는 초.
func play(name: String, fade := 1.5, from_start := false) -> void:
	# 다른 곳에서 곡을 직접 고르면(보스곡·타이틀·엔딩·정적) 회상 곡 붙잡기는 끝난다
	_hold_name = ""
	_pending_region = ""
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


## 지역 배경음악. 회상 주제곡을 붙잡고 있으면 그 곡이 끝날 때까지 미룬다.
func play_region(region: String) -> void:
	if _hold_name != "" and _hold_name == _current:
		_pending_region = region
		return
	_play_region_now(region, 2.0)


func _play_region_now(region: String, fade: float) -> void:
	var name := "ambient_" + region
	if not ResourceLoader.exists(DIR + name + ".wav"):
		# 확장 지역의 곡이 아직 없으면 가까운 지역곡으로 (수액의 호수 → 심연, 잠긴 채굴장 → 채굴장)
		name = "ambient_" + {"sap_lake": "abyss", "flooded_mine": "mine"}.get(region, "canopy")
	play(name, fade)
