class_name RescuedHomes
extends RefCounted
## 구원된 사람의 '집' 자리. data/dialogue/relocations.json 을 읽어, 방이 열릴 때(Room._ready 끝) 그 방이 집인 사람들을
## 사람 모습(RescuedPerson, home 모드)으로 세운다. 정적 함수만 있다 — 방 파일은 손대지 않는다.
##
## 표 형식 (rescue_id → 항목):
##   "scene": 방의 room_id (예 "village_01")      "position": [x, y] 발이 닿는 자리 (바닥 윗면 y)
##   "facing": 1(오른쪽) / -1(왼쪽)                 "texture": 사람 모습 그림 경로 (지금은 구원형 적 그림을 임시로 씀)
##   "art_scale", "art_faces_right": 그림 배율·그림이 오른쪽을 보는지
##   "npc_id": 그 방에 이미 같은 npc_id 의 NPC(npc.tscn)가 있으면 새로 세우지 않는다 (오웬은 기존 마을 NPC 가 맡는다)
## relocations_*.json 도 함께 읽히므로(DialogueData), 확장판 구원자는 파일만 더하면 된다.
##
## 판단 규칙: Progress.rescued 에 있으면 집에 있다. 깃발 "home_<id>" 는 '떠났다'는 표시(대사 조건용)로, 들판에서 빛이 되어 사라질 때
## 또는 말을 안 걸고 방을 떠날 때 서며, 여기서도 없으면 세운다(옛 세이브).
## 표에 없는 구원자는 들판에서 떠나지 않는다 (RescuedPerson 이 옛 동작대로 대사를 돌아가며 말함).
##
## 구원 보상 (npcs.json 의 reward): 구원하는 순간(적의 rescued 신호) 깃발 "reward_due_<id>"(받을 보상)를 적고,
## 감사의 말이 끝나면(RescuedPerson.greet) 또는 그 전에 방을 떠나면(_exit_tree) 또는 다음 방이 열릴 때(spawn_into) 준 뒤
## 깃발 "rewarded_<id>"(받았음)로 바꾼다. 받을 보상 깃발은 진행 상태(세이브)와 함께 움직이므로, 불러오기로 구원 전 상태가 되면
## 보상도 함께 사라지고 다시 구원하면 한 번만 받는다.

const DATA_PATH := "res://data/dialogue/relocations.json"
const NPCS_PATH := "res://data/dialogue/npcs.json"
const SCENE := "res://scenes/npcs/rescued_person.tscn"
const DUE := "reward_due_"     # 깃발: 구원했지만 아직 안 준 보상
const GIVEN := "rewarded_"     # 깃발: 보상을 받았음

## 시험용 덮어쓰기: rescue_id → 항목(사전)이면 그 항목으로, 빈 사전이면 표에서 뺀다. 게임에서는 늘 비어 있다.
static var test_override := {}


## 표 전체 (설명 키 "_…" 는 뺀다).
static func table() -> Dictionary:
	var all: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	var out := {}
	for k in all:
		if not str(k).begins_with("_") and all[k] is Dictionary:
			out[k] = all[k]
	for k in test_override:
		var v = test_override[k]
		if v is Dictionary and not v.is_empty():
			out[k] = v
		else:
			out.erase(k)
	return out


static func home_of(rescue_id: String) -> Dictionary:
	return table().get(rescue_id, {})


## 방을 가리키는 열쇠: room_id, 없으면 장면 파일 이름.
static func room_key(room: Node) -> String:
	if room == null:
		return ""
	var id := ""
	var v = room.get("room_id")
	if v != null:
		id = str(v)
	if id == "" and room.scene_file_path != "":
		id = room.scene_file_path.get_file().get_basename()
	return id


static func is_home_room(entry: Dictionary, room: Node) -> bool:
	var key := room_key(room)
	return key != "" and str(entry.get("scene", "")) == key


