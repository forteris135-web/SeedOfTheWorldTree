extends Node2D
class_name RescuedPerson
## 구원되어 사람으로 돌아온 이. 두 모습이 있다.
##  - 들판(home = false): 정화 직후 그 자리에 선다. 감사의 말과 보상(greet) → 말 걸 때마다 talk_lines 한 줄씩 →
##    다 말한 뒤 한 번 더 말 걸면 마지막 한 마디(leave_line)를 남기고 0.8초 동안 빛이 되어 사라진다. 그 뒤로는 '집'에 있다.
##    말을 안 걸고 방을 떠나도 집으로 간 것으로 친다 (깃발 home_<id>).
##    relocations.json 에 집 항목이 없는 사람(확장판에서 아직 자리를 안 정한 이)은 떠나지 않고 talk_lines 를 돌아가며 말한다.
##  - 집(home = true): data/dialogue/relocations.json 의 자리에 RescuedHomes 가 세운다. 말 걸면 home_lines 를 대화 상자로 말한다
##    (home_lines 의 요소가 사전이면 마을 NPC 처럼 when(깃발 조건)·once·set·message 를 쓴다; 글자면 늘 하는 말).
## 대사와 보상은 data/dialogue/npcs.json. 보상 수치는 RescuedHomes 가 구원 순간에 '받을 보상'으로 적어 두었다가 준다
## (감사의 말 중에 방을 떠나도, 불러오기를 해도 꼭 한 번만). (사람 모습 그림은 relocations.json 의 texture — 나중에 교체)

const DATA_PATH := "res://data/dialogue/npcs.json"
const LEAVE_SAY_MIN := 2.4   # 마지막 한 마디가 떠 있는 최소 시간 (초) — 사라지기 시작할 때까지
const LEAVE_SAY_MAX := 5.5   # 〃 최대
const READ_CPS := 9.0        # 마지막 한 마디를 읽는 빠르기 (글자/초): 글자 수 / 9 초 동안 서 있다가 사라진다
const VANISH_TIME := 0.8     # 빛이 되어 사라지는 시간 (초)
const APPEAR_TIME := 0.9     # 같은 방이 집일 때 빛에서 나타나는 시간 (초)
const GREET_REWARD_DELAY := 4.2
const READ_MIN := 1.0        # 말풍선이 뜬 뒤 이 시간 안의 손길은 무시한다 (연타로 못 읽고 넘어가지 않게)
const LEAVE_GATE := 2.5      # 마지막 대사 말풍선이 이만큼 떠 있었거나 사라진 뒤에야 '떠나기' 누름을 받는다
const TALK_SAY := 3.5        # 들판 대사 말풍선 시간
const REST_TINT := Color(1.0, 0.97, 0.92)   # 평소 색. 1.0 을 넘지 않는다 (마을의 글로우 문턱 1.0 — 사람은 빛나지 않는다)
const GLOW := Color(2.6, 2.4, 1.9, 0.0)

var rescue_id := ""
var texture: Texture2D
var art_faces_right := true
var art_scale := 0.17
var facing := 1
## 부위 뼈대로 서는 경우 (art/rigs/<rig_id>, 구원형 몹의 뼈대 — EnemyRigVisual.npc_look 이나 relocations.json 의 "rig")
var rig_id := ""
var rig_scale := 1.0
## 집 모드 (RescuedHomes 가 세운다).
var home := false
## 시험·마을 시험이 Npc 처럼 읽을 수 있게.
var npc_id: String:
	get: return rescue_id

## 보이는 모습: 그림 한 장(Sprite2D) 또는 부위 뼈대(PartRig). 색·크기·자리 연출은 둘 다 같은 Node2D 값으로 한다.
var _sprite: Node2D
var _rig: PartRig
var _motion: RigMotion
var _prompt: Label
var _near: Player
var _data := {}
var _bubble: Label
var _bubble_timer := 0.0
var _bubble_since := -100.0
var _line_index := 0
var _area: Area2D
var _greeting := false
var _leaving := false
var _gone := false
var _has_home := false
var _t := 0.0


