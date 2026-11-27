"""Imagenes del lobby (plaza): suelo de marmol premium y agua de la fuente.

    python assets/lobby/generate.py

Suelo (MaterialVariant LobbyFloorPremium, 16 studs por repeticion = 4x4 baldosas):
    floor_color.png, floor_normal.png, floor_roughness.png, floor_metalness.png
Fuente:
    water_streak.png   chorro / cortina de agua (Beam, se desplaza hacia abajo)
    water_ripples.png  brillos de ondas en la superficie (Texture que se desplaza)
    caustics.png       red de luz en el fondo (Texture que se desplaza)
    mosaic.png         gresite azul del fondo del vaso
    splash.png         gota/espuma (particulas)
    ripple_ring.png    anillo de onda (particulas planas sobre el agua)
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "skins"))
from generate import fbm, sample_wrap, voronoi, ramp  # noqa: E402  (utilidades de las skins)

OUT = os.path.join(HERE, "images")


def save(name, arr, mode):
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode)
    img.save(os.path.join(OUT, name))
    print(name)


# ----------------------------------------------------------------------------- suelo

FN = 1024          # pixeles de la imagen
TILES = 4          # 4x4 baldosas por repeticion
TP = FN // TILES   # pixeles por baldosa
GROUT = 2          # junta (px)
CAB = 30           # media diagonal del inserto de granito (px)


def marble_field(seed):
    """Marmol blanco calido con nubes beige y vetas grises (periodico)."""
    # vetas: crestas finas de un ruido suave deformado (lineas largas que serpentean)
    a = fbm(seed, 3.6, FN) * FN * 0.18
    b = fbm(seed + 1, 3.6, FN) * FN * 0.18
    yy, xx = np.mgrid[0:FN, 0:FN].astype(np.float32)
    n = sample_wrap(fbm(seed + 2, 3.8, FN), yy + a, xx + b)
    veins = (1 - np.abs(n - 0.5) * 2) ** 90
    m = sample_wrap(fbm(seed + 3, 3.4, FN), yy - b * 0.5, xx + a * 0.5)
    veins2 = (1 - np.abs(m - 0.5) * 2) ** 160
    veins = np.asarray(Image.fromarray((np.clip(veins, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    halo = np.asarray(Image.fromarray((np.clip(veins, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6)), np.float32) / 255
    cloud = fbm(seed + 4, 3.6, FN)
    base = ramp(cloud, [(0, (236, 231, 221)), (0.5, (244, 241, 235)), (1, (250, 248, 244))])
    base -= (veins * 0.85 + veins2 * 0.5)[..., None] * np.array([120, 112, 104], np.float32)
    base -= halo[..., None] * np.array([14, 12, 9], np.float32)  # sombra calida junto a la veta
    base += (fbm(seed + 5, 0.6, FN)[..., None] - 0.5) * 4  # grano
    return base


def floor():
    field = marble_field(201)
    rng = np.random.default_rng(202)
    color = np.zeros((FN, FN, 3), np.float32)
    height = np.ones((FN, FN), np.float32)
    rough = np.zeros((FN, FN), np.float32)
    # cada baldosa: un trozo distinto del marmol, girado 0/90/180/270 (como baldosas reales)
    for ty in range(TILES):
        for tx in range(TILES):
            oy, ox = rng.integers(0, FN, 2)
            crop = np.roll(np.roll(field, -oy, 0), -ox, 1)[:TP, :TP]
            crop = np.rot90(crop, rng.integers(0, 4))
            tone = rng.uniform(-6, 6)  # cada baldosa un pelin distinta
            color[ty * TP:(ty + 1) * TP, tx * TP:(tx + 1) * TP] = crop + tone
            rough[ty * TP:(ty + 1) * TP, tx * TP:(tx + 1) * TP] = rng.uniform(0.07, 0.13)
    rough += (fbm(203, 1.5, FN) - 0.5) * 0.05
    # juntas
    yy, xx = np.mgrid[0:FN, 0:FN]
    gx = np.minimum(xx % TP, TP - xx % TP)
    gy = np.minimum(yy % TP, TP - yy % TP)
    grout = (np.minimum(gx, gy) < GROUT / 2 + 0.5)
    color[grout] = (150, 144, 136)
    height[grout] = 0.0
    rough[grout] = 0.7
    # insertos (rombos de granito negro con filo dorado) en cada cruce de juntas
    metal = np.zeros((FN, FN), np.float32)
    dx = np.minimum(xx % TP, TP - xx % TP).astype(np.float32)
    dy = np.minimum(yy % TP, TP - yy % TP).astype(np.float32)
    diamond = dx + dy  # distancia "rombo" al cruce mas cercano
    rim = (diamond < CAB) & (diamond >= CAB - 4)
    core = diamond < CAB - 4
    speck = fbm(204, 0.2, FN)
    granite = ramp(speck, [(0, (14, 14, 16)), (0.7, (32, 32, 36)), (0.85, (70, 70, 76)), (1, (150, 150, 155))])
    color[core] = granite[core]
    height[core] = 0.92
    rough[core] = 0.12
    color[rim] = (205, 165, 85)
    height[rim] = 1.0
    rough[rim] = 0.25
    metal[rim] = 1.0
    save("floor_color.png", color, "RGB")
    # normal (OpenGL: verde hacia arriba) a partir de la altura
    h = np.asarray(Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255
    sx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 2.5
    sy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 2.5
    nz = np.ones_like(h)
    n = np.stack([-sx, sy, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    save("floor_normal.png", (n * 0.5 + 0.5) * 255, "RGB")
    save("floor_roughness.png", np.clip(rough, 0, 1) * 255, "L")
    save("floor_metalness.png", metal * 255, "L")


# ----------------------------------------------------------------------------- agua

def water_streak():
    w, h = 128, 512
    rng = np.random.default_rng(301)
    xx = np.arange(w)[None, :].astype(np.float32)
    yy = np.arange(h)[:, None].astype(np.float32)
    streak = np.zeros((h, w), np.float32)
    for _ in range(26):  # hilos de agua: lineas verticales con brillo que cambia a lo largo
        cx = rng.uniform(6, w - 6)
        width = rng.uniform(1.2, 4.5)
        phase = rng.uniform(0, 2 * math.pi)
        k = rng.integers(1, 4)  # vueltas enteras -> se repite en vertical
        bright = 0.55 + 0.45 * np.sin(yy / h * 2 * math.pi * k + phase)
        streak += np.exp(-((xx - cx) / width) ** 2) * bright * rng.uniform(0.4, 1)
    streak = np.clip(streak, 0, 1.4) / 1.4
    edge = np.clip(np.minimum(xx, w - 1 - xx) / 18, 0, 1)  # bordes suaves
    alpha = (0.28 + 0.72 * streak) * edge
    rgb = np.stack([np.full((h, w), 225), np.full((h, w), 240), np.full((h, w), 255)], -1).astype(np.float32)
    rgb = rgb * (0.85 + 0.15 * streak[..., None])
    save("water_streak.png", np.dstack([rgb, alpha * 255]), "RGBA")


def caustic_lines(seed, count, width, size=512):
    f1, f2, _, _ = voronoi(seed, count, size)
    edge = np.clip(1 - (f2 - f1) / width, 0, 1) ** 1.5
    # que la red no sea perfecta: se deforma con ruido
    a = fbm(seed + 1, 3.0, size) * 22
    b = fbm(seed + 2, 3.0, size) * 22
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    return sample_wrap(edge, yy + a, xx + b)


def water_ripples():
    lines = caustic_lines(311, 60, 5)
    lines = np.asarray(Image.fromarray((lines * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    alpha = lines * 0.85
    rgb = np.dstack([np.full(lines.shape, 240), np.full(lines.shape, 250), np.full(lines.shape, 255)]).astype(np.float32)
    save("water_ripples.png", np.dstack([rgb, alpha * 255]), "RGBA")


def caustics():
    lines = caustic_lines(321, 45, 7)
    soft = np.asarray(Image.fromarray((lines * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.5)), np.float32) / 255
    v = np.clip(lines * 0.7 + soft * 0.6, 0, 1)
    rgb = np.dstack([np.full(v.shape, 200), np.full(v.shape, 245), np.full(v.shape, 255)]).astype(np.float32)
    save("caustics.png", np.dstack([rgb, v * 0.75 * 255]), "RGBA")


def mosaic():
    size, cell = 512, 16
    rng = np.random.default_rng(331)
    img = np.zeros((size, size, 3), np.float32)
    palette = [(20, 95, 130), (30, 120, 150), (40, 140, 165), (25, 80, 120), (60, 160, 175), (15, 70, 105)]
    for cy in range(size // cell):
        for cx in range(size // cell):
            c = np.array(palette[rng.integers(len(palette))], np.float32) + rng.uniform(-10, 10)
            img[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = c
    yy, xx = np.mgrid[0:size, 0:size]
    grout = ((xx % cell) < 2) | ((yy % cell) < 2)
    img[grout] = (175, 190, 190)
    shine = (fbm(332, 1.0, size)[..., None] - 0.5) * 20
    save("mosaic.png", img + shine, "RGB")


def splash():
    s = 128
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    r = np.sqrt((xx - s / 2) ** 2 + (yy - s / 2) ** 2) / (s / 2)
    n = fbm(341, 2.0, s)
    blob = np.clip(1 - r / (0.6 + 0.35 * n), 0, 1) ** 0.8
    rgb = np.dstack([np.full((s, s), 245), np.full((s, s), 250), np.full((s, s), 255)]).astype(np.float32)
    save("splash.png", np.dstack([rgb, blob * 230]), "RGBA")


def ripple_ring():
    s = 256
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    r = np.sqrt((xx - s / 2) ** 2 + (yy - s / 2) ** 2) / (s / 2)
    ring = np.exp(-((r - 0.82) / 0.07) ** 2) + 0.45 * np.exp(-((r - 0.62) / 0.05) ** 2)
    ring *= r < 1
    rgb = np.dstack([np.full((s, s), 235), np.full((s, s), 248), np.full((s, s), 255)]).astype(np.float32)
    save("ripple_ring.png", np.dstack([rgb, np.clip(ring, 0, 1) * 220]), "RGBA")


def medallion():
    """Medallon del spawn: rosa de los vientos de granito negro y oro sobre marmol blanco,
    con la luna de Plaza Luna en el centro. Disco (fondo transparente fuera del circulo)."""
    S = 1024
    field = marble_field(401)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = cy = S / 2
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (S / 2)
    img = Image.fromarray(np.clip(field, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    big = 2  # supermuestreo para los poligonos
    layer = Image.new("RGBA", (S * big, S * big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    C = S * big / 2
    R = S * big / 2
    speck = fbm(402, 0.2, S)
    granite = np.dstack([ramp(speck, [(0, (12, 12, 14)), (0.75, (30, 30, 34)), (0.9, (75, 75, 80)), (1, (150, 150, 155))]), np.full((S, S), 255)])
    granite_img = Image.fromarray(np.clip(granite, 0, 255).astype(np.uint8), "RGBA").resize((S * big, S * big))
    grey = Image.fromarray(np.clip(granite[..., :3] * 0.6 + 70, 0, 255).astype(np.uint8), "RGB").convert("RGBA").resize((S * big, S * big))
    GOLD = (212, 170, 80, 255)

    def pt(angle, rad):
        return (C + math.cos(angle) * rad * R, C - math.sin(angle) * rad * R)

    # banda negra con filos dorados cerca del borde
    def circle(rad, **kw):
        d.ellipse((C - rad * R, C - rad * R, C + rad * R, C + rad * R), **kw)

    band = Image.new("L", (S * big, S * big), 0)
    bd = ImageDraw.Draw(band)
    bd.ellipse((C - 0.93 * R, C - 0.93 * R, C + 0.93 * R, C + 0.93 * R), fill=255)
    bd.ellipse((C - 0.85 * R, C - 0.85 * R, C + 0.85 * R, C + 0.85 * R), fill=0)
    layer.paste(granite_img, (0, 0), band)
    circle(0.93, outline=GOLD, width=6 * big)
    circle(0.85, outline=GOLD, width=6 * big)
    # 16 marcas doradas en la banda (como un reloj de sol)
    for k in range(16):
        a = k * math.pi / 8
        d.line([pt(a, 0.865), pt(a, 0.915)], fill=GOLD, width=5 * big)

    # rosa de los vientos: 8 puntas, cada una en dos mitades (negra y gris: relieve)
    def point(angle, length, half_width):
        tip = pt(angle, length)
        left = pt(angle + math.pi / 8, half_width)
        right = pt(angle - math.pi / 8, half_width)
        center = (C, C)
        return [center, left, tip], [center, tip, right]

    for k in range(8):
        a = math.pi / 2 - k * math.pi / 4
        main = k % 2 == 0
        length, hw = (0.82, 0.2) if main else (0.56, 0.17)
        for half, src in zip(point(a, length, hw), (granite_img, grey)):
            mask = Image.new("L", (S * big, S * big), 0)
            ImageDraw.Draw(mask).polygon(half, fill=255)
            layer.paste(src, (0, 0), mask)
            d.polygon(half, outline=GOLD, width=4 * big)
    # centro: disco dorado con la luna creciente negra
    circle(0.17, fill=GOLD)
    circle(0.17, outline=(150, 115, 45, 255), width=5 * big)
    moon = Image.new("L", (S * big, S * big), 0)
    md = ImageDraw.Draw(moon)
    mr = 0.11 * R
    md.ellipse((C - mr, C - mr, C + mr, C + mr), fill=255)
    md.ellipse((C - mr + mr * 0.45, C - mr - mr * 0.1, C + mr + mr * 0.45, C + mr - mr * 0.1), fill=0)
    layer.paste(granite_img, (0, 0), moon)

    layer = layer.resize((S, S), Image.LANCZOS)
    img = Image.alpha_composite(img, layer)
    alpha = np.clip((1.0 - r) * S / 2, 0, 1) * 255  # disco con borde suave de 1 px
    arr = np.asarray(img, np.float32)
    arr[..., 3] = alpha
    save("medallion.png", arr, "RGBA")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    medallion()
    floor()
    water_streak()
    water_ripples()
    caustics()
    mosaic()
    splash()
    ripple_ring()
