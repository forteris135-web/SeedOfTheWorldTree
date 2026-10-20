class_name PostEnding
extends RefCounted
## 엔딩 뒤의 세계 (ENDINGS.md 0장 "엔딩마다 끝나면 엔딩 후 이어서 탐험"). 마지막으로 본 엔딩(깃발 last_ending_*, EndingScene.mark_seen)에 따라
## 마을의 빛을 바꾼다: 되돌림의 끝 — 큰 등불이 꺼진 달빛 밤(푸른 어둠), 제3의 길 — 작은 등불만 남은 조금 어두운 저녁,
## 희생의 끝 — 그대로 (등불은 여전히 따뜻하다). 값은 data/dialogue/endings*.json 각 엔딩의 "post": {"village_tint": [r, g, b]}.
## 마을 사람들의 엔딩 뒤 대사는 data/dialogue/npcs_endings.json. 정적 함수만 있다 — 방 파일은 손대지 않는다 (Room._ready 가 apply 를 부른다).


## 마지막으로 본 엔딩 이름 (sacrifice / return / third), 아직 엔딩을 안 봤으면 "".
## 깃발이 없는 옛 진행은 타이틀(TitleScreen.cleared_state)과 같이 클리어 기록 + 저장된 엔딩 값으로 고른다
## (보통은 SaveGame.load_game 이 깃발을 채워 둔다).
static func last_ending() -> String:
	for n in EndingScene.ENDINGS:
		if Progress.has("last_ending_" + n):
			return n
	if Progress.has("cleared") and Progress.ending in EndingScene.ENDINGS:
		return Progress.ending
	return ""


## 방이 열릴 때: 마을 방이면 마지막 엔딩의 마을 빛을 입힌다 (CanvasModulate). 입힌 노드를 돌려준다 (없으면 null).
## 원래 어두운 방(dark)은 그대로 둔다.
static func apply(room: Node) -> CanvasModulate:
	if room == null or str(room.get("region")) != "village" or bool(room.get("dark")):
		return null
	var e := last_ending()
	if e == "":
		return null
	var post: Dictionary = EndingScene.ending_data(e).get("post", {})
	var t = post.get("village_tint", null)
	if not (t is Array) or t.size() < 3:
		return null
	var cm := CanvasModulate.new()
	cm.name = "PostEndingTint"
	cm.color = Color(float(t[0]), float(t[1]), float(t[2]))
	room.add_child(cm)
	return cm
