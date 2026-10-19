#!/usr/bin/env python3
"""방 전수 점검 (표준 라이브러리만). 방 .tscn 을 읽어 소녀의 점프 모델로
  - 등장 표식에서 포탈·달빛풀·기록물·아이템·구원 대상·NPC 에 닿을 수 있는지 (이단 점프 없이 / 있이)
  - 닿기는 하는데 '뛸 자리의 여유'가 좁은(60px 미만) 길로만 닿는 목표 = 빠듯함 (오류로 센다)
  - 가시 때문에 막힌 간선 (가시가 없었다면 건너갔을 길)
  - 가시 둘레(뛰는 자리·날아가는 길) 위에 머리 공간을 막는 단단한 지형이 있는지 (뛰면 머리를 박고 가시로 떨어지는 함정)
  - 막다른 자리 (갈 수는 있는데 포탈·달빛풀로 되돌아올 수 없는 면)
  - one_way 발판에서 아래로 내려갔을 때 가시·방 밖으로 떨어지는지
를 찾는다.

사용:
  python3 tools/audit_rooms.py                 # 25개 방 전부 (ORDER)
  python3 tools/audit_rooms.py mine_01 canopy_03   # 고른 방만
  python3 tools/audit_rooms.py --verbose mine_01   # 면·간선(창 폭까지) 자세히
  python3 tools/audit_rooms.py --oneway            # one_way 후보 발판 목록(규칙 + 내려가기 안전 확인, 파일의 켜짐 상태 그대로 표시)
  python3 tools/audit_rooms.py --robust            # 여유 모델(달리기 580, 점프 속도 98.5%)도 함께 (느리다)
  python3 tools/audit_rooms.py --locked            # 벽 부수기 전(1편 상태): 금 간 벽(cracked_wall)을 단단한 벽으로 치고,
                                                   #  숨겨진 방(_hidden_) 포탈은 [나중에], 그 방에서 돌아오는 FromHidden1/2 등장은 뺀다
                                                   #  → 금 간 벽이 본편 길을 막지 않는지 본다 (기본은 '부서진 뒤' = 벽 없음)

모델 (player.gd 수치): 걷기 380, 달리기 640, 점프 높이 260·최고점 0.4초 → 중력 3250, 초기 속도 1300,
낙하 중력 1.7배, 짧은 점프(일찍 떼면 상승 속도 ×0.4), 코요테 0.1초, 1/60초 적분(소녀와 같은 순서: 중력 → 점프 → 이동).
점프 버튼은 '본 다음 틱'에 먹는다고 치고(사람의 반응·입력 지연) 이륙을 한 틱(가로 ~10px) 늦춘다.
몸: 캡슐 반지름 23 → 가시 판정·지형 충돌 모두 반폭 23, 키 134(발 위로), 발끝 점.
가시 판정 상자(thorns.gd): [x+4, x+w-4] × [y+0.3h, y+h].

'창 폭': 어떤 면에서 다른 면으로 가는 간선은 20px 간격 표본점마다 여러 점프 방식으로 시도해 보고, 같은 방식으로
연속 3개 이상(≥60px)의 표본에서 성공해야 '깨끗한 간선'이다. 1~2개 표본에서만 되는 길은 '좁은 간선'으로 따로 두고,
좁은 간선 없이는 못 닿는 목표를 '빠듯함'으로 보고한다 (사람은 10~20px 안에서 정확히 뛸 수 없다).
"""
import argparse
import collections
import math
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ROOM_DIR = os.environ.get("AUDIT_ROOM_DIR") or os.path.join(ROOT, "scenes", "rooms")   # 다른 폴더의 방을 보려면 AUDIT_ROOM_DIR=...

# ---------------- 소녀 수치 ----------------
DT = 1.0 / 60.0
WALK = 380.0
RUN = 640.0
JUMP_H = 260.0
APEX = 0.4
FALL_MULT = 1.7
CUT = 0.4
MAX_FALL = 1900.0
COYOTE_FRAMES = 6
G = 2.0 * JUMP_H / (APEX * APEX)        # 3250
JV = G * APEX                            # 1300
BODY_HW = 23.0                           # 가시 판정 몸 반폭 (캡슐 반지름)
BODY_H = 134.0
CORE_HW = 23.0                           # 지형 충돌 심 반폭 (캡슐 반지름)
FOOT_R = 23.0                            # 캡슐 반지름 (발끝 둥근 부분)
MAX_FRAMES = 240
SAMPLE_STEP = 20.0                       # 표본 간격 (창 폭 측정 단위)
MIN_WINDOW_SAMPLES = 3                   # 연속 3개(≥60px) 이상 성공해야 깨끗한 간선
TAKEOFF_DELAY_FRAMES = 1                 # 점프 입력이 먹기까지 한 틱
JUMP_REACH = 271.0                       # 실제 측정 점프 높이
HEADROOM_NEED = BODY_H + JUMP_REACH      # 가시 둘레에서 점프가 끊기지 않으려면 필요한 머리 공간 (405)
APPROACH = 460.0                         # 가시 양옆에서 뛰는 자리·날아가는 길의 폭 (달리기 점프 434 + 여유)

# 설계상 나중에(이단 점프를 얻은 뒤) 오는 목표: 기본 모드에서 못 닿아도 '참고'로만 적는다
LATER_TARGETS = {"canopy_01": {"ToHidden"}}
# 이단 점프 없이 도는 방 (수관: 첫 보스 전)
NO_DOUBLE_ROOMS = {"canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_05", "canopy_06", "canopy_07",
                   "canopy_mini_1", "canopy_mini_2", "canopy_boss", "canopy_hidden", "canopy_hidden_1", "canopy_hidden_2"}
BOSS_ROOMS = {"canopy_boss", "mine_boss", "abyss_boss", "flooded_mine_boss"}
# --locked: 벽 부수기 전 (금 간 벽이 단단하다)
LOCKED = False

ORDER = ["canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_05", "canopy_06", "canopy_07",
         "canopy_mini_1", "canopy_mini_2", "canopy_hidden", "canopy_boss",
         "village_01", "village_02", "village_shrine", "village_mini_1",
         "mine_01", "mine_02", "mine_mini_1", "mine_deep", "mine_boss",
         "abyss_01", "abyss_02", "abyss_mini_1", "moon_garden", "abyss_boss",
         # 확장판 · 잠긴 채굴장 묶음 (금 간 벽 뒤 숨겨진 방들은 작아서 함께 돈다)
         "flooded_mine_01", "flooded_mine_02", "flooded_mine_boss",
         "canopy_hidden_1", "canopy_hidden_2", "village_hidden_1", "village_hidden_2",
         "mine_hidden_1", "mine_hidden_2", "abyss_hidden_1", "abyss_hidden_2", "flooded_mine_hidden_1"]


