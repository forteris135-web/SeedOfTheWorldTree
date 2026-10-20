extends Node
## 음악 재생 (자동 로드 Music). 두 플레이어를 번갈아 써서 부드럽게 바꾼다(크로스페이드).
## 곡: 기획자의 정식 곡 18곡 (audio/music/*.wav, 48kHz 스테레오 → 가져올 때 QOA 압축, .import 의 compress/mode=2).
##   반복은 각 곡의 .import 설정을 따른다: 곡 전체를 앞으로 반복(edit/loop_mode=2). selenia_humming 만 한 번만(loop_mode=1) —
##   엔딩 마지막 장면부터 크레딧까지 한 번 흐르는 곡이라서 (ENDINGS.md 0장). 클리어 후 타이틀에서는 이번 재생만 반복으로 바꿔 튼다.
## 소리는 'Music' 버스로 흐른다 → 설정의 음악 음량은 이 버스만 바꾼다 (AudioBuses, default_bus_layout.tres). 효과음은 'SFX' 버스.
##
## 쓰는 법
##   Music.play(name, opts)      곡을 튼다. 같은 곡이 흐르고 있으면 그대로 둔다(방을 옮겨도 다시 시작하지 않는다).
##                                opts 는 사전: {"fade": 초(기본 1.5), "from": 시작 위치(초; 주면 같은 곡이어도 그 자리부터 다시),
##                                "restart": true(같은 곡이어도 처음부터), "loop": true/false(이번 재생만 반복 여부를 바꿈; 없으면 .import 설정)}
##                                옛 방식 play(name, fade, from_start) 도 그대로 된다.
##   Music.stop(fade)            조용히 끈다 (보스가 쓰러질 때의 정적 등)
##   Music.enter_room(region, room_id, field_now, resting)   방에 들어설 때 (Room 이 부른다)
##   Music.play_region(region, room_id)   지역의 들판 곡 (region_track 표)
##   Music.rest_begin() / rest_end()      달빛풀에서 쉬는 동안 쉼터 곡 → 일어서면 들판 곡
##   Music.hold(name, seconds)            회상 곡을 방으로 돌아온 뒤에도 seconds 초 더 붙잡았다가 들판 곡으로 넘긴다
##   Music.falter(depth, time)            곡이 잠깐 휘청인다 (무쇠 펌프 2페이즈: 규칙이 무너지는 순간)
##   Music.title_track(cleared) / region_track(region, room_id) / playback_time(name) / current() / current_length()

const DIR := "res://audio/music/"
## 음악 버스 이름 (AudioBuses.MUSIC 과 같음)
const BUS := "Music"
## 플레이어 기본 음량 (dB). 음량 설정은 버스가 맡고, 이 값은 효과음과의 균형용.
const BASE_DB := -6.0

## 곡 이름 (audio/music/<이름>.wav)
const TITLE := "title"
const ENDING_TRACK := "selenia_humming"     # 세 엔딩 공통 + 클리어 후 타이틀 (ENDINGS.md 0장 ③⑤)
const RECOLLECTION := "recollection"        # 보스 회상 씬
const REST := "rest_moonlight_grass"        # 달빛풀에서 쉬는 동안
const CANOPY_RESTORED := "field_canopy_restored"
## 수관 곡이 '되살아난 수관'으로 바뀌는 깃발 (잎새의 새를 정화함)
const CANOPY_RESTORED_FLAG := "boss_bird_defeated"
## 지역 → 들판 곡. 숨은 내리막(hidden_descent)은 지역이 sap_lake 라 수액의 호수 곡 (호수로 내려가는 길, EXPANSION.md 2장).
const REGION_TRACKS := {
	"canopy": "field_canopy",
	"village": "field_village",
	"mine": "field_mine",
	"abyss": "field_abyss",
	"sap_lake": "field_sap_lake",
	"flooded_mine": "field_flooded_mine",
}
## 방 하나만 다른 곡을 쓰는 곳 (room_id → 곡). 달빛 정원은 지역이 심연이지만 자기 곡이 있다.
const ROOM_TRACKS := {
	"moon_garden": "field_moon_garden",
}
## 게임이 쓰는 곡 전부 (시험·음악 감상용 목록)
const TRACKS := [
	"title", "field_canopy", "field_canopy_restored", "field_village", "field_mine", "field_abyss", "field_moon_garden",
	"field_sap_lake", "field_flooded_mine", "rest_moonlight_grass", "recollection",
	"boss_bird", "boss_knight", "boss_rootkeeper_p1", "boss_rootkeeper_p2", "boss_sap_queen", "boss_iron_pump",
	"selenia_humming",
]

## 회상 곡을 붙잡았다가 들판 곡으로 넘어갈 때의 페이드 (초)
const HOLD_FADE := 4.0

