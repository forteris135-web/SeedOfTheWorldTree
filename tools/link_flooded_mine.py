#!/usr/bin/env python3
"""확장판 · 잠긴 채굴장 묶음이 **기존 방**에 끼워 넣는 것들 (EXPANSION.md 2장). 두 번 실행해도 안전하다 (이미 있으면 건너뜀).
사용: python3 -I tools/link_flooded_mine.py          → scenes/rooms/*.tscn 을 고치고, 끝에 연결 검사를 한다
      python3 -I tools/link_flooded_mine.py --dry    → 무엇을 바꿀지만 적는다
      python3 -I tools/link_flooded_mine.py --check  → 고치지 않고 연결 검사만 (문제가 있으면 exit 1)
      --root <방 폴더>  → scenes/rooms 대신 다른 폴더(사본)에 적용·검사

**통합할 때 꼭:** 이 묶음의 브랜치에는 기존 방(수관·마을·채굴장·심연 10곳)을 일부러 기준판 그대로 두었다 (다른 묶음과 방 파일이
부딪히지 않게). 그래서 브랜치 그대로는 잠긴 채굴장 입구·금 간 벽 벽장이 없다. 다른 묶음(특히 levels)을 합친 **뒤에** 이 도구를
한 번 돌리고 → `--check` 가 "잘못된 포탈 0, 지도 겹침 0" → `python3 -I tools/audit_rooms.py` 와 `--locked` 오류 0
→ `res://tools/probe_mine.tscn -- --linked` 실패 0 을 확인한다.

1) 채굴장 · 책임자의 방(mine_deep): 오른쪽 벽을 1800 밀어(3000 → 4800) 심연 포탈 너머로 **수액에 잠긴 통로**를 낸다.
   통로 바닥 위에 수액 웅덩이 세 개(sap_pool: 수액 위 걷기가 없으면 느려지고 체력이 깎인다), 끝에 잠긴 채굴장 포탈
   (requires_ability "sap_walk" → 잠긴 길 "수액이 깊다…"), 돌아오는 자리 Markers/FromFlooded.
   지도: 책임자의 방이 넓어지므로 심연 지역 방(region "abyss", 숨겨진 방 제외 — abyss_01·abyss_02·moon_garden·abyss_boss 와
   다른 묶음이 더한 심연 방)의 map_offset.x 를 +1800 (책임자의 방 오른쪽 끝과 겹칠 때만 → 두 번 돌려도 한 번만 민다).
   옛 저장 파일의 지도(가 본 방의 자리)는 책임자의 방에 끼우는 MapFix 노드(scripts/world/map_offset_fix.gd)가 바로잡는다.
2) 수관·마을·채굴장·심연에 **금 간 벽** 2개씩 (벽장 CLOSETS 표; 채굴장은 관의 복도·책임자의 방): 바깥벽에 붙은 작은 벽장 = 안쪽 바닥(단단) + 디딤 턱(one_way)
   + 천장 + 금 간 벽(cracked_wall, 벽 부수기 능력이 있어야 부서짐). 벽장 안에 숨겨진 방(<지역>_hidden_N)으로 가는 포탈과
   돌아오는 자리 Markers/FromHiddenN. 본편 경로는 바꾸지 않는다 (옆 갈래).
좌표계: 왼쪽 위 (0,0), 아래로 y 증가. 소녀 키 134, 한 번 점프 최고 271px, 달리기 점프 가로 434px.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scenes", "rooms")
if "--root" in sys.argv:
    ROOT = sys.argv[sys.argv.index("--root") + 1]
DRY = "--dry" in sys.argv
CHECK_ONLY = "--check" in sys.argv

EXT_CRACKED = '[ext_resource type="PackedScene" uid="uid://c1seedcrackedwall" path="res://scenes/world/cracked_wall.tscn" id="50_cracked_wall"]\n'
EXT_SAP = '[ext_resource type="PackedScene" uid="uid://c1seedsappool" path="res://scenes/world/sap_pool.tscn" id="54_sap_pool"]\n'
EXT_MAPFIX = '[ext_resource type="Script" path="res://scripts/world/map_offset_fix.gd" id="56_map_fix"]\n'
EXT_PORTAL = '[ext_resource type="PackedScene" uid="uid://c1seedportal" path="res://scenes/world/portal.tscn" id="40_portal"]\n'
LOCK_MSG = "수액이 깊다. 수면 위를 걸을 힘이 필요하다."

# 벽장 표: 방 → (벽 쪽 "L"/"R", 벽장 바닥의 윗면 y, 디딤 턱 길이, 턱이 one_way 인가, 숨겨진 방 id)
#  L: 안 0~380, 금 간 벽 380~440, 턱 440~440+ledge.   R(방 너비 W): 안 W-380~W, 벽 W-440~W-380, 턱 W-440-ledge~W-440.
#  벽장 포탈은 안쪽 262(R: W-262) — 아래층 원래 출구 포탈(x 190)과 세로로 겹쳐 보이지 않게 어긋나 있고, 그림(폭 약 230)이 금 간 벽(380)에
#  닿지 않는다. 돌아오는 자리는 170(R: W-170).
#  턱이 기존 발판과 같은 높이로 이어지면(마을 입구 P5, 갱도 P6) 단단한 바닥으로 잇고(one_way 아님), 아니면 아래서 뛰어오르게 one_way.
CLOSETS = {
    "canopy_02": ("L", 700, 180, True, "canopy_hidden_1"),     # P11(800~1120, 700) 옆. P10(300~600, 950) 에서 뛰어올라도 닿는다
    "canopy_04": ("L", 1550, 180, True, "canopy_hidden_2"),    # P2(500~800, 1750) 에서 뛰어올라 턱을 통과한다 (P7 쪽은 이단 점프 없이는 좁은 길이라 피함)
    "village_01": ("R", 1020, 100, False, "village_hidden_1"),  # 지붕 P5(3200~3660, 1020) 와 같은 높이로 이어진다
    "village_02": ("L", 950, 180, True, "village_hidden_2"),   # P2(900~1300, 1150) 에서 뛰어 닿는다
    # 채굴장 둘째 벽장은 책임자의 방(mine_deep) 왼쪽 위: 내려가는 갱도(mine_01)는 왼쪽으로 달려 내려가는 본편 길(P6 → P8 → 바닥)이
    #  벽장 바닥·천장에 막혀 바뀌므로 피했다 (probe_levels 의 mine_01 내려가기 시험). 책임자의 방은 바닥(1100)이 본편 길이고
    #  P2(700~1000, 850) 는 기록물로 가는 옆 발판. 출구 포탈 그림(윗끝 889) 위에 벽장 바닥(아랫면 880)이 오게 840.
    "mine_deep": ("L", 840, 180, True, "mine_hidden_1"),
    "mine_02": ("L", 870, 180, True, "mine_hidden_2"),         # P4(800~1100, 950) 에서 뛰어 닿는다. 포탈 그림(윗끝 889) 위에 바닥이 오게 870
    # P6(3400~3700, 1500) 오른쪽 위. 벽장 바닥(3720~4200, 1320)은 P6 와 겹치지 않고 머리 위로 떠 있어(아랫면 1360 < 머리 1366)
    #  P6 오른쪽 끝에서 걸어 내려가는 길이 그대로다. P6 에서 180 뛰어올라 앞 턱(40px)에 선다.
    "abyss_01": ("R", 1320, 40, False, "abyss_hidden_1"),
    "abyss_02": ("L", 1750, 180, True, "abyss_hidden_2"),      # P2(400~700, 1950) 에서 뛰어올라 턱을 통과한다. P3(900~1200, 1750) 에서 달려도 된다
}
EXTRA_TERRAIN = {}
MAP_SHIFT_REGION = "abyss"   # 이 지역의 방(숨겨진 방 제외)을 민다
MAP_SHIFT_DX = 1800

NODE_RE = re.compile(r'^\[node name="([^"]+)"(?: type="([^"]+)")? parent="([^"]+)"(?: instance=ExtResource\("([^"]+)"\))?\]\n((?:[^\[\n].*\n?)*)\n?', re.M)
MAP_RE = re.compile(r'^map_offset = Vector2\((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)$', re.M)
BOUNDS_RE = re.compile(r'^bounds = Rect2\((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?), (\d+(?:\.\d+)?), (\d+(?:\.\d+)?)\)$', re.M)
REGION_RE = re.compile(r'^region = "([^"]*)"$', re.M)


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


def insert_after_section(txt, parent, nodes_text):
    """parent 아래 마지막 노드 블록 뒤에 끼운다. 자식이 없으면 parent 노드 블록 바로 뒤. parent 가 없으면 Markers 앞에 만든다."""
    last = None
    for m in NODE_RE.finditer(txt):
        if m.group(3) == parent:
            last = m
    if last is None:
        last = find_node(txt, parent)
        if last is None:
            # 부모 노드가 없다 (Hazards 가 없는 방): Markers 앞에 만든다
            m = find_node(txt, "Markers")
            txt = txt[:m.start()] + '[node name="%s" type="Node2D" parent="."]\n\n' % parent + txt[m.start():]
            last = find_node(txt, parent)
    end = last.end()
    head = txt[:end]
    if not head.endswith("\n\n"):
        head = head.rstrip("\n") + "\n\n"
    return head + nodes_text + txt[end:].lstrip("\n")


def add_ext(txt, ext_id, line):
    if ('id="%s"' % ext_id) in txt:
        return txt
    txt = re.sub(r'load_steps=(\d+)', lambda m: "load_steps=%d" % (int(m.group(1)) + 1), txt, count=1)
    last_ext = list(re.finditer(r'^\[ext_resource .*\]\n', txt, re.M))[-1]
    return txt[:last_ext.end()] + line + txt[last_ext.end():]


def platform(name, x, y, w, h, one_way=False, decorate=True):
    s = '[node name="%s" parent="Terrain" instance=ExtResource("3_platform")]\nposition = Vector2(%d, %d)\nsize = Vector2(%d, %d)\n' % (name, x, y, w, h)
    if one_way:
        s += "one_way = true\n"
    if not decorate:
        s += "decorate = false\n"
    return s + "\n"


def cracked(name, x, y, w, h, sid):
    return '[node name="%s" parent="Terrain" instance=ExtResource("50_cracked_wall")]\nposition = Vector2(%d, %d)\nsize = Vector2(%d, %d)\nsecret_id = "%s"\n\n' % (name, x, y, w, h, sid)


def portal(name, x, y, target, spawn, requires="", locked="", art_scale=None):
    s = '[node name="%s" parent="Exits" instance=ExtResource("40_portal")]\nposition = Vector2(%d, %d)\ntarget_scene = "res://scenes/rooms/%s.tscn"\nspawn_name = "%s"\n' % (name, x, y, target, spawn)
    if requires:
        s += 'requires_ability = "%s"\n' % requires
    if locked:
        s += 'locked_message = "%s"\n' % locked
    if art_scale:
        s += "art_scale = %s\n" % art_scale
    return s + "\n"


def marker(name, x, y):
    return '[node name="%s" type="Marker2D" parent="Markers"]\nposition = Vector2(%d, %d)\n\n' % (name, x, y)


def sap_pool(name, x, y, w, h):
    return '[node name="%s" parent="Hazards" instance=ExtResource("54_sap_pool")]\nposition = Vector2(%d, %d)\nsize = Vector2(%d, %d)\n\n' % (name, x, y, w, h)


def read(room):
    return open(os.path.join(ROOT, room + ".tscn"), encoding="utf-8").read()


def save(room, txt):
    if DRY:
        return
    open(os.path.join(ROOT, room + ".tscn"), "w", encoding="utf-8").write(txt)


def room_width(txt):
    m = re.search(r'^bounds = Rect2\((-?\d+), (-?\d+), (\d+), (\d+)\)$', txt, re.M)
    return int(m.group(3))


# ---------- 1) 책임자의 방: 수액에 잠긴 통로 ----------
def link_mine_deep():
    room = "mine_deep"
    txt = read(room)
    if 'name="ToFlooded"' in txt:
        print("%s: 잠긴 통로 이미 있음, 건너뜀" % room)
        return
    w = room_width(txt)
    if w != 3000:
        raise SystemExit("%s: 너비가 3000 이 아니다(%d) — 표를 다시 맞춰야 한다" % (room, w))
    txt = add_ext(txt, "54_sap_pool", EXT_SAP)
    txt = txt.replace("bounds = Rect2(0, 0, 3000, 1400)", "bounds = Rect2(0, 0, 4800, 1400)", 1)
    txt = set_prop(txt, "WallRight", "position", "Vector2(4800, -100)")
    txt = set_prop(txt, "Ceiling", "size", "Vector2(4800, 100)")
    terrain = platform("P1Flooded", 3000, 1100, 1800, 300)
    txt = insert_after_section(txt, "Terrain", terrain)
    pools = sap_pool("SapPool1", 3060, 1020, 460, 100) + sap_pool("SapPool2", 3600, 1020, 420, 100) + sap_pool("SapPool3", 4080, 1020, 420, 100)
    txt = insert_after_section(txt, "Hazards", pools)
    txt = insert_after_section(txt, "Markers", marker("FromFlooded", 4700, 1032))
    txt = insert_after_section(txt, "Exits", portal("ToFlooded", 4610, 1100, "flooded_mine_01", "FromMineDeep", "sap_walk", LOCK_MSG))
    save(room, txt)
    print("%s: 오른쪽으로 1800 넓힘 + 수액 웅덩이 3 + 잠긴 채굴장 포탈(sap_walk) + FromFlooded" % room)


def room_files():
    return sorted(f[:-5] for f in os.listdir(ROOT) if f.endswith(".tscn"))


def map_rect(txt):
    m = MAP_RE.search(txt)
    b = BOUNDS_RE.search(txt)
    if not (m and b):
        return None
    x, y = float(m.group(1)), float(m.group(2))
    return (x, y, x + float(b.group(3)), y + float(b.group(4)))


def shift_abyss_map():
    """책임자의 방 지도 사각형이 심연 첫 방(abyss_01)과 겹치면 심연 지역 방들을 MAP_SHIFT_DX 만큼 민다.
    (원래 책임자의 방 35600~38600, 심연 39300~ → 넓히면 ~40400 이라 겹침 → 41100~ 으로. 민 뒤에는 겹치지 않아 다시 밀지 않는다.)"""
    deep = map_rect(read("mine_deep"))
    first = map_rect(read("abyss_01"))
    if deep is None or first is None:
        raise SystemExit("mine_deep / abyss_01 의 지도 자리를 읽지 못했다")
    if first[0] >= deep[2]:
        print("지도 자리 밀기: 이미 비켜 있음 (책임자의 방 끝 %d ≤ abyss_01 %d), 건너뜀" % (deep[2], first[0]))
        return
    moves = []
    for room in room_files():
        if "_hidden_" in room:
            continue   # 숨겨진 방은 처음부터 민 자리에 놓았다
        txt = read(room)
        rg = REGION_RE.search(txt)
        m = MAP_RE.search(txt)
        if not (rg and m) or rg.group(1) != MAP_SHIFT_REGION:
            continue
        x, y = float(m.group(1)), float(m.group(2))
        new = MAP_RE.sub("map_offset = Vector2(%d, %d)" % (x + MAP_SHIFT_DX, y), txt, count=1)
        save(room, new)
        rid = re.search(r'^room_id = "([^"]+)"$', txt, re.M)
        moves.append((rid.group(1) if rid else room, x, y))
        print("지도 자리 밀기: %s (%d, %d) → (%d, %d)" % (room, x, y, x + MAP_SHIFT_DX, y))
    add_map_fix(moves)


def add_map_fix(moves):
    """옛 저장 파일(가 본 방의 지도 자리가 저장돼 있음)을 위해, 넓어진 책임자의 방에 들어서는 순간 민 방들의 옛 자리를 새 자리로 고치는 노드."""
    room = "mine_deep"
    txt = read(room)
    if 'name="MapFix"' in txt or not moves:
        return
    txt = add_ext(txt, "56_map_fix", EXT_MAPFIX)
    items = ", ".join('"%s": [Vector2(%d, %d), Vector2(%d, %d)]' % (rid, x, y, x + MAP_SHIFT_DX, y) for rid, x, y in moves)
    node = '[node name="MapFix" type="Node" parent="."]\nscript = ExtResource("56_map_fix")\nmoves = {%s}\n\n' % items
    m = find_node(txt, "Markers")
    txt = txt[:m.start()] + node + txt[m.start():]
    save(room, txt)
    print("%s: 옛 저장 파일 지도 바로잡기(MapFix) %d방" % (room, len(moves)))


# ---------- 2) 금 간 벽 벽장 ----------
def link_closet(room):
    side, fy, ledge, ledge_one_way, hidden = CLOSETS[room]
    txt = read(room)
    if 'name="CrackedWall1"' in txt:
        print("%s: 금 간 벽 이미 있음, 건너뜀" % room)
        return
    w = room_width(txt)
    txt = add_ext(txt, "50_cracked_wall", EXT_CRACKED)
    txt = add_ext(txt, "40_portal", EXT_PORTAL)
    if side == "L":
        floor_in = (0, fy, 440, 40)
        ledge_rect = (440, fy, ledge, 40)
        ceiling = (0, fy - 360, 440, 40)
        wall = (380, fy - 320, 60, 320)
        px, mx = 262, 170
    else:
        floor_in = (w - 440, fy, 440, 40)
        ledge_rect = (w - 440 - ledge, fy, ledge, 40)
        ceiling = (w - 440, fy - 360, 440, 40)
        wall = (w - 440, fy - 320, 60, 320)
        px, mx = w - 262, w - 170
    terrain = ""
    if ledge_one_way:
        terrain += platform("ClosetFloor1", *floor_in, decorate=False)
        terrain += platform("ClosetLedge1", *ledge_rect, one_way=True)
    else:
        # 턱이 기존 발판과 같은 높이로 이어진다: 하나의 단단한 바닥
        x0 = min(floor_in[0], ledge_rect[0])
        terrain += platform("ClosetFloor1", x0, fy, 440 + ledge, 40, decorate=False)
    terrain += platform("ClosetCeiling1", *ceiling, decorate=False)
    for extra in EXTRA_TERRAIN.get(room, []):
        terrain += platform(*extra)
    terrain += cracked("CrackedWall1", *wall, "cracked_%s_1" % room)
    txt = insert_after_section(txt, "Terrain", terrain)
    txt = insert_after_section(txt, "Markers", marker("FromHidden1", mx, fy - 68))
    txt = insert_after_section(txt, "Exits", portal("ToHidden1", px, fy, hidden, "FromMain", art_scale="0.2"))
    save(room, txt)
    print("%s: 금 간 벽 벽장(%s, 바닥 %d) + 포탈 → %s" % (room, side, fy, hidden))


# ---------- 연결 검사 ----------
PORTAL_RE = re.compile(r'^target_scene = "res://scenes/rooms/([^"]+)\.tscn"\nspawn_name = "([^"]*)"$', re.M)
MARKER_RE = re.compile(r'^\[node name="([^"]+)" type="Marker2D" parent="Markers"\]$', re.M)


def check():
    """모든 방의 포탈 → 건너갈 방의 등장 자리(Markers/<spawn_name>)가 있는지, 지도 사각형(map_offset + bounds)이 겹치지 않는지."""
    rooms = {r: read(r) for r in room_files()}
    markers = {r: set(MARKER_RE.findall(t)) for r, t in rooms.items()}
    bad = 0
    for r, t in rooms.items():
        for target, spawn in PORTAL_RE.findall(t):
            if target not in rooms:
                print("  잘못된 포탈: %s → %s.tscn (방이 없다)" % (r, target))
                bad += 1
            elif spawn and not spawn.startswith("Grass:") and spawn not in markers[target]:
                print("  잘못된 포탈: %s → %s.tscn 의 등장 자리 '%s' 가 없다" % (r, target, spawn))
                bad += 1
    rects = {r: map_rect(t) for r, t in rooms.items()}
    rects = {r: v for r, v in rects.items() if v}
    keys = sorted(rects)
    over = 0
    for a in range(len(keys)):
        for b in range(a + 1, len(keys)):
            p, q = rects[keys[a]], rects[keys[b]]
            if p[0] < q[2] and q[0] < p[2] and p[1] < q[3] and q[1] < p[3]:
                print("  지도 겹침: %s %s ↔ %s %s" % (keys[a], tuple(int(v) for v in p), keys[b], tuple(int(v) for v in q)))
                over += 1
    print("연결 검사 (%d방): 잘못된 포탈 %d, 지도 겹침 %d" % (len(rooms), bad, over))
    return bad + over


if __name__ == "__main__":
    if CHECK_ONLY:
        sys.exit(1 if check() else 0)
    link_mine_deep()
    shift_abyss_map()
    for r in CLOSETS:
        link_closet(r)
    print("끝" + (" (dry)" if DRY else ""))
    if not DRY:
        check()
