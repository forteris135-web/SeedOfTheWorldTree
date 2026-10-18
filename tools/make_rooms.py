#!/usr/bin/env python3
"""수관 지역의 방(.tscn)을 간단한 설명으로부터 만든다.
사용: python3 tools/make_rooms.py   → scenes/rooms/canopy_02.tscn ... 생성
방을 고치고 싶으면 아래 ROOMS 의 숫자만 바꾸고 다시 실행한다 (손으로 만든 canopy_01·canopy_boss 는 건드리지 않는다).
좌표: 왼쪽 위가 (0,0), 아래로 갈수록 y 가 커진다. 발판은 (x, y, 너비, 높이). 소녀 키는 약 110.
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "rooms")

HEADER = '''[gd_scene load_steps={steps} format=3 uid="uid://{uid}"]

[ext_resource type="Script" path="res://scripts/world/{script}.gd" id="1_room"]
[ext_resource type="PackedScene" uid="uid://c1seedplayer" path="res://scenes/player/player.tscn" id="2_player"]
[ext_resource type="PackedScene" uid="uid://c1seedplatform" path="res://scenes/world/platform.tscn" id="3_platform"]
[ext_resource type="PackedScene" uid="uid://c1seedtouchctl" path="res://scenes/ui/touch_controls.tscn" id="6_touch"]
[ext_resource type="PackedScene" uid="uid://c1seeddebughud" path="res://scenes/ui/debug_hud.tscn" id="7_hud"]
[ext_resource type="PackedScene" uid="uid://c1seedcombathud" path="res://scenes/ui/combat_hud.tscn" id="8_combat_hud"]
[ext_resource type="PackedScene" uid="uid://c1seedmoongrass" path="res://scenes/world/moonlight_grass.tscn" id="9_grass"]
[ext_resource type="Texture2D" path="res://art/backgrounds/{bg}.png" id="11_bg"]
[ext_resource type="Script" path="res://scripts/world/art_backdrop.gd" id="12_art_backdrop"]
[ext_resource type="Script" path="res://scripts/world/light_shafts.gd" id="13_shafts"]
[ext_resource type="Script" path="res://scripts/world/fog_layer.gd" id="14_fog"]
[ext_resource type="Script" path="res://scripts/world/falling_leaves.gd" id="15_leaves"]
[ext_resource type="PackedScene" uid="uid://c1seedroomexit" path="res://scenes/world/room_exit.tscn" id="16_exit"]
[ext_resource type="PackedScene" uid="uid://c1seedthorns" path="res://scenes/world/thorns.tscn" id="17_thorns"]
[ext_resource type="PackedScene" uid="uid://c1seedwoodcutter" path="res://scenes/enemies/woodcutter.tscn" id="20_woodcutter"]
[ext_resource type="PackedScene" uid="uid://c1seedgardener" path="res://scenes/enemies/gardener.tscn" id="21_gardener"]
[ext_resource type="PackedScene" uid="uid://c1seedwoodcuttersav" path="res://scenes/enemies/woodcutter_savable.tscn" id="22_woodcutter_sav"]
[ext_resource type="PackedScene" uid="uid://c1seedgardenersav" path="res://scenes/enemies/gardener_savable.tscn" id="23_gardener_sav"]
[ext_resource type="PackedScene" uid="uid://c1seedashgiant" path="res://scenes/enemies/ash_giant.tscn" id="24_giant"]
[ext_resource type="PackedScene" uid="uid://c1seedbosshud" path="res://scenes/ui/boss_hud.tscn" id="25_boss_hud"]
[ext_resource type="Script" path="res://scripts/world/fog_gate.gd" id="26_gate"]
[ext_resource type="PackedScene" uid="uid://c1seedguard" path="res://scenes/enemies/guard.tscn" id="27_guard"]
[ext_resource type="PackedScene" uid="uid://c1seedguardsav" path="res://scenes/enemies/guard_savable.tscn" id="28_guard_sav"]
[ext_resource type="PackedScene" uid="uid://c1seednpc" path="res://scenes/npcs/npc.tscn" id="29_npc"]
[ext_resource type="PackedScene" uid="uid://c1seedrecord" path="res://scenes/world/record.tscn" id="30_record"]
[ext_resource type="Texture2D" path="res://art/npcs/npc_tia.png" id="31_tia"]
[ext_resource type="Texture2D" path="res://art/npcs/npc_lampkeeper.png" id="32_lampkeeper"]
[ext_resource type="Texture2D" path="res://art/npcs/npc_owen.png" id="33_owen"]
[ext_resource type="PackedScene" uid="uid://c1seedmachine" path="res://scenes/enemies/machine.tscn" id="34_machine"]
[ext_resource type="PackedScene" uid="uid://c1seedowen" path="res://scenes/enemies/owen.tscn" id="35_owen_enemy"]
[ext_resource type="PackedScene" uid="uid://c1seedherbalist" path="res://scenes/enemies/herbalist.tscn" id="36_herbalist"]
[ext_resource type="PackedScene" uid="uid://c1seedherbalistsav" path="res://scenes/enemies/herbalist_savable.tscn" id="37_herbalist_sav"]

[sub_resource type="Environment" id="Environment_glow"]
background_mode = 3
glow_enabled = true
glow_levels/1 = 0.0
glow_levels/2 = 0.5
glow_levels/3 = 1.0
glow_levels/4 = 0.7
glow_levels/5 = 0.3
glow_intensity = 0.6
glow_strength = 1.0
glow_bloom = 0.03
glow_blend_mode = 1
glow_hdr_threshold = 1.0
glow_hdr_scale = 2.0

[sub_resource type="Gradient" id="Gradient_mote"]
offsets = PackedFloat32Array(0, 0.35, 1)
colors = PackedColorArray(1, 0.85, 0.45, 1, 1, 0.85, 0.45, 0.5, 1, 0.85, 0.45, 0)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_mote"]
gradient = SubResource("Gradient_mote")
width = 32
height = 32
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(1, 0.5)

[node name="{name}" type="Node2D"]
script = ExtResource("1_room")
bounds = Rect2(0, 0, {w}, {h})
region = "{region}"
room_id = "{room_id}"
display_name = "{display}"
map_offset = Vector2({mx}, {my})
terrain_color = {terrain_color}
{dark}{extra_props}
[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_glow")

[node name="Backdrop" type="Node2D" parent="."]

[node name="Far" type="Parallax2D" parent="Backdrop"]
scroll_scale = Vector2(0.1, 0.1)

[node name="Sky" type="Sprite2D" parent="Backdrop/Far"]
texture = ExtResource("11_bg")
script = ExtResource("12_art_backdrop")

[node name="Shafts" type="Parallax2D" parent="Backdrop"]
scroll_scale = Vector2(0.3, 0.3)

[node name="LightShafts" type="Node2D" parent="Backdrop/Shafts"]
script = ExtResource("13_shafts")
seed = {seed}

[node name="FogFar" type="Parallax2D" parent="Backdrop"]
scroll_scale = Vector2(0.45, 0.45)

[node name="Fog" type="Sprite2D" parent="Backdrop/FogFar"]
script = ExtResource("14_fog")
drift = Vector2(16, -3)
fog_color = Color(1, 0.95, 0.82, 0.13)
noise_scale = 1.3
seed = {seed}

[node name="Leaves" type="Parallax2D" parent="Backdrop"]
scroll_scale = Vector2(0.8, 0.8)

[node name="FallingLeaves" type="CPUParticles2D" parent="Backdrop/Leaves"]
script = ExtResource("15_leaves")
count = 30

[node name="Motes" type="Parallax2D" parent="Backdrop"]
scroll_scale = Vector2(0.9, 0.9)

[node name="Particles" type="CPUParticles2D" parent="Backdrop/Motes"]
modulate = Color(1.7, 1.5, 1.1, 1)
position = Vector2({cx}, {cy})
amount = 60
lifetime = 9.0
preprocess = 9.0
texture = SubResource("GradientTexture2D_mote")
emission_shape = 3
emission_rect_extents = Vector2({ex}, {ey})
direction = Vector2(0, -1)
spread = 180.0
gravity = Vector2(0, -6)
initial_velocity_min = 8.0
initial_velocity_max = 26.0
scale_amount_min = 0.25
scale_amount_max = 0.7
color = Color(1, 0.85, 0.45, 0.55)

[node name="Terrain" type="Node2D" parent="."]
'''

FOOTER = '''
[node name="FogNear" type="Parallax2D" parent="."]
scroll_scale = Vector2(1.15, 1.15)

[node name="Fog" type="Sprite2D" parent="FogNear"]
script = ExtResource("14_fog")
drift = Vector2(28, -6)
fog_color = Color(1, 0.96, 0.86, 0.06)
noise_scale = 1.9
seed = {seed2}

[node name="CombatHUD" parent="." instance=ExtResource("8_combat_hud")]
{boss_hud}
[node name="TouchControls" parent="." instance=ExtResource("6_touch")]

[node name="DebugHUD" parent="." instance=ExtResource("7_hud")]
'''

ENEMY_RES = {"woodcutter": "20_woodcutter", "gardener": "21_gardener", "woodcutter_sav": "22_woodcutter_sav", "gardener_sav": "23_gardener_sav", "giant": "24_giant", "guard": "27_guard", "guard_sav": "28_guard_sav", "machine": "34_machine", "owen": "35_owen_enemy", "herbalist": "36_herbalist", "herbalist_sav": "37_herbalist_sav"}
NPC_TEX = {"tia": ("31_tia", 0.105), "lampkeeper": ("32_lampkeeper", 0.175), "owen": ("33_owen", 0.165)}


def platform(name, x, y, w, h, label="", decorate=True):
    s = f'\n[node name="{name}" parent="Terrain" instance=ExtResource("3_platform")]\nposition = Vector2({x}, {y})\nsize = Vector2({w}, {h})\n'
    if label:
        s += f'label_text = "{label}"\n'
    if not decorate:
        s += 'decorate = false\n'
    return s


def build(room):
    w, h = room["size"]
    walls = [("WallLeft", -100, -100, 100, h + 200, "", False), ("WallRight", w, -100, 100, h + 200, "", False), ("Ceiling", 0, -100, w, 100, "", False)]
    out = HEADER.format(steps=30, uid=room["uid"], script=room.get("script", "room"), bg=room["bg"], name=room["name"], w=w, h=h,
                        room_id=room["id"], display=room["display"], mx=room["map"][0], my=room["map"][1], seed=room.get("seed", 3),
                        region=room.get("region", "canopy"), terrain_color=room.get("terrain_color", "Color(0.09, 0.085, 0.06, 1)"),
                        dark=("dark = true\n" if room.get("dark") else ""),
                        cx=w // 2, cy=h // 2, ex=w // 2 + 300, ey=h // 2 + 300,
                        extra_props=room.get("extra_props", ""))
    for p in walls:
        out += platform(*p)
    for i, p in enumerate(room["platforms"]):
        out += platform(f"P{i+1}", *p)
    if room.get("thorns"):
        out += '\n[node name="Hazards" type="Node2D" parent="."]\n'
        for i, (x, y, tw) in enumerate(room["thorns"]):
            out += f'\n[node name="Thorns{i+1}" parent="Hazards" instance=ExtResource("17_thorns")]\nposition = Vector2({x}, {y})\nsize = Vector2({tw}, 60)\n'
    out += '\n[node name="Markers" type="Node2D" parent="."]\n'
    for mname, (x, y) in room["markers"].items():
        out += f'\n[node name="{mname}" type="Marker2D" parent="Markers"]\nposition = Vector2({x}, {y})\n'
    out += '\n[node name="Exits" type="Node2D" parent="."]\n'
    for i, ex in enumerate(room["exits"]):
        x, y, ew, eh, target, spawn = ex[:6]
        out += f'\n[node name="Exit{i+1}" parent="Exits" instance=ExtResource("16_exit")]\nposition = Vector2({x}, {y})\ntarget_scene = "res://scenes/rooms/{target}.tscn"\nspawn_name = "{spawn}"\n'
        if len(ex) > 6:
            out += f'requires_ability = "{ex[6]}"\n'
        out += f'\n[sub_resource type="RectangleShape2D" id="ExitShape{i+1}"]\nsize = Vector2({ew}, {eh})\n' if False else ''
        out += f'\n[node name="Shape" type="CollisionShape2D" parent="Exits/Exit{i+1}"]\nshape = SubResource("ExitShape{i+1}")\n'
    out += '\n[node name="Interactables" type="Node2D" parent="."]\n'
    for i, (x, y, sc) in enumerate(room.get("decor_grass", [])):
        out += f'\n[node name="Decor{i+1}" parent="Interactables" instance=ExtResource("9_grass")]\nposition = Vector2({x}, {y})\nart_scale = {sc}\nis_open = true\ndecor = true\n'
    for i, (x, y, gid, gname) in enumerate(room.get("grasses", [])):
        out += f'\n[node name="Grass{i+1}" parent="Interactables" instance=ExtResource("9_grass")]\nposition = Vector2({x}, {y})\ngrass_id = "{gid}"\ndisplay_name = "{gname}"\n'
    for npc in room.get("npcs", []):
        nid, x, y = npc[0], npc[1], npc[2]
        tex, sc = NPC_TEX[nid]
        out += f'\n[node name="Npc_{nid}" parent="Interactables" instance=ExtResource("29_npc")]\nposition = Vector2({x}, {y})\nnpc_id = "{nid}"\ntexture = ExtResource("{tex}")\nart_scale = {sc}\n'
        if len(npc) > 3:
            out += f'require_flag = "{npc[3]}"\n'
    for i, (rid, x, y, kind) in enumerate(room.get("records", [])):
        out += f'\n[node name="Record_{rid}" parent="Interactables" instance=ExtResource("30_record")]\nposition = Vector2({x}, {y})\nrecord_id = "{rid}"\nkind = "{kind}"\n'
    if room.get("gate"):
        gx, gy, gh = room["gate"]
        out += f'\n[node name="GateIn" type="StaticBody2D" parent="."]\nposition = Vector2({gx}, {gy})\nscript = ExtResource("26_gate")\nsize = Vector2(60, {gh})\n'
    if room.get("trigger"):
        tx, ty = room["trigger"]
        out += f'\n[node name="BossTrigger" type="Node2D" parent="."]\nposition = Vector2({tx}, {ty})\n'
    out += '\n[node name="Enemies" type="Node2D" parent="."]\n'
    for i, (kind, x, y) in enumerate(room["enemies"]):
        nname = "MiniBoss" if kind == "giant" else f"{kind.capitalize()}{i+1}"
        out += f'\n[node name="{nname}" parent="Enemies" instance=ExtResource("{ENEMY_RES[kind]}")]\nposition = Vector2({x}, {y})\n'
    px, py = room["player"]
    out += f'\n[node name="Player" parent="." instance=ExtResource("2_player")]\nposition = Vector2({px}, {py})\n'
    out += FOOTER.format(seed2=room.get("seed", 3) + 7, boss_hud='\n[node name="BossHUD" parent="." instance=ExtResource("25_boss_hud")]\n' if room.get("boss_hud") else "")
    # 출구 모양 서브리소스는 헤더 뒤에 넣어야 한다
    shapes = ""
    for i, ex in enumerate(room["exits"]):
        ew, eh = ex[2], ex[3]
        shapes += f'\n[sub_resource type="RectangleShape2D" id="ExitShape{i+1}"]\nsize = Vector2({ew}, {eh})\n'
    out = out.replace('\n[node name="' + room["name"] + '" type="Node2D"]', shapes + '\n[node name="' + room["name"] + '" type="Node2D"]', 1)
    return out


# 발판 높이 기준: 소녀는 발판 윗면에서 68 위에 선다 (등장 자리 y = 발판 y - 68)
ROOMS = [
    {  # 위로 오르는 방
        "name": "Canopy02", "id": "canopy_02", "display": "수관 · 바람의 틈", "uid": "c1seedcanopy02", "bg": "bg_canopy_1", "seed": 4,
        "size": (2400, 2600), "map": (4800, -1600),
        "platforms": [
            (0, 2400, 900, 300, "바람의 틈"), (900, 2420, 700, 280, "", False), (1600, 2400, 800, 300),
            (200, 2150, 260, 40), (700, 1950, 260, 40), (1250, 1800, 300, 40), (1800, 1600, 300, 40),
            (1350, 1350, 300, 40), (800, 1150, 300, 40), (300, 950, 300, 40), (800, 700, 320, 40), (1400, 500, 320, 40),
            (1900, 300, 500, 80, "위로"),
        ],
        "thorns": [(900, 2360, 700)],
        "markers": {"FromCanopy01": (120, 2332), "FromCanopy03": (2200, 232)},
        "exits": [(-50, 2250, 80, 300, "canopy_01", "FromCanopy02"), (2360, 180, 80, 240, "canopy_03", "FromCanopy02")],
        "grasses": [(2050, 300, "canopy_wind", "수관 · 바람의 틈 위")],
        "enemies": [("woodcutter", 1950, 1543), ("gardener", 950, 643), ("woodcutter", 1450, 1293)],
        "player": (120, 2332),
    },
    {  # 긴 복도
        "name": "Canopy03", "id": "canopy_03", "display": "수관 · 잎의 회랑", "uid": "c1seedcanopy03", "bg": "bg_canopy_2", "seed": 5,
        "size": (5200, 1400), "map": (7200, -2400),
        "platforms": [
            (0, 1100, 1500, 300, "잎의 회랑"), (1500, 1120, 300, 280, "", False), (1800, 1100, 1500, 300), (3300, 1120, 400, 280, "", False), (3700, 1100, 1500, 300),
            (1400, 880, 220, 40), (1700, 760, 240, 40), (2300, 850, 300, 40), (3200, 860, 240, 40), (3550, 720, 260, 40), (3900, 860, 240, 40),
            (4400, 820, 300, 40), (600, 820, 300, 40),
        ],
        "thorns": [(1500, 1060, 300), (3300, 1060, 400)],
        "markers": {"FromCanopy02": (120, 1032), "FromCanopy04": (5080, 1032)},
        "exits": [(-50, 900, 80, 300, "canopy_02", "FromCanopy03"), (5160, 900, 80, 300, "canopy_04", "FromCanopy03")],
        "grasses": [],
        "enemies": [("woodcutter", 900, 1043), ("gardener", 2450, 793), ("woodcutter", 2900, 1043), ("gardener_sav", 4200, 1043), ("woodcutter", 4700, 1043), ("gardener", 4550, 763)],
        "player": (120, 1032),
    },
    {  # 갈림길
        "name": "Canopy04", "id": "canopy_04", "display": "수관 · 가지 갈림길", "uid": "c1seedcanopy04", "bg": "bg_canopy_1", "seed": 6,
        "size": (3200, 2200), "map": (12400, -3200),
        "platforms": [
            (0, 2000, 3200, 200, "갈림길"),
            (500, 1750, 300, 40), (1000, 1550, 300, 40), (1500, 1350, 320, 40), (2000, 1150, 320, 40), (2500, 950, 320, 40),
            (1200, 800, 900, 60, "높은 가지 (기록물 자리)"), (2900, 700, 300, 60),
        ],
        "thorns": [],
        "markers": {"FromCanopy03": (120, 1932), "FromBoss": (3080, 1932)},
        "exits": [(-50, 1800, 80, 300, "canopy_03", "FromCanopy04"), (3160, 1800, 80, 300, "canopy_boss", "FromCanopy04")],
        "grasses": [(400, 2000, "canopy_fork", "수관 · 갈림길")],
        "enemies": [("woodcutter", 1300, 1943), ("woodcutter", 2200, 1943), ("gardener", 1650, 743)],
        "player": (120, 1932),
    },
    {  # 숨겨진 둥지 (중간 보스)
        "name": "CanopyHidden", "id": "canopy_hidden", "display": "수관 · 잿가지의 둥지", "uid": "c1seedcanopyhidden", "bg": "bg_canopy_2", "seed": 9,
        "script": "miniboss_room", "boss_hud": True,
        "size": (2600, 1500), "map": (1200, -2400),
        "extra_props": 'boss_name = "잿가지 거인"\n',
        "platforms": [(0, 1300, 2600, 200, "잿가지의 둥지"), (300, 1050, 260, 40), (2100, 1000, 300, 40), (1150, 850, 300, 40)],
        "thorns": [],
        "markers": {"FromCanopy01": (220, 1232)},
        "exits": [(-50, 1100, 80, 300, "canopy_01", "FromHidden")],
        "grasses": [],
        "gate": (560, 1300, 800), "trigger": (700, 1200),
        "enemies": [("giant", 1700, 1183)],
        "player": (220, 1232),
    },
]

VILLAGE_TERRAIN = "Color(0.11, 0.085, 0.06, 1)"
ROOMS += [
    {  # 마을 입구
        "name": "Village01", "id": "village_01", "display": "마을 · 입구의 거리", "uid": "c1seedvillage01", "bg": "bg_village_1", "seed": 21,
        "region": "village", "terrain_color": VILLAGE_TERRAIN,
        "size": (4200, 1600), "map": (19200, -2523),
        "platforms": [
            (0, 1400, 4200, 200, "가지 위의 마을"),
            (700, 1150, 480, 50, "지붕"), (1500, 1000, 420, 50, "지붕"), (2300, 1180, 520, 50, "지붕"), (3200, 1020, 460, 50, "지붕"),
        ],
        "thorns": [],
        "markers": {"FromCanopy": (120, 1332), "FromVillage02": (4080, 1332)},
        "exits": [(-50, 1200, 80, 300, "canopy_boss", "FromVillage"), (4160, 1200, 80, 300, "village_02", "FromVillage01")],
        "grasses": [(480, 1400, "village_gate", "마을 · 입구의 등불")],
        "records": [("village_poster", 1900, 1400, "poster")],
        "enemies": [("guard", 1300, 1343), ("guard_sav", 2900, 1343)],
        "player": (120, 1332),
    },
    {  # 등불 골목 (티아, 사당으로 오르는 길)
        "name": "Village02", "id": "village_02", "display": "마을 · 등불 골목", "uid": "c1seedvillage02", "bg": "bg_village_2", "seed": 22,
        "region": "village", "terrain_color": VILLAGE_TERRAIN,
        "size": (3800, 1600), "map": (23400, -2523),
        "platforms": [
            (0, 1400, 3800, 200, "등불 골목"),
            (900, 1150, 400, 50, "계단"), (1500, 950, 400, 50, "계단"), (2100, 760, 400, 50, "계단"), (2700, 560, 1100, 70, "사당으로"),
            (3100, 1400, 700, 200, "", False),
        ],
        "thorns": [],
        "markers": {"FromVillage01": (120, 1332), "FromShrine": (3550, 503), "FromMine": (3600, 1332)},
        "exits": [(-50, 1200, 80, 300, "village_01", "FromVillage02"), (3760, 380, 80, 240, "village_shrine", "FromVillage02"), (3760, 1200, 80, 300, "mine_01", "FromVillage")],
        "grasses": [(3350, 1400, "village_tia", "마을 · 마을 끝 달빛풀")],
        "npcs": [("tia", 3050, 1400), ("owen", 2850, 1400, "owen_rescued")],
        "records": [],
        "enemies": [("guard", 1200, 1343)],
        "player": (120, 1332),
    },
    {  # 사당
        "name": "VillageShrine", "id": "village_shrine", "display": "마을 · 세계수의 사당", "uid": "c1seedvillageshrine", "bg": "bg_village_shrine", "seed": 23,
        "region": "village", "terrain_color": VILLAGE_TERRAIN,
        "size": (2400, 1200), "map": (27200, -3200),
        "platforms": [(0, 1000, 2400, 200, "사당"), (1000, 760, 400, 40, "제단")],
        "thorns": [],
        "markers": {"FromVillage02": (120, 932)},
        "exits": [(-50, 800, 80, 300, "village_02", "FromShrine")],
        "grasses": [],
        "npcs": [("lampkeeper", 800, 1000)],
        "records": [("scripture_village", 1200, 760, "book")],
        "enemies": [],
        "player": (120, 932),
    },
]

MINE_TERRAIN = "Color(0.1, 0.07, 0.06, 1)"
ROOMS += [
    {  # 채굴장 입구: 마을 아래로 내려가는 수직 갱도
        "name": "Mine01", "id": "mine_01", "display": "채굴장 · 내려가는 갱도", "uid": "c1seedmine01", "bg": "bg_mine_1", "seed": 31,
        "region": "mine", "terrain_color": MINE_TERRAIN,
        "size": (2600, 3200), "map": (27300, -1000),
        "platforms": [
            (0, 300, 1200, 100, "마을에서 내려오는 길"), (1800, 600, 800, 60), (300, 900, 500, 50), (1200, 1150, 500, 50), (2000, 1400, 600, 50),
            (600, 1700, 600, 50), (1500, 1950, 600, 50), (200, 2250, 500, 50), (1100, 2500, 700, 50, "포스터"), (0, 3000, 2600, 200, "갱도 바닥"),
        ],
        "thorns": [(1200, 240, 600), (1200, 2940, 500)],
        "markers": {"FromVillage": (120, 232), "FromMine02": (2480, 2932)},
        "exits": [(-50, 100, 80, 300, "village_02", "FromMine"), (2560, 2800, 80, 300, "mine_02", "FromMine01")],
        "grasses": [(600, 300, "mine_top", "채굴장 · 갱도 입구")],
        "records": [("mine_poster", 1500, 2500, "poster")],
        "enemies": [("guard", 2300, 532), ("machine", 1400, 1082), ("machine", 500, 2932), ("gardener", 1700, 1882)],
        "player": (120, 232),
    },
    {  # 관이 박힌 복도: 오웬
        "name": "Mine02", "id": "mine_02", "display": "채굴장 · 관의 복도", "uid": "c1seedmine02", "bg": "bg_mine_1", "seed": 32,
        "region": "mine", "terrain_color": MINE_TERRAIN,
        "size": (5000, 1500), "map": (29900, 700),
        "platforms": [
            (0, 1200, 1800, 300, "관의 복도"), (1800, 1230, 500, 270, "", False), (2300, 1200, 2700, 300),
            (800, 950, 300, 40), (1700, 900, 300, 40), (2500, 920, 320, 40), (3400, 880, 300, 40), (4200, 940, 300, 40),
            (3000, 650, 1200, 60, "훼손된 경전"),
        ],
        "thorns": [(1800, 1170, 500)],
        "markers": {"FromMine01": (120, 1132), "FromMineBoss": (4880, 1132), "FromMineDeep": (3900, 582)},
        "exits": [(-50, 1000, 80, 300, "mine_01", "FromMine02"), (4960, 1000, 80, 300, "mine_boss", "FromMine02"), (4960, 450, 80, 240, "mine_deep", "FromMine02", "lantern")],
        "grasses": [(2600, 1200, "mine_owen", "채굴장 · 오웬의 등불")],
        "records": [("scripture_mine", 3600, 650, "book")],
        "enemies": [("machine", 1200, 1132), ("owen", 3300, 1132), ("guard", 4300, 1132), ("machine", 4500, 872)],
        "player": (120, 1132),
    },
    {  # 가장 깊은 곳: 책임자의 방 (어둡다, 등불 필요)
        "name": "MineDeep", "id": "mine_deep", "display": "채굴장 · 책임자의 방", "uid": "c1seedminedeep", "bg": "bg_mine_2", "seed": 33,
        "region": "mine", "terrain_color": MINE_TERRAIN, "dark": True,
        "size": (3000, 1400), "map": (34900, 500),
        "platforms": [(0, 1100, 3000, 300, "책임자의 방"), (700, 850, 300, 40), (1400, 700, 400, 40, "책상"), (2200, 850, 300, 40)],
        "thorns": [],
        "markers": {"FromMine02": (120, 1032), "ToAbyss": (2880, 1032)},
        "exits": [(-50, 900, 80, 300, "mine_02", "FromMineDeep"), (2960, 900, 80, 300, "abyss_01", "FromMineDeep")],
        "grasses": [(2600, 1100, "mine_deep", "채굴장 · 가장 깊은 곳")],
        "records": [("last_order", 1600, 700, "note")],
        "enemies": [("machine", 1000, 1032), ("machine", 2000, 1032)],
        "player": (120, 1032),
    },
]

ABYSS_TERRAIN = "Color(0.08, 0.06, 0.12, 1)"
ROOMS += [
    {  # 심연 초입: 어둡다, 그을린 뿌리
        "name": "Abyss01", "id": "abyss_01", "display": "심연 · 그을린 뿌리", "uid": "c1seedabyss01", "bg": "bg_abyss_1", "seed": 41,
        "region": "abyss", "terrain_color": ABYSS_TERRAIN, "dark": True,
        "size": (4200, 2000), "map": (38000, 500),
        "platforms": [(0, 1800, 4200, 200, "그을린 뿌리"), (700, 1550, 300, 40), (1300, 1350, 320, 40), (2000, 1500, 360, 40), (2700, 1300, 320, 40), (3400, 1500, 300, 40)],
        "thorns": [],
        "markers": {"FromMineDeep": (120, 1732), "FromAbyss02": (4080, 1732)},
        "exits": [(-50, 1600, 80, 300, "mine_deep", "ToAbyss"), (4160, 1600, 80, 300, "abyss_02", "FromAbyss01")],
        "grasses": [(500, 1800, "abyss_entry", "심연 · 초입")],
        "records": [("burnt_roots", 2200, 1800, "stone")],
        "enemies": [("herbalist", 1600, 1732), ("herbalist", 3000, 1732), ("machine", 2400, 1732)],
        "player": (120, 1732),
    },
    {  # 비석의 방
        "name": "Abyss02", "id": "abyss_02", "display": "심연 · 옛 약속의 비석", "uid": "c1seedabyss02", "bg": "bg_abyss_2", "seed": 42,
        "region": "abyss", "terrain_color": ABYSS_TERRAIN, "dark": True,
        "size": (3600, 2400), "map": (42200, 100),
        "platforms": [
            (0, 2200, 3600, 200, "비석의 방"), (400, 1950, 300, 40), (900, 1750, 300, 40), (1400, 1550, 300, 40), (1900, 1350, 300, 40), (2400, 1150, 300, 40),
            (1200, 900, 1400, 80, "비석 앞"), (3000, 700, 600, 80),
        ],
        "thorns": [],
        "markers": {"FromAbyss01": (120, 2132), "FromGarden": (3480, 632)},
        "exits": [(-50, 2000, 80, 300, "abyss_01", "FromAbyss02"), (3560, 500, 80, 240, "moon_garden", "FromAbyss02")],
        "grasses": [],
        "records": [("old_promise", 1900, 900, "stone")],
        "enemies": [("herbalist_sav", 2000, 2132), ("herbalist", 800, 2132), ("machine", 2800, 2132), ("herbalist", 1600, 832)],
        "player": (120, 2132),
    },
    {  # 달빛 정원: 적 없음, 달빛풀 무리
        "name": "MoonGarden", "id": "moon_garden", "display": "달빛 정원", "uid": "c1seedmoongarden", "bg": "bg_moon_garden", "seed": 43,
        "region": "abyss", "terrain_color": "Color(0.09, 0.1, 0.12, 1)",
        "size": (3000, 1300), "map": (45800, 300),
        "platforms": [(0, 1100, 3000, 200, "달빛 정원")],
        "thorns": [],
        "markers": {"FromAbyss02": (120, 1032), "FromBoss": (2880, 1032)},
        "exits": [(-50, 900, 80, 300, "abyss_02", "FromGarden"), (2960, 900, 80, 300, "abyss_boss", "FromGarden")],
        "grasses": [(1500, 1100, "moon_garden", "달빛 정원")],
        "decor_grass": [(300, 1100, 0.2), (650, 1100, 0.26), (1000, 1100, 0.18), (1950, 1100, 0.24), (2300, 1100, 0.17), (2650, 1100, 0.22)],
        "records": [],
        "enemies": [],
        "player": (120, 1032),
    },
]

if __name__ == "__main__":
    for room in ROOMS:
        path = os.path.join(OUT, room["id"] + ".tscn")
        with open(path, "w", encoding="utf-8") as f:
            f.write(build(room))
        print("wrote", os.path.relpath(path))
