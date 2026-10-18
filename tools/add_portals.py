#!/usr/bin/env python3
"""모든 방(.tscn)에 포탈을 하나씩 넣는다 (기획서 8장 "포탈").
사용: python3 tools/add_portals.py   → 이미 들어 있는 방은 건너뛴다.
자리는 아래 PORTALS 표(방 id → x, 바닥 y, 깨어나는 깃발). 보스 방은 수호자를 정화해야 깨어난다.
"""
import os, re

ROOT = os.path.join(os.path.dirname(__file__), "..", "scenes", "rooms")
PORTALS = {
    "canopy_01": (1150, 2200, ""), "canopy_02": (560, 2400, ""), "canopy_03": (450, 1100, ""), "canopy_04": (850, 2000, ""),
    "canopy_hidden": (600, 1300, ""), "canopy_boss": (1800, 1500, "boss_bird_defeated"),
    "village_01": (900, 1400, ""), "village_02": (600, 1400, ""), "village_shrine": (2000, 1000, ""),
    "mine_01": (950, 300, ""), "mine_02": (500, 1200, ""), "mine_deep": (450, 1100, ""), "mine_boss": (1800, 1500, "boss_knight_defeated"),
    "abyss_01": (900, 1800, ""), "abyss_02": (420, 2200, ""), "moon_garden": (1250, 1100, ""), "abyss_boss": (1800, 1500, "boss_root_defeated"),
}
EXT = '[ext_resource type="PackedScene" uid="uid://c1seedportal" path="res://scenes/world/portal.tscn" id="40_portal"]\n'

for room_id, (x, y, flag) in PORTALS.items():
    path = os.path.join(ROOT, room_id + ".tscn")
    txt = open(path, encoding="utf-8").read()
    if "40_portal" in txt:
        print("이미 있음:", room_id)
        continue
    display = re.search(r'^display_name = "([^"]+)"', txt, re.M).group(1)
    # 1) 자원 줄 + load_steps
    txt = re.sub(r'load_steps=(\d+)', lambda m: "load_steps=%d" % (int(m.group(1)) + 1), txt, count=1)
    last_ext = list(re.finditer(r'^\[ext_resource .*\]\n', txt, re.M))[-1]
    txt = txt[:last_ext.end()] + EXT + txt[last_ext.end():]
    # 2) Interactables 묶음 끝(다음 최상위 노드 앞)에 포탈 노드
    m = re.search(r'^\[node name="Interactables" type="Node2D" parent="\."\]\n', txt, re.M)
    assert m, room_id
    nxt = re.compile(r'^\[node name="[^"]+"(?: type="[^"]+")? parent="\."', re.M).search(txt, m.end())
    node = '[node name="Portal" parent="Interactables" instance=ExtResource("40_portal")]\nposition = Vector2(%d, %d)\nportal_id = "%s"\ndisplay_name = "%s"\n' % (x, y, room_id, display)
    if flag:
        node += 'requires_flag = "%s"\n' % flag
    node += "\n"
    txt = txt[:nxt.start()] + node + txt[nxt.start():]
    open(path, "w", encoding="utf-8").write(txt)
    print("넣음:", room_id, (x, y), flag or "")
