#!/usr/bin/env python3
"""비밀 벽·비밀 천장·아이템을 방(.tscn)에 배치한다 (기획서 8장 "비밀 벽·비밀 천장·아이템", 2026-10-18 기획자 결정).
사용: python3 tools/add_secrets.py   → 아래 표의 여섯 방을 고친다. 두 번 실행해도 안전하다 (이미 있으면 건너뜀).

좌표계: 왼쪽 위 (0,0), 아래로 y 증가. 소녀 키 134(중심은 발에서 67 위), 한 번 점프 최고 271px.
- 비밀 벽: 벽면에 소녀 키만 한 조각(60×200). 옆에 서서 공격 3대. 뒤에 작은 굴과 아이템.
- 비밀 천장: 천장에서 내려온 두꺼운 가지(SecretStalk) 끝의 옹이. 바닥에서 점프해 머리를 박으면 부서지고 아이템이 떨어진다.
id 규칙: 비밀 "secret_<방>_<번호>", 아이템 "pick_<방>_<번호>".
"""
import os, re

ROOT = os.path.join(os.path.dirname(__file__), "..", "scenes", "rooms")
EXTS = [
    ("50_secret_wall", '[ext_resource type="PackedScene" uid="uid://c1seedsecretwall" path="res://scenes/world/secret_wall.tscn" id="50_secret_wall"]\n'),
    ("51_secret_ceiling", '[ext_resource type="PackedScene" uid="uid://c1seedsecretceil" path="res://scenes/world/secret_ceiling.tscn" id="51_secret_ceiling"]\n'),
    ("52_pickup", '[ext_resource type="PackedScene" uid="uid://c1seedpickup" path="res://scenes/world/pickup.tscn" id="52_pickup"]\n'),
]


def platform(name, x, y, w, h, decorate=True):
    s = f'[node name="{name}" parent="Terrain" instance=ExtResource("3_platform")]\nposition = Vector2({x}, {y})\nsize = Vector2({w}, {h})\n'
    if not decorate:
        s += "decorate = false\n"
    return s + "\n"


def wall(name, x, y, w, h, secret_id):
    return f'[node name="{name}" parent="Terrain" instance=ExtResource("50_secret_wall")]\nposition = Vector2({x}, {y})\nsize = Vector2({w}, {h})\nsecret_id = "{secret_id}"\n\n'


def ceiling(name, x, y, w, h, secret_id):
    return f'[node name="{name}" parent="Terrain" instance=ExtResource("51_secret_ceiling")]\nposition = Vector2({x}, {y})\nsize = Vector2({w}, {h})\nsecret_id = "{secret_id}"\n\n'


def pickup(name, x, y, pickup_id, kind, amount, hidden_in, fall_to=None):
    s = f'[node name="{name}" parent="Interactables" instance=ExtResource("52_pickup")]\nposition = Vector2({x}, {y})\npickup_id = "{pickup_id}"\nkind = "{kind}"\namount = {float(amount)}\nhidden_in = "{hidden_in}"\n'
    if fall_to:
        s += f"fall_to = Vector2({fall_to[0]}, {fall_to[1]})\n"
    return s + "\n"