# ---------------- .tscn 파싱 ----------------
def parse_value(v):
    v = v.strip()
    m = re.match(r'^Vector2\(\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*\)$', v)
    if m:
        return (float(m.group(1)), float(m.group(2)))
    m = re.match(r'^Rect2\(\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*\)$', v)
    if m:
        return tuple(float(m.group(i)) for i in range(1, 5))
    m = re.match(r'^PackedVector2Array\((.*)\)$', v)
    if m:
        nums = [float(t) for t in re.findall(r'[-\d.e]+', m.group(1))]
        return [(nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)]
    if v.startswith('"') and v.endswith('"'):
        return v[1:-1]
    if v == "true":
        return True
    if v == "false":
        return False
    m = re.match(r'^ExtResource\("([^"]+)"\)$', v)
    if m:
        return ("ext", m.group(1))
    try:
        return float(v)
    except ValueError:
        return v


def parse_tscn(path):
    ext = {}
    nodes = []
    cur = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.match(r'\[ext_resource type="(\w+)"(?: uid="[^"]*")? path="([^"]+)" id="([^"]+)"\]', line)
            if m:
                ext[m.group(3)] = m.group(2)
                continue
            m = re.match(r'\[node name="([^"]+)"(?: type="(\w+)")?(?: parent="([^"]+)")?(?: instance=ExtResource\("([^"]+)"\))?[^\]]*\]', line)
            if m:
                cur = {"name": m.group(1), "type": m.group(2), "parent": m.group(3),
                       "instance": ext.get(m.group(4)) if m.group(4) else None, "props": {}}
                nodes.append(cur)
                continue
            if line.startswith("["):
                cur = None
                continue
            if cur is not None and "=" in line:
                k, v = line.split("=", 1)
                val = parse_value(v)
                if isinstance(val, tuple) and len(val) == 2 and val[0] == "ext":
                    val = ext.get(val[1], val[1])
                cur["props"][k.strip()] = val
    # 경로와 전역 위치
    by_path = {}
    for n in nodes:
        if n["parent"] is None:
            n["path"] = ""
        elif n["parent"] == ".":
            n["path"] = n["name"]
        else:
            n["path"] = n["parent"] + "/" + n["name"]
        by_path[n["path"]] = n
    for n in nodes:
        pos = n["props"].get("position", (0.0, 0.0))
        if not (isinstance(pos, tuple) and len(pos) == 2):
            pos = (0.0, 0.0)
        gx, gy = pos
        p = n["parent"]
        while p not in (None, "."):
            pn = by_path.get(p)
            if pn is None:
                break
            pp = pn["props"].get("position", (0.0, 0.0))
            if isinstance(pp, tuple) and len(pp) == 2:
                gx += pp[0]
                gy += pp[1]
            p = pn["parent"]
        n["gpos"] = (gx, gy)
    return nodes


