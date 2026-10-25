#!/bin/bash
# 전체 회귀 시험 (방 시험 · 보스 다섯 곳 · 방 41개 로드 · probe_* 정찰 시험 전부 · 지형 감사 · 포탈 연결 검사).
# 사용: tools/regress.sh [로그 폴더]        (프로젝트 폴더 어디서 실행해도 된다; 기본 로그 폴더 .regress/ — git 에 올리지 않는다)
# Godot 실행 파일은 GODOT 환경변수로 준다 (없으면 tools/test.sh 처럼 흔한 자리를 찾는다).
# 병렬 작업 폴더에서는 user:// (세이브·설정)가 섞이지 않게 폴더마다 HOME 을 따로 쓰는 래퍼를 GODOT 으로 준다.
# 한 줄 요약: "<이름> | <마지막 줄> | err <SCRIPT ERROR 수>" — 끝까지 FAIL 이 없고 err 가 모두 0 이어야 통과.
# 주의: --bosstest 는 screenshots/debug_boss_*.png 를 다시 쓴다 (.gitignore 에 있음).
P="$(cd "$(dirname "$0")/.." && pwd)"
L="${1:-$P/.regress}"; mkdir -p "$L"; rm -f "$L"/*.log
cd "$P" || exit 2
G="${GODOT:-}"
for c in "$G" "$HOME/godot" /Applications/Godot.app/Contents/MacOS/Godot /Users/wj/Downloads/Godot.app/Contents/MacOS/Godot; do
  if [ -n "$c" ] && [ -x "$c" ]; then G="$c"; break; fi
done
[ -x "$G" ] || { echo "Godot 실행 파일을 못 찾았다. GODOT=/path/to/godot tools/regress.sh"; exit 2; }
export GODOT="$G"
tmo(){ if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
t(){ local name="$1_${2//[- ]/}"; tools/test.sh "$1" "$2" "${3:-160}" > "$L/$name.log" 2>&1; echo "$name | $(tail -1 "$L/$name.log") | err $(grep -c 'SCRIPT ERROR\|Parse Error' "$L/$name.log") | $(grep -E '^\[' "$L/$name.log" | tail -1 | cut -c1-120)"; }
p(){ local f="$1"; shift; [ -f tools/$f.tscn ] || { echo "$f (없음)"; return; }; tmo 900 "$G" --headless --path . res://tools/$f.tscn "$@" > $L/$f.log 2>&1; echo "$f exit $? | $(grep -E '^\[probe\] (끝|결과)' $L/$f.log | tail -1) | err $(grep -c 'SCRIPT ERROR' $L/$f.log)"; grep -E "FAIL" $L/$f.log | head -5; }
echo "== 방 시험"
t canopy_01 --autotest; t village_02 --villagetest; t canopy_01 --savetest; t canopy_01 --remaptest
for r in canopy_01 canopy_hidden mine_02 mine_01; do t $r --portaltest; done
t canopy_01 --grasstest; t canopy_01 --nooktest; t canopy_boss --camtest
for r in canopy_01 canopy_03 canopy_04 mine_01 village_01 abyss_02; do t $r --secrettest; done
for r in canopy_01 village_01 mine_02 abyss_02; do t $r --rescuetest; done
t canopy_hidden --minitest
for r in canopy_boss mine_boss abyss_boss sap_lake_boss flooded_mine_boss; do t $r --bosstest 260; grep -h "정화 뒤" $L/${r}_bosstest.log; done
echo "== 방 로드"
for r in scenes/rooms/*.tscn; do n=$(basename $r .tscn); out=$(tmo 60 "$G" --headless --path . res://$r -- --screenshot 2>&1 | grep -E "SCRIPT ERROR|Parse Error" | head -1); [ -n "$out" ] && echo "$n: $out"; done; echo "rooms: $(ls scenes/rooms/*.tscn | wc -l | tr -d ' ') loaded"
echo "== probe"
for f in $(ls tools/probe_*.tscn | xargs -n1 basename | sed 's/\.tscn$//'); do
  case $f in probe_lake) p $f -- --hidden;; probe_mine) p $f -- --linked;; *) p $f;; esac
done
# 씬이 없는 -s 스크립트 시험 (씬이 생기면 위에서 이미 돌았다)
for f in probe_selenia probe_texts; do
  [ -f tools/$f.tscn ] && continue
  tmo 600 "$G" --headless --path . -s res://tools/$f.gd > $L/$f.log 2>&1; echo "$f exit $? | $(grep -E '^\[probe\] (끝|결과)' $L/$f.log | tail -1) | err $(grep -c 'SCRIPT ERROR' $L/$f.log)"; grep -E "FAIL" $L/$f.log | head -5
done
echo "== audit"; python3 -I tools/audit_rooms.py > $L/audit.log 2>&1; tail -1 $L/audit.log; python3 -I tools/audit_rooms.py --locked > $L/audit_locked.log 2>&1; tail -1 $L/audit_locked.log
python3 -I tools/link_flooded_mine.py --check 2>&1 | tail -1
python3 -I tools/make_rooms_index.py --check 2>&1 | tail -1
echo "== 끝"
