extends Node
## Claude Code용 HUD 성장 반영 시험 (화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_hud.tscn
## 첫 방(canopy_01)을 띄운 뒤 Progress.add_upgrade 로 이슬·체력·공격·회복 성장을 넣고,
## HUD 가 그리기에 쓰는 계산 함수(dew_slots / hp_bar_width / hp_frame_pieces / growth_labels / soul_dots)로
##  - 이슬 자리가 겹치지 않는지 (자리 간 거리 ≥ 그림 폭), 7개 넘으면 둘째 줄로 가는지
##  - 체력 막대가 max_hp 에 비례해 길어지고(최대 1.6배) 틀 세 조각이 이어지며 끝 장식 자리가 그대로인지, 0.5초에 걸쳐 자라는지
##  - 성장 표시 문자열("+10%", "+15")이 맞는지, 성장이 없을 땐 비는지
##  - 영혼 원이 soul 값("wind"/"light"/"seed"/"")에 상관없이 오류 없이 나오는지
##  - 성장 순간의 짧은 글자(flash)가 뜨고, 같은 때 가운데 안내(show_message)가 있으면 하나만 남는지
## 를 찍는다. headless 라 그림은 못 보지만 draw 콜백은 돌므로 그리기 오류(SCRIPT ERROR)는 출력에 드러난다.

const S := 0.36

var _fail := 0
var _draws := 0
var _hud: CanvasLayer
var _player: Player


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fmt_slots(slots: Array) -> String:
	var parts := []
	for p in slots:
		parts.append("(%.1f, %.1f)" % [p.x, p.y])
	return ", ".join(parts)


## 같은 줄의 이웃끼리 겹치지 않는지 (다음 자리 x − 이 자리 x ≥ 이 그림 폭)
func _no_overlap(slots: Array) -> bool:
	for i in slots.size() - 1:
		var a: Vector2 = slots[i]
		var b: Vector2 = slots[i + 1]
		if absf(a.y - b.y) < 1.0 and b.x - a.x < _hud.dew_size(i).x - 0.01:
			return false
	return true