func _ready() -> void:
	add_to_group("npc")
	var all: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	_data = all.get(rescue_id, {})
	var entry := RescuedHomes.home_of(rescue_id)
	_has_home = not entry.is_empty()
	RescuedHomes.apply_look(self, entry)
	if rig_id != "" and FileAccess.file_exists("res://art/rigs/%s/rig.json" % rig_id):
		# 부위 뼈대: 원점이 발(땅)이라 그대로 세운다. 힘을 뺀 'npc' 자세로 숨 쉰다.
		_rig = PartRig.new()
		add_child(_rig)
		if _rig.build(rig_id):
			_motion = RigMotion.new(_rig)
			_motion.set_target(_motion.pose("npc"))
			_motion.snap_feet()
			_motion.update(0.0, {})
			_sprite = _rig
		else:
			_rig.queue_free()
			_rig = null
	if _sprite == null:
		var spr := Sprite2D.new()
		spr.texture = texture
		spr.scale = Vector2(art_scale, art_scale)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if texture:
			spr.position = Vector2(0, -texture.get_height() * art_scale / 2.0 + 20.0 * art_scale)
		add_child(spr)
		_sprite = spr
	_face(facing > 0)
	_sprite.modulate = REST_TINT
	var h := _height()
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("cfe9ff"))
	_prompt.position = Vector2(-80, -h - 40)
	_prompt.visible = false
	add_child(_prompt)
	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 24)
	_bubble.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	_bubble.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_bubble.add_theme_constant_override("shadow_outline_size", 6)
	_bubble.position = Vector2(-260, -h - 110)
	_bubble.size = Vector2(520, 60)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 140.0
	shape.shape = c
	shape.position = Vector2(0, -60)
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(func(b): if b is Player and not _leaving: _near = b; b.register_interactable(self))
	_area.body_exited.connect(func(b): if b is Player: b.unregister_interactable(self); _near = null)


func _exit_tree() -> void:
	# 들판에 선 채로 소녀가 방을 떠났다 (방 이동·불러오기·타이틀).
	if home or _gone or rescue_id == "":
		return
	# 감사의 말이 끝나기 전에 떠나도 보상은 받는다. 단, 지금 진행 상태에 '받을 보상'으로 적혀 있을 때만
	# (불러오기로 구원 전 세이브가 들어와 있으면 아무것도 주지 않는다 — RescuedHomes.settle_reward).
	RescuedHomes.settle_reward(rescue_id)
	# 말을 안 걸었어도 집으로 간 것으로 친다 (집 항목이 있고, 지금 진행 상태에서 구원된 사람일 때만).
	if _has_home and Progress.rescued.has(rescue_id) and not Progress.has("home_" + rescue_id):
		Progress.flags["home_" + rescue_id] = true   # 방이 닫히는 중이라 신호 없이 조용히 세운다


func _process(delta: float) -> void:
	_t += delta
	_prompt.visible = _near != null and not _bubble.visible and not _leaving and not Dialogue.is_active()
	if _prompt.visible:
		if home:
			_prompt.text = "%s  %s" % [InputDevice.prompt("interact"), _data.get("name", "말 걸기")]
		else:
			_prompt.text = "%s  말 걸기" % InputDevice.prompt("interact")
	if _bubble.visible:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_bubble.visible = false
	if _near:
		_face(_near.global_position.x > global_position.x)
	# 숨쉬기 (뼈대는 RigMotion 이 숨 쉰다)
	if _motion:
		_motion.update(delta, {})
	elif not _leaving:
		_sprite.scale.y = art_scale * (1.0 + sin(_t * 1.8) * 0.012)


## 구원 직후: 빛이 번지고 첫 말, 감사의 말이 끝나면 보상 안내.
func greet(by: Player) -> void:
	_greeting = true
	# 보통은 구원 순간(적의 rescued 신호)에 이미 적혀 있다. 감시 밖의 적이었다면 여기서 적는다.
	RescuedHomes.mark_reward_due(rescue_id)
	var tw := create_tween()
	_sprite.modulate = Color(3, 3, 3)
	tw.tween_property(_sprite, "modulate", REST_TINT, 1.2)
	var name: String = _data.get("name", "구원된 사람")
	var lines: Array = _data.get("rescued_lines", ["…고마워요."])
	_say("%s: %s" % [name, lines[0]], 4.0)
	# 일시정지 중엔 멈추는 타이머 (메뉴를 연 채로 보상·진동이 나오지 않게)
	await get_tree().create_timer(GREET_REWARD_DELAY, false).timeout   # 감사의 말이 끝난 뒤
	if not is_inside_tree():
		return
	var text := RescuedHomes.settle_reward(rescue_id)
	if text != "":
		RescuedHomes.show_reward_text(self, text)
		Juice.rumble(0.2, 0.4, 0.2)
	_greeting = false


