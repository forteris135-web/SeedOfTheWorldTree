extends EnemyRigVisual
class_name OwenRigVisual
## 침식된 광부 오웬의 부위 뼈대 그림. EnemyRigVisual 에 오웬만의 연출을 더한다 (판정·시간은 EnemyBase 그대로).
##  - 곡괭이는 두 손으로 쥔다: 앞손(무기 팔)이 곡괭이를 휘두르고, 뒷손은 매 프레임 '두 뼈 IK' 로 자루 끝(설계도 sockets.grip_b)을 잡는다.
##    맞음·무너짐·무릎 꿇기·쓰러짐·공중에서는 뒷손을 놓는다 (부드럽게 섞인다).
##  - 헬멧 등불(sockets.lamp)과 허리 등불(lantern 뼈)이 은은히 빛난다. 예고 동안 헬멧 등불이 밝아진다. 허리 등불은 천처럼 흔들린다(설계도 chain).
##  - 얼굴: 싸울 때는 흰 눈(변형 eroded), 무릎 꿇고 정화를 기다릴 때는 눈 감은 얼굴(calm). 구원된 오웬(RescuedPerson)은 기본 얼굴(눈을 내리깐)로 선다.

## 뒷손이 곡괭이를 잡는 상태 (그 밖의 상태는 손을 놓는다)
const GRIP_STATES := [EnemyBase.State.IDLE, EnemyBase.State.PATROL, EnemyBase.State.CHASE, EnemyBase.State.ALERT,
	EnemyBase.State.LUNGE, EnemyBase.State.WINDUP, EnemyBase.State.STRIKE, EnemyBase.State.RECOVER, EnemyBase.State.BACKSTEP]
## 등불 빛 색 (HDR — 1 을 넘는 값이 글로우로 번진다)
const LAMP_COLOR := Color(1.6, 1.15, 0.6)

var _owen_ok := false
var _i_up := -1
var _i_lo := -1
var _i_fup := -1
var _i_flo := -1
var _i_weapon := -1
var _i_torso := -1
var _grip := Vector2.ZERO      # 곡괭이 뼈 틀의 뒷손 자리
var _hand_b := Vector2.ZERO    # 뒷팔 아래팔 틀의 손 자리
var _len_a := 0.0
var _len_b := 0.0
var _grip_w := 0.0
var _face := ""
var _lamp: Sprite2D
var _lantern_glow: Sprite2D
var _lamp_k := 0.0


func _ready() -> void:
	super._ready()
	if not _ready_ok or motion == null:
		return
	_i_up = rig.bone_index("arm_b_up")
	_i_lo = rig.bone_index("arm_b_lo")
	_i_fup = rig.bone_index("arm_f_up")
	_i_flo = rig.bone_index("arm_f_lo")
	_i_weapon = rig.bone_index("weapon")
	_i_torso = rig.bone_index("torso")
	var socks: Dictionary = rig.data.get("sockets", {})
	if socks.has("grip_b") and _i_up >= 0 and _i_lo >= 0 and _i_weapon >= 0:
		_grip = PartRig._v(socks["grip_b"]["pos"])
		_len_a = rig.base_pos[_i_lo].length()
		_len_b = rig.bone_len[_i_lo]
		_hand_b = Vector2(0, _len_b)
	_lamp = _make_glow(64)
	if socks.has("lamp"):
		rig.attach(str(socks["lamp"]["bone"]), _lamp, PartRig._v(socks["lamp"]["pos"]))
	if rig.has_bone("lantern"):
		_lantern_glow = _make_glow(64)
		rig.attach("lantern", _lantern_glow, Vector2(0, rig.bone_len[rig.bone_index("lantern")] * 0.62))
	_set_face("eroded")
	_owen_ok = true


