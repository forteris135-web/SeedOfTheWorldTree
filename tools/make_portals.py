#!/usr/bin/env python3
"""방의 출구(보이지 않는 RoomExit)를 메이플스토리식 포탈(Portal)로 바꾼다 (기획서 8장 "포탈").
사용: python3 tools/make_portals.py   → 모든 scenes/rooms/*.tscn 을 고친다. 두 번 실행해도 안전하다.
- 출구마다 포탈 하나: 아래 PORTAL_POS 표(방 id → 출구 노드 이름 → 포탈이 서는 자리(x, 바닥 y)).
  건너간 방의 등장 자리(Markers/<spawn_name>)는 그대로 쓰므로, 포탈은 그 자리 바로 옆에 둔다.
- 예전에 방 한가운데 두었던 포탈(Interactables/Portal)은 지운다.
- 포탈 자리를 비우려고 달빛풀 몇 개를 옮기고, 채굴장 관의 복도에는 등불 길 포탈이 설 선반을 하나 둔다.
"""
import os, re

ROOT = os.path.join(os.path.dirname(__file__), "..", "scenes", "rooms")
EXT = '[ext_resource type="PackedScene" uid="uid://c1seedportal" path="res://scenes/world/portal.tscn" id="40_portal"]\n'

PORTAL_POS = {
    "canopy_01": {"ToCanopy02": (4620, 400), "ToHidden": (1650, 60)},
    "canopy_02": {"Exit1": (190, 2400), "Exit2": (2230, 300)},
    "canopy_03": {"Exit1": (190, 1100), "Exit2": (5010, 1100)},
    "canopy_04": {"Exit1": (190, 2000), "Exit2": (3010, 2000)},
    "canopy_boss": {"ToCanopy04": (140, 1380), "ToVillage": (3610, 1500)},
    "canopy_hidden": {"Exit1": (190, 1300)},
    "village_01": {"Exit1": (190, 1400), "Exit2": (4010, 1400)},
    "village_02": {"Exit1": (190, 1400), "Exit2": (3610, 560), "Exit3": (3610, 1400)},
    "village_shrine": {"Exit1": (190, 1000)},
    "mine_01": {"Exit1": (190, 300), "Exit2": (2410, 3000)},
    "mine_02": {"Exit1": (190, 1200), "Exit2": (4810, 1200), "Exit3": (4830, 720)},
    "mine_boss": {"ToMine02": (140, 1380)},
    "mine_deep": {"Exit1": (190, 1100), "Exit2": (2810, 1100)},
    "abyss_01": {"Exit1": (190, 1800), "Exit2": (4010, 1800)},
    "abyss_02": {"Exit1": (190, 2200), "Exit2": (3410, 700)},
    "moon_garden": {"Exit1": (190, 1100), "Exit2": (2810, 1100)},
    "abyss_boss": {"ToGarden": (140, 1380)},
}

# 포탈 자리를 비우려고 옮기는 것들: (노드 이름, 옛 position 줄, 새 position 줄[, 추가 바꿈])
MOVES = {
    "canopy_boss": [("MoonlightGrass", "Vector2(330, 1380)", "Vector2(420, 1380)")],
    "mine_boss": [("MoonlightGrass", "Vector2(330, 1380)", "Vector2(420, 1380)")],
    "abyss_boss": [("MoonlightGrass", "Vector2(330, 1380)", "Vector2(420, 1380)")],
    "mine_deep": [("Grass1", "Vector2(2600, 1100)", "Vector2(1150, 1100)")],
    "village_02": [("Grass1", "Vector2(3350, 1400)", "Vector2(3300, 1400)")],
    "moon_garden": [("Decor1", "Vector2(300, 1100)", "Vector2(410, 1100)"), ("Decor3", "Vector2(900, 1100)", "Vector2(1000, 1100)"),
                    ("Decor4", "Vector2(2000, 1100)", "Vector2(1950, 1100)"), ("Decor6", "Vector2(2650, 1100)", "Vector2(2560, 1100)"),
                    ("Grass1", "Vector2(1600, 1100)", "Vector2(1500, 1100)")],
    "mine_02": [("FromMineDeep", "Vector2(3900, 582)", "Vector2(4760, 652)")],
}
# 등불 길 포탈이 설 선반 (관의 복도 오른쪽 벽, P8에서 뛰어오른다)
MINE02_LEDGE = '\n[node name="PLedge" parent="Terrain" instance=ExtResource("3_platform")]\nposition = Vector2(4620, 720)\nsize = Vector2(380, 40)\n'

