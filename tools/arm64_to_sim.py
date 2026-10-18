#!/usr/bin/env python3
"""아이폰용(arm64) 정적 라이브러리(.a)를 애플 실리콘 시뮬레이터용으로 바꾼다.

Godot 공식 템플릿의 시뮬레이터용 라이브러리는 인텔(x86_64) 전용이라
애플 실리콘 맥의 iOS 시뮬레이터에서는 쓸 수 없다. 이 스크립트는 아이폰용
라이브러리 안의 모든 오브젝트 파일에서 LC_BUILD_VERSION의 platform 값을
iOS(2) → iOS 시뮬레이터(7)로 바꾼 사본을 만든다. 파일 크기는 그대로라서
아카이브 구조와 심볼 표는 손대지 않는다.

사용: python3 tools/arm64_to_sim.py <입력 arm64 .a> <출력 .a>
"""
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2
PLATFORM_IOSSIMULATOR = 7


def patch_macho(buf: bytearray, off: int) -> str:
    """buf[off:]에 있는 Mach-O 64 오브젝트의 platform을 바꾼다. 결과 문자열을 돌려준다."""
    magic, _cpu, _sub, _ftype, ncmds, _sizeofcmds, _flags, _res = struct.unpack_from("<IiiIIIII", buf, off)
    if magic != MH_MAGIC_64:
        return "skip"
    pos = off + 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, pos)
        if cmd == LC_BUILD_VERSION:
            platform = struct.unpack_from("<I", buf, pos + 8)[0]
            if platform == PLATFORM_IOS:
                struct.pack_into("<I", buf, pos + 8, PLATFORM_IOSSIMULATOR)
                return "patched"
            if platform == PLATFORM_IOSSIMULATOR:
                return "already"
            return "other-platform-%d" % platform
        if cmd == LC_VERSION_MIN_IPHONEOS:
            return "version-min"  # 크기가 달라 제자리 수정 불가
        pos += cmdsize
    return "no-build-version"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    buf = bytearray(open(src, "rb").read())
    if buf[:8] != b"!<arch>\n":
        print("ar 아카이브가 아닙니다:", src)
        return 1
    pos = 8
    counts = {}
    while pos + 60 <= len(buf):
        header = buf[pos:pos + 60]
        name = header[0:16].decode("ascii", "replace").rstrip()
        size = int(header[48:58].decode("ascii").strip())
        data = pos + 60
        name_len = 0
        if name.startswith("#1/"):
            name_len = int(name[3:])
            name = buf[data:data + name_len].split(b"\0", 1)[0].decode("ascii", "replace")
        obj = data + name_len
        if name.startswith("__.SYMDEF"):
            result = "symdef"
        else:
            result = patch_macho(buf, obj)
        counts[result] = counts.get(result, 0) + 1
        pos = data + size
        if pos % 2:
            pos += 1
    open(dst, "wb").write(buf)
    print("결과:", counts)
    bad = [k for k in counts if k in ("version-min", "no-build-version") or k.startswith("other-platform")]
    if bad:
        print("경고: 바꾸지 못한 오브젝트가 있습니다:", bad)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