# 방마다: 지울 노드, 바꿀 속성 [(노드, 속성, 새 값)], 방 속성, Terrain 에 더할 노드, Interactables 에 더할 노드
PLAN = {
    "canopy_01": {
        # 오른쪽 큰 덩어리(4020,1500 / 780×1000)를 셋으로 쪼개 왼쪽 면 아래에 굴(x 4080~4320, y 1850~2050)을 판다.
        "remove": ["BlockRight"],
        "terrain": (platform("BlockTop", 4020, 1500, 780, 350)
                    + platform("BlockBottom", 4020, 2050, 780, 450)
                    + platform("BlockRightPart", 4320, 1850, 480, 200, decorate=False)
                    + wall("SecretWall1", 4020, 1850, 60, 200, "secret_canopy_01_1")),
        "items": pickup("Pickup1", 4200, 2010, "pick_canopy_01_1", "dews", 1, "secret_canopy_01_1"),
    },
    "canopy_03": {
        # 바닥 P1(윗면 1100) 위, 천장에서 내려온 가지 끝의 옹이 (아랫면 760). 점프하면 머리(966 → 695)가 닿는다.
        "terrain": platform("SecretStalk", 1050, -100, 200, 700) + ceiling("SecretCeiling1", 1050, 600, 200, 160, "secret_canopy_03_1"),
        "items": pickup("Pickup1", 1150, 690, "pick_canopy_03_1", "max_hp", 10, "secret_canopy_03_1", fall_to=(1150, 1060)),
    },
    "canopy_04": {
        # P8(2900~3200, 윗면 700)이 닿은 오른쪽 벽을 300 밀고, 벽 안에 굴(x 3260~3500, y 500~700).
        "room": [("bounds = Rect2(0, 0, 3200, 2200)", "bounds = Rect2(0, 0, 3500, 2200)")],
        "props": [("WallRight", "position", "Vector2(3500, -100)"), ("P1", "size", "Vector2(3500, 200)")],
        "terrain": (platform("RightUpper", 3200, -100, 300, 600, decorate=False)
                    + platform("RightLower", 3200, 700, 300, 1400)
                    + wall("SecretWall1", 3200, 500, 60, 200, "secret_canopy_04_1")),
        "items": pickup("Pickup1", 3400, 660, "pick_canopy_04_1", "attack", 0.05, "secret_canopy_04_1"),
    },
    "mine_01": {
        # P2(1800~2600, 윗면 600)가 닿은 오른쪽 벽을 300 밀고, 굴(x 2660~2900, y 400~600).
        "room": [("bounds = Rect2(0, 0, 2600, 3200)", "bounds = Rect2(0, 0, 2900, 3200)")],
        "props": [("WallRight", "position", "Vector2(2900, -100)")],
        "terrain": (platform("RightUpper", 2600, -100, 300, 500, decorate=False)
                    + platform("RightLower", 2600, 600, 300, 2700)
                    + wall("SecretWall1", 2600, 400, 60, 200, "secret_mine_01_1")),
        "items": pickup("Pickup1", 2800, 560, "pick_mine_01_1", "dews", 1, "secret_mine_01_1"),
    },
    "village_01": {
        # 지붕 P2(700~1180, 윗면 1150) 위의 옹이 (아랫면 950). 지붕에서 점프하면 머리(1016 → 745)가 닿는다.
        "terrain": platform("SecretStalk", 1000, -100, 180, 900) + ceiling("SecretCeiling1", 1000, 800, 180, 150, "secret_village_01_1"),
        "items": pickup("Pickup1", 1090, 880, "pick_village_01_1", "heal", 10, "secret_village_01_1", fall_to=(1090, 1110)),
    },
    "abyss_02": {
        # 비석 앞 P7(1200~2600, 윗면 900) 위의 옹이 (아랫면 700). 점프하면 머리(766 → 495)가 닿는다.
        "terrain": platform("SecretStalk", 2200, -100, 200, 650) + ceiling("SecretCeiling1", 2200, 550, 200, 150, "secret_abyss_02_1"),
        "items": pickup("Pickup1", 2300, 630, "pick_abyss_02_1", "max_hp", 10, "secret_abyss_02_1", fall_to=(2300, 860)),
    },
}

NODE_RE = re.compile(r'^\[node name="([^"]+)"(?: type="([^"]+)")? parent="([^"]+)"(?: instance=ExtResource\("([^"]+)"\))?\]\n((?:[^\[\n].*\n?)*)\n?', re.M)


def find_node(txt, name):
    for m in NODE_RE.finditer(txt):
        if m.group(1) == name:
            return m
    return None


def set_prop(txt, name, prop, value):
    m = find_node(txt, name)
    if m is None:
        raise SystemExit("노드 %s 가 없다" % name)
    block = m.group(0)
    new_block = re.sub(r'^%s = .+$' % prop, '%s = %s' % (prop, value), block, count=1, flags=re.M)
    if new_block == block:
        raise SystemExit("노드 %s 에 속성 %s 가 없다" % (name, prop))
    return txt[:m.start()] + new_block + txt[m.end():]


def remove_node(txt, name):
    m = find_node(txt, name)
    if m is None:
        return txt
    return txt[:m.start()] + txt[m.end():]


def insert_after_section(txt, parent, nodes_text):
    """parent 아래 마지막 노드 블록 뒤에 끼운다. 자식이 없으면 parent 노드 블록 바로 뒤."""
    last = None
    for m in NODE_RE.finditer(txt):
        if m.group(3) == parent:
            last = m
    if last is None:
        last = find_node(txt, parent)
        if last is None:
            raise SystemExit("부모 %s 가 없다" % parent)
    end = last.end()
    head = txt[:end]
    if not head.endswith("\n\n"):
        head = head.rstrip("\n") + "\n\n"
    return head + nodes_text + txt[end:].lstrip("\n")


