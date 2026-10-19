#!/usr/bin/env python3
"""채굴장·잠긴 채굴장 방에 그림 장식(Props)을 놓는다 (판정 없음 — 겉모습만).

사용:  python3 -I tools/add_mine_props.py          (적용)
       python3 -I tools/add_mine_props.py --check  (방 파일이 이 표와 같은지만 본다)

- 방 파일의 Props 노드(지형 Terrain 바로 앞 = 지형·소녀 뒤에 그려짐)를 이 표대로 다시 만든다 (여러 번 돌려도 같다).
- 장식 종류:
    prop   : TerrainProp (scripts/world/terrain_prop.gd) — 지역 atlas 조각 하나 (밑동 가운데가 자리)
    wheel  : Waterwheel (scripts/world/waterwheel.gd) — 도는 물레방아 (자리 = 바퀴 축)
    lamp   : MachineLamp (scripts/world/machine_lamp.gd) — 기계 표시등 (flag 가 서면 lamp_on 색으로)
- 자리 고르는 기준: 발판·가시·포탈·달빛풀과 겹치지 않게, 발판처럼 보이는 조각(등불 선반 등)은 쓰지 않는다,
  붉은 수정(= 채굴장 가시)이 박힌 조각은 바닥에 두지 않는다. 뒤 장식은 shade 로 조금 어둡게.
- 무쇠 펌프 문(잠긴 채굴장 · 배관 위의 오른쪽 위 포탈)과 싸움터의 표시등은 펌프를 정화하기 전 빨강, 정화 뒤 초록.
"""
import re
import sys

PUMP = "boss_pump_defeated"
DIM = (0.8, 0.78, 0.78)

# 방 → [(이름, 종류, (x, y), {속성})]
PROPS = {
    # ---- 채굴장 (나무 비계·크레인·교수대 모양 등불 기둥)
    "mine_01": [
        ("Crane", "prop", (300, 3000), {"piece": "crane_a", "shade": DIM}),
        ("Gallows", "prop", (860, 440), {"piece": "gallows_a", "shade": DIM}),
        ("FrameB", "prop", (2150, 3000), {"piece": "frame_b", "shade": DIM}),
    ],
    "mine_02": [
        ("Gallows", "prop", (600, 1200), {"piece": "gallows_a", "shade": DIM}),
        ("FrameB", "prop", (1500, 1200), {"piece": "frame_b", "shade": DIM}),
        ("Crane", "prop", (2950, 1200), {"piece": "crane_a", "shade": DIM, "flip_h": True}),
        ("FrameA", "prop", (4000, 1200), {"piece": "frame_a", "shade": DIM}),
    ],
    "mine_boss": [
        ("Crane", "prop", (860, 1500), {"piece": "crane_a", "shade": DIM}),
        ("FrameB", "prop", (3480, 1500), {"piece": "frame_b", "shade": DIM}),
    ],
    "mine_deep": [
        ("Gallows", "prop", (1900, 1100), {"piece": "gallows_a", "shade": DIM}),
        ("FrameA", "prop", (2700, 1100), {"piece": "frame_a", "shade": DIM}),
        ("Crane", "prop", (3800, 1100), {"piece": "crane_a", "shade": DIM, "flip_h": True}),
    ],
    "mine_hidden_1": [
        ("FrameB", "prop", (600, 700), {"piece": "frame_b", "shade": DIM}),
    ],
    "mine_hidden_2": [
        ("Gallows", "prop", (560, 700), {"piece": "gallows_a", "shade": DIM}),
    ],
    "mine_mini_1": [
        ("FrameB", "prop", (1250, 1300), {"piece": "frame_b", "shade": DIM}),
        ("Gallows", "prop", (2050, 1300), {"piece": "gallows_a", "shade": DIM, "flip_h": True}),
    ],
    # ---- 잠긴 채굴장 (물레방아·기계 벽·기계 문·표시등·관)
    "flooded_mine_01": [
        ("PanelA", "prop", (760, 1100), {"piece": "panel_a", "shade": DIM}),
        ("LampA", "lamp", (700, 940), {"lamp": "lamp_y"}),
        ("Wheel1", "wheel", (1530, 1000), {"art_scale": 0.7}),
        ("Elbow", "prop", (2150, 1100), {"piece": "pipe_elbow", "shade": DIM}),
        ("Wheel2", "wheel", (2905, 1012), {"art_scale": 0.55, "speed": 0.4, "with_tower": False}),
        ("Gate", "prop", (3810, 1100), {"piece": "gate_a", "shade": DIM}),
        ("LampGateL", "lamp", (3700, 800), {"lamp": "lamp_y"}),
        ("LampGateR", "lamp", (3920, 800), {"lamp": "lamp_y"}),
    ],
    "flooded_mine_02": [
        ("PanelA", "prop", (1000, 2100), {"piece": "panel_a", "shade": DIM}),
        ("Wheel", "wheel", (1660, 1972), {"art_scale": 0.55, "speed": -0.38}),
        ("PanelB", "prop", (2300, 2100), {"piece": "panel_b", "shade": DIM}),
        ("Gate", "prop", (2810, 420), {"piece": "gate_a", "shade": DIM}),
        ("LampGateL", "lamp", (2700, 120), {"lamp": "lamp_r", "lamp_on": "lamp_g", "flag": PUMP}),
        ("LampGateR", "lamp", (2920, 120), {"lamp": "lamp_r", "lamp_on": "lamp_g", "flag": PUMP}),
    ],
    "flooded_mine_boss": [
        ("WheelL", "wheel", (850, 1372), {"art_scale": 0.65, "speed": -0.3}),
        ("Gate", "prop", (1760, 1500), {"piece": "gate_a", "shade": (0.72, 0.7, 0.7), "art_scale": 1.15}),
        ("LampGateL", "lamp", (1600, 1000), {"lamp": "lamp_r", "lamp_on": "lamp_g", "flag": PUMP, "art_scale": 0.5}),
        ("LampGateR", "lamp", (1920, 1000), {"lamp": "lamp_r", "lamp_on": "lamp_g", "flag": PUMP, "art_scale": 0.5}),
        ("WheelR", "wheel", (2900, 1372), {"art_scale": 0.65, "speed": 0.3, "with_tower": False}),
        ("LampP", "lamp", (3300, 1150), {"lamp": "lamp_p", "pulse": 0.3}),
    ],
    "flooded_mine_hidden_1": [
        ("PanelB", "prop", (520, 700), {"piece": "panel_b", "shade": DIM}),
        ("LampB", "lamp", (520, 490), {"lamp": "lamp_b"}),
        ("Rock", "prop", (1300, 700), {"piece": "rock_a", "shade": DIM}),
    ],
}