# ---------------- 방 모델 ----------------
class Room:
    def __init__(self, room_id, nodes):
        self.id = room_id
        self.nodes = nodes
        root = nodes[0]
        self.bounds = root["props"].get("bounds", (0.0, 0.0, 4800.0, 2400.0))
        self.boss = bool(root["props"].get("is_boss_room", False)) or room_id in BOSS_ROOMS
        self.plats = []     # dict(name, x0,y0,x1,y1, one_way, kind, decorate, suspicious)
        self.polys = []     # dict(name, pts, bbox)
        self.thorns = []    # dict(name, x0,y0,x1,y1)
        self.spawns = []    # (name, x, y)
        self.targets = []   # dict(kind, name, x, y, requires, secret)
        for n in nodes:
            inst = n["instance"] or ""
            p = n["props"]
            gx, gy = n["gpos"]
            base = os.path.basename(inst)
            if base in ("platform.tscn", "secret_wall.tscn", "secret_ceiling.tscn") or (LOCKED and base == "cracked_wall.tscn"):
                w, h = p.get("size", (400.0, 40.0) if base == "platform.tscn" else ((60.0, 200.0) if base == "secret_wall.tscn" else ((60.0, 320.0) if base == "cracked_wall.tscn" else (200.0, 150.0))))
                self.plats.append({"name": n["path"], "short": n["name"], "x0": gx, "y0": gy, "x1": gx + w, "y1": gy + h,
                                   "w": w, "h": h, "one_way": bool(p.get("one_way", False)),
                                   "kind": base[:-5], "decorate": p.get("decorate", True) is not False,
                                   "suspicious": bool(p.get("suspicious", False)), "label": p.get("label_text", "")})
            elif base == "terrain_polygon.tscn":
                pts = [(gx + a, gy + b) for a, b in p.get("polygon", [])]
                xs = [q[0] for q in pts]
                ys = [q[1] for q in pts]
                self.polys.append({"name": n["path"], "short": n["name"], "pts": pts, "bbox": (min(xs), min(ys), max(xs), max(ys))})
            elif base == "thorns.tscn":
                w, h = p.get("size", (400.0, 60.0))
                self.thorns.append({"name": n["name"], "x0": gx + 4.0, "y0": gy + 0.3 * h, "x1": gx + w - 4.0, "y1": gy + h,
                                    "rx0": gx, "ry0": gy, "w": w, "h": h})
            elif base == "portal.tscn":
                self.targets.append({"kind": "portal", "name": n["name"], "x": gx, "y": gy, "requires": p.get("requires_ability", ""), "secret": "",
                                     "later": LOCKED and "_hidden_" in str(p.get("target_scene", ""))})
            elif base == "moonlight_grass.tscn":
                if not p.get("decor", False):
                    self.targets.append({"kind": "grass", "name": n["name"], "x": gx, "y": gy, "requires": "", "secret": ""})
            elif base == "record.tscn":
                self.targets.append({"kind": "record", "name": n["name"], "x": gx, "y": gy, "requires": "", "secret": ""})
            elif base == "pickup.tscn":
                self.targets.append({"kind": "pickup", "name": n["name"], "x": gx, "y": gy, "requires": "", "secret": p.get("hidden_in", ""), "fall_to": p.get("fall_to")})
            elif base == "npc.tscn":
                self.targets.append({"kind": "npc", "name": n["name"], "x": gx, "y": gy, "requires": "", "secret": ""})
            elif base.endswith("_savable.tscn") or base == "owen.tscn":
                self.targets.append({"kind": "rescue", "name": n["name"], "x": gx, "y": gy + 68.0, "requires": "", "secret": ""})
            elif n["type"] == "Marker2D" and n["parent"] == "Markers":
                if n["name"] == "GroundLine" or n["name"].startswith("Hover"):
                    continue
                if LOCKED and re.match(r"FromHidden\d", n["name"]):
                    continue   # 금 간 벽 뒤 숨겨진 방에서 돌아오는 자리(FromHidden1/2): 벽을 부순 뒤에만 온다 (수관의 FromHidden 은 본편)
                self.spawns.append((n["name"], gx, gy))
        self.solids = [pl for pl in self.plats if not pl["one_way"]]
        self._build_surfaces()
        self._build_grid()

    # 서 있을 수 있는 면: 발판 윗변 + 다각형의 위 변
    def _build_surfaces(self):
        self.surfaces = []
        for pl in self.plats:
            self.surfaces.append({"id": len(self.surfaces), "name": pl["short"], "kind": "plat", "x0": pl["x0"], "x1": pl["x1"],
                                  "ya": pl["y0"], "yb": pl["y0"], "one_way": pl["one_way"], "plat": pl, "poly": None})
        for po in self.polys:
            pts = po["pts"]
            for i in range(len(pts)):
                a = pts[i]
                b = pts[(i + 1) % len(pts)]
                ex, ey = b[0] - a[0], b[1] - a[1]
                if ex > 0.0 and abs(ey) < ex * 1.2:
                    self.surfaces.append({"id": len(self.surfaces), "name": "%s[%d]" % (po["short"], i), "kind": "poly", "x0": a[0], "x1": b[0],
                                          "ya": a[1], "yb": b[1], "one_way": False, "plat": None, "poly": po})
        # 걷는 구간: 머리 위 공간(134)이 막히거나 가시가 있는 곳을 잘라 낸다
        self.segments = []
        for s in self.surfaces:
            blocked = []
            if s["kind"] == "plat":
                y = s["ya"]
                for so in self.solids:
                    if so is s["plat"]:
                        continue
                    if so["y0"] < y - 2.0 and so["y1"] > y - BODY_H + 2.0:
                        blocked.append((so["x0"] - CORE_HW, so["x1"] + CORE_HW))
                for po in self.polys:
                    bx0, by0, bx1, by1 = po["bbox"]
                    if by0 < y - 2.0 and by1 > y - BODY_H + 2.0 and bx1 > s["x0"] and bx0 < s["x1"]:
                        # 다각형은 x 를 훑으며 겹치는 자리를 찾는다
                        x = max(s["x0"], bx0 - CORE_HW)
                        run0 = None
                        while x <= min(s["x1"], bx1 + CORE_HW) + 1.0:
                            hit = poly_rect_overlap(po["pts"], x - CORE_HW, y - BODY_H + 2.0, x + CORE_HW, y - 2.0)
                            if hit and run0 is None:
                                run0 = x
                            if not hit and run0 is not None:
                                blocked.append((run0, x))
                                run0 = None
                            x += 10.0
                        if run0 is not None:
                            blocked.append((run0, x))
                for th in self.thorns:
                    if th["y0"] < y and th["y1"] > y - BODY_H:
                        blocked.append((th["x0"] - BODY_HW, th["x1"] + BODY_HW))
            else:
                for th in self.thorns:
                    ymin = min(s["ya"], s["yb"])
                    ymax = max(s["ya"], s["yb"])
                    if th["y0"] < ymax and th["y1"] > ymin - BODY_H:
                        blocked.append((th["x0"] - BODY_HW, th["x1"] + BODY_HW))
            blocked.sort()
            x = s["x0"]
            segs = []
            for b0, b1 in blocked:
                if b1 <= x:
                    continue
                if b0 > x:
                    segs.append((x, min(b0, s["x1"])))
                x = max(x, b1)
                if x >= s["x1"]:
                    break
            if x < s["x1"]:
                segs.append((x, s["x1"]))
            s["segs"] = []
            for a, b in segs:
                if b - a >= 20.0:
                    seg = {"id": len(self.segments), "surf": s, "x0": a, "x1": b,
                           "left_end": abs(a - s["x0"]) < 2.0, "right_end": abs(b - s["x1"]) < 2.0}
                    s["segs"].append(seg)
                    self.segments.append(seg)

    def _build_grid(self):
        self.cell = 200.0
        self.grid_solid = collections.defaultdict(list)
        self.grid_thorn = collections.defaultdict(list)
        self.grid_poly = collections.defaultdict(list)
        self.grid_surf = collections.defaultdict(list)     # x 칸 → 면 (착지 검색용)
        for i, so in enumerate(self.solids):
            for c in self._cells(so["x0"], so["y0"], so["x1"], so["y1"]):
                self.grid_solid[c].append(i)
        for i, th in enumerate(self.thorns):
            for c in self._cells(th["x0"], th["y0"], th["x1"], th["y1"]):
                self.grid_thorn[c].append(i)
        for i, po in enumerate(self.polys):
            for c in self._cells(*po["bbox"]):
                self.grid_poly[c].append(i)
        for s in self.surfaces:
            for cx in range(int(math.floor(s["x0"] / self.cell)), int(math.floor(s["x1"] / self.cell)) + 1):
                self.grid_surf[cx].append(s)

    def _cells(self, x0, y0, x1, y1):
        cx0 = int(math.floor(x0 / self.cell))
        cx1 = int(math.floor(x1 / self.cell))
        cy0 = int(math.floor(y0 / self.cell))
        cy1 = int(math.floor(y1 / self.cell))
        return [(cx, cy) for cx in range(cx0, cx1 + 1) for cy in range(cy0, cy1 + 1)]

    def surf_y(self, s, x):
        if s["kind"] == "plat":
            return s["ya"]
        t = (x - s["x0"]) / (s["x1"] - s["x0"])
        return s["ya"] + (s["yb"] - s["ya"]) * t

    # 심 사각형 [x-23, x+23] × [y-134+1, y-23] 과 발끝 점 (x, y-1) 이 지형과 겹치는지
    def solid_hit(self, x, y):
        rx0, ry0, rx1, ry1 = x - CORE_HW, y - BODY_H + 1.0, x + CORE_HW, y - FOOT_R
        fx, fy = x, y - 1.0
        seen = set()
        for c in self._cells(rx0, ry0, rx1, y):
            for i in self.grid_solid.get(c, ()):
                if i in seen:
                    continue
                seen.add(i)
                so = self.solids[i]
                if rx0 < so["x1"] and rx1 > so["x0"] and ry0 < so["y1"] and ry1 > so["y0"]:
                    return so
                if so["x0"] < fx < so["x1"] and so["y0"] < fy < so["y1"]:
                    return so
        seen = set()
        for c in self._cells(rx0, ry0, rx1, y):
            for i in self.grid_poly.get(c, ()):
                if i in seen:
                    continue
                seen.add(i)
                po = self.polys[i]
                if poly_rect_overlap(po["pts"], rx0, ry0, rx1, ry1) or point_in_poly(po["pts"], fx, fy):
                    return po
        return None

    def thorn_hit(self, x, y):
        rx0, ry0, rx1, ry1 = x - BODY_HW, y - BODY_H, x + BODY_HW, y
        for c in self._cells(rx0, ry0, rx1, ry1):
            for i in self.grid_thorn.get(c, ()):
                th = self.thorns[i]
                if rx0 < th["x1"] and rx1 > th["x0"] and ry0 < th["y1"] and ry1 > th["y0"]:
                    return th
        return None

    # 떨어지다 면을 지나면 그 면에 선다 (가장 높은 면). one_way 도 위에서 내려오면 선다.
    def landing(self, x, y_prev, y_new):
        best = None
        for s in self.grid_surf.get(int(math.floor(x / self.cell)), ()):
            if x < s["x0"] or x > s["x1"]:
                continue
            ys = self.surf_y(s, x)
            if y_prev <= ys + 0.01 and y_new >= ys:
                if best is None or ys < best[1]:
                    best = (s, ys)
        return best

    def seg_at(self, s, x):
        for seg in s["segs"]:
            if seg["x0"] - 0.01 <= x <= seg["x1"] + 0.01:
                return seg
        return None

    # 면 y 위의 x 구간 [x0, x1] 에서 머리 공간을 막는 가장 낮은 단단한 지형 (one_way 제외). (밑면 y, 이름) 또는 None.
    def lowest_solid_above(self, x0, x1, y, need):
        best = None
        for so in self.solids:
            if so["x1"] <= x0 or so["x0"] >= x1:
                continue
            if so["y1"] <= y - 2.0 and so["y1"] > y - need:
                if best is None or so["y1"] > best[0]:
                    best = (so["y1"], so["short"])
        for po in self.polys:
            bx0, by0, bx1, by1 = po["bbox"]
            if bx1 <= x0 or bx0 >= x1 or by0 >= y - 2.0:
                continue
            if poly_rect_overlap(po["pts"], x0, y - need, x1, y - 2.0):
                # 겹치는 가장 낮은 꼭짓점 높이로 근사
                ys = [q[1] for q in po["pts"] if x0 - 1.0 <= q[0] <= x1 + 1.0 and q[1] < y - 2.0]
                yy = max(ys) if ys else y - need + 1.0
                if best is None or yy > best[0]:
                    best = (yy, po["short"])
        return best