static func home_position(entry: Dictionary) -> Vector2:
	var pos = entry.get("position", [0, 0])
	if pos is Array and pos.size() >= 2:
		return Vector2(float(pos[0]), float(pos[1]))
	return Vector2.ZERO


## 방이 열릴 때 한 번(Room._ready 끝): 구원 보상 감시를 걸고, 남은 보상을 정산한 뒤
## 이 방이 집인 구원된 사람들을 모두 세운다. 세운 노드들을 돌려준다.
static func spawn_into(room: Node) -> Array:
	var spawned: Array = []
	watch_rescues(room)
	settle_all(room)
	var key := room_key(room)
	if key == "":
		return spawned
	var t := table()
	for id in t:
		var entry: Dictionary = t[id]
		if str(entry.get("scene", "")) != key:
			continue
		if not Progress.rescued.has(id):
			continue
		if not Progress.has("home_" + id):
			Progress.set_flag("home_" + id)   # 방을 옮겨 왔으니 이미 집에 와 있다 (옛 세이브 포함)
		if already_there(room, id, entry):
			continue
		var npc := spawn_one(room, id, entry)
		if npc:
			spawned.append(npc)
	return spawned


## 들판에서 빛이 되어 사라진 직후: 집이 바로 이 방이면 그 자리에 바로 나타난다 (경비병처럼 같은 방이 집인 경우).
static func spawn_if_here(room: Node, id: String) -> RescuedPerson:
	var entry := home_of(id)
	if entry.is_empty() or not is_home_room(entry, room):
		return null
	if already_there(room, id, entry):
		return null
	return spawn_one(room, id, entry, true)


