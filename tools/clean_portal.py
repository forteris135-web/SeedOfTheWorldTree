#!/usr/bin/env python3
"""포탈 그림의 배경 제거 찌꺼기(주황 테두리)를 정리한다.
사용: python3 tools/clean_portal.py "art/_원본/objects/포탈.png" art/objects/portal.png
"""
import sys
from PIL import Image
import numpy as np
src, dst = sys.argv[1], sys.argv[2]
a = np.array(Image.open(src).convert("RGBA")).astype(np.float32)
rgb, al = a[..., :3], a[..., 3]
# 1) 아주 옅은 안개 같은 픽셀은 지운다
al[al < 12] = 0
# 2) 반투명 가장자리(배경 제거 찌꺼기: 주황빛 테두리)의 색을 가까운 불투명 픽셀 색으로 바꾼다 (알파는 유지)
known = al >= 236
col = rgb.copy()
col[~known] = 0
w = known.astype(np.float32)
for _ in range(60):
    # 3x3 이웃 평균으로 한 겹씩 채운다
    acc = np.zeros_like(col); wacc = np.zeros_like(w)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            acc += np.roll(np.roll(col * w[..., None], dy, 0), dx, 1)
            wacc += np.roll(np.roll(w, dy, 0), dx, 1)
    fill = wacc > 0
    newcol = np.where(fill[..., None], acc / np.maximum(wacc, 1e-6)[..., None], col)
    newly = fill & (w == 0)
    col = np.where(newly[..., None], newcol, col)
    w = np.where(newly, 1.0, w)
    if not newly.any():
        break
semi = (al > 0) & (al < 236)
# 채도가 높은(주황) 찌꺼기일수록 이웃 색으로 강하게 바꾼다
mx = rgb.max(-1); mn = rgb.min(-1); sat = (mx - mn)
t = np.clip((sat - 50) / 90.0, 0, 1)[..., None] * semi[..., None]
out = rgb * (1 - t) + col * t
# 3) 남은 옅은 가장자리는 알파를 살짝 줄여 테두리 느낌을 없앤다
soft = (al > 0) & (al < 120)
al[soft] *= 0.8
res = np.concatenate([np.clip(out, 0, 255), al[..., None]], -1).astype(np.uint8)
Image.fromarray(res, "RGBA").save(dst, optimize=True)
print("saved", dst, res.shape)
