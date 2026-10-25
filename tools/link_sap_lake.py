#!/usr/bin/env python3
"""확장판 · 수액의 호수 입구를 기존 방에 끼워 넣는다 (EXPANSION.md 2장: "마을 한구석의 어두운 틈을 등불로 비춰야 숨은 내리막이 보인다").
사용: python3 tools/link_sap_lake.py     → scenes/rooms/village_02.tscn 을 고친다. 두 번 실행해도 안전하다 (이미 있으면 건너뜀).

하는 일 (마을 · 등불 골목 village_02):
  - 골목 왼쪽 구석(x 720, 바닥 1400 — 입구 포탈 Exit1(190) 오른쪽)에 **숨은 포탈**(scenes/world/hidden_portal.tscn)
    Exits/ToHiddenDescent 를 둔다: 처음엔 어두운 틈으로만 보이고(지도에도 없음), 등불이 없어도 700px 안에선 옅은 청록빛이 맥동한다.
    v1.1.0(기획자 요청 19): 등불과 상관없이 400px 안에 오면 '본 것'(깃발 seen_hidden_descent — 지도 ◆, 잠긴 포탈 모양).
    들어가는 조건은 그대로 등불(lantern) — 없이 손길을 내밀면 "깊은 틈 아래에서 수액 냄새가 올라온다… 등불 없이는 내려갈 수 없다".
    등불을 가진 채 드러나면 "등불이 어두운 틈을 비춘다…" (scripts/world/hidden_portal.gd).
    건너가는 곳: hidden_descent 의 Markers/FromVillage. (지도: hidden_descent 의 map_offset 이 이 자리 바로 아래로 맞춰져 있다)
    2026-10-19 검토: 예전 자리(x 2330)는 큰길 한가운데(계단 선반 아래)라 '한구석'이 아니었다 → 왼쪽 구석으로.
  - 숨은 내리막에서 되돌아올 자리 Markers/FromHiddenDescent (820, 1332).
통합 뒤 확인: godot --headless --path . res://tools/probe_lake.tscn -- --hidden  (숨은 입구 검사가 '건너뜀' 없이 돌아야 한다)
방 파일 편집 방식은 tools/add_secrets.py 의 insert_after_section 과 같다 (노드 블록 뒤에 끼워 넣기).
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scenes", "rooms")
ROOM = "village_02"
EXT_ID = "63_hidden_portal"
EXT_LINE = '[ext_resource type="PackedScene" uid="uid://c1seedhiddenportal" path="res://scenes/world/hidden_portal.tscn" id="%s"]\n' % EXT_ID

PORTAL = (
    '[node name="ToHiddenDescent" parent="Exits" instance=ExtResource("%s")]\n' % EXT_ID
    + 'position = Vector2(720, 1400)\n'
    + 'target_scene = "res://scenes/rooms/hidden_descent.tscn"\n'
    + 'spawn_name = "FromVillage"\n'
    + 'requires_ability = "lantern"\n'
    + 'locked_message = "깊은 틈 아래에서 수액 냄새가 올라온다… 등불 없이는 내려갈 수 없다"\n'
    + 'reveal_message = "등불이 어두운 틈을 비춘다. 아래로 이어지는 길이 보인다."\n\n'
)
MARKER = '[node name="FromHiddenDescent" type="Marker2D" parent="Markers"]\nposition = Vector2(820, 1332)\n\n'

NODE_RE = re.compile(r'^\[node name="([^"]+)"(?: type="([^"]+)")? parent="([^"]+)"(?: instance=ExtResource\("([^"]+)"\))?\]\n((?:[^\[\n].*\n?)*)\n?', re.M)


def find_node(txt, name):
    for m in NODE_RE.finditer(txt):
        if m.group(1) == name:
            return m
    return None


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


def main():
    path = os.path.join(ROOT, ROOM + ".tscn")
    txt = open(path, encoding="utf-8").read()
    changed = False
    if ('id="%s"' % EXT_ID) not in txt:
        txt = re.sub(r'load_steps=(\d+)', lambda m: "load_steps=%d" % (int(m.group(1)) + 1), txt, count=1)
        last_ext = list(re.finditer(r'^\[ext_resource .*\]\n', txt, re.M))[-1]
        txt = txt[:last_ext.end()] + EXT_LINE + txt[last_ext.end():]
        changed = True
    if 'name="FromHiddenDescent"' not in txt:
        txt = insert_after_section(txt, "Markers", MARKER)
        changed = True
    if 'name="ToHiddenDescent"' not in txt:
        txt = insert_after_section(txt, "Exits", PORTAL)
        changed = True
    if changed:
        txt = re.sub(r'\n{3,}', "\n\n", txt)
        open(path, "w", encoding="utf-8").write(txt)
        print("%s: 숨은 내리막 입구(ToHiddenDescent)·되돌아올 자리(FromHiddenDescent) 끼워 넣음" % ROOM)
    else:
        print("%s: 이미 있음, 건너뜀" % ROOM)


if __name__ == "__main__":
    main()
