#!/usr/bin/env python3
"""ListenIELTS 图标 — 极简耳机 + 深色磨砂风格"""

import struct, zlib, math, os, subprocess, shutil

# ── PNG 底层工具 ──────────────────────────────────────────────

def make_png(w, h, px):
    def ch(ct, d):
        c = ct + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            r, g, b, a = px[y * w + x]
            raw += struct.pack('BBBB', r, g, b, a)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', ihdr) +
            ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))

def blend(bg, fg):
    br, bg_, bb, ba = bg
    fr, fg_, fb, fa = fg
    if fa == 0: return bg
    if fa == 255: return fg
    a = fa / 255.0
    return (int(fr*a + br*(1-a)), int(fg_*a + bg_*(1-a)),
            int(fb*a + bb*(1-a)), min(255, ba + int(fa * (1 - ba/255))))

def set_px(px, w, h, x, y, c, aa=1.0):
    if x < 0 or x >= w or y < 0 or y >= h: return
    r, g, b, a = c
    px[y*w+x] = blend(px[y*w+x], (r, g, b, int(a * aa)))

# ── 基础绘图 ──────────────────────────────────────────────────

def fill_circle(px, w, h, cx, cy, radius, color):
    """实心圆（带 AA）"""
    r, g, b, a = color
    for dy in range(int(cy - radius - 2), int(cy + radius + 3)):
        for dx in range(int(cx - radius - 2), int(cx + radius + 3)):
            if dx < 0 or dx >= w or dy < 0 or dy >= h: continue
            d = math.sqrt((dx - cx)**2 + (dy - cy)**2)
            if d < radius - 0.5:
                px[dy*w+dx] = blend(px[dy*w+dx], (r, g, b, a))
            elif d < radius + 0.5:
                aa = radius + 0.5 - d
                px[dy*w+dx] = blend(px[dy*w+dx], (r, g, b, int(a * aa)))

def draw_arc(px, w, h, cx, cy, radius, angle_start, angle_end, thickness, color, steps=None):
    """圆弧（带 AA，逐点画粗线）"""
    r, g, b, a = color
    if steps is None:
        steps = max(200, int(radius * abs(angle_end - angle_start) * 4))
    half_t = thickness / 2.0
    for i in range(steps + 1):
        t = angle_start + (angle_end - angle_start) * i / steps
        mx = cx + radius * math.cos(t)
        my = cy + radius * math.sin(t)
        # 画一个小实心圆代表线段的一个点
        for dy in range(int(my - half_t - 1), int(my + half_t + 2)):
            for dx in range(int(mx - half_t - 1), int(mx + half_t + 2)):
                if dx < 0 or dx >= w or dy < 0 or dy >= h: continue
                d = math.sqrt((dx - mx)**2 + (dy - my)**2)
                if d < half_t - 0.3:
                    fa = a
                elif d < half_t + 0.7:
                    fa = int(a * max(0, half_t + 0.7 - d))
                else:
                    continue
                px[dy*w+dx] = blend(px[dy*w+dx], (r, g, b, fa))

def draw_line(px, w, h, x1, y1, x2, y2, thickness, color):
    """直线段（带 AA）"""
    r, g, b, a = color
    length = math.sqrt((x2-x1)**2 + (y2-y1)**2)
    steps = max(int(length * 3), 10)
    half_t = thickness / 2.0
    for i in range(steps + 1):
        t = i / steps
        mx = x1 + (x2 - x1) * t
        my = y1 + (y2 - y1) * t
        for dy in range(int(my - half_t - 1), int(my + half_t + 2)):
            for dx in range(int(mx - half_t - 1), int(mx + half_t + 2)):
                if dx < 0 or dx >= w or dy < 0 or dy >= h: continue
                d = math.sqrt((dx - mx)**2 + (dy - my)**2)
                if d < half_t - 0.3: fa = a
                elif d < half_t + 0.7: fa = int(a * max(0, half_t + 0.7 - d))
                else: continue
                px[dy*w+dx] = blend(px[dy*w+dx], (r, g, b, fa))

def rounded_rect_bg(px, w, h, corner_r, c1, c2):
    """圆角矩形背景，从 c1 到 c2 的对角渐变"""
    for y in range(h):
        for x in range(w):
            # 圆角 clip
            in_corner = False
            corners = [(corner_r, corner_r), (w-corner_r, corner_r),
                       (corner_r, h-corner_r), (w-corner_r, h-corner_r)]
            for ccx, ccy in corners:
                if x < corner_r and y < corner_r:
                    in_corner = True
                    d = math.sqrt((x - ccx)**2 + (y - ccy)**2)
                    if d > corner_r: px[y*w+x] = (0,0,0,0); in_corner = False; break
                elif x >= w-corner_r and y < corner_r:
                    in_corner = True
                    d = math.sqrt((x - (w-corner_r))**2 + (y - corner_r)**2)
                    if d > corner_r: px[y*w+x] = (0,0,0,0); in_corner = False; break
                elif x < corner_r and y >= h-corner_r:
                    in_corner = True
                    d = math.sqrt((x - corner_r)**2 + (y - (h-corner_r))**2)
                    if d > corner_r: px[y*w+x] = (0,0,0,0); in_corner = False; break
                elif x >= w-corner_r and y >= h-corner_r:
                    in_corner = True
                    d = math.sqrt((x - (w-corner_r))**2 + (y - (h-corner_r))**2)
                    if d > corner_r: px[y*w+x] = (0,0,0,0); in_corner = False; break
            if px[y*w+x] == (0,0,0,0): continue
            # 渐变：左上→右下
            t = (x / w * 0.5 + y / h * 0.5)
            nr = int(c1[0] + (c2[0] - c1[0]) * t)
            ng = int(c1[1] + (c2[1] - c1[1]) * t)
            nb = int(c1[2] + (c2[2] - c1[2]) * t)
            px[y*w+x] = (nr, ng, nb, 255)

