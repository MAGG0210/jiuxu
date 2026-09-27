"""Remove a white background and crop the largest subject from an input image.

Usage: python tools/make_icon.py <source-image> [output-image]
Requires Pillow (PIL).
"""
from PIL import Image
from collections import deque
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if len(sys.argv) < 2:
    raise SystemExit('Usage: python tools/make_icon.py <source-image> [output-image]')
SRC = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / 'assets' / 'k_icon_clean.png'

im = Image.open(SRC).convert('RGB')
W, H = im.size

# --- 缩小到 256 做连通分量 ---
S = 256
small = im.resize((S, S))
spx = small.load()

def is_bg(r, g, b):
    return r > 238 and g > 238 and b > 238

# 二值化 + BFS 连通分量
grid = [[0]*S for _ in range(S)]
for y in range(S):
    for x in range(S):
        r, g, b = spx[x, y]
        if not is_bg(r, g, b):
            grid[y][x] = 1

visited = [[False]*S for _ in range(S)]
best = None  # (size, minx, miny, maxx, maxy)
for sy in range(S):
    for sx in range(S):
        if grid[sy][sx] and not visited[sy][sx]:
            q = deque([(sx, sy)])
            visited[sy][sx] = True
            comp = []
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < S and 0 <= ny < S and grid[ny][nx] and not visited[ny][nx]:
                        visited[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) > 500:
                xs = [p[0] for p in comp]; ys = [p[1] for p in comp]
                bbox = (min(xs), min(ys), max(xs), max(ys))
                if best is None or len(comp) > best[0]:
                    best = (len(comp),) + bbox

size, cminx, cminy, cmaxx, cmaxy = best
print('main component:', best)

# 映射回原图坐标,加 3% 边距
scale = W / S
pad = 0.03 * (cmaxx - cminx)
x0 = max(0, int((cminx - pad) * scale))
y0 = max(0, int((cminy - pad) * scale))
x1 = min(W, int((cmaxx + pad) * scale))
y1 = min(H, int((cmaxy + pad) * scale))
print('crop box:', (x0, y0, x1, y1))

crop = im.crop((x0, y0, x1, y1)).convert('RGBA')
cpx = crop.load()
cw, ch = crop.size
# 白色 -> 透明;边缘轻微羽化
for y in range(ch):
    for x in range(cw):
        r, g, b, a = cpx[x, y]
        if r > 238 and g > 238 and b > 238:
            cpx[x, y] = (r, g, b, 0)
        else:
            # 半白边缘 -> 降低 alpha
            m = min(r, g, b)
            if m > 200:
                cpx[x, y] = (r, g, b, max(0, 255 - (m - 200) * 3))

import os
OUT.parent.mkdir(parents=True, exist_ok=True)
crop.save(OUT)
print('saved:', OUT, crop.size)