## 이미 그 사람이 방에 서 있는가 (집 모드 RescuedPerson, 또는 npc_id 가 가리키는 기존 NPC).
static func already_there(room: Node, id: String, entry: Dictionary) -> bool:
	var tree := room.get_tree()
	if tree == null:
		return false
	var npc_id := str(entry.get("npc_id", ""))
	for n in tree.get_nodes_in_group("npc"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n is RescuedPerson and n.home and n.rescue_id == id:
			return true
		if npc_id != "" and n is Npc and n.npc_id == npc_id:
			return true
	return false


## 한 사람을 집 모드로 세운다. appear 가 참이면 빛에서 천천히 나타난다.
static func spawn_one(room: Node, id: String, entry: Dictionary, appear := false) -> RescuedPerson:
	var scene: PackedScene = load(SCENE)
	if scene == null:
		return null
	var npc: RescuedPerson = scene.instantiate()
	npc.rescue_id = id
	npc.home = true
	npc.facing = int(entry.get("facing", 1))
	apply_look(npc, entry)
	npc.name = "Home_" + id
	var parent: Node = room.get_node_or_null("Interactables")
	if parent == null:
		parent = room
	var pos := home_position(entry)
	npc.position = pos
	parent.add_child(npc)
	npc.global_position = pos
	if appear:
		npc.appear()
	return npc


## 표의 그림 설정을 입힌다 (들판의 RescuedPerson 도 같은 그림을 쓰게 — 적의 몸통 조각 대신 온전한 사람 그림).
static func apply_look(npc: RescuedPerson, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	# 부위 뼈대가 있으면 그것으로 선다 (그림 한 장은 뼈대가 없을 때의 대신)
	if str(entry.get("rig", "")) != "":
		npc.rig_id = str(entry["rig"])
		npc.rig_scale = float(entry.get("rig_scale", 1.0))
	var path := str(entry.get("texture", ""))
	if path != "" and ResourceLoader.exists(path):
		npc.texture_path = path   # 뼈대를 못 세울 때만 읽힌다 (RescuedPerson._ready)
		npc.art_scale = float(entry.get("art_scale", npc.art_scale))
		npc.art_faces_right = bool(entry.get("art_faces_right", npc.art_faces_right))


# ---------- 구원 보상 ----------

## 구원 순간을 잡는다: 이 방의 적들과, 앞으로 트리에 들어오는 적들(달빛풀에서 쉬거나 쓰러진 뒤 다시 깨어나는 적)의
## rescued 신호를 mark_reward_due 에 잇는다. 여러 번 불러도 한 번만 이어진다.
static func watch_rescues(room: Node) -> void:
	var tree := room.get_tree() if room else null
	if tree == null:
		return
	var added := Callable(RescuedHomes, "_on_node_added")
	if not tree.node_added.is_connected(added):
		tree.node_added.connect(added)
	for e in tree.get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			_watch_enemy(e)


static func _on_node_added(n: Node) -> void:
	if n is EnemyBase:
		_watch_enemy(n)


static func _watch_enemy(e: Node) -> void:
	if not e.has_signal("rescued"):
		return
	var cb := Callable(RescuedHomes, "mark_reward_due")
	if not e.is_connected("rescued", cb):
		e.connect("rescued", cb)


## npcs.json 의 보상 (없으면 빈 사전).
static func reward_of(id: String) -> Dictionary:
	var d = DialogueData.load_dialogue(NPCS_PATH).get(id, {})
	if not d is Dictionary:
		return {}
	var r = d.get("reward", {})
	return r if r is Dictionary else {}


## 보상 안내 글자.
static func reward_text(reward: Dictionary) -> String:
	var amount := float(reward.get("amount", 0))
	match str(reward.get("type", "")):
		"max_hp": return "최대 체력이 %d 늘었다" % int(amount)
		"attack": return "공격력이 %d%% 올랐다" % int(round(amount * 100))
		"dews": return "이슬 방울을 %d개 더 담을 수 있다" % int(amount)
		"heal": return "회복량이 %d 늘었다" % int(amount)
	return ""


## 구원했다: 받을 보상으로 적어 둔다 (지금 진행 상태에 구원이 있고, 아직 받지도 적지도 않았을 때만).
static func mark_reward_due(id: String) -> void:
	if id == "" or not Progress.rescued.has(id):
		return
	if Progress.has(GIVEN + id) or Progress.has(DUE + id):
		return
	if reward_of(id).is_empty():
		return
	Progress.flags[DUE + id] = true


## 받을 보상이 적혀 있으면 지금 준다. 준 보상의 안내 글자를 돌려준다 (안 줬으면 "").
static func settle_reward(id: String) -> String:
	if id == "" or not Progress.has(DUE + id):
		return ""
	Progress.flags.erase(DUE + id)
	if not Progress.rescued.has(id) or Progress.has(GIVEN + id):
		return ""
	var reward := reward_of(id)
	Progress.flags[GIVEN + id] = true
	var kind := str(reward.get("type", ""))
	var amount := float(reward.get("amount", 0))
	if not kind in ["max_hp", "attack", "dews", "heal"] or amount == 0.0:
		return ""
	Progress.add_upgrade(kind, amount)
	return reward_text(reward)


## 남은 받을 보상을 모두 준다 (쓰러짐 연출 0.5초 안에 방을 떠났거나, 감사의 말 중에 저장한 세이브를 읽었을 때). 안내도 띄운다.
static func settle_all(room: Node) -> void:
	for k in Progress.flags.keys():
		var key := str(k)
		if key.begins_with(DUE) and Progress.flags.get(k, false):
			var text := settle_reward(key.trim_prefix(DUE))
			if text != "":
				show_reward_text(room, text)


static func show_reward_text(from: Node, text: String) -> void:
	var hud := find_hud(from)
	if hud and hud.has_method("show_message"):
		hud.show_message(text, 3.0)


## 그 노드가 들어 있는 방의 CombatHUD (방이 current_scene 이 아닌 시험에서도 찾게 위로 올라가며 본다).
static func find_hud(from: Node) -> Node:
	var n: Node = from
	while n:
		var h := n.get_node_or_null("CombatHUD")
		if h:
			return h
		n = n.get_parent()
	if from and from.is_inside_tree() and from.get_tree().current_scene:
		return from.get_tree().current_scene.get_node_or_null("CombatHUD")
	return null