func _ready() -> void:
	print("[probe] 시작: HUD 성장 반영")
	await _frames(2)
	Progress.reset()
	var room: Node = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(room)
	await _frames(6)
	_player = get_tree().get_first_node_in_group("player") as Player
	_hud = room.get_node("CombatHUD")
	var n := 0
	while _hud._player == null and n < 60:
		await get_tree().process_frame
		n += 1
	_check(_player != null and _hud._player == _player, "첫 방이 뜨고 HUD 가 소녀를 붙잡았다 (%d 프레임)" % n)
	_hud._canvas.draw.connect(func() -> void: _draws += 1)
	_player._apply_abilities()
	await _frames(2)

	# ── 기본 상태
	var slots: Array = _hud.dew_slots()
	print("[probe] 기본 이슬 %d개 자리: %s / 그림 폭 %.1f %.1f %.1f" % [slots.size(), _fmt_slots(slots), _hud.dew_size(0).x, _hud.dew_size(1).x, _hud.dew_size(2).x])
	_check(slots.size() == 3 and _no_overlap(slots), "기본 이슬 3개, 겹침 없음")
	_check(is_equal_approx(slots[0].x, 10.0 + 405.0 * S) and is_equal_approx(slots[1].x - slots[0].x, 155.0 * S), "첫 자리는 시트 (405,445), 간격은 시트 155px")
	var pieces: Array = _hud.hp_frame_pieces()
	print("[probe] 기본 체력 막대: 배수 %.2f 폭 %.1f, 틀 조각 %d" % [_hud.hp_bar_scale(), _hud.hp_bar_width(), pieces.size()])
	_check(is_equal_approx(_hud.hp_bar_scale(), 1.0) and is_equal_approx(_hud.hp_bar_width(), 1400.0 * S), "체력 100 → 막대 배수 1.0, 폭 %.1f" % (1400.0 * S))
	_check(pieces.size() == 2 and is_equal_approx(pieces[1]["dst"].end.x - pieces[0]["dst"].position.x, 1616.0 * S), "배수 1.0 이면 틀 두 조각이 원래 그림 폭(%.1f) 그대로" % (1616.0 * S))
	_check(_hud.growth_labels().is_empty(), "성장이 없으면 성장 표시 없음 (%s)" % str(_hud.growth_labels()))
	print("[probe] 영혼 없음: soul='%s' dots=%d" % [_player.soul, _hud.soul_dots().size()])
	_check(_hud.soul_dots().size() == _hud.soul_list().size(), "영혼 원 수 = 표시할 영혼 수 (%d)" % _hud.soul_dots().size())

	# ── 이슬 +2 (아무도 가운데 안내를 띄우지 않는 경우 → 짧은 글자가 뜬다)
	_hud._flash_text = ""
	_hud._flash_timer = 0.0
	Progress.add_upgrade("dews", 2)
	_player._apply_abilities()
	await _frames(2)   # (타이머 뒤의 1프레임 대기는 _process 가 한 번도 안 돌 수 있어 2프레임)
	slots = _hud.dew_slots()
	print("[probe] 이슬 +2 → 최대 %d, 자리: %s, 반짝임 %s" % [_player.max_dews, _fmt_slots(slots), str(_hud._dew_pop)])
	_check(_player.max_dews == 5 and slots.size() == 5 and _no_overlap(slots), "이슬 5개가 겹치지 않고 한 줄로 늘어선다")
	_check(_hud._dew_pop.has(3) and _hud._dew_pop.has(4) and not _hud._dew_pop.has(2), "새 이슬(4·5번째)만 반짝이기 시작")
	_check(_hud.growth_origin().x >= slots[4].x + _hud.dew_size(4).x, "성장 표시 줄은 마지막 이슬 오른쪽 (%.1f ≥ %.1f)" % [_hud.growth_origin().x, slots[4].x + _hud.dew_size(4).x])
	await _frames(3)
	_check(_hud._flash_text == "이슬 +2" and _hud._flash_timer > 0.0, "가운데 안내가 없으면 짧은 글자 '이슬 +2' (지금 '%s')" % _hud._flash_text)
	await get_tree().create_timer(0.75).timeout
	_check(_hud._dew_pop.is_empty(), "반짝임은 0.6초 뒤 끝난다 (%s)" % str(_hud._dew_pop))

	# ── 최대 체력 +30
	_hud._flash_text = ""
	_hud._flash_timer = 0.0
	var scale_before: float = _hud._hp_scale_shown
	Progress.add_upgrade("max_hp", 30)
	_player._apply_abilities()
	await _frames(2)
	pieces = _hud.hp_frame_pieces()
	print("[probe] 체력 +30 → 최대 %.0f, 목표 배수 %.2f 폭 %.1f, 지금 그리는 배수 %.3f, 번쩍 %.2f, 틀 조각 %d" % [_player.max_hp, _hud.hp_bar_scale(), _hud.hp_bar_width(), _hud._hp_scale_shown, _hud._hp_grow_flash, pieces.size()])
	_check(is_equal_approx(_hud.hp_bar_scale(), 1.3) and is_equal_approx(_hud.hp_bar_width(), 1400.0 * 1.3 * S), "체력 130 → 막대 배수 1.3, 폭 %.1f" % (1400.0 * 1.3 * S))
	_check(_hud._hp_scale_shown < 1.3 - 0.01 and _hud._hp_scale_shown >= scale_before and _hud._hp_grow_flash > 0.5, "막대는 바로 뛰지 않고 자라는 중 + 번쩍")
	_check(pieces.size() == 3, "늘어나면 틀 세 조각")
	if pieces.size() == 3:
		var l: Rect2 = pieces[0]["dst"]
		var m: Rect2 = pieces[1]["dst"]
		var r: Rect2 = pieces[2]["dst"]
		print("[probe]   왼쪽 %s / 늘림 %s (src %s) / 오른쪽 %s (src %s)" % [l, m, pieces[1]["src"], r, pieces[2]["src"]])
		_check(is_equal_approx(l.end.x, m.position.x) and is_equal_approx(m.end.x, r.position.x), "세 조각이 틈·겹침 없이 이어진다")
		_check(is_equal_approx(m.size.x, 1400.0 * 0.3 * S), "늘림 조각 폭 = 늘어난 채움 길이 (%.1f)" % m.size.x)
		_check(pieces[2]["src"].position.x == _hud.HP_FRAME_SPLIT and is_equal_approx(r.size.x, (1616.0 - _hud.HP_FRAME_SPLIT) * S), "오른쪽 끝 조각은 원래 그림의 끝부분 그대로")
		var fill: Rect2 = _hud.hp_fill_rect()
		_check(is_equal_approx(fill.end.x - r.position.x, (1420.0 - _hud.HP_FRAME_SPLIT) * S), "채움 끝과 끝 장식의 거리가 기본 길이 때와 같다 (%.1f)" % (fill.end.x - r.position.x))
	_check(is_equal_approx(_hud.hp_bar_scale(300.0), 1.6) and is_equal_approx(_hud.hp_bar_scale(50.0), 1.0), "배수는 1.0~1.6 사이로 막는다")
	await _frames(3)
	_check(_hud._flash_text == "체력 +30", "짧은 글자 '체력 +30' (지금 '%s')" % _hud._flash_text)
	await get_tree().create_timer(0.7).timeout
	print("[probe] 0.7초 뒤 그리는 배수 %.4f" % _hud._hp_scale_shown)
	_check(is_equal_approx(_hud._hp_scale_shown, 1.3), "0.5초가 지나면 막대가 목표 길이에 닿는다")

	# ── 공격 +10% (안내 없음) / 회복 +15 (아이템처럼 같은 때 가운데 안내 → 짧은 글자는 안 뜬다)
	Progress.add_upgrade("attack", 0.1)
	_player._apply_abilities()
	await _frames(1)
	print("[probe] 공격 +10%% → 배수 %.2f, 성장 표시 %s" % [_player.attack_multiplier, str(_hud.growth_labels())])
	_check(_hud.growth_labels() == ["+10%"], "성장 표시 ['+10%']")
	_hud._flash_text = ""
	_hud._flash_timer = 0.0
	Progress.add_upgrade("heal", 15)
	_hud.show_message("맑은 샘물 — 회복량 +15", 3.0)   # pickup.gd 와 같은 순서
	_player._apply_abilities()
	await _frames(4)
	print("[probe] 회복 +15 → 회복량 %.0f, 성장 표시 %s, 짧은 글자 '%s', 가운데 안내 '%s'" % [_player.heal_amount, str(_hud.growth_labels()), _hud._flash_text, _hud._message])
	_check(_hud.growth_labels() == ["+10%", "+15"], "성장 표시 ['+10%', '+15']")
	_check(_hud._flash_text == "" and _hud._message_timer > 0.0, "가운데 안내가 같은 때 떴으면 짧은 글자는 안 뜬다 (하나만)")
	var items: Array = _hud.growth_items()
	_check(items.size() == 2 and items[0]["kind"] == "attack" and items[1]["kind"] == "heal", "아이콘 종류: 검, 물방울")

	# ── 영혼: 씨앗은 처음부터 있다(플레이어 묶음) → wind 획득 → wind 선택 → light 획득·선택 → seed 로 되돌림 → ""
	var draws0 := _draws
	var dots: Array = _hud.soul_dots()
	print("[probe] 영혼 처음: soul='%s' dots=%d %s" % [_player.soul, dots.size(), str(dots)])
	_check(dots.size() == 1 and dots[0]["soul"] == "seed" and dots[0]["selected"] and dots[0]["color"].is_equal_approx(Color(0.85, 1.0, 0.75)) and is_equal_approx(dots[0]["radius"], 9.0), "처음엔 씨앗 원 하나, 연둣빛, 고른 것은 반지름 9")
	Progress.gain_ability("wind")
	_player._apply_abilities()
	await _frames(2)
	dots = _hud.soul_dots()
	print("[probe] 영혼 wind 획득: soul='%s' dots=%d %s" % [_player.soul, dots.size(), str(dots)])
	_check(dots.size() == 2 and dots[0]["selected"] and not dots[1]["selected"] and dots[1]["color"].is_equal_approx(Color(0.85, 1.0, 0.9)) and is_equal_approx(dots[1]["radius"], 7.0), "바람을 얻어도 고른 것은 씨앗 그대로, 바람 원은 민트색 작게(반지름 7)")
	Progress.soul = "wind"
	_player._apply_abilities()
	_player.soul_changed.emit("wind")
	await _frames(1)
	dots = _hud.soul_dots()
	_check(dots.size() == 2 and dots[1]["selected"] and is_equal_approx(dots[1]["radius"], 9.0), "바람으로 전환하면 바람 원이 크게(반지름 9)")
	_check(_hud._soul_flash > 0.8, "전환 순간 번쩍 시작 (%.2f)" % _hud._soul_flash)
	Progress.gain_ability("light")
	Progress.soul = "light"
	_player._apply_abilities()
	_player.soul_changed.emit("light")
	await _frames(1)
	dots = _hud.soul_dots()
	print("[probe] 영혼 seed+wind+light(고른 것 light): dots=%d flash=%.2f" % [dots.size(), _hud._soul_flash])
	_check(dots.size() == 3 and dots[2]["selected"] and not dots[1]["selected"] and dots[2]["color"].is_equal_approx(Color(1.0, 0.9, 0.7)) and is_equal_approx(dots[1]["radius"], 7.0), "원 셋, light 금빛·크게, wind 작게(반지름 7)")
	_check(dots[1]["center"].x - dots[0]["center"].x >= 16.0 and dots[2]["center"].x - dots[1]["center"].x >= 16.0, "원끼리 겹치지 않는다 (간격 %.1f)" % (dots[1]["center"].x - dots[0]["center"].x))
	await get_tree().create_timer(0.4).timeout
	_check(is_zero_approx(_hud._soul_flash), "번쩍은 0.3초 뒤 꺼진다 (%.2f)" % _hud._soul_flash)
	_player.soul = "foo"   # 모르는 영혼 값: owned_souls 에 없어도 맨 앞에 흰 원으로 표시되고 오류가 없어야 한다
	await _frames(2)
	dots = _hud.soul_dots()
	print("[probe] 영혼 foo(목록 밖): dots=%d 첫 원 %s" % [dots.size(), str(dots[0]) if dots.size() > 0 else "-"])
	_check(dots.size() == 4 and dots[0]["soul"] == "foo" and dots[0]["selected"], "모르는 영혼 값도 맨 앞에 원으로 (오류 없음)")
	_player.soul = ""
	await _frames(2)
	dots = _hud.soul_dots()
	var any_sel := false
	for d in dots:
		if d["selected"]:
			any_sel = true
	_check(dots.size() == 3 and not any_sel, "soul='' 이면 고른 원 없이 가진 영혼만 (%d)" % dots.size())
	Progress.soul = "wind"
	_player._apply_abilities()
	await _frames(1)
	_check(_draws > draws0 + 5, "영혼 상태를 바꾸는 동안 HUD 가 계속 그려졌다 (%d회)" % (_draws - draws0))

	# ── 이슬 9개: 둘째 줄, 영혼 줄은 그 아래로
	Progress.add_upgrade("dews", 4)
	_player._apply_abilities()
	await _frames(2)
	slots = _hud.dew_slots()
	print("[probe] 이슬 +4 → 최대 %d, 줄 %d, 자리: %s" % [_player.max_dews, _hud.dew_rows(), _fmt_slots(slots)])
	_check(slots.size() == 9 and _hud.dew_rows() == 2 and _no_overlap(slots), "이슬 9개: 겹침 없음, 두 줄")
	_check(is_equal_approx(slots[7].x, slots[0].x) and slots[7].y > slots[0].y + _hud.dew_size(0).y * 0.9 and is_equal_approx(slots[6].y, slots[0].y), "8번째부터 둘째 줄 (첫 줄 7개)")
	var soul_y: float = _hud.soul_origin().y
	print("[probe] 영혼 줄 기준선 y %.1f, 둘째 줄 이슬 아래 %.1f" % [soul_y, slots[7].y + _hud.dew_size(7).y])
	_check(soul_y >= slots[7].y + _hud.dew_size(7).y, "영혼 줄은 둘째 이슬 줄 아래로 내려간다")
	_check(_hud.growth_origin().x >= slots[6].x + _hud.dew_size(6).x, "성장 표시는 첫 줄의 마지막(7번째) 이슬 오른쪽")
	await _frames(3)
	print("[probe] draw 호출 수 %d" % _draws)
	_check(_draws > 20, "HUD draw 가 돌았다")

	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(_fail)
