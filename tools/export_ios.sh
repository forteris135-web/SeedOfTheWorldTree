#!/bin/zsh
# 아이폰용 Xcode 프로젝트를 내보내고, 애플 실리콘 시뮬레이터용 라이브러리까지 만든다.
# 사용: tools/export_ios.sh        (프로젝트 폴더 어디서 실행해도 됨)
set -e
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Users/wj/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT=/Applications/Godot.app/Contents/MacOS/Godot
OUT="$PROJECT/build/ios"
XCF="$OUT/SeedOfTheWorldTree.xcframework"

echo "== 1/3 Godot 내보내기 =="
mkdir -p "$OUT"
touch "$PROJECT/build/.gdignore"   # Godot가 build 폴더를 게임 자료로 긁지 않게
"$GODOT" --headless --path "$PROJECT" --export-debug "iOS" "$OUT/SeedOfTheWorldTree.xcodeproj" 2>&1 | grep -E "ERROR|error" || true
[ -f "$XCF/ios-arm64/libgodot.a" ] || { echo "내보내기 실패: libgodot.a 없음"; exit 1; }

echo "== 2/3 시뮬레이터용(arm64) 라이브러리 만들기 =="
SIM_DIR="$XCF/ios-arm64_x86_64-simulator"
TMP="$(mktemp -d)"
python3 "$PROJECT/tools/arm64_to_sim.py" "$XCF/ios-arm64/libgodot.a" "$TMP/libgodot_arm64sim.a"
# 시뮬레이터 Metal에 없는 상수 보충
xcrun -sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator -fobjc-arc -c "$PROJECT/tools/sim_stubs.m" -o "$TMP/sim_stubs.o"
ar -q "$TMP/libgodot_arm64sim.a" "$TMP/sim_stubs.o" 2>/dev/null
ranlib "$TMP/libgodot_arm64sim.a"
if [ -f "$SIM_DIR/libgodot.a" ] && lipo -info "$SIM_DIR/libgodot.a" | grep -q x86_64; then
  lipo -create "$SIM_DIR/libgodot.a" "$TMP/libgodot_arm64sim.a" -output "$TMP/libgodot_fat.a"
  mv "$TMP/libgodot_fat.a" "$SIM_DIR/libgodot.a"
else
  mkdir -p "$SIM_DIR"
  mv "$TMP/libgodot_arm64sim.a" "$SIM_DIR/libgodot.a"
fi
rm -rf "$TMP"
lipo -info "$SIM_DIR/libgodot.a"

echo "== 3/3 끝 =="
echo "Xcode 프로젝트: $OUT/SeedOfTheWorldTree.xcodeproj"