func _process(delta: float) -> void:
	super._process(delta)
	if not _owen_ok or _enemy == null:
		return
	var st := _enemy.state
	# 얼굴: 무너져 무릎 꿇으면(정화를 기다림) 눈을 감는다. 구원(빛이 됨)도 그 얼굴.
	_set_face("calm" if st in [EnemyBase.State.BROKEN, EnemyBase.State.DEAD] else "eroded")
	# 두 손 쥐기
	var airborne := not _enemy.is_on_floor() and absf(_enemy.velocity.y) > 60.0
	var want := 1.0 if (st in GRIP_STATES and not airborne) else 0.0
	_grip_w = Motion.damp(_grip_w, want, 14.0 if want > _grip_w else 9.0, delta)
	if _grip_w > 0.01 and _len_a > 0.0:
		_solve_back_arm(_grip_w)
	# 등불 빛: 은은한 깜빡임, 예고 동안 헬멧 등불이 밝아진다. 흩어져 사라지면 함께 꺼진다.
	var fl := 0.85 + 0.1 * sin(_t * 7.3) + 0.05 * sin(_t * 17.1)
	var boost := 0.0
	if st == EnemyBase.State.WINDUP:
		boost = 0.6 * _enemy.windup_progress
	_lamp_k = Motion.damp(_lamp_k, boost, 10.0, delta)
	var fade := 1.0 - rig.dissolve_amount()
	if _lamp:
		_lamp.modulate = Color(LAMP_COLOR.r, LAMP_COLOR.g, LAMP_COLOR.b, (0.4 + 0.35 * _lamp_k) * fl * fade)
		_lamp.scale = Vector2.ONE * (0.26 + 0.18 * _lamp_k)   # 뼈대 노드가 이미 art_scale 배율
	if _lantern_glow:
		_lantern_glow.modulate = Color(LAMP_COLOR.r, LAMP_COLOR.g, LAMP_COLOR.b, 0.3 * fl * fade)
		_lantern_glow.scale = Vector2.ONE * 0.34


## 뒷팔 두 뼈 IK: 어깨에서 곡괭이 자루 끝까지 위팔·아래팔을 푼다. 팔꿈치는 앞팔과 같은 쪽으로 굽힌다.
## 뼈대 틀(뿌리 기준, body_xf 전)에서 풀고 w 만큼 지금 자세와 섞는다. 다 풀면 그림을 다시 놓는다.
func _solve_back_arm(w: float) -> void:
	var s := rig.xf[_i_up].origin
	var t := rig.xf[_i_weapon] * _grip
	var d := t - s
	var dist := clampf(d.length(), absf(_len_a - _len_b) + 0.01, _len_a + _len_b - 0.01)
	var cos_a := clampf((_len_a * _len_a + dist * dist - _len_b * _len_b) / (2.0 * _len_a * dist), -1.0, 1.0)
	var alpha := acos(cos_a)
	# 팔꿈치가 굽는 쪽: 앞팔(어깨→팔꿈치→손)의 굽힘 방향과 같게
	var fe := rig.xf[_i_flo].origin - rig.xf[_i_fup].origin
	var fh := (rig.xf[_i_flo] * Vector2(0, rig.bone_len[_i_flo])) - rig.xf[_i_flo].origin
	var bend := 1.0 if fe.cross(fh) >= 0.0 else -1.0
	var phi1 := d.angle() - alpha * bend
	var elbow := s + Vector2.from_angle(phi1) * _len_a
	var phi2 := (t - elbow).angle()
	# 뼈 틀의 +y 가 뼈 방향: 세상 회전 r ↔ 방향각 φ = r + π/2
	var parent_rot := rig.xf[rig.parent[_i_up]].get_rotation()
	var up_local := (phi1 - PI * 0.5) - parent_rot
	var lo_local := (phi2 - PI * 0.5) - (phi1 - PI * 0.5)
	rig.rot[_i_up] = lerp_angle(rig.rot[_i_up], up_local, w)
	rig.rot[_i_lo] = lerp_angle(rig.rot[_i_lo], lo_local, w)
	rig.compute_from(_i_up)
	rig.apply()


func _set_face(f: String) -> void:
	if f == _face:
		return
	_face = f
	rig.set_variant("head", f)


func _make_glow(px: int) -> Sprite2D:
	var g := Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = px
	gt.height = px
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	g.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = add
	g.z_index = 1
	return g