var _players: Array[AudioStreamPlayer] = []
var _names := ["", ""]      # 각 플레이어에 실린 곡 이름
var _active := 0
var _current := ""
var _tween: Tween
var _pitch_tween: Tween
var _latency := -1.0
## 지금 방의 지역·방 이름 (쉼이 끝나거나 회상 곡을 놓을 때 돌아갈 들판 곡을 정한다)
var _region := ""
var _room_id := ""
var _resting := false
## 회상 곡 붙잡기: _hold_name 이 흐르는 동안 들판 곡 요청은 미뤘다가, 첫 요청 뒤 _hold_seconds 초가 지나면 넘긴다.
var _hold_name := ""
var _hold_seconds := 0.0
var _hold_release_ms := -1   # 넘길 시각 (Time.get_ticks_msec), -1 = 아직 들판 곡 요청이 안 왔다
var _pending_region := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


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


## 지금 곡이 반복하는가 (시험용)
func current_loops() -> bool:
	var p := _players[_active]
	return _current != "" and p.stream is AudioStreamWAV and (p.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED


# ---------- 곡 고르기 ----------

## 지역(과 방)의 들판 곡 이름. 수관은 잎새의 새를 정화한 뒤 '되살아난 수관' 곡.
func region_track(region: String, room_id := "") -> String:
	if ROOM_TRACKS.has(room_id):
		return ROOM_TRACKS[room_id]
	if region == "canopy" and Progress.has(CANOPY_RESTORED_FLAG):
		return CANOPY_RESTORED
	return REGION_TRACKS.get(region, REGION_TRACKS["canopy"])


## 타이틀 곡: 클리어 전 title, 엔딩을 하나라도 본 뒤 selenia_humming (ENDINGS.md 5장).
static func title_track(cleared: bool) -> String:
	return ENDING_TRACK if cleared else TITLE


# ---------- 재생 ----------

## 곡을 튼다. 같은 곡이면 그대로 둔다. opts: 페이드 초(숫자) 또는 사전 {fade, from, restart, loop} — 맨 위 설명 참고.
func play(name: String, opts: Variant = 1.5, from_start := false) -> void:
	var fade := 1.5
	var restart := from_start
	var from := 0.0
	var loop := -1
	if opts is Dictionary:
		var o: Dictionary = opts
		fade = float(o.get("fade", 1.5))
		restart = bool(o.get("restart", o.has("from")))
		from = maxf(float(o.get("from", 0.0)), 0.0)
		if o.has("loop"):
			loop = 1 if o["loop"] else 0
	else:
		fade = float(opts)
	# 다른 곳에서 곡을 직접 고르면(보스곡·타이틀·회상·엔딩·정적) 쉼과 회상 곡 붙잡기는 끝난다
	_resting = false
	_clear_hold()
	_switch(name, fade, restart, from, loop)


func stop(fade := 1.0) -> void:
	play("", fade)


func _switch(name: String, fade: float, restart := false, from := 0.0, loop := -1) -> void:
	if name == _current and not restart and (name == "" or _players[_active].playing):
		return
	if name == "":
		# 정적: 흐르던 곡을 모두 줄여서 멈춘다
		_current = ""
		_crossfade(fade)
		return
	var other := 1 - _active
	if name != "" and not restart and _names[other] == name and _players[other].playing:
		# 막 꺼지던 곡으로 바로 돌아간다 (예: 들판 곡이 막 시작된 순간 쉼터 곡으로): 처음부터가 아니라 흐르던 자리에서 다시 키운다
		_active = other
		_current = name
		_crossfade(fade)
		return
	var stream: AudioStream = _load(name, loop)
	if stream == null:
		push_warning("음악 파일이 없다: " + DIR + name + ".wav")
		return
	_active = other
	var nw := _players[_active]
	_current = name
	nw.stop()
	nw.stream = stream
	_names[_active] = name
	if _pitch_tween:
		_pitch_tween.kill()
	for p in _players:
		p.pitch_scale = 1.0
	nw.volume_db = -80.0
	nw.play(from)
	_crossfade(fade)


## 지금 플레이어(_active)를 키우고 나머지는 줄여서 멈춘다.
func _crossfade(fade: float) -> void:
	if _tween:
		_tween.kill()
	if fade <= 0.0:
		for i in _players.size():
			var p := _players[i]
			if i == _active and _current != "":
				p.volume_db = BASE_DB
			else:
				p.volume_db = -80.0
				p.stop()
				_names[i] = ""
		return
	_tween = create_tween().set_parallel(true)
	for i in _players.size():
		var p := _players[i]
		if i == _active and _current != "":
			_tween.tween_property(p, "volume_db", BASE_DB, fade).set_trans(Tween.TRANS_SINE)
		elif p.playing:
			_tween.tween_property(p, "volume_db", -80.0, fade).set_trans(Tween.TRANS_SINE)
			_tween.tween_callback(_stop_player.bind(i)).set_delay(fade)


func _stop_player(i: int) -> void:
	if i == _active and _current != "":
		return
	_players[i].stop()
	_names[i] = ""


## 곡을 읽는다. loop: -1 = .import 설정 그대로, 0 = 이번엔 한 번만, 1 = 이번엔 반복 (곡 전체).
func _load(name: String, loop := -1) -> AudioStream:
	var path := DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = load(path)
	if st is AudioStreamWAV and loop >= 0:
		var wav := st as AudioStreamWAV
		var want := AudioStreamWAV.LOOP_FORWARD if loop == 1 else AudioStreamWAV.LOOP_DISABLED
		if wav.loop_mode != want:
			# 원본(캐시)은 건드리지 않고 사본의 반복만 바꾼다 (소리 데이터는 복사되지 않고 함께 쓴다)
			wav = wav.duplicate()
			wav.loop_mode = want
			if want == AudioStreamWAV.LOOP_FORWARD:
				wav.loop_begin = 0
				wav.loop_end = maxi(roundi(wav.get_length() * wav.mix_rate) - 1, 1)
			st = wav
	return st


# ---------- 방 · 들판 곡 · 쉼 ----------

## 방에 들어섰다. field_now: 들판 곡을 지금 튼다 (보스를 아직 정화하지 않은 보스 방은 false — 앞 방의 곡이 이어지다 보스곡으로),
## resting: 달빛풀로 이동해 와서 쉬는 자세로 도착했다 (쉼터 곡을 이어 간다).
func enter_room(region: String, room_id: String, field_now := true, resting := false) -> void:
	_region = region
	_room_id = room_id
	if resting:
		rest_begin()
	elif field_now:
		play_region(region, room_id)
	else:
		_resting = false


## 지역 들판 곡. 회상 곡을 붙잡고 있으면 미뤘다가 정해진 시간 뒤에 넘긴다.
func play_region(region: String, room_id := "") -> void:
	_region = region
	_room_id = room_id
	_resting = false
	if _hold_name != "" and _hold_name == _current:
		if not _pending_region:
			_pending_region = true
			_hold_release_ms = Time.get_ticks_msec() + int(_hold_seconds * 1000.0)
		return
	_clear_hold()
	_switch(region_track(region, room_id), 2.0)


## 달빛풀에서 쉬기 시작: 쉼터 곡으로 (이미 흐르면 그대로 — 달빛풀 사이를 이동해도 이어진다).
func rest_begin(fade := 2.5) -> void:
	_resting = true
	_clear_hold()
	_switch(REST, fade)


## 쉼이 끝났다(일어섬): 지금 방의 들판 곡으로.
func rest_end(fade := 2.0) -> void:
	if not _resting:
		return
	_resting = false
	if _region != "":
		_switch(region_track(_region, _room_id), fade)


func is_resting() -> bool:
	return _resting


# ---------- 회상 곡 붙잡기 ----------

## 지금 곡(name)을 붙잡는다: 그사이 들판 곡 요청(play_region)은 미뤄졌다가, 첫 요청 뒤 seconds 초가 지나면 HOLD_FADE 초에 걸쳐 넘어간다.
## 회상 씬이 부른다 — 방으로 돌아온 뒤 영혼이 깃드는 연출 동안 회상 곡이 이어지고, 그다음 (되살아난) 들판 곡이 스며든다.
## (다른 곡을 play 하거나 stop·쉼을 시작하면 붙잡기는 풀린다.)
func hold(name: String, seconds: float) -> void:
	if name == "" or name != _current:
		return
	_hold_name = name
	_hold_seconds = maxf(seconds, 0.0)
	_hold_release_ms = -1
	_pending_region = false


## 붙잡은 곡이 남았는가 (시험용)
func is_holding() -> bool:
	return _hold_name != ""


func _clear_hold() -> void:
	_hold_name = ""
	_hold_release_ms = -1
	_pending_region = false


func _process(_delta: float) -> void:
	if _hold_name == "":
		return
	if _current != _hold_name:
		_clear_hold()
		return
	if _pending_region and _hold_release_ms >= 0 and Time.get_ticks_msec() >= _hold_release_ms:
		_clear_hold()
		_switch(region_track(_region, _room_id), HOLD_FADE)


# ---------- 연출 ----------

## 곡이 잠깐 휘청인다: 재생 속도(음 높이)를 depth 만큼 떨어뜨렸다가 time 초에 걸쳐 되돌린다 (테이프가 늘어지듯).
## 무쇠 펌프 2페이즈 — 기계의 규칙이 무너지는 순간 음악도 함께 흐트러진다 (EXPANSION.md 4장). 곡을 바꾸지는 않는다.
func falter(depth := 0.16, time := 1.4) -> void:
	if _current == "":
		return
	var p := _players[_active]
	if _pitch_tween:
		_pitch_tween.kill()
	_pitch_tween = create_tween()
	_pitch_tween.tween_property(p, "pitch_scale", 1.0 - depth, time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pitch_tween.tween_property(p, "pitch_scale", 1.0, time * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 지금 곡이 흐르는 빠르기 (1 = 그대로, 휘청이는 동안 1 − depth 까지 처진다). 곡이 없으면 1.
## 곡에 맞춰 움직이는 그림(무쇠 펌프의 '쿵')이 곡과 같은 빠르기로 늘어지게 읽는다.
func tempo_scale() -> float:
	if _current == "":
		return 1.0
	var p := _players[_active]
	return p.pitch_scale if p.playing else 1.0


## 휘청이는 중인가 (시험용)
func is_faltering() -> bool:
	return _pitch_tween != null and _pitch_tween.is_running()