SCRIPTS = {
    "prop": ("res://scripts/world/terrain_prop.gd", "61_prop"),
    "wheel": ("res://scripts/world/waterwheel.gd", "62_wheel"),
    "lamp": ("res://scripts/world/machine_lamp.gd", "63_lamp"),
}


def _val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, tuple) and len(v) == 3:
        return "Color(%g, %g, %g, 1)" % v
    return '"%s"' % v


def _block(entries) -> str:
    out = ['[node name="Props" type="Node2D" parent="."]']
    for name, kind, (x, y), props in entries:
        out.append("")
        out.append('[node name="%s" type="Node2D" parent="Props"]' % name)
        out.append("position = Vector2(%g, %g)" % (x, y))
        out.append('script = ExtResource("%s")' % SCRIPTS[kind][1])
        for k, v in props.items():
            out.append("%s = %s" % (k, _val(v)))
    return "\n".join(out) + "\n"


def _strip_props(txt: str) -> str:
    """기존 Props 노드와 그 자식 블록을 지운다."""
    blocks = re.split(r"\n(?=\[node )", txt)
    keep = []
    for b in blocks:
        head = b.split("\n", 1)[0]
        if head.startswith("[node "):
            nm = re.search(r'name="([^"]+)"', head)
            pa = re.search(r'parent="([^"]+)"', head)
            name = nm.group(1) if nm else ""
            parent = pa.group(1) if pa else ""
            if (name == "Props" and parent == ".") or parent == "Props" or parent.startswith("Props/"):
                continue
        keep.append(b)
    return "\n".join(keep)


def _ensure_ext(txt: str, kind: str) -> str:
    path, rid = SCRIPTS[kind]
    if 'id="%s"' % rid in txt:
        return txt
    lines = txt.split("\n")
    last = max(i for i, l in enumerate(lines) if l.startswith("[ext_resource"))
    lines.insert(last + 1, '[ext_resource type="Script" path="%s" id="%s"]' % (path, rid))
    txt = "\n".join(lines)
    m = re.search(r"load_steps=(\d+)", txt)
    if m:
        txt = txt.replace(m.group(0), "load_steps=%d" % (int(m.group(1)) + 1), 1)
    return txt


def apply(room: str, entries, check: bool) -> bool:
    path = "scenes/rooms/%s.tscn" % room
    txt = open(path, encoding="utf-8").read()
    new = _strip_props(txt)
    for kind in sorted({e[1] for e in entries}):
        new = _ensure_ext(new, kind)
    i = new.find('\n[node name="Terrain" type="Node2D" parent="."]')
    if i < 0:
        raise SystemExit("%s: Terrain 노드를 못 찾음" % room)
    new = new[: i + 1] + _block(entries) + "\n" + new[i + 1 :]
    same = new == txt
    if not check and not same:
        open(path, "w", encoding="utf-8").write(new)
    return same


def main() -> None:
    check = "--check" in sys.argv
    bad = []
    for room, entries in PROPS.items():
        if not apply(room, entries, check):
            bad.append(room)
    if check:
        print("장식 표와 다른 방: %d %s" % (len(bad), bad))
        sys.exit(1 if bad else 0)
    print("장식 놓음: %d방 (바뀐 방 %s)" % (len(PROPS), bad))


if __name__ == "__main__":
    main()