# ── 图标主体 ──────────────────────────────────────────────────

def generate_icon(size):
    w = h = size
    px = [(0, 0, 0, 0)] * (w * h)

    # 背景：深灰蓝，有明显可见的色调
    cr = int(size * 0.22)
    rounded_rect_bg(px, w, h, cr,
                    (28, 32, 48),   # 左上：深蓝灰
                    (14, 16, 28))   # 右下：更深

    # 中心光晕
    cx, cy = w / 2, h / 2
    glow_r = size * 0.6
    for y in range(h):
        for x in range(w):
            if px[y*w+x][3] == 0: continue
            d = math.sqrt((x - cx)**2 + (y - cy)**2)
            if d < glow_r:
                t = 1.0 - d / glow_r
                g_a = int(40 * t * t)
                px[y*w+x] = blend(px[y*w+x], (100, 120, 200, g_a))

    # ── 耳机图形参数 ──
    hcx = cx
    hcy = cy - size * 0.03

    arc_r   = size * 0.285
    ear_r   = size * 0.088
    stem_w  = size * 0.048
    stem_h  = size * 0.105
    line_t  = max(2.5, size * 0.042)  # 更粗的线条

    # 纯白，不透明
    WHITE  = (255, 255, 255, 255)
    WHITE2 = (255, 255, 255, 200)

    # 1. 头弓弧线（上半圆）
    draw_arc(px, w, h,
             hcx, hcy,
             arc_r,
             math.pi * 1.08,   # 从左
             math.pi * 1.92,   # 到右（留空让两端自然结束）
             line_t, WHITE)

    # 2. 两侧竖杆（头弓末端 → 耳罩顶部）
    for side in [-1, 1]:
        # 头弓末端点
        ang = math.pi * (1.08 if side == -1 else 1.92)
        bx = hcx + arc_r * math.cos(ang)
        by = hcy + arc_r * math.sin(ang)
        # 耳罩中心
        ex = hcx + side * (arc_r - size * 0.01)
        ey = hcy + stem_h * 1.3
        draw_line(px, w, h, bx, by, ex, ey, line_t, WHITE)

        # 3. 耳罩圆形（外圆）
        fill_circle(px, w, h, ex, ey, ear_r, (255, 255, 255, 28))   # 淡填充
        draw_arc(px, w, h, ex, ey, ear_r,
                 0, math.pi * 2, line_t, WHITE)

        # 4. 耳罩内圆（小圆，增加细节层次）
        inner_r = ear_r * 0.48
        draw_arc(px, w, h, ex, ey, inner_r,
                 0, math.pi * 2, max(1.0, line_t * 0.55), WHITE2)

    return px

# ── 导出 ─────────────────────────────────────────────────────

def create_iconset(iconset_dir):
    sizes = {
        "icon_16x16.png": 16,     "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,     "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,  "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,  "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,  "icon_512x512@2x.png": 1024,
    }
    os.makedirs(iconset_dir, exist_ok=True)
    for name, s in sizes.items():
        print(f"  渲染 {name} ({s}px)...")
        with open(os.path.join(iconset_dir, name), 'wb') as f:
            f.write(make_png(s, s, generate_icon(s)))

if __name__ == '__main__':
    project_dir = os.path.dirname(os.path.abspath(__file__))
    app_dir     = os.path.join(project_dir, 'ListenIELTS.app')
    iconset     = '/tmp/ListenIELTS.iconset'
    icns        = '/tmp/ListenIELTS.icns'

    shutil.rmtree(iconset, ignore_errors=True)
    print("🎨 渲染极简耳机图标...\n")
    create_iconset(iconset)

    subprocess.run(['iconutil', '-c', 'icns', '-o', icns, iconset], check=True)
    print(f"\n✅ icns 生成完成: {icns}")

    # 安装到 .app（如果已存在）
    res = os.path.join(app_dir, 'Contents', 'Resources')
    if os.path.isdir(app_dir):
        os.makedirs(res, exist_ok=True)
        shutil.copy(icns, os.path.join(res, 'AppIcon.icns'))
        import plistlib
        plist_path = os.path.join(app_dir, 'Contents', 'Info.plist')
        with open(plist_path, 'rb') as f:
            pl = plistlib.load(f)
        pl['CFBundleIconFile'] = 'AppIcon'
        pl['CFBundleIconName'] = 'AppIcon'
        with open(plist_path, 'wb') as f:
            plistlib.dump(pl, f)
        subprocess.run(['touch', app_dir])
        print(f"✅ 图标已安装到 {app_dir}")