# ---------------- 기하 ----------------
def point_in_poly(pts, x, y):
    inside = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def seg_intersect(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) > (b[1] - a[1]) * (c[0] - a[0])
    return ccw(p1, p3, p4) != ccw(p2, p3, p4) and ccw(p1, p2, p3) != ccw(p1, p2, p4)


def poly_rect_overlap(pts, x0, y0, x1, y1):
    if x1 <= x0 or y1 <= y0:
        return False
    for px, py in pts:
        if x0 < px < x1 and y0 < py < y1:
            return True
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    for c in corners:
        if point_in_poly(pts, c[0], c[1]):
            return True
    n = len(pts)
    for i in range(n):
        a = pts[i]
        b = pts[(i + 1) % n]
        for k in range(4):
            if seg_intersect(a, b, corners[k], corners[(k + 1) % 4]):
                return True
    return False


# ---------------- 점프 모델 ----------------
class Model:
    def __init__(self, run=RUN, jv_scale=1.0):
        self.run = run
        self.jv = JV * jv_scale

    # 한 번의 시도: 시작 발 위치(x, y), 수평 속도 vx(상수), 사건표 events = {frame: "jump"|"cut"}
    # start_jump 면 '점프 입력을 본 자리'가 x 이고 실제 이륙은 TAKEOFF_DELAY_FRAMES 틱 뒤(그동안 가로로 흐른다).
    def fly(self, room, x, y, vx, events, start_jump, max_frames=MAX_FRAMES):
        vy = 0.0
        thorn = None
        bottom = room.bounds[1] + room.bounds[3] + 200.0
        if start_jump and vx != 0.0:
            for _ in range(TAKEOFF_DELAY_FRAMES):
                nx = x + vx * DT
                if room.solid_hit(nx, y) is None:
                    x = nx
        on_ground = start_jump   # 첫 프레임에 땅에서 점프하면 중력 없음
        for f in range(max_frames):
            ev = events.get(f)
            if not on_ground:
                g = G * (FALL_MULT if vy > 0.0 else 1.0)
                if ev == "cut" and vy < 0.0:
                    vy *= CUT
                vy = min(vy + g * DT, MAX_FALL)
            if ev == "jump" or (f == 0 and start_jump):
                vy = -self.jv
            on_ground = False
            # 가로 이동 → 벽
            nx = x + vx * DT
            if vx != 0.0 and room.solid_hit(nx, y) is not None:
                vx = 0.0
                nx = x
            x = nx
            # 세로 이동 → 착지 / 머리 박기
            ny = y + vy * DT
            if vy > 0.0:
                land = room.landing(x, y, ny)
                if land is not None:
                    s, ys = land
                    th = room.thorn_hit(x, ys)
                    if th is not None and thorn is None:
                        thorn = th
                    return ("land", s, x, thorn, f)
                so = room.solid_hit(x, ny)
                if so is not None:
                    # 벽에 스치며 떨어진다: 심이 벽에서 떨어지도록 살짝 밀어내고 계속 (다각형이면 포기)
                    if "x0" not in so or "x1" not in so:
                        return ("stuck", None, x, thorn, f)
                    vx = 0.0
                    x = so["x0"] - CORE_HW - 0.5 if x < (so["x0"] + so["x1"]) * 0.5 else so["x1"] + CORE_HW + 0.5
                    if room.solid_hit(x, ny) is not None:
                        return ("stuck", None, x, thorn, f)
            else:
                so = room.solid_hit(x, ny)
                if so is not None:
                    vy = 0.0
                    ny = y
            y = ny
            th = room.thorn_hit(x, y)
            if th is not None and thorn is None:
                thorn = th
            if y > bottom:
                return ("out", None, x, thorn, f)
        return ("timeout", None, x, thorn, max_frames)

    # 한 점에서 해 볼 모든 시도 (시작 점프 여부, vx, 사건표, 이름, 묶음 이름)
    # 묶음(family): 같은 조작 방식. 창 폭은 묶음별로 잰다. 이단 점프는 둘째 점프 시각마다 다른 묶음(시각도 맞춰야 하므로).
    def profiles(self, double, left_end, right_end):
        out = []
        speeds = [(self.run, "달"), (WALK, "걷")]
        for d, dn in ((1, "→"), (-1, "←")):
            for v, vn in speeds:
                out.append((True, d * v, {}, "점프%s%s" % (vn, dn)))
                out.append((True, d * v, {8: "cut"}, "짧은점프%s%s" % (vn, dn)))
                if double:
                    for f2 in (12, 18, 24, 30, 36, 42, 48, 54):
                        out.append((True, d * v, {f2: "jump"}, "이단%s%s@%d" % (vn, dn, f2)))
        out.append((True, 0.0, {}, "제자리점프"))
        if double:
            out.append((True, 0.0, {24: "jump"}, "제자리이단"))
        for d, is_end in ((1, right_end), (-1, left_end)):
            if not is_end:
                continue
            dn = "→" if d > 0 else "←"
            for v, vn in ((120.0, "천천히"), (WALK, "걷"), (self.run, "달")):
                out.append((False, d * v, {}, "내려서기%s%s" % (vn, dn)))
            for v, vn in speeds:
                out.append((False, d * v, {4: "jump"}, "코요테점프%s%s" % (vn, dn)))
                if double:
                    out.append((False, d * v, {4: "jump", 28: "jump"}, "코요테이단%s%s" % (vn, dn)))
                    for f2 in (20, 40):
                        out.append((False, d * v, {f2: "jump"}, "떨어지다점프%s%s@%d" % (vn, dn, f2)))
        return out


