"""Genera las imagenes de las skins (Config.Skins): una textura de mosaico por skin
(textures/<Skin>.png, 512x512, se repite sin costuras) y un emblema con fondo
transparente (emblems/<Skin>.png, 256x256).

    python assets/skins/generate.py

Todo es procedural (numpy + Pillow): ruido periodico por FFT, Voronoi periodico y
dibujos repetidos en las 9 copias vecinas para que el mosaico no tenga cortes.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

N = 512
HERE = os.path.dirname(os.path.abspath(__file__))
TEX_DIR = os.path.join(HERE, "textures")
EMB_DIR = os.path.join(HERE, "emblems")


# ----------------------------------------------------------------------------- utilidades

def fbm(seed, beta=2.0, size=N, stretch=(1.0, 1.0)):
    """Ruido periodico (se repite sin costuras) con espectro 1/f^beta, en [0, 1]."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None] * stretch[1]
    fx = np.fft.fftfreq(size)[None, :] * stretch[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = np.fft.fft2(white) / (f ** (beta / 2.0))
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / out.max()


def sample_wrap(img, ys, xs):
    """Muestreo bilineal con envoltura (para deformar ruido sin perder la periodicidad)."""
    h, w = img.shape
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    x0 %= w
    y0 %= h
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    a = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    b = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return a * (1 - fy) + b * fy


def voronoi(seed, count, size=N):
    """Voronoi periodico: distancias F1, F2 (en pixeles) e indice de la celda."""
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2)) * size
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    f1 = np.full((size, size), 1e9, np.float32)
    f2 = np.full((size, size), 1e9, np.float32)
    idx = np.zeros((size, size), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, size - dx)
        dy = np.minimum(dy, size - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        idx = np.where(closer, i, idx)
        f1 = np.where(closer, d, f1)
    return f1, f2, idx, pts


def ramp(v, stops):
    """Mapa de color: stops = [(posicion, (r, g, b)), ...] con v en [0, 1]."""
    v = np.clip(v, 0, 1)
    out = np.zeros(v.shape + (3,), np.float32)
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (v >= p0) & (v <= p1)
        t = ((v - p0) / max(p1 - p0, 1e-6))[m][:, None]
        out[m] = np.array(c0) * (1 - t) + np.array(c1) * t
    return out


def blend(base, color, mask):
    mask = np.clip(mask, 0, 1)[..., None]
    return base * (1 - mask) + np.array(color, np.float32) * mask


def wrapped_canvas(scale=1):
    """Lienzo 3x3 (para dibujar con envoltura): devuelve imagen y funcion de recorte."""
    img = Image.new("RGBA", (N * 3 * scale, N * 3 * scale), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def crop_center(img, scale=1):
    s = N * scale
    out = img.crop((s, s, 2 * s, 2 * s))
    return out.resize((N, N), Image.LANCZOS) if scale != 1 else out


def tiles(x, y):
    """Las 9 copias de un punto (para dibujar en el lienzo 3x3)."""
    for oy in (0, 1, 2):
        for ox in (0, 1, 2):
            yield x + ox * N, y + oy * N


def overlay(base_rgb, layer_rgba):
    """Pone una capa RGBA (Pillow) sobre un array RGB float."""
    arr = np.asarray(layer_rgba, np.float32)
    a = arr[..., 3:4] / 255.0
    return base_rgb * (1 - a) + arr[..., :3] * a


def add_glow(base_rgb, layer_rgba, radius, strength=1.0):
    """Suma el brillo (desenfocado) de una capa: luces de neon."""
    blurred = layer_rgba.filter(ImageFilter.GaussianBlur(radius))
    arr = np.asarray(blurred, np.float32)
    a = arr[..., 3:4] / 255.0
    return base_rgb + arr[..., :3] * a * strength


def stars(base, seed, count, colors=((255, 255, 255),), big=0.05):
    rng = np.random.default_rng(seed)
    layer, d = wrapped_canvas()
    for _ in range(count):
        x, y = rng.random() * N, rng.random() * N
        r = rng.uniform(0.6, 1.6)
        if rng.random() < big:
            r = rng.uniform(2.2, 3.4)
        c = colors[rng.integers(len(colors))]
        alpha = int(rng.uniform(150, 255))
        for tx, ty in tiles(x, y):
            d.ellipse((tx - r, ty - r, tx + r, ty + r), fill=c + (alpha,))
            if r > 2:  # destello en cruz
                d.line((tx - r * 3, ty, tx + r * 3, ty), fill=c + (120,), width=1)
                d.line((tx, ty - r * 3, tx, ty + r * 3), fill=c + (120,), width=1)
    layer = crop_center(layer)
    base = add_glow(base, layer, 2.5, 0.8)
    return overlay(base, layer)


def save_tex(name, rgb):
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    img.save(os.path.join(TEX_DIR, name + ".png"))
    print("textura", name)


# ----------------------------------------------------------------------------- texturas

def tex_camo():
    base = np.zeros((N, N, 3), np.float32) + (88, 104, 62)
    base = blend(base, (52, 66, 36), fbm(11, 3.2) > 0.52)
    base = blend(base, (118, 92, 58), fbm(12, 3.2) > 0.58)
    base = blend(base, (34, 34, 28), fbm(13, 3.4) > 0.64)
    base = blend(base, (150, 150, 105), (fbm(14, 3.4) > 0.72) * 0.9)
    # trama de tela
    yy, xx = np.mgrid[0:N, 0:N]
    weave = (np.sin(xx * math.pi / 2) * np.sin(yy * math.pi / 2)) * 6
    base += weave[..., None] + (fbm(15, 0.5)[..., None] - 0.5) * 18
    save_tex("Camo", base)


def tex_ice():
    n = fbm(21, 2.4)
    base = ramp(n, [(0, (170, 205, 235)), (0.5, (215, 236, 252)), (1, (245, 252, 255))])
    f1, f2, _, _ = voronoi(22, 28)
    crack = np.clip(1 - (f2 - f1) / 3.0, 0, 1)
    base = blend(base, (255, 255, 255), crack * 0.55)
    # helechos de escarcha: ramas que se abren
    rng = np.random.default_rng(23)
    layer, d = wrapped_canvas()

    def branch(x, y, ang, length, depth):
        if depth == 0 or length < 4:
            return
        x2 = x + math.cos(ang) * length
        y2 = y + math.sin(ang) * length
        for tx, ty in tiles(x, y):
            d.line((tx, ty, tx + x2 - x, ty + y2 - y), fill=(255, 255, 255, 200), width=max(1, depth - 1))
        for k in range(1, 4):
            px = x + (x2 - x) * k / 4
            py = y + (y2 - y) * k / 4
            branch(px, py, ang + 0.9, length * 0.38, depth - 1)
            branch(px, py, ang - 0.9, length * 0.38, depth - 1)
        branch(x2, y2, ang + rng.uniform(-0.3, 0.3), length * 0.6, depth - 1)

    for _ in range(9):
        branch(rng.random() * N, rng.random() * N, rng.uniform(0, 2 * math.pi), rng.uniform(40, 80), 3)
    layer = crop_center(layer)
    base = add_glow(base, layer, 3, 0.35)
    base = overlay(base, layer)
    base = stars(base, 24, 60, ((255, 255, 255), (200, 240, 255)), big=0.1)
    save_tex("Ice", base)


def tex_rust():
    coarse = fbm(31, 3.0)
    fine = fbm(32, 1.2)
    streak = fbm(33, 2.6, stretch=(1.0, 0.12))
    base = ramp(fine * 0.6 + streak * 0.4, [(0, (70, 34, 18)), (0.45, (150, 72, 30)), (0.75, (195, 105, 45)), (1, (225, 150, 80))])
    metal = ramp(fine, [(0, (85, 82, 80)), (1, (150, 146, 140))])
    m = np.clip((coarse - 0.6) * 6, 0, 1)
    base = base * (1 - m[..., None]) + metal * m[..., None]
    pits = fbm(34, 0.3)
    base = blend(base, (40, 20, 10), (pits > 0.82) * 0.8)
    # aranazos
    rng = np.random.default_rng(35)
    layer, d = wrapped_canvas()
    for _ in range(40):
        x, y = rng.random() * N, rng.random() * N
        a = rng.uniform(-0.5, 0.5)
        L = rng.uniform(20, 90)
        for tx, ty in tiles(x, y):
            d.line((tx, ty, tx + math.cos(a) * L, ty + math.sin(a) * L), fill=(210, 200, 190, 110), width=1)
    base = overlay(base, crop_center(layer))
    save_tex("Rust", base)


def tex_crimson():
    yy, xx = np.mgrid[0:N, 0:N]
    cell = 16
    u = (xx % cell) / cell
    v = (yy % cell) / cell
    # sarga de fibra de carbono: bloques que alternan direccion en diagonal
    diag = ((xx // cell + yy // cell) % 2) == 0
    shade = np.where(diag, np.sin(u * math.pi), np.sin(v * math.pi))
    shade = shade ** 0.7
    base = ramp(shade, [(0, (18, 6, 8)), (0.6, (90, 10, 20)), (1, (205, 35, 50))])
    base += (fbm(41, 0.8)[..., None] - 0.5) * 14
    # filo rojo brillante en diagonal (raya de carreras)
    stripe = np.abs(((xx + yy) % 256) - 128)
    base = blend(base, (255, 60, 70), np.clip(1 - np.abs(stripe - 120) / 3, 0, 1) * 0.9)
    save_tex("Crimson", base)


def tex_neon():
    base = np.zeros((N, N, 3), np.float32) + (16, 18, 24)
    base += (fbm(51, 1.0)[..., None] - 0.5) * 10
    yy, xx = np.mgrid[0:N, 0:N]
    seams = ((xx % 128) < 2) | ((yy % 128) < 2)
    base = blend(base, (40, 44, 56), seams * 0.9)
    rng = np.random.default_rng(52)
    layer, d = wrapped_canvas()
    cyan = (0, 255, 210, 255)
    for _ in range(26):  # pistas de circuito en angulos de 45/90
        x = rng.integers(0, N // 16) * 16
        y = rng.integers(0, N // 16) * 16
        pts = [(x, y)]
        for _ in range(rng.integers(3, 7)):
            dirs = [(1, 0), (0, 1), (1, 1), (-1, 1), (-1, 0), (0, -1)]
            dx, dy = dirs[rng.integers(len(dirs))]
            L = rng.integers(2, 6) * 16
            x, y = x + dx * L, y + dy * L
            pts.append((x, y))
        for ox in (0, N, 2 * N):
            for oy in (0, N, 2 * N):
                shifted = [(px + ox, py + oy) for px, py in pts]
                d.line(shifted, fill=cyan, width=3, joint="curve")
                for px, py in (shifted[0], shifted[-1]):
                    d.ellipse((px - 6, py - 6, px + 6, py + 6), outline=cyan, width=3)
    layer = crop_center(layer)
    base = add_glow(base, layer, 6, 1.1)
    base = overlay(base, layer)
    save_tex("Neon", base)


def tex_toxic():
    n = fbm(61, 2.6)
    base = ramp(n, [(0, (14, 30, 10)), (0.6, (35, 70, 22)), (1, (70, 120, 30))])
    f1, f2, _, pts = voronoi(62, 22)
    # burbujas de baba brillante
    rng = np.random.default_rng(63)
    layer, d = wrapped_canvas()
    for _ in range(55):
        x, y = rng.random() * N, rng.random() * N
        r = rng.uniform(5, 22)
        for tx, ty in tiles(x, y):
            d.ellipse((tx - r, ty - r, tx + r, ty + r), fill=(150, 255, 40, 120), outline=(200, 255, 120, 230), width=2)
            d.ellipse((tx - r * 0.5, ty - r * 0.6, tx - r * 0.1, ty - r * 0.2), fill=(240, 255, 220, 200))
    layer = crop_center(layer)
    base = blend(base, (120, 230, 30), np.clip(1 - (f2 - f1) / 5, 0, 1) * 0.5)
    base = add_glow(base, layer, 8, 0.9)
    base = overlay(base, layer)
    save_tex("Toxic", base)


def tex_gold():
    n = fbm(71, 2.2)
    base = ramp(n, [(0, (150, 100, 25)), (0.4, (215, 165, 50)), (0.7, (250, 210, 100)), (1, (255, 240, 180))])
    # filigrana grabada: volutas en cuadricula
    S = 4  # supermuestreo
    layer = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    hl = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    d, dh = ImageDraw.Draw(layer), ImageDraw.Draw(hl)
    cell = N // 4 * S
    for gy in range(5):
        for gx in range(5):
            cx, cy = gx * cell, gy * cell
            for k, (sx, sy) in enumerate(((1, 1), (-1, -1))):
                pts = []
                for i in range(120):
                    t = i / 119 * 4.2 * math.pi
                    r = cell * 0.34 * (1 - i / 140)
                    pts.append((cx + sx * cell * 0.2 + math.cos(t + k * math.pi) * r, cy + sy * cell * 0.2 + math.sin(t + k * math.pi) * r))
                d.line(pts, fill=(90, 55, 10, 255), width=3 * S)
                dh.line([(x - S * 2, y - S * 2) for x, y in pts], fill=(255, 250, 220, 200), width=S * 2)
            d.ellipse((cx - S * 10, cy - S * 10, cx + S * 10, cy + S * 10), outline=(90, 55, 10, 255), width=3 * S)
    layer = layer.resize((N, N), Image.LANCZOS)
    hl = hl.resize((N, N), Image.LANCZOS)
    base = overlay(base, hl)
    base = overlay(base, layer)
    base = stars(base, 72, 30, ((255, 250, 220),), big=0.2)
    save_tex("Gold", base)


def tex_diamond():
    f1, f2, idx, pts = voronoi(81, 34)
    rng = np.random.default_rng(82)
    count = len(pts)
    ang = rng.uniform(0, 2 * math.pi, count)
    tone = rng.uniform(0.4, 1.0, count)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    px, py = pts[idx, 0], pts[idx, 1]
    dx = (xx - px + N / 2) % N - N / 2
    dy = (yy - py + N / 2) % N - N / 2
    facet = (dx * np.cos(ang[idx]) + dy * np.sin(ang[idx])) / 40.0
    v = np.clip(tone[idx] * 0.7 + facet * 0.3, 0, 1)
    base = ramp(v, [(0, (25, 60, 120)), (0.35, (70, 140, 210)), (0.7, (170, 225, 250)), (1, (250, 254, 255))])
    edges = np.clip(1 - (f2 - f1) / 2.2, 0, 1)
    base = blend(base, (255, 255, 255), edges)
    # destellos de arcoiris en algunas caras
    hue = fbm(83, 2.0)
    rainbow = np.stack([np.sin(hue * 6.28) * 0.5 + 0.5, np.sin(hue * 6.28 + 2.1) * 0.5 + 0.5, np.sin(hue * 6.28 + 4.2) * 0.5 + 0.5], -1) * 255
    m = (tone[idx] > 0.85) * 0.35
    base = base * (1 - m[..., None]) + rainbow * m[..., None]
    base = stars(base, 84, 45, ((255, 255, 255),), big=0.25)
    save_tex("Diamond", base)


def tex_plasma():
    a, b = fbm(91, 3.4) * N * 0.35, fbm(92, 3.4) * N * 0.35
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    n = sample_wrap(fbm(93, 3.2), yy + a, xx + b)
    ridges = 1 - np.abs(n - 0.5) * 2
    v = ridges ** 14  # filamentos finos de energia
    base = ramp(fbm(94, 3.0), [(0, (14, 3, 26)), (0.5, (55, 12, 95)), (1, (110, 25, 150))])
    glow = Image.fromarray((np.clip(v * 1.6, 0, 1) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(6))
    base = blend(base, (220, 40, 210), np.asarray(glow, np.float32) / 255 * 0.9)
    base = blend(base, (255, 90, 240), np.clip(v * 1.5, 0, 1))
    base = blend(base, (255, 235, 255), np.clip((v - 0.55) * 3, 0, 1))
    save_tex("Plasma", base)


def crescent(d, x, y, r, rot, color):
    """Luna creciente: circulo menos otro desplazado (dibujado como poligono)."""
    pts = []
    for i in range(40):
        t = -math.pi / 2 + i / 39 * math.pi
        pts.append((math.cos(t) * r, math.sin(t) * r))
    for i in range(40):
        t = math.pi / 2 - i / 39 * math.pi
        pts.append((math.cos(t) * r * 0.45, math.sin(t) * r * 0.92))
    c, s = math.cos(rot), math.sin(rot)
    d.polygon([(x + px * c - py * s, y + px * s + py * c) for px, py in pts], fill=color)


def tex_luna():
    n = fbm(101, 2.6)
    base = ramp(n, [(0, (12, 8, 40)), (0.55, (35, 22, 95)), (1, (80, 45, 150))])
    base = stars(base, 102, 160, ((255, 255, 255), (255, 235, 180), (210, 190, 255)), big=0.06)
    rng = np.random.default_rng(103)
    layer, d = wrapped_canvas()
    # constelaciones
    for _ in range(6):
        x, y = rng.random() * N, rng.random() * N
        pts = [(x, y)]
        for _ in range(4):
            x += rng.uniform(-50, 50)
            y += rng.uniform(-50, 50)
            pts.append((x, y))
        for ox in (0, N, 2 * N):
            for oy in (0, N, 2 * N):
                p = [(px + ox, py + oy) for px, py in pts]
                d.line(p, fill=(255, 225, 150, 110), width=1)
                for px, py in p:
                    d.ellipse((px - 2.5, py - 2.5, px + 2.5, py + 2.5), fill=(255, 235, 170, 255))
    # lunas crecientes doradas
    for gy in range(3):
        for gx in range(3):
            x = gx * N / 3 + (N / 6 if gy % 2 else 0) + rng.uniform(-10, 10)
            y = gy * N / 3 + N / 6 + rng.uniform(-10, 10)
            for tx, ty in tiles(x, y):
                crescent(d, tx, ty, 22, rng.uniform(-0.6, 0.6), (250, 220, 130, 255))
    layer = crop_center(layer)
    base = add_glow(base, layer, 5, 0.7)
    base = overlay(base, layer)
    save_tex("Luna", base)


def tex_inferno():
    f1, f2, _, _ = voronoi(111, 26)
    rock = fbm(112, 1.6)
    base = ramp(rock, [(0, (18, 12, 12)), (0.6, (45, 30, 26)), (1, (70, 50, 40))])
    w = fbm(113, 2.4) * 3 + 1.5  # grosor de la grieta variable
    edge = f2 - f1
    lava = np.clip(1 - edge / w, 0, 1)
    glow = np.clip(1 - edge / (w * 4), 0, 1) ** 2
    base = blend(base, (150, 30, 5), glow * 0.8)
    base = blend(base, (255, 110, 15), lava)
    base = blend(base, (255, 230, 120), np.clip((lava - 0.5) * 2, 0, 1))
    # brasas sueltas
    base = stars(base, 114, 40, ((255, 170, 60), (255, 220, 120)), big=0.1)
    save_tex("Inferno", base)


def bolt(d, x, y, ang, length, width, rng, depth=0):
    pts = [(x, y)]
    for _ in range(8):
        ang += rng.uniform(-0.6, 0.6)
        step = length / 8
        x += math.cos(ang) * step
        y += math.sin(ang) * step
        pts.append((x, y))
        if depth < 2 and rng.random() < 0.25:
            bolt(d, x, y, ang + rng.choice([-0.8, 0.8]), length * 0.45, max(1, width - 1), rng, depth + 1)
    for ox in (0, N, 2 * N):
        for oy in (0, N, 2 * N):
            d.line([(px + ox, py + oy) for px, py in pts], fill=(200, 240, 255, 255), width=width, joint="curve")


def tex_storm():
    n = fbm(121, 2.4)
    n2 = fbm(122, 1.4)
    base = ramp(n * 0.75 + n2 * 0.25, [(0, (14, 16, 26)), (0.5, (45, 52, 72)), (0.8, (90, 100, 125)), (1, (130, 140, 160))])
    rng = np.random.default_rng(123)
    layer, d = wrapped_canvas()
    for _ in range(5):
        bolt(d, rng.random() * N, rng.random() * N, rng.uniform(0, 2 * math.pi), rng.uniform(140, 240), 3, rng)
    layer = crop_center(layer)
    base = add_glow(base, layer, 10, 1.3)
    base = add_glow(base, layer, 3, 0.8)
    base = overlay(base, layer)
    save_tex("Storm", base)


def tex_galaxy():
    a, b = fbm(131, 2.6) * 60, fbm(132, 2.6) * 60
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    neb1 = sample_wrap(fbm(133, 2.4), yy + a, xx + b)
    neb2 = sample_wrap(fbm(134, 2.4), yy - b, xx + a)
    base = np.zeros((N, N, 3), np.float32) + (6, 4, 18)
    base = blend(base, (120, 30, 160), np.clip((neb1 - 0.45) * 2.5, 0, 1))
    base = blend(base, (255, 70, 180), np.clip((neb1 - 0.68) * 3.5, 0, 1))
    base = blend(base, (40, 90, 255), np.clip((neb2 - 0.55) * 2.6, 0, 1) * 0.8)
    base = blend(base, (150, 230, 255), np.clip((neb2 - 0.8) * 4, 0, 1) * 0.7)
    base = stars(base, 135, 420, ((255, 255, 255), (200, 220, 255), (255, 210, 240)), big=0.04)
    save_tex("Galaxy", base)


def tex_prism():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    n = fbm(141, 2.6)
    # tono: ruido + diagonal con un numero entero de vueltas (para que se repita)
    hue = (n * 1.4 + (xx + yy) / N) % 1.0
    r = np.sin(hue * 2 * math.pi) * 0.5 + 0.5
    g = np.sin(hue * 2 * math.pi + 2.094) * 0.5 + 0.5
    b = np.sin(hue * 2 * math.pi + 4.189) * 0.5 + 0.5
    base = np.stack([r, g, b], -1) * 120 + 135  # holografico: claro y poco saturado
    lines = np.sin((xx - yy) * 2 * math.pi * 64 / N) * 0.5 + 0.5  # rejilla de difraccion
    base += (lines[..., None] - 0.5) * 22
    sheen = np.clip(1 - np.abs(((xx + yy) % N) - N / 2) / 40, 0, 1) ** 2
    base = blend(base, (255, 255, 255), sheen * 0.45)
    base = stars(base, 142, 70, ((255, 255, 255), (255, 220, 240), (220, 255, 255)), big=0.2)
    save_tex("Prism", base)


def tex_phoenix():
    S = 3
    img = Image.new("RGBA", (N * 3 * S, N * 3 * S), (60, 8, 6, 255))
    d = ImageDraw.Draw(img)
    rows, cols = 8, 8
    fw, fh = N / cols, N / rows * 1.9
    for row in range(-1, rows * 3 + 1):
        for col in range(-1, cols * 3 + 1):
            cx = (col + (0.5 if row % 2 else 0)) * fw
            cy = row * N / rows
            # pluma: lagrima con la punta abajo (gradiente rojo -> naranja -> dorado)
            for k in range(10, 0, -1):
                t = k / 10
                w = fw * 0.62 * t
                h = fh * 0.62 * t
                col_rgb = (
                    int(170 + 85 * (1 - t)),
                    int(25 + 185 * (1 - t) ** 1.3),
                    int(10 + 90 * (1 - t) ** 3),
                )
                poly = []
                for i in range(24):
                    a = i / 23 * math.pi
                    poly.append((cx + math.cos(a) * w, cy + math.sin(a) * h * 0.35))
                poly.append((cx, cy + h))
                d.polygon([(x * S, y * S) for x, y in poly], fill=col_rgb + (255,))
            # raquis y barbas
            d.line([(cx * S, cy * S), (cx * S, (cy + fh * 0.55) * S)], fill=(255, 235, 160, 255), width=S)
            for i in range(1, 6):
                yb = cy + fh * 0.09 * i
                d.line([(cx * S, yb * S), ((cx - fw * 0.22) * S, (yb + fh * 0.06) * S)], fill=(120, 20, 10, 140), width=S)
                d.line([(cx * S, yb * S), ((cx + fw * 0.22) * S, (yb + fh * 0.06) * S)], fill=(120, 20, 10, 140), width=S)
    img = img.crop((N * S, N * S, 2 * N * S, 2 * N * S)).resize((N, N), Image.LANCZOS)
    base = np.asarray(img, np.float32)[..., :3]
    base = stars(base, 151, 40, ((255, 230, 140),), big=0.15)
    save_tex("Phoenix", base)


# ----------------------------------------------------------------------------- emblemas

E = 256
ES = 4  # supermuestreo


def emblem(name, draw_fn, color, glow_color=None):
    big = E * ES
    shape = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(shape)
    draw_fn(d, big)
    shape = shape.resize((E, E), Image.LANCZOS)
    rgba = Image.new("RGBA", (E, E), (0, 0, 0, 0))
    glow = Image.new("RGBA", (E, E), (glow_color or color) + (0,))
    glow.putalpha(shape.filter(ImageFilter.GaussianBlur(7)).point(lambda v: min(255, int(v * 1.3))))
    rgba = Image.alpha_composite(rgba, glow)
    # contorno oscuro y relleno
    outline = Image.new("RGBA", (E, E), (15, 12, 18, 0))
    outline.putalpha(shape.filter(ImageFilter.MaxFilter(5)))
    rgba = Image.alpha_composite(rgba, outline)
    fill = Image.new("RGBA", (E, E), color + (0,))
    fill.putalpha(shape)
    rgba = Image.alpha_composite(rgba, fill)
    rgba.save(os.path.join(EMB_DIR, name + ".png"))
    print("emblema", name)


def star_points(cx, cy, r_out, r_in, n=5, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + i * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def e_camo(d, s):
    d.polygon(star_points(s / 2, s / 2, s * 0.42, s * 0.17), fill=255)


def e_ice(d, s):
    c = s / 2
    w = int(s * 0.045)
    for k in range(6):
        a = k * math.pi / 3
        x2, y2 = c + math.cos(a) * s * 0.42, c + math.sin(a) * s * 0.42
        d.line((c, c, x2, y2), fill=255, width=w)
        for t in (0.45, 0.7):
            bx, by = c + math.cos(a) * s * 0.42 * t, c + math.sin(a) * s * 0.42 * t
            for side in (-1, 1):
                b = a + side * 0.7
                d.line((bx, by, bx + math.cos(b) * s * 0.12, by + math.sin(b) * s * 0.12), fill=255, width=w)
    d.ellipse((c - s * 0.07, c - s * 0.07, c + s * 0.07, c + s * 0.07), fill=255)


def e_rust(d, s):
    c = s / 2
    pts = []
    for i in range(48):  # engranaje
        a = i / 48 * 2 * math.pi
        r = s * (0.42 if (i // 3) % 2 == 0 else 0.33)
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=255)
    d.ellipse((c - s * 0.14, c - s * 0.14, c + s * 0.14, c + s * 0.14), fill=0)


def e_crimson(d, s):
    for k in range(3):  # tres zarpazos
        x = s * (0.28 + k * 0.2)
        d.polygon([(x - s * 0.02, s * 0.1), (x + s * 0.07, s * 0.12), (x - s * 0.06, s * 0.9), (x - s * 0.1, s * 0.86)], fill=255)


def e_neon(d, s):
    c = s / 2
    hexa = [(c + math.cos(a) * s * 0.42, c + math.sin(a) * s * 0.42) for a in [i * math.pi / 3 + math.pi / 6 for i in range(6)]]
    d.polygon(hexa, outline=255, width=int(s * 0.05))
    d.polygon([(c + s * 0.05, s * 0.2), (c - s * 0.13, c + s * 0.04), (c, c + s * 0.04), (c - s * 0.05, s * 0.8), (c + s * 0.14, c - s * 0.06), (c + s * 0.01, c - s * 0.06)], fill=255)


def e_toxic(d, s):
    c = s / 2
    for k in range(3):  # trebol de radiacion
        a0 = -90 + k * 120 - 30
        d.pieslice((c - s * 0.42, c - s * 0.42, c + s * 0.42, c + s * 0.42), a0, a0 + 60, fill=255)
    d.ellipse((c - s * 0.15, c - s * 0.15, c + s * 0.15, c + s * 0.15), fill=0)
    d.ellipse((c - s * 0.09, c - s * 0.09, c + s * 0.09, c + s * 0.09), fill=255)


def e_gold(d, s):
    d.polygon([(s * 0.12, s * 0.72), (s * 0.12, s * 0.3), (s * 0.31, s * 0.5), (s * 0.5, s * 0.2), (s * 0.69, s * 0.5), (s * 0.88, s * 0.3), (s * 0.88, s * 0.72)], fill=255)
    d.rectangle((s * 0.12, s * 0.76, s * 0.88, s * 0.84), fill=255)
    for x, y in ((0.12, 0.3), (0.5, 0.2), (0.88, 0.3)):
        d.ellipse(((x - 0.05) * s, (y - 0.05) * s, (x + 0.05) * s, (y + 0.05) * s), fill=255)


def e_diamond(d, s):
    top = [(s * 0.3, s * 0.22), (s * 0.7, s * 0.22), (s * 0.9, s * 0.4), (s * 0.5, s * 0.88), (s * 0.1, s * 0.4)]
    d.polygon(top, fill=255)
    w = int(s * 0.02)
    for a, b in (((0.1, 0.4), (0.9, 0.4)), ((0.3, 0.22), (0.4, 0.4)), ((0.7, 0.22), (0.6, 0.4)), ((0.4, 0.4), (0.5, 0.88)), ((0.6, 0.4), (0.5, 0.88)), ((0.5, 0.22), (0.4, 0.4)), ((0.5, 0.22), (0.6, 0.4))):
        d.line((a[0] * s, a[1] * s, b[0] * s, b[1] * s), fill=0, width=w)


def e_plasma(d, s):
    c = s / 2
    w = int(s * 0.04)
    for k in range(3):  # atomo: 3 orbitas
        ang = k * math.pi / 3
        pts = []
        for i in range(80):
            t = i / 79 * 2 * math.pi
            x, y = math.cos(t) * s * 0.42, math.sin(t) * s * 0.15
            pts.append((c + x * math.cos(ang) - y * math.sin(ang), c + x * math.sin(ang) + y * math.cos(ang)))
        d.line(pts, fill=255, width=w)
    d.ellipse((c - s * 0.09, c - s * 0.09, c + s * 0.09, c + s * 0.09), fill=255)


def e_luna(d, s):
    crescent(d, s * 0.44, s * 0.5, s * 0.38, math.pi, 255)
    d.polygon(star_points(s * 0.72, s * 0.32, s * 0.12, s * 0.05, 4, 0), fill=255)
    d.polygon(star_points(s * 0.78, s * 0.66, s * 0.07, s * 0.03, 4, 0), fill=255)


def e_inferno(d, s):
    def flame(cx, base_y, w, h):
        pts = []
        for i in range(60):
            t = i / 59
            a = t * 2 * math.pi
            x = math.sin(a) * w * (1 - t * 0.2)
            y = -math.cos(a) * 0.5 * h * 0.5 - (1 - abs(math.sin(a / 2))) * h * 0.55
            pts.append((cx + x * (0.6 + 0.4 * math.cos(a)), base_y + y))
        return pts
    d.polygon(flame(s * 0.5, s * 0.72, s * 0.3, s * 1.0), fill=255)
    d.polygon(flame(s * 0.5, s * 0.78, s * 0.14, s * 0.55), fill=0)


def e_storm(d, s):
    d.polygon([(s * 0.58, s * 0.06), (s * 0.24, s * 0.55), (s * 0.47, s * 0.55), (s * 0.36, s * 0.94), (s * 0.78, s * 0.4), (s * 0.54, s * 0.4), (s * 0.7, s * 0.06)], fill=255)


def e_galaxy(d, s):
    c = s / 2
    for arm in range(3):
        for i in range(140):
            t = i / 139
            a = arm * 2 * math.pi / 3 + t * 4.2
            r = s * 0.06 + t * s * 0.38
            rr = s * (0.045 * (1 - t) + 0.012)
            x, y = c + math.cos(a) * r, c + math.sin(a) * r * 0.8
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)
    d.ellipse((c - s * 0.1, c - s * 0.08, c + s * 0.1, c + s * 0.08), fill=255)


def e_prism(d, s):
    w = int(s * 0.05)
    d.polygon([(s * 0.5, s * 0.12), (s * 0.86, s * 0.78), (s * 0.14, s * 0.78)], outline=255, width=w)
    d.line((s * 0.02, s * 0.5, s * 0.36, s * 0.46), fill=255, width=w)
    for k in range(4):  # el haz que sale abierto en abanico
        d.line((s * 0.62, s * 0.48, s * 0.98, s * (0.36 + k * 0.08)), fill=255, width=int(w * 0.8))


def e_phoenix(d, s):
    c = s / 2
    # alas
    for side in (-1, 1):
        pts = [(c, s * 0.42)]
        for k in range(5):
            pts.append((c + side * s * (0.18 + k * 0.065), s * (0.16 + k * 0.06)))
            pts.append((c + side * s * (0.16 + k * 0.06), s * (0.28 + k * 0.06)))
        pts.append((c + side * s * 0.1, s * 0.6))
        d.polygon(pts, fill=255)
    # cuerpo y cabeza
    d.ellipse((c - s * 0.07, s * 0.3, c + s * 0.07, s * 0.62), fill=255)
    d.ellipse((c - s * 0.05, s * 0.2, c + s * 0.05, s * 0.32), fill=255)
    d.polygon([(c + s * 0.04, s * 0.24), (c + s * 0.11, s * 0.27), (c + s * 0.04, s * 0.29)], fill=255)
    # cola de llamas
    for k in (-1, 0, 1):
        d.polygon([(c - s * 0.05, s * 0.58), (c + s * 0.05, s * 0.58), (c + k * s * 0.16, s * 0.95)], fill=255)


EMBLEMS = {
    "Camo": (e_camo, (200, 195, 140)),
    "Ice": (e_ice, (225, 245, 255), (120, 200, 255)),
    "Rust": (e_rust, (215, 120, 60)),
    "Crimson": (e_crimson, (255, 60, 70)),
    "Neon": (e_neon, (0, 255, 210)),
    "Toxic": (e_toxic, (160, 255, 40)),
    "Gold": (e_gold, (255, 215, 90), (255, 240, 170)),
    "Diamond": (e_diamond, (200, 245, 255), (120, 220, 255)),
    "Plasma": (e_plasma, (255, 90, 240)),
    "Luna": (e_luna, (255, 225, 140), (190, 150, 255)),
    "Inferno": (e_inferno, (255, 140, 30), (255, 60, 10)),
    "Storm": (e_storm, (170, 230, 255), (80, 160, 255)),
    "Galaxy": (e_galaxy, (235, 200, 255), (200, 80, 255)),
    "Prism": (e_prism, (255, 255, 255), (255, 150, 220)),
    "Phoenix": (e_phoenix, (255, 200, 70), (255, 80, 20)),
}

TEXTURES = [tex_camo, tex_ice, tex_rust, tex_crimson, tex_neon, tex_toxic, tex_gold, tex_diamond,
            tex_plasma, tex_luna, tex_inferno, tex_storm, tex_galaxy, tex_prism, tex_phoenix]


if __name__ == "__main__":
    os.makedirs(TEX_DIR, exist_ok=True)
    os.makedirs(EMB_DIR, exist_ok=True)
    for fn in TEXTURES:
        fn()
    for name, spec in EMBLEMS.items():
        emblem(name, spec[0], spec[1], spec[2] if len(spec) > 2 else None)