def process(room_id, plan):
    path = os.path.join(ROOT, room_id + ".tscn")
    txt = open(path, encoding="utf-8").read()
    if 'name="SecretWall1"' in txt or 'name="SecretCeiling1"' in txt:
        print("%s: 이미 배치됨, 건너뜀" % room_id)
        return
    # 자원 줄
    for rid, line in EXTS:
        if ('id="%s"' % rid) in txt:
            continue
        if rid not in plan.get("terrain", "") + plan.get("items", ""):
            continue
        txt = re.sub(r'load_steps=(\d+)', lambda m: "load_steps=%d" % (int(m.group(1)) + 1), txt, count=1)
        last_ext = list(re.finditer(r'^\[ext_resource .*\]\n', txt, re.M))[-1]
        txt = txt[:last_ext.end()] + line + txt[last_ext.end():]
    for old, new in plan.get("room", []):
        if old not in txt:
            raise SystemExit("%s: '%s' 가 없다" % (room_id, old))
        txt = txt.replace(old, new, 1)
    for name, prop, value in plan.get("props", []):
        txt = set_prop(txt, name, prop, value)
    for name in plan.get("remove", []):
        txt = remove_node(txt, name)
    if plan.get("terrain"):
        txt = insert_after_section(txt, "Terrain", plan["terrain"])
    if plan.get("items"):
        txt = insert_after_section(txt, "Interactables", plan["items"])
    open(path, "w", encoding="utf-8").write(txt)
    print("%s: 배치함" % room_id)


# ── 지도 자리 밀기 ─────────────────────────────────────────────────────────────
# 가지 갈림길(canopy_04)을 3200→3500, 내려가는 갱도(mine_01)를 2600→2900 으로 넓혔으므로,
# 지도(map_offset = 세계 좌표의 방 왼쪽 위, 크기 = bounds)에서 오른쪽 이웃들이 300px 겹치지 않게 뒤 방들을 민다.
# 겸사겸사 전부터 있던 겹침도 푼다 (꼭대기의 하늘↔입구의 거리 100px, 등불의 심장이 책임자의 방 위에 통째로 겹침).
#   map_offset.x ≥ 15600 (canopy_boss 부터):            +300  ← 가지 갈림길 넓힘
#   map_offset.x ≥ 19200 (village_01 부터):             +100  ← 꼭대기의 하늘(3700 폭) 과의 옛 겹침
#   map_offset.x ≥ 29900 (mine_02 부터):                +300  ← 내려가는 갱도 넓힘
#   map_offset.x ≥ 38000 (abyss_01 부터):               +600  ← 등불의 심장(3700 폭) 오른쪽 끝을 비켜 가게
#   등불의 심장(mine_boss) 은 y 400 → 1900 (관의 복도 오른쪽 두 출구: 위 = 책임자의 방, 아래 = 등불의 심장 — 그 순서로 쌓는다)
# 이미 밀었는지는 canopy_boss 의 map_offset.x 로 본다 (15600 = 아직, 15900 = 밀었음).
SHIFT_RULES = [(15600, 300), (19200, 100), (29900, 300), (38000, 600)]   # (이 x 이상이면, 이만큼 더한다) — 해당하는 것을 모두 더한다
Y_MOVES = {"mine_boss": (400, 1900)}   # 방: (지금 y, 새 y)
SHIFT_FLAG_ROOM = "canopy_boss"
SHIFT_FLAG_DONE_X = 15900
MAP_RE = re.compile(r'^map_offset = Vector2\((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)$', re.M)


def read_map_offset(txt):
    m = MAP_RE.search(txt)
    return (float(m.group(1)), float(m.group(2))) if m else None


def fmt(v):
    return str(int(v)) if float(v).is_integer() else str(v)


def shift_map_offsets():
    flag_path = os.path.join(ROOT, SHIFT_FLAG_ROOM + ".tscn")
    flag = read_map_offset(open(flag_path, encoding="utf-8").read())
    if flag is None:
        raise SystemExit("%s 에 map_offset 이 없다" % SHIFT_FLAG_ROOM)
    if flag[0] >= SHIFT_FLAG_DONE_X:
        print("지도 자리 밀기: 이미 밀었음(%s x=%s), 건너뜀" % (SHIFT_FLAG_ROOM, fmt(flag[0])))
        return
    for fn in sorted(os.listdir(ROOT)):
        if not fn.endswith(".tscn"):
            continue
        path = os.path.join(ROOT, fn)
        txt = open(path, encoding="utf-8").read()
        off = read_map_offset(txt)
        if off is None:
            continue
        dx = sum(d for limit, d in SHIFT_RULES if off[0] >= limit)
        new_y = off[1]
        room = fn[:-5]
        if room in Y_MOVES and off[1] == Y_MOVES[room][0]:
            new_y = Y_MOVES[room][1]
        if dx == 0 and new_y == off[1]:
            continue
        new_txt = MAP_RE.sub("map_offset = Vector2(%s, %s)" % (fmt(off[0] + dx), fmt(new_y)), txt, count=1)
        open(path, "w", encoding="utf-8").write(new_txt)
        print("지도 자리 밀기: %s (%s, %s) → (%s, %s)" % (room, fmt(off[0]), fmt(off[1]), fmt(off[0] + dx), fmt(new_y)))


if __name__ == "__main__":
    for room_id, plan in PLAN.items():
        process(room_id, plan)
    shift_map_offsets()