def sample_points(seg):
    """20px 간격 표본 (양 끝 포함). 연속 표본 3개 = 60px 창."""
    xs = []
    x = seg["x0"]
    while x < seg["x1"]:
        xs.append(round(x, 1))
        x += SAMPLE_STEP
    xs.append(round(seg["x1"], 1))
    out = []
    for v in xs:
        if not out or v - out[-1] >= 5.0:
            out.append(v)
    return out


# ---------------- 그래프 ----------------
class Graph:
    def __init__(self, room, model, double):
        self.room = room
        self.model = model
        self.double = double
        self.edges = collections.defaultdict(set)        # seg id -> set(seg id)   (깨끗한 간선: 창 폭 ≥ 60px)
        self.narrow = collections.defaultdict(set)       # seg id -> set(seg id)   (좁은 간선: 1~2 표본에서만)
        self.edge_how = {}                                # (a, b) -> 설명 (가장 넓은 묶음)
        self.edge_width = {}                              # (a, b) -> 창 폭(px)
        self.thorn_edges = {}                             # (a, b, thorn) -> 설명
        self.drop_issues = []                             # one_way 내려가기 문제
        self.drops = collections.defaultdict(set)
        self._hits = collections.defaultdict(lambda: collections.defaultdict(set))   # (a,b) -> family -> set(sample index)
        self._fixed = {}                                  # (a,b) -> how  (걷기·턱·내려서기·one_way 내려가기: 창 폭 무관)
        self._build()

    def _add_fixed(self, a, b, how):
        if a == b:
            return
        if (a, b) not in self._fixed:
            self._fixed[(a, b)] = how

    def _build(self):
        room = self.room
        # 걷기 이음: 같은 높이로 맞닿은 면, 또는 30px 이하로 내려서는 턱
        for a in room.segments:
            for b in room.segments:
                if a is b:
                    continue
                if a["x1"] + 40.0 < b["x0"] or b["x1"] + 40.0 < a["x0"]:
                    continue
                ya = room.surf_y(a["surf"], min(max(b["x0"], a["x0"]), a["x1"]))
                yb = room.surf_y(b["surf"], min(max(a["x1"], b["x0"]), b["x1"]))
                # 맞닿는 쪽 끝의 높이 차
                if a["x1"] <= b["x0"] + 40.0 and a["x1"] >= b["x0"] - 40.0:
                    ya = room.surf_y(a["surf"], a["x1"])
                    yb = room.surf_y(b["surf"], b["x0"])
                elif b["x1"] <= a["x0"] + 40.0 and b["x1"] >= a["x0"] - 40.0:
                    ya = room.surf_y(a["surf"], a["x0"])
                    yb = room.surf_y(b["surf"], b["x1"])
                dy = yb - ya
                if -6.0 <= dy <= 6.0:
                    self._add_fixed(a["id"], b["id"], "걷기")
                elif 6.0 < dy <= 30.0:
                    self._add_fixed(a["id"], b["id"], "턱 내려서기")
        # 점프·내려서기
        for seg in room.segments:
            profs = self.model.profiles(self.double, seg["left_end"], seg["right_end"])
            xs = sample_points(seg)
            for si, x in enumerate(xs):
                y = room.surf_y(seg["surf"], x)
                at_left = si == 0
                at_right = si == len(xs) - 1
                for start_jump, vx, events, name in profs:
                    sx = x
                    if not start_jump:
                        # 끝에서 내려서기: 심이 발판을 벗어난 자리에서 시작
                        if vx > 0.0 and not at_right:
                            continue
                        if vx < 0.0 and not at_left:
                            continue
                        sx = x + (CORE_HW + 1.0) * (1.0 if vx > 0.0 else -1.0)
                    res, s, lx, thorn, fr = self.model.fly(room, sx, y, vx, events, start_jump)
                    if res != "land":
                        continue
                    tseg = room.seg_at(s, lx)
                    if tseg is None or tseg is seg:
                        continue
                    how = "%s x=%.0f→%.0f (%.2f초)" % (name, x, lx, fr * DT)
                    if thorn is not None:
                        key = (seg["id"], tseg["id"], thorn["name"])
                        if key not in self.thorn_edges:
                            self.thorn_edges[key] = how
                        continue
                    key = (seg["id"], tseg["id"])
                    if name.startswith("내려서기"):
                        self._add_fixed(seg["id"], tseg["id"], how)
                    else:
                        self._hits[key][name].add(si)
                        self.edge_how.setdefault(key, how)
            # one_way 발판: 아래로 내려가기 (다른 묶음이 소녀 쪽을 만든다 — 여기서는 안전만 본다)
            if seg["surf"]["one_way"]:
                for si, x in enumerate(xs):
                    y = room.surf_y(seg["surf"], x)
                    # 똑바로 내려가기 + 끝에서는 살짝 흘러가며(±60px/s) 내려가기
                    drifts = [0.0]
                    if si == 0:
                        drifts.append(-60.0)
                    if si == len(xs) - 1:
                        drifts.append(60.0)
                    for vx in drifts:
                        res, s, lx, thorn, fr = self.model.fly(room, x, y + 2.0, vx, {}, False)
                        if res == "land":
                            tseg = room.seg_at(s, lx)
                            if thorn is not None:
                                self.drop_issues.append("%s x=%.0f 아래로 내려가면 %s 에 닿는다 (%s 위에 떨어짐)" % (seg["surf"]["name"], x, thorn["name"], s["name"]))
                            elif tseg is not None and tseg is not seg:
                                self.drops[seg["id"]].add(tseg["id"])
                                self._add_fixed(seg["id"], tseg["id"], "one_way 내려가기 x=%.0f" % x)
                        elif res == "out":
                            self.drop_issues.append("%s x=%.0f 아래로 내려가면 방 밖으로 떨어진다" % (seg["surf"]["name"], x))
        # 창 폭 → 깨끗한 간선 / 좁은 간선
        for (a, b), how in self._fixed.items():
            self.edges[a].add(b)
            self.edge_how[(a, b)] = how
            self.edge_width[(a, b)] = 9999.0
        for (a, b), fams in self._hits.items():
            best_n = 0
            best_fam = ""
            best_x = None
            seg = self.room.segments[a]
            xs = sample_points(seg)
            # 이단 점프: 둘째 점프 시각이 다른 묶음끼리는 합치지 않는다 (시각도 맞춰야 하므로)
            for fam, idxs in fams.items():
                # 같은 묶음 안에서 연속 표본의 가장 긴 줄
                run = 0
                best_run = 0
                run_start = None
                best_start = None
                for i in range(len(xs)):
                    if i in idxs:
                        if run == 0:
                            run_start = i
                        run += 1
                        if run > best_run:
                            best_run = run
                            best_start = run_start
                    else:
                        run = 0
                if best_run > best_n:
                    best_n = best_run
                    best_fam = fam
                    best_x = (xs[best_start], xs[best_start + best_run - 1])
            width = best_n * SAMPLE_STEP
            self.edge_width[(a, b)] = width
            if (a, b) in self._fixed:
                continue
            how = "%s x=%.0f~%.0f (창 %.0fpx)" % (best_fam, best_x[0], best_x[1], width)
            self.edge_how[(a, b)] = how
            if best_n >= MIN_WINDOW_SAMPLES:
                self.edges[a].add(b)
            else:
                self.narrow[a].add(b)

    def reach(self, starts, with_narrow=False):
        seen = set(starts)
        q = collections.deque(starts)
        while q:
            a = q.popleft()
            nxt = set(self.edges.get(a, ()))
            if with_narrow:
                nxt |= self.narrow.get(a, set())
            for b in nxt:
                if b not in seen:
                    seen.add(b)
                    q.append(b)
        return seen

    def reverse_reach(self, goals, with_narrow=False):
        rev = collections.defaultdict(set)
        for a, bs in self.edges.items():
            for b in bs:
                rev[b].add(a)
        if with_narrow:
            for a, bs in self.narrow.items():
                for b in bs:
                    rev[b].add(a)
        seen = set(goals)
        q = collections.deque(goals)
        while q:
            b = q.popleft()
            for a in rev.get(b, ()):
                if a not in seen:
                    seen.add(a)
                    q.append(a)
        return seen