NODE_RE = re.compile(r'^\[node name="([^"]+)"(?: type="([^"]+)")? parent="([^"]+)"(?: instance=ExtResource\("([^"]+)"\))?\]\n((?:[^\[\n].*\n?)*)\n?', re.M)


def props_of(body):
    return dict(re.findall(r'^(\w+) = (.+)$', body, re.M))


def process(room_id):
    path = os.path.join(ROOT, room_id + ".tscn")
    txt = open(path, encoding="utf-8").read()
    # 0) 포탈 자원 줄
    if "40_portal" not in txt:
        txt = re.sub(r'load_steps=(\d+)', lambda m: "load_steps=%d" % (int(m.group(1)) + 1), txt, count=1)
        last_ext = list(re.finditer(r'^\[ext_resource .*\]\n', txt, re.M))[-1]
        txt = txt[:last_ext.end()] + EXT + txt[last_ext.end():]
    # 1) 예전 한가운데 포탈 지우기
    txt = re.sub(r'\[node name="Portal" parent="Interactables" instance=ExtResource\("40_portal"\)\]\n(?:[^\[\n].*\n)*\n?', "", txt)
    # 2) 출구 → 포탈
    exits = {}
    def grab(m):
        name, typ, parent, inst, body = m.groups()
        if parent == "Exits" and inst == "16_exit":
            exits[name] = props_of(body)
            return ""
        if parent.startswith("Exits/") and typ == "CollisionShape2D":
            return ""
        return m.group(0)
    txt = NODE_RE.sub(grab, txt)
    table = PORTAL_POS[room_id]
    for name, props in exits.items():
        if name not in table:
            raise SystemExit("%s: 출구 %s 의 포탈 자리가 표에 없다" % (room_id, name))
    # 이미 포탈로 바뀐 방이면(출구가 없으면) 포탈 노드는 그대로 둔다
    if exits:
        block = ""
        for name, (x, y) in table.items():
            p = exits[name]
            block += '\n[node name="%s" parent="Exits" instance=ExtResource("40_portal")]\nposition = Vector2(%d, %d)\ntarget_scene = %s\nspawn_name = %s\n' % (name, x, y, p["target_scene"], p["spawn_name"])
            for k in ("requires_ability", "locked_message"):
                if k in p:
                    block += "%s = %s\n" % (k, p[k])
        m = re.search(r'^\[node name="Exits" type="Node2D" parent="\."\]\n', txt, re.M)
        txt = txt[:m.end()] + block + txt[m.end():]
    # 3) 옮기기
    for mv in MOVES.get(room_id, []):
        node, old, new = mv[:3]
        pat = re.compile(r'(\[node name="%s"[^\n]*\]\nposition = )%s' % (re.escape(node), re.escape(old)))
        if pat.search(txt):
            txt = pat.sub(lambda m: m.group(1) + new, txt, count=1)
    if room_id == "mine_02" and "PLedge" not in txt:
        m = re.search(r'\n\[node name="Hazards"', txt)
        txt = txt[:m.start()] + MINE02_LEDGE + txt[m.start():]
    # 빈 줄 정리
    txt = re.sub(r'\n{3,}', "\n\n", txt)
    open(path, "w", encoding="utf-8").write(txt)
    print("%s: 포탈 %d개 (%s)" % (room_id, len(table), ", ".join(table)))


for rid in PORTAL_POS:
    process(rid)