func is_greeting() -> bool:
	return _greeting


func is_leaving() -> bool:
	return _leaving


func has_home() -> bool:
	return _has_home


func bubble_text() -> String:
	return _bubble.text if _bubble.visible else ""


## 지금 말풍선이 떠 있었던 시간 (없으면 큰 값).
func bubble_age() -> float:
	return _t - _bubble_since if _bubble.visible else 999.0


## 마지막 한 마디가 떠 있다가 사라지기 시작할 때까지의 시간: 글자 수에 맞춘다.
func leave_say_time() -> float:
	var line: String = _data.get("leave_line", "…이제 가 볼게요.")
	return clampf(float(line.length()) / READ_CPS, LEAVE_SAY_MIN, LEAVE_SAY_MAX)


func interact(_by: Player) -> void:
	if _leaving or _gone:
		return
	if home:
		_talk_home()
		return
	# 말풍선이 막 떴으면 연타는 무시 (정화와 같은 버튼이라 연타하기 쉽다)
	if bubble_age() < READ_MIN:
		return
	var name: String = _data.get("name", "구원된 사람")
	var lines: Array = _data.get("talk_lines", _data.get("rescued_lines", []))
	if not _has_home:
		# 집이 정해지지 않은 사람: 떠나지 않고 대사를 돌아가며 말한다 (옛 동작)
		if not lines.is_empty():
			_say("%s: %s" % [name, lines[_line_index % lines.size()]], TALK_SAY)
			_line_index += 1
		return
	if _line_index < lines.size():
		_say("%s: %s" % [name, lines[_line_index]], TALK_SAY)
		_line_index += 1
		return
	if _greeting:
		return   # 감사의 말·보상이 끝나기 전엔 떠나지 않는다
	if bubble_age() < LEAVE_GATE:
		return   # 마지막 대사를 읽을 틈을 준다
	_leave()


# ---------- 들판: 떠나기 ----------

## 마지막 한 마디를 남기고 빛이 되어 사라진다. 그 뒤로는 집(relocations.json)에 있다.
func _leave() -> void:
	_leaving = true
	var name: String = _data.get("name", "구원된 사람")
	var line: String = _data.get("leave_line", "…이제 가 볼게요.")
	var say := leave_say_time()
	_say("%s: %s" % [name, line], say + VANISH_TIME)
	_unregister()
	await get_tree().create_timer(say, false).timeout   # 일시정지 중엔 멈춘다
	if not is_inside_tree():
		return
	await _vanish()
	if not is_inside_tree():
		return
	_gone = true
	Progress.set_flag("home_" + rescue_id)
	var room := _find_room()
	if room:
		RescuedHomes.spawn_if_here(room, rescue_id)
	queue_free()


func _unregister() -> void:
	if _near and is_instance_valid(_near):
		_near.unregister_interactable(self)
	_near = null
	_area.set_deferred("monitoring", false)


## 빛 가루가 피어오르며 그림이 밝아졌다가 사라진다 (VANISH_TIME).
func _vanish() -> void:
	Sfx.play("bloom", -4.0)
	_light_motes(VANISH_TIME, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_sprite, "modulate", GLOW, VANISH_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	var k := rig_scale if _rig else art_scale
	tw.tween_property(_sprite, "scale", Vector2(signf(_sprite.scale.x) * absf(k) * 1.06, k * 1.1), VANISH_TIME).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_sprite, "position:y", _sprite.position.y - 26.0, VANISH_TIME).set_trans(Tween.TRANS_SINE)
	await tw.finished


## 집이 바로 이 방일 때: 빛에서 천천히 나타난다.
func appear() -> void:
	_sprite.modulate = GLOW
	_light_motes(APPEAR_TIME, 0.75)
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", REST_TINT, APPEAR_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func _height() -> float:
	if _rig:
		return float(_rig.data.get("height", 1000.0)) * _rig.game_scale * rig_scale
	return texture.get_height() * art_scale if texture else 200.0


## 오른쪽(right)을 보게 한다: 그림 한 장은 좌우 뒤집기, 뼈대는 늘 오른쪽을 보는 그림이라 scale.x 부호로.
func _face(right: bool) -> void:
	if _rig:
		_rig.scale = Vector2(rig_scale if right else -rig_scale, rig_scale)
	elif _sprite is Sprite2D:
		(_sprite as Sprite2D).flip_h = right != art_faces_right