# ---------------- 목표를 면에 붙이기 ----------------
def find_segments(room, x, y, dy_tol, x_pad):
    out = []
    for seg in room.segments:
        if x < seg["x0"] - x_pad or x > seg["x1"] + x_pad:
            continue
        cx = min(max(x, seg["x0"]), seg["x1"])
        ys = room.surf_y(seg["surf"], cx)
        if abs(ys - y) <= dy_tol:
            out.append(seg)
    return out


def target_segments(room, t):
    k = t["kind"]
    if k == "portal":
        return find_segments(room, t["x"], t["y"], 20.0, 100.0)
    if k == "grass":
        return find_segments(room, t["x"], t["y"], 20.0, 100.0)
    if k in ("record", "npc"):
        return find_segments(room, t["x"], t["y"], 20.0, 80.0)
    if k == "rescue":
        return find_segments(room, t["x"], t["y"], 24.0, 80.0)
    if k == "pickup":
        out = []
        for seg in room.segments:
            if t["x"] < seg["x0"] - 70.0 or t["x"] > seg["x1"] + 70.0:
                continue
            cx = min(max(t["x"], seg["x0"]), seg["x1"])
            ys = room.surf_y(seg["surf"], cx)
            if ys - 440.0 <= t["y"] <= ys + 40.0:
                out.append(seg)
        # 비밀 천장에서 떨어지는 것은 떨어진 자리에서도 주울 수 있다
        if t.get("fall_to"):
            fx, fy = t["fall_to"]
            out += find_segments(room, fx, fy, 60.0, 70.0)
        return out
    return []


def spawn_segments(room, sx, sy):
    return find_segments(room, sx, sy + 67.0, 20.0, 0.0)


def seg_label(seg):
    s = seg["surf"]
    return "%s[%.0f~%.0f, y%.0f]" % (s["name"], seg["x0"], seg["x1"], s["ya"])


# ---------------- 가시 둘레 머리 공간 ----------------
def thorn_headroom_issues(room):
    """가시 양옆 APPROACH 안의 걷는 면 위에, 점프(271)+키(134) 보다 낮은 단단한 지형이 걸려 있으면 함정:
    턱 근처에서 뛰면 머리를 박고 가시로 떨어진다. (one_way 는 머리가 지나가므로 제외.)"""
    out = []
    for th in room.thorns:
        base_y = th["y1"]          # 가시 밑면 (구덩이 바닥·선반 윗면 근처)
        for seg in room.segments:
            s = seg["surf"]
            y = s["ya"] if s["kind"] == "plat" else min(s["ya"], s["yb"])
            if not (base_y - 90.0 <= y <= base_y + 30.0):
                continue
            # 가시와 맞닿은(60px 안) 면만
            if seg["x1"] < th["x0"] - 60.0 or seg["x0"] > th["x1"] + 60.0:
                continue
            if seg["x1"] <= th["x0"] + 1.0:      # 가시 왼쪽 면
                zx0, zx1 = max(seg["x0"], th["x0"] - APPROACH), th["x1"] + APPROACH
                side = "왼쪽"
            elif seg["x0"] >= th["x1"] - 1.0:    # 가시 오른쪽 면
                zx0, zx1 = th["x0"] - APPROACH, min(seg["x1"], th["x1"] + APPROACH)
                side = "오른쪽"
            else:
                continue
            low = room.lowest_solid_above(zx0, zx1, y, HEADROOM_NEED)
            if low is not None:
                out.append("%s %s 접근 구간 [%.0f~%.0f] 위에 %s (밑면 y%.0f, 머리 공간 %.0f < %.0f): 뛰면 머리를 박고 가시로 떨어진다"
                           % (th["name"], side, zx0, zx1, low[1], low[0], y - low[0], HEADROOM_NEED))
    return sorted(set(out))


