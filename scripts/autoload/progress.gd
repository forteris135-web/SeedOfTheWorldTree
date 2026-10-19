extends Node
## 이야기 진행과 능력. (세이브는 14단계에서 이 내용을 저장한다)

signal flag_changed(flag: String, value: bool)
signal ability_gained(ability: String)

## 진행 깃발: boss_bird_defeated, met_tia ...
var flags := {}
## 얻은 능력: double_jump, wind, lantern ...
var abilities := {}
## 고른 영혼 기술: "seed"(처음부터) / "wind" / "light". 소녀는 방마다 새로 만들어지므로 선택은 여기 둔다 (세이브에도 들어간다).
var soul := "seed"
## 다음 방에서 소녀가 설 자리 (RoomExit 가 정한다). 비어 있으면 방의 기본 자리.
var next_spawn := ""
## 지금 보여 줄 회상 (memories.json 의 키)과 끝난 뒤 돌아갈 방.
var pending_memory := ""
var memory_return_scene := ""
## 성장 보상 누적: max_hp(+체력), attack(+배수, 0.1 = 10%), dews(+개수), heal(+회복량)
var upgrades := {}
## 피워 둔 달빛풀: id -> {"scene": 경로, "name": 표시 이름}
var grasses := {}
## 마지막으로 쉰 달빛풀 {"id", "scene", "name"}. 메뉴에서 '지금 저장하기'를 누르면 여기서 이어진다.
var last_grass := {}
## 구원한 사람들 (id)
var rescued := {}
## 지도: 가 본 방 (room_id -> offset, size, name, region, grasses, boss)
var visited_rooms := {}
## 고른 엔딩: sacrifice / return
var ending := ""
## 모은 것·부순 것 (id -> true): 아이템(pick_<방>_<번호>), 비밀 벽·천장(secret_<방>_<번호>).
## 한 번 모으거나 부순 것은 다시 와도 그대로다.
var collected := {}
## 재화 '빛 가루': 적을 쓰러뜨리거나 정화하면 떨어지고, 달빛풀에서 성장에 쓴다 (2026-10-19 기획자 요청).
var dust := 0
## 영혼별 남은 쿨다운(초). 소녀가 방마다 새로 만들어져도 이어진다 (저장하지 않음).
var soul_cooldowns := {}
signal dust_changed(amount: int)


func add_dust(n: int) -> void:
	if n == 0:
		return
	dust = maxi(dust + n, 0)
	dust_changed.emit(dust)


func spend_dust(n: int) -> bool:
	if n > dust:
		return false
	dust -= n
	dust_changed.emit(dust)
	return true

signal upgraded(kind: String, amount: float)
## 무언가를 모으거나 부쉈다 (숨은 아이템이 나타나고, 지도의 탐사 수가 바뀐다).
signal collected_changed(id: String)


func is_collected(id: String) -> bool:
	return collected.get(id, false)


func collect(id: String) -> void:
	if id == "" or is_collected(id):
		return
	collected[id] = true
	collected_changed.emit(id)


func add_upgrade(kind: String, amount: float) -> void:
	upgrades[kind] = upgrades.get(kind, 0.0) + amount
	upgraded.emit(kind, amount)
	ability_gained.emit("upgrade")


func has(flag: String) -> bool:
	return flags.get(flag, false)


func set_flag(flag: String, value := true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)


func has_ability(ability: String) -> bool:
	return abilities.get(ability, false)


func gain_ability(ability: String) -> void:
	if has_ability(ability):
		return
	abilities[ability] = true
	ability_gained.emit(ability)


## 테스트용 초기화.
func reset() -> void:
	flags.clear()
	abilities.clear()
	soul = "seed"
	upgrades.clear()
	grasses.clear()
	last_grass = {}
	rescued.clear()
	visited_rooms.clear()
	collected.clear()
	dust = 0
	soul_cooldowns.clear()
	next_spawn = ""
