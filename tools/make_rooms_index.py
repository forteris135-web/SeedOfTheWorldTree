#!/usr/bin/env python3
"""방 목록 만들기: scenes/rooms/*.tscn 를 읽어 data/map/rooms_index.json 을 쓴다 (v1.1.0 기획자 요청 21·22·25).

지도·달빛풀 이동 목록·저장 칸 요약·포탈 안내가 모두 이 한 파일의 방 이름을 쓴다 (scripts/world/room_index.gd 가 읽는다).
방 파일을 고친 뒤(이름·자리·포탈·달빛풀·금 간 벽·기록물) 다시 돌린다.

  사용: python3 -I tools/make_rooms_index.py          → 다시 만든다
        python3 -I tools/make_rooms_index.py --check  → 지금 방 파일과 다르면 exit 1 (tools/regress.sh 가 돈다)

파일 형식:
  {"region_labels": {지역: 이름},
   "rooms": {room_id: {"name", "region", "offset":[x,y], "bounds":[x,y,w,h], "boss":bool,
                       "markers": {이름:[x,y]},
                       "portals": [{"node","pos":[x,y],"to":room_id,"spawn","requires","hidden":bool}],
                       "grasses": [{"id","name","pos":[x,y],"decor":bool}],
                       "cracked": [secret_id...], "records": [record_id...]}}}
  자리(pos·markers)는 방 원점 기준 (부모 노드 자리를 더한 값). offset = Room.map_offset, bounds = Room.bounds.
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ROOMS_DIR = os.path.join(ROOT, "scenes", "rooms")
OUT = os.path.join(ROOT, "data", "map", "rooms_index.json")

# RoomIndex.REGION_LABEL 와 같아야 한다 (tools/probe_map.gd 가 견준다)
REGION_LABELS = {"canopy": "수관", "village": "마을", "mine": "채굴장", "flooded_mine": "잠긴 채굴장", "sap_lake": "수액의 호수", "abyss": "심연"}

# scripts/world/room.gd 의 기본값 (방 파일에 적히지 않은 값)
ROOM_DEFAULTS = {"bounds": [0, 0, 4800, 2400], "region": "canopy", "room_id": "", "display_name": "", "map_offset": [0, 0], "is_boss_room": False}

KIND_OF_SCENE = {
    "res://scenes/world/portal.tscn": "portal",
    "res://scenes/world/hidden_portal.tscn": "hidden_portal",
    "res://scenes/world/moonlight_grass.tscn": "grass",
    "res://scenes/world/cracked_wall.tscn": "cracked",
    "res://scenes/world/record.tscn": "record",
}

NODE_RE = re.compile(r'^\[node (.*)\]\s*$')
ATTR_RE = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|ExtResource\("[^"]*"\)|\S+)')
EXT_RE = re.compile(r'^\[ext_resource (.*)\]\s*$')
PROP_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_/]*) = (.*)$')


def num(s):
    f = float(s)
    return int(f) if f == int(f) else f


def parse_value(v):
    v = v.strip()
    if v.startswith('"') and v.endswith('"'):
        return json.loads(v)   # 글자 (따옴표·역슬래시 풀기)
    if v in ("true", "false"):
        return v == "true"
    m = re.match(r'^Vector2i?\(([-\d.e]+), ([-\d.e]+)\)$', v)
    if m:
        return [num(m.group(1)), num(m.group(2))]
    m = re.match(r'^Rect2i?\(([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+)\)$', v)
    if m:
        return [num(m.group(i)) for i in range(1, 5)]
    if re.match(r'^-?\d+(\.\d+)?(e-?\d+)?$', v):
        return num(v)
    return v   # 그 밖(ExtResource·배열 등)은 글자 그대로 — 여기서는 쓰지 않는다


def parse_tscn(path):
    """→ (ext: {id: path}, nodes: [{"name","type","parent","instance","props"}])"""
    ext = {}
    nodes = []
    cur = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            m = EXT_RE.match(line)
            if m:
                attrs = dict(ATTR_RE.findall(m.group(1)))
                ext[json.loads(attrs.get("id", '""'))] = json.loads(attrs.get("path", '""'))
                cur = None
                continue
            m = NODE_RE.match(line)
            if m:
                attrs = dict(ATTR_RE.findall(m.group(1)))
                inst = attrs.get("instance", "")
                im = re.match(r'ExtResource\("([^"]*)"\)', inst)
                cur = {"name": json.loads(attrs["name"]), "type": json.loads(attrs.get("type", '""')),
                       "parent": json.loads(attrs["parent"]) if "parent" in attrs else None,
                       "instance": ext.get(im.group(1), "") if im else "", "props": {}}
                nodes.append(cur)
                continue
            if line.startswith("["):
                cur = None
                continue
            if cur is not None:
                m = PROP_RE.match(line)
                if m:
                    cur["props"][m.group(1)] = parse_value(m.group(2))
    return ext, nodes


_scene_root_cache = {}


def scene_root_props(res_path):
    """인스턴스로 놓은 장면(포탈 등)의 뿌리 노드 기본값."""
    if res_path not in _scene_root_cache:
        props = {}
        fs = os.path.join(ROOT, res_path.replace("res://", ""))
        if os.path.exists(fs):
            _, nodes = parse_tscn(fs)
            if nodes:
                props = dict(nodes[0]["props"])
        _scene_root_cache[res_path] = props
    return _scene_root_cache[res_path]


def node_path(n):
    p = n["parent"]
    if p is None:
        return ""
    return n["name"] if p == "." else p + "/" + n["name"]


def build_room(path):
    _, nodes = parse_tscn(path)
    root = nodes[0]
    rp = dict(ROOM_DEFAULTS)
    rp.update({k: v for k, v in root["props"].items() if k in ROOM_DEFAULTS})
    rid = rp["room_id"] or os.path.splitext(os.path.basename(path))[0]
    # 노드 자리: 부모 자리를 더한다 (방 원점 기준)
    local = {}
    for n in nodes[1:]:
        merged = dict(scene_root_props(n["instance"])) if n["instance"] else {}
        merged.update(n["props"])
        n["merged"] = merged
        pos = merged.get("position", [0, 0])
        if not isinstance(pos, list):
            pos = [0, 0]
        parent_pos = local.get(n["parent"], [0, 0]) if n["parent"] not in (None, ".") else [0, 0]
        p = [num(pos[0] + parent_pos[0]), num(pos[1] + parent_pos[1])]
        local[node_path(n)] = p
        n["pos"] = p
    room = {"name": rp["display_name"] or rid, "region": rp["region"], "offset": rp["map_offset"], "bounds": rp["bounds"],
            "boss": bool(rp["is_boss_room"]), "markers": {}, "portals": [], "grasses": [], "cracked": [], "records": []}
    for n in nodes[1:]:
        props = n["merged"]
        if n["parent"] == "Markers" and n["type"] == "Marker2D":
            room["markers"][n["name"]] = n["pos"]
            continue
        kind = KIND_OF_SCENE.get(n["instance"], "")
        if kind in ("portal", "hidden_portal"):
            target = str(props.get("target_scene", ""))
            room["portals"].append({"node": node_path(n), "pos": n["pos"],
                                    "to": os.path.splitext(os.path.basename(target))[0] if target else "",
                                    "spawn": str(props.get("spawn_name", "")), "requires": str(props.get("requires_ability", "")),
                                    "hidden": kind == "hidden_portal"})
        elif kind == "grass":
            room["grasses"].append({"id": str(props.get("grass_id", "")), "name": str(props.get("display_name", "")),
                                    "pos": n["pos"], "decor": bool(props.get("decor", False))})
        elif kind == "cracked":
            sid = str(props.get("secret_id", ""))
            if sid:
                room["cracked"].append(sid)
        elif kind == "record":
            rec = str(props.get("record_id", ""))
            if rec:
                room["records"].append(rec)
    return rid, room


def build():
    rooms = {}
    for f in sorted(os.listdir(ROOMS_DIR)):
        if not f.endswith(".tscn"):
            continue
        rid, room = build_room(os.path.join(ROOMS_DIR, f))
        rooms[rid] = room
    return {"region_labels": REGION_LABELS, "rooms": dict(sorted(rooms.items()))}


def warnings(data):
    """방 사이 연결 점검 (실패는 아니고 알림만): 포탈 목적지·도착 표식, 지도 칸 겹침, 달빛풀 id 겹침."""
    out = []
    rooms = data["rooms"]
    seen_grass = {}
    for rid, r in rooms.items():
        for p in r["portals"]:
            if p["to"] not in rooms:
                out.append("%s %s: 목적지 방 '%s' 이 없다" % (rid, p["node"], p["to"]))
            elif p["spawn"] and p["spawn"] not in rooms[p["to"]]["markers"]:
                out.append("%s %s: %s 에 도착 표식 '%s' 이 없다" % (rid, p["node"], p["to"], p["spawn"]))
        for g in r["grasses"]:
            if g["decor"] or not g["id"]:
                continue
            if g["id"] in seen_grass:
                out.append("달빛풀 id '%s' 이 %s 와 %s 에 함께 있다" % (g["id"], seen_grass[g["id"]], rid))
            seen_grass[g["id"]] = rid
    ids = list(rooms)
    for i, a in enumerate(ids):
        ra = rooms[a]
        ax, ay = ra["offset"][0] + ra["bounds"][0], ra["offset"][1] + ra["bounds"][1]
        for b in ids[i + 1:]:
            rb = rooms[b]
            bx, by = rb["offset"][0] + rb["bounds"][0], rb["offset"][1] + rb["bounds"][1]
            if ax < bx + rb["bounds"][2] and bx < ax + ra["bounds"][2] and ay < by + rb["bounds"][3] and by < ay + ra["bounds"][3]:
                out.append("지도 칸 겹침: %s ↔ %s" % (a, b))
    return out


def dump(data):
    return json.dumps(data, ensure_ascii=False, indent=1) + "\n"


def main():
    data = build()
    text = dump(data)
    n_rooms = len(data["rooms"])
    n_grass = sum(1 for r in data["rooms"].values() for g in r["grasses"] if not g["decor"] and g["id"])
    n_portal = sum(len(r["portals"]) for r in data["rooms"].values())
    for w in warnings(data):
        print("[방 목록] 알림: " + w)
    if "--check" in sys.argv:
        try:
            with open(OUT, encoding="utf-8") as f:
                old = json.load(f)
        except (OSError, ValueError) as e:
            print("[방 목록] --check: %s 를 읽지 못했다 (%s) → python3 -I tools/make_rooms_index.py 로 만들 것" % (os.path.relpath(OUT, ROOT), e))
            sys.exit(1)
        if old != json.loads(text):
            changed = sorted(set(old.get("rooms", {})) ^ set(data["rooms"])) + \
                sorted(k for k in data["rooms"] if k in old.get("rooms", {}) and old["rooms"][k] != data["rooms"][k])
            print("[방 목록] --check: 방 파일과 다르다 (%s) → python3 -I tools/make_rooms_index.py 로 다시 만들 것" % ", ".join(changed[:12]))
            sys.exit(1)
        print("[방 목록] --check 통과: 방 %d개, 달빛풀 %d개, 포탈 %d개" % (n_rooms, n_grass, n_portal))
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("[방 목록] %s 씀: 방 %d개, 달빛풀 %d개, 포탈 %d개" % (os.path.relpath(OUT, ROOT), n_rooms, n_grass, n_portal))


if __name__ == "__main__":
    main()