# ---------------- 방 하나 점검 ----------------
def audit_room(room_id, model_exact, model_robust, verbose=False, force_double=None):
    path = os.path.join(ROOM_DIR, room_id + ".tscn")
    nodes = parse_tscn(path)
    room = Room(room_id, nodes)
    primary_double = room_id not in NO_DOUBLE_ROOMS
    report = {"id": room_id, "errors": [], "warns": [], "infos": [], "thorn_critical": [], "thorn_info": [], "traps": [], "drops": [], "headroom": []}
    modes = [(False, "이단X"), (True, "이단O")]
    graphs = {}
    for dbl, mname in modes:
        graphs[(dbl, "exact")] = Graph(room, model_exact, dbl)
        if model_robust is not None:
            graphs[(dbl, "robust")] = Graph(room, model_robust, dbl)

    lines = []
    lines.append("=" * 78)
    lines.append("[%s] 경계 %s, 면 %d(걷는 구간 %d), 가시 %d, 등장 %d, 목표 %d, 기본 모드: %s" % (
        room_id, tuple(int(v) for v in room.bounds), len(room.surfaces), len(room.segments), len(room.thorns), len(room.spawns), len(room.targets),
        "이단 점프 있음" if primary_double else "이단 점프 없음"))
    if verbose:
        for seg in room.segments:
            lines.append("   면 #%d %s%s" % (seg["id"], seg_label(seg), " one_way" if seg["surf"]["one_way"] else ""))

    # 가시 둘레 머리 공간 (모드 무관)
    for msg in thorn_headroom_issues(room):
        lines.append("   XX 머리 공간: " + msg)
        report["headroom"].append(msg)

    # 목표 → 면
    tsegs = {}
    for t in room.targets:
        segs = target_segments(room, t)
        tsegs[t["name"]] = segs
        if not segs:
            msg = "%s '%s' (%.0f,%.0f): 서 있을 면이 없다 (가시·벽에 막힌 자리?)" % (t["kind"], t["name"], t["x"], t["y"])
            if t["secret"]:
                report["infos"].append(msg + " [비밀]")
            else:
                report["errors"].append(msg)

    goal_ids = set()
    for t in room.targets:
        if t["kind"] in ("portal", "grass"):
            for seg in tsegs[t["name"]]:
                goal_ids.add(seg["id"])

    for dbl, mname in modes:
        is_primary = (dbl == primary_double) if force_double is None else (dbl == force_double)
        g = graphs[(dbl, "exact")]
        gr = graphs.get((dbl, "robust"))
        tag = "%s%s" % (mname, " (기본)" if is_primary else "")
        lines.append("-- %s --" % tag)
        for sname, sx, sy in room.spawns:
            starts = [s["id"] for s in spawn_segments(room, sx, sy)]
            if not starts:
                msg = "등장 '%s' (%.0f,%.0f) 발 밑에 면이 없다" % (sname, sx, sy)
                lines.append("   !! " + msg)
                if is_primary:
                    report["errors"].append(msg)
                continue
            reach = g.reach(starts)                       # 깨끗한 간선만
            reach_any = g.reach(starts, with_narrow=True)  # 좁은 간선까지
            reach_r = gr.reach(starts) if gr else reach
            unreachable = []
            tight = []
            for t in room.targets:
                segs = tsegs[t["name"]]
                if not segs:
                    continue
                ok = any(s["id"] in reach for s in segs)
                ok_any = any(s["id"] in reach_any for s in segs)
                ok_r = any(s["id"] in reach_r for s in segs)
                label = "%s '%s'" % (t["kind"], t["name"])
                if t["secret"]:
                    label += "[비밀]"
                if t["requires"]:
                    label += "(%s 필요)" % t["requires"]
                if t["name"] in LATER_TARGETS.get(room_id, set()) or t.get("later"):
                    label += "[나중에]"
                if not ok_any:
                    unreachable.append(label)
                elif not ok:
                    # 좁은 간선으로만 닿는다: 어떤 간선이 좁은지 적어 준다
                    tight.append(label + " (좁은 간선으로만)")
                elif not ok_r:
                    tight.append(label + " (여유 모델에서 실패)")
            # 막다른 자리: 갈 수 있는데 포탈·달빛풀로 못 돌아가는 면 (돌아오는 길도 깨끗한 간선이어야 한다)
            back = g.reverse_reach(list(goal_ids))
            traps = [room.segments[i] for i in sorted(reach_any) if i not in back]
            lines.append("   등장 '%s': 면 %d개 도달(좁은 길 포함 %d), 닿을 수 없는 목표 %d, 빠듯한 목표 %d, 막다른 면 %d" % (sname, len(reach), len(reach_any), len(unreachable), len(tight), len(traps)))
            for u in unreachable:
                lines.append("      X 닿을 수 없음: %s" % u)
                if is_primary and "[비밀]" not in u and "[나중에]" not in u:
                    report["errors"].append("등장 '%s' → %s 닿을 수 없음 (%s)" % (sname, u, mname))
                elif is_primary:
                    report["infos"].append("등장 '%s' → %s 닿을 수 없음 (%s)" % (sname, u, mname))
            for u in tight:
                lines.append("      ~ 빠듯함: %s" % u)
                if is_primary and "[비밀]" not in u and "[나중에]" not in u:
                    report["warns"].append("등장 '%s' → %s 빠듯함 (%s)" % (sname, u, mname))
            for tr in traps:
                lines.append("      ! 막다른 면: %s" % seg_label(tr))
                if is_primary:
                    report["traps"].append("등장 '%s' 에서 갈 수 있는 %s 에서는 포탈·달빛풀로 (깨끗한 길로) 못 돌아간다" % (sname, seg_label(tr)))
            if verbose:
                for i in sorted(reach_any):
                    lines.append("      도달 #%d %s%s" % (i, seg_label(room.segments[i]), "" if i in reach else "  (좁은 길로만)"))
        # 가시로 막힌 간선: 깨끗한 길로는 그 면에 못 가는 경우만 '치명'
        all_starts = []
        for sname, sx, sy in room.spawns:
            all_starts += [s["id"] for s in spawn_segments(room, sx, sy)]
        reach_all = g.reach(all_starts)
        reach_all_any = g.reach(all_starts, with_narrow=True)
        for (a, b, thorn), how in sorted(g.thorn_edges.items()):
            msg = "%s → %s : %s 에 막힘 [%s]" % (seg_label(room.segments[a]), seg_label(room.segments[b]), thorn, how)
            critical = (b not in reach_all) and (a in reach_all_any)
            lines.append("      %s 가시 간선: %s" % ("XX" if critical else "  ", msg))
            if is_primary:
                (report["thorn_critical"] if critical else report["thorn_info"]).append(msg)
        for d in sorted(set(g.drop_issues)):
            lines.append("      XX one_way: %s" % d)
            if is_primary:
                report["drops"].append(d)
        # 좁은 간선 목록 (기본 모드에서, 닿는 데 꼭 필요한 것만 표시: 깨끗한 길로 못 가는 면으로 들어가는 간선)
        narrow_needed = []
        for a, bs in sorted(g.narrow.items()):
            for b in sorted(bs):
                if b not in reach_all and a in reach_all_any:
                    narrow_needed.append("#%d %s → #%d %s [%s]" % (a, seg_label(room.segments[a]), b, seg_label(room.segments[b]), g.edge_how[(a, b)]))
        for n in narrow_needed:
            lines.append("      ~~ 좁은 간선(이 길밖에 없음): %s" % n)
        if verbose:
            for (a, b), how in sorted(g.edge_how.items()):
                kind = "간선" if b in g.edges.get(a, ()) else "좁은간선"
                lines.append("      %s #%d→#%d %s" % (kind, a, b, how))
    report["lines"] = lines
    report["room"] = room
    return report