## 빛 가루(둥글고 부드러운 입자, 발광) + 잠깐의 더하기 혼합 번쩍임.
## 사라질 때는 이 노드가 곧 지워지므로 방(부모)에 둔다 (빛이 끝까지 남게).
func _light_motes(seconds: float, strength: float) -> void:
	var h := _height()
	var holder: Node = get_parent() if get_parent() is Node2D else self
	var center := global_position + Vector2(0, -h * 0.5)
	var tex := _mote_texture()
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.5
	p.amount = int(34 * strength) + 8
	p.lifetime = seconds + 0.7
	p.texture = tex
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(36.0, h * 0.45)
	p.direction = Vector2(0, -1)
	p.spread = 50.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 150.0
	p.gravity = Vector2(0, -60)
	p.damping_min = 20.0
	p.damping_max = 40.0
	p.scale_amount_min = 0.3    # 32px 그림 → 약 10~19px
	p.scale_amount_max = 0.6
	p.color = Color(1.6, 1.45, 1.0)   # 빛 입자: 글로우 문턱(1.0)을 넘겨 은은히 번진다
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	p.color_ramp = ramp
	p.emitting = true
	holder.add_child(p)
	p.global_position = center
	p.finished.connect(p.queue_free)   # 한 번 피어오르고 나면 스스로 지워진다
	# 번쩍임: 사람 키만 한 부드러운 빛이 0.5초 동안 피었다 진다
	var flash := Sprite2D.new()
	flash.texture = tex
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = add
	flash.modulate = Color(1.3, 1.15, 0.8, 0.0)
	var s := h * 1.3 / 32.0
	flash.scale = Vector2(s * 0.6, s * 0.6)
	holder.add_child(flash)
	flash.global_position = center
	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "modulate:a", 0.75 * strength, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "scale", Vector2(s, s), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(flash, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(flash.queue_free)


## 둥글고 부드러운 빛 한 점 (32px). 정적 변수에 붙잡아 두면 끝낼 때 새는 객체로 남으므로 그때그때 만든다 (작다).
static func _mote_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.8, 1.0), Color(1, 0.9, 0.65, 0.55), Color(1, 0.85, 0.5, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32
	gt.height = 32
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


func _find_room() -> Node:
	var n: Node = get_parent()
	while n:
		if n is Room:
			return n
		n = n.get_parent()
	return null


# ---------- 집: 대화 ----------

## home_lines 를 마을 NPC 의 talks 처럼 묶음으로 만든다: 사전 요소는 그대로(when/once/set/message/lines), 글자 요소들은 마지막의 '늘 하는 말' 묶음.
func home_groups() -> Array:
	var raw: Array = _data.get("home_lines", _data.get("talk_lines", []))
	var groups: Array = []
	var plain: Array = []
	for el in raw:
		if el is Dictionary:
			groups.append(el)
		else:
			plain.append(el)
	if not plain.is_empty():
		groups.append({"lines": plain})
	return groups


## 지금 조건에 맞는 집 대사 묶음 (없으면 빈 사전). 시험도 쓴다.
func current_home_group() -> Dictionary:
	var groups := home_groups()
	for i in groups.size():
		var g: Dictionary = groups[i]
		if g.get("once", false) and Progress.has(_once_flag(i)):
			continue
		if Npc.condition_ok(g.get("when", "")):
			return g
	return {}


func _talk_home() -> void:
	if Dialogue.is_active():
		return
	var chosen := current_home_group()
	if chosen.is_empty():
		return
	var idx := home_groups().find(chosen)
	var name: String = _data.get("name", "")
	var lines: Array = []
	for l in chosen.get("lines", []):
		if l is String:
			lines.append({"speaker": name, "text": l})
		else:
			lines.append(l)
	if lines.is_empty():
		return
	Dialogue.start(lines, func() -> void:
		if chosen.get("once", false):
			Progress.set_flag(_once_flag(idx))
		var flag: String = chosen.get("set", "")
		if flag != "":
			Progress.set_flag(flag)
		var give: String = chosen.get("message", "")
		if give != "":
			var hud := RescuedHomes.find_hud(self)
			if hud:
				hud.show_message(give, 3.5))


func _once_flag(i: int) -> String:
	return "talked_home_%s_%d" % [rescue_id, i]


func _say(text: String, seconds: float) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_timer = seconds
	_bubble_since = _t
