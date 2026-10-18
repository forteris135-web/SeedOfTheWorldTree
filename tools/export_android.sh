#!/bin/zsh
# 안드로이드 APK 내보내기. 결과: build/android/SeedOfTheWorldTree.apk (디버그 서명, 바로 설치 가능)
# 필요한 것: Godot 내보내기 템플릿, JDK 17(~/Library/Application Support/Godot/jdk17), Android SDK(~/Library/Android/sdk)
set -e
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Users/wj/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT=/Applications/Godot.app/Contents/MacOS/Godot
mkdir -p "$PROJECT/build/android"
touch "$PROJECT/build/.gdignore"
"$GODOT" --headless --path "$PROJECT" --export-debug "Android" "$PROJECT/build/android/SeedOfTheWorldTree.apk" 2>&1 | grep -E "ERROR|error|Signed" || true
ls -la "$PROJECT/build/android/SeedOfTheWorldTree.apk"
echo "설치: 안드로이드 기기를 USB로 연결하고 개발자 옵션의 USB 디버깅을 켠 뒤"
echo "  ~/Library/Android/sdk/platform-tools/adb install -r build/android/SeedOfTheWorldTree.apk"