# ---------------- one_way 후보 ----------------
def oneway_candidates(room):
    """규칙: Terrain 의 얇은(≤60) 떠 있는 발판. 바닥·벽·천장이 아니고, 경계에 붙지 않고, 다른 두꺼운 덩어리와 겹치지 않고,
    비밀·수상한 발판이 아니고, 보스 방의 아레나 바닥(=두꺼움)이 아닌 것."""
    bx, by, bw, bh = room.bounds
    out = []
    for pl in room.plats:
        if pl["kind"] != "platform" or pl["suspicious"] or not pl["decorate"]:
            continue
        if pl["h"] > 60.0 or pl["w"] < 120.0:
            continue
        if pl["x0"] <= bx + 1.0 or pl["x1"] >= bx + bw - 1.0 or pl["y0"] <= by + 1.0 or pl["y1"] >= by + bh - 1.0:
            continue
        overlap = False
        for other in room.plats:
            if other is pl:
                continue
            if other["x0"] < pl["x1"] and other["x1"] > pl["x0"] and other["y0"] < pl["y1"] and other["y1"] > pl["y0"]:
                overlap = True
                break
        for po in room.polys:
            if poly_rect_overlap(po["pts"], pl["x0"], pl["y0"], pl["x1"], pl["y1"]):
                overlap = True
        if overlap:
            continue
        out.append(pl)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rooms", nargs="*")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--robust", action="store_true", help="여유 모델(달리기 580, 점프 속도 98.5%%)도 함께 돌린다 (느리다)")
    ap.add_argument("--no-robust", action="store_true", help="(예전 플래그, 이제 기본값)")
    ap.add_argument("--oneway", action="store_true", help="one_way 후보 발판 목록과 내려가기 안전 여부")
    ap.add_argument("--double", choices=["on", "off"], help="기본 모드를 강제 (보고 판정용)")
    ap.add_argument("--model", choices=["exact", "robust"], default="exact", help="robust: 여유 모델을 기본 모델로 써서 어디가 빠듯한지 본다")
    ap.add_argument("--locked", action="store_true", help="벽 부수기 전: 금 간 벽을 단단하게, 숨겨진 방 포탈은 [나중에]")
    args = ap.parse_args()
    global LOCKED
    LOCKED = args.locked
    # ORDER 에 없는 방(확장판 등 새로 더한 .tscn)도 이름순으로 뒤에 붙여 모두 본다
    extra = sorted(fn[:-5] for fn in os.listdir(ROOM_DIR) if fn.endswith(".tscn") and fn[:-5] not in ORDER)
    rooms = args.rooms or (ORDER + extra)
    robust = Model(run=580.0, jv_scale=0.985)
    model_exact = Model() if args.model == "exact" else robust
    model_robust = robust if (args.robust and args.model == "exact") else None
    force = None if args.double is None else (args.double == "on")

    if args.oneway:
        for rid in rooms:
            nodes = parse_tscn(os.path.join(ROOM_DIR, rid + ".tscn"))
            room = Room(rid, nodes)
            cands = oneway_candidates(room)
            was_on = {id(pl): pl["one_way"] for pl in room.plats}    # 파일에 적힌 상태 (표시용)
            print("[%s] one_way 후보 %d개 (파일에서 켜진 것 %d개)" % (rid, len(cands), sum(1 for p in room.plats if p["one_way"])))
            # 후보를 모두 one_way 로 친 상태에서 내려가기를 본다 (자기 몸에 걸리지 않게)
            for pl in cands:
                pl["one_way"] = True
            room.solids = [pl for pl in room.plats if not pl["one_way"]]
            room._build_grid()
            for pl in cands:
                # 내려가기 안전: 발판 아래로 떨어지면 어디에 닿는가
                notes = []
                for x, vxs in ((pl["x0"] + 10.0, (0.0, -60.0)), ((pl["x0"] + pl["x1"]) * 0.5, (0.0,)), (pl["x1"] - 10.0, (0.0, 60.0))):
                    for vx in vxs:
                        res, s, lx, thorn, fr = model_exact.fly(room, x, pl["y0"] + 2.0, vx, {}, False)
                        if thorn is not None:
                            notes.append("가시 %s" % thorn["name"])
                        elif res == "out":
                            notes.append("방 밖")
                        elif res == "land":
                            notes.append("→%s" % s["name"])
                        else:
                            notes.append(res)
                lands = sorted(set(n for n in notes if n.startswith("→")))
                bad = sorted(set(n for n in notes if not n.startswith("→")))
                print("   %-14s (%.0f,%.0f) %.0fx%.0f%s  아래: %s%s" % (pl["short"], pl["x0"], pl["y0"], pl["w"], pl["h"],
                                                                     " [켜짐]" if was_on[id(pl)] else " [꺼짐]", ", ".join(lands) or "-",
                                                                     ("  !! " + ", ".join(bad)) if bad else ""))
        return

    total_err = 0
    summary = []
    for rid in rooms:
        rep = audit_room(rid, model_exact, model_robust, verbose=args.verbose, force_double=force)
        print("\n".join(rep["lines"]))
        n_err = len(rep["errors"]) + len(rep["thorn_critical"]) + len(rep["drops"]) + len(rep["warns"]) + len(rep["headroom"])
        total_err += n_err
        summary.append((rid, len(rep["errors"]), len(rep["thorn_critical"]), len(rep["traps"]), len(rep["warns"]), len(rep["drops"]), len(rep["headroom"]), len(rep["thorn_info"])))
        if rep["errors"] or rep["thorn_critical"] or rep["traps"] or rep["warns"] or rep["drops"] or rep["headroom"]:
            print("   >> 문제 요약 [%s]" % rid)
            for e in rep["errors"]:
                print("      오류: " + e)
            for e in rep["thorn_critical"]:
                print("      가시: " + e)
            for e in rep["headroom"]:
                print("      머리공간: " + e)
            for e in rep["drops"]:
                print("      one_way: " + e)
            for e in rep["traps"]:
                print("      막다름: " + e)
            for e in rep["warns"]:
                print("      빠듯: " + e)
        for e in rep["infos"]:
            print("      참고: " + e)
    print("\n" + "=" * 78)
    print("%-14s %6s %6s %6s %6s %8s %8s %8s" % ("방", "오류", "가시", "막다름", "빠듯", "one_way", "머리공간", "가시참고"))
    for row in summary:
        print("%-14s %6d %6d %6d %6d %8d %8d %8d" % row)
    print("오류(닿을 수 없음+치명 가시+one_way+빠듯+머리 공간) 합계: %d" % total_err)
    sys.exit(1 if total_err > 0 else 0)


if __name__ == "__main__":
    main()
