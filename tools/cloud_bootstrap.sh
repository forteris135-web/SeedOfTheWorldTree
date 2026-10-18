#!/bin/bash
# 클라우드 작업용: 새 작업 폴더(git worktree)에서 Godot 캐시를 준비한다.
# 1) 본 저장소의 .godot 캐시를 복사해 그림 재임포트를 건너뛰고 2) 새 스크립트·씬이 등록되게 --import 를 한 번 돈다.
# 사용: tools/cloud_bootstrap.sh            (작업 폴더 어디서 실행해도 됨)
set -u
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="${MAIN_PROJECT:-/home/user/seedoftheworldtree}"
G="${GODOT:-/tmp/claude-0/-home-user/c632609b-bc85-55ec-8d51-8895afedec3f/scratchpad/bin/godot}"
if [ ! -d "$PROJECT/.godot" ] && [ -d "$MAIN/.godot" ] && [ "$PROJECT" != "$MAIN" ]; then
  cp -r "$MAIN/.godot" "$PROJECT/.godot"
  echo "캐시 복사함: $MAIN/.godot → $PROJECT/.godot"
fi
timeout 900 "$G" --headless --path "$PROJECT" --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error" | head -20
echo "import 끝 (exit ${PIPESTATUS[0]})"
