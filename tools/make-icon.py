#!/usr/bin/env python3
"""Genera el ícono de PinVol.

Uso: python3 tools/make-icon.py VARIANTE salida.png [salida.icns]
VARIANTE: a (barras + chincheta), b (marcador con altavoz), c (altavoz 3D + chincheta)

Requiere Pillow y numpy (pip install pillow numpy).
Dibuja todo a mano (sin símbolos SF ni CoreGraphics), así que el resultado es
idéntico en cualquier plataforma.

Las tres propuestas juegan con la misma idea: un nivel de volumen "pinchado" en su sitio.
"""
import math
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024          # tamaño final
SS = 3            # supermuestreo para suavizar bordes
W = S * SS


def px(v):
    """Coordenada en el lienzo de 1024 → píxeles del lienzo supermuestreado."""
    return v * SS


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def blank():
    return Image.new("L", (W, W), 0)


def gradient(box, stops, angle=90):
    """Degradado lineal RGBA que cubre todo el lienzo.

    box: (x0, y0, x1, y1) en coords de 1024, extremos del degradado.
    stops: [(posición 0..1, '#rrggbb' o (r, g, b, a))].
    """
    x0, y0, x1, y1 = [px(v) for v in box]
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    dx, dy = x1 - x0, y1 - y0
    t = ((xs - x0) * dx + (ys - y0) * dy) / (dx * dx + dy * dy)
    t = np.clip(t, 0, 1)
    pos = [p for p, _ in stops]
    cols = []
    for _, c in stops:
        c = rgb(c) + (255,) if isinstance(c, str) else tuple(c)
        cols.append(c)
    out = np.stack([np.interp(t, pos, [c[k] for c in cols]) for k in range(4)], axis=-1)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def solid(color):
    c = rgb(color) + (255,) if isinstance(color, str) else tuple(color)
    return Image.new("RGBA", (W, W), c)


def paste(dst, fill, mask, opacity=1.0):
    """Pinta `fill` sobre `dst` a través de `mask` (L)."""
    if opacity < 1:
        mask = mask.point(lambda v: int(v * opacity))
    a = ImageChops.multiply(fill.getchannel("A"), mask)
    fill = fill.copy()
    fill.putalpha(a)
    dst.alpha_composite(fill)


def shadow(dst, mask, dx, dy, blur, alpha, color="#000000"):
    m = ImageChops.offset(mask, px(dx), px(dy)).filter(ImageFilter.GaussianBlur(px(blur)))
    paste(dst, solid(color), m, alpha)


def squircle(cx, cy, half, n=5.0):
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    u = np.abs((xs - px(cx)) / px(half))
    v = np.abs((ys - px(cy)) / px(half))
    d = (u ** n + v ** n) ** (1 / n)
    # borde con 1 px supermuestreado de antialias
    edge = np.clip((1 - d) * px(half) + 0.5, 0, 1)
    return Image.fromarray((edge * 255).astype(np.uint8), "L")


def rrect(x0, y0, x1, y1, r, base=None):
    m = base or blank()
    ImageDraw.Draw(m).rounded_rectangle([px(x0), px(y0), px(x1), px(y1)], radius=px(r), fill=255)
    return m


def ellipse(x0, y0, x1, y1):
    m = blank()
    ImageDraw.Draw(m).ellipse([px(x0), px(y0), px(x1), px(y1)], fill=255)
    return m


def polygon(pts):
    m = blank()
    ImageDraw.Draw(m).polygon([(px(x), px(y)) for x, y in pts], fill=255)
    return m



def radial(cx, cy, rx, ry, stops):
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    t = np.clip(np.sqrt(((xs - px(cx)) / px(rx)) ** 2 + ((ys - px(cy)) / px(ry)) ** 2), 0, 1)
    pos = [p for p, _ in stops]
    cols = [rgb(c) + (255,) if isinstance(c, str) else tuple(c) for _, c in stops]
    out = np.stack([np.interp(t, pos, [c[k] for c in cols]) for k in range(4)], axis=-1)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def ring(cx, cy, r_out, r_in):
    return ImageChops.subtract(ellipse(cx - r_out, cy - r_out, cx + r_out, cy + r_out),
                               ellipse(cx - r_in, cy - r_in, cx + r_in, cy + r_in))


def new_canvas(stops, glow=None):
    """Lienzo con la losa y su sombra. Devuelve (img, tile)."""
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    tile = squircle(512, 512, 412)            # losa de 824 px, como pide Apple
    shadow(img, tile, 0, 14, 16, 0.45)
    bg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    paste(bg, gradient((100, 100, 924, 924), stops), tile)
    if glow:
        paste(bg, radial(*glow[:4], [(0, glow[4]), (1, glow[4][:3] + (0,))]), tile)
    paste(bg, gradient((0, 100, 0, 520), [(0, (255, 255, 255, 46)), (1, (255, 255, 255, 0))]), tile)
    img.alpha_composite(bg)
    return img, tile


def finish(img, tile, path_png, path_icns=None):
    # Borde interior fino arriba, para que la losa no se pierda sobre fondos oscuros
    rim = ImageChops.subtract(tile, tile.filter(ImageFilter.MinFilter(px(4) | 1)))
    paste(img, gradient((0, 100, 0, 400), [(0, (255, 255, 255, 110)), (1, (255, 255, 255, 0))]), rim)
    out = img.resize((S, S), Image.LANCZOS)
    out.save(path_png)
    if path_icns:
        out.save(path_icns, format="ICNS", sizes=[(s, s) for s in (16, 32, 64, 128, 256, 512, 1024)])


def draw_pin(img, tip_x, tip_y, angle, shadow_dx=14, shadow_dy=22):
    """Chincheta roja vertical con la punta en (tip_x, tip_y), girada `angle` grados."""
    ux, uy = tip_x, tip_y
    Y = lambda d: uy - d                      # altura sobre la punta
    pin = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    needle = polygon([(ux - 9, Y(86)), (ux + 9, Y(86)), (ux + 1.5, Y(0)), (ux - 1.5, Y(0))])
    paste(pin, gradient((ux - 9, 0, ux + 9, 0), [(0, "#ffffff"), (0.4, "#c9d2e6"), (1, "#6b7391")]), needle)

    body = blank()
    rrect(ux - 82, Y(122), ux + 82, Y(84), 18, body)       # base ancha
    rrect(ux - 44, Y(206), ux + 44, Y(110), 10, body)       # cilindro
    rrect(ux - 86, Y(250), ux + 86, Y(196), 26, body)       # tapa
    paste(pin, gradient((ux - 86, 0, ux + 86, 0),
                        [(0, "#ff9a7a"), (0.3, "#ff4d4a"), (0.75, "#d3213f"), (1, "#8f1236")]), body)
    for (lo, hi, half) in [(84, 122, 82), (110, 206, 44), (196, 250, 86)]:
        seg = ImageChops.multiply(rrect(ux - half, Y(hi), ux + half, Y(lo), 12), body)
        paste(pin, gradient((0, Y(hi), 0, Y(lo)), [(0, (255, 255, 255, 40)), (1, (60, 0, 20, 70))]), seg)
    paste(pin, solid((255, 255, 255, 255)),
          ImageChops.multiply(rrect(ux - 76, Y(246), ux + 76, Y(232), 7), body).filter(ImageFilter.GaussianBlur(px(2))), 0.55)
    paste(pin, solid((255, 255, 255, 255)),
          rrect(ux - 30, Y(196), ux - 18, Y(116), 6).filter(ImageFilter.GaussianBlur(px(2.5))), 0.55)
    for d in (108, 194):
        line = ImageChops.multiply(rrect(ux - 84, Y(d + 2), ux + 84, Y(d - 2), 2), body)
        paste(pin, solid((70, 0, 25, 255)), line.filter(ImageFilter.GaussianBlur(px(2))), 0.45)

    pin = pin.rotate(angle, resample=Image.BICUBIC, center=(px(tip_x), px(tip_y)))
    hole = ellipse(tip_x - 15, tip_y - 6, tip_x + 15, tip_y + 6)
    paste(img, solid("#06113a"), hole.filter(ImageFilter.GaussianBlur(px(2))), 0.9)
    shadow(img, pin.getchannel("A"), shadow_dx, shadow_dy, 12, 0.5, "#020520")
    img.alpha_composite(pin)


# ───────────────────────── A: barras de volumen + chincheta ─────────────────────────
def variant_a():
    img, tile = new_canvas([(0, "#2a2f86"), (0.55, "#141a52"), (1, "#080b2c")], (560, 790, 430, 330, (38, 110, 255, 190)))
    BAR_W, GAP, BOTTOM, LEVEL = 92, 34, 806, 2
    heights = [150, 232, 314, 396, 478]
    x_start = 512 - (5 * BAR_W + 4 * GAP) / 2
    bars = [(x_start + i * (BAR_W + GAP), BOTTOM - h, x_start + i * (BAR_W + GAP) + BAR_W, BOTTOM)
            for i, h in enumerate(heights)]
    on_mask, off_mask = blank(), blank()
    for i, (x0, y0, x1, y1) in enumerate(bars):
        rrect(x0, y0, x1, y1, 30, on_mask if i <= LEVEL else off_mask)
    paste(img, solid((255, 255, 255, 255)), off_mask, 0.10)
    edge = ImageChops.subtract(off_mask, off_mask.filter(ImageFilter.MinFilter(px(3) | 1)))
    paste(img, solid((255, 255, 255, 255)), edge, 0.20)
    shadow(img, on_mask, 0, 0, 26, 0.65, "#2f8bff")
    paste(img, gradient((0, 330, 0, BOTTOM), [(0, "#9afcff"), (0.45, "#3fc4ff"), (1, "#2a6bff")]), on_mask)
    for (x0, y0, x1, y1) in bars[:LEVEL + 1]:
        hl = rrect(x0 + 8, y0 + 6, x1 - 8, y0 + 34, 14)
        paste(img, solid((255, 255, 255, 255)), hl.filter(ImageFilter.GaussianBlur(px(3))), 0.45)
    bx0, by0, bx1, _ = bars[LEVEL]
    draw_pin(img, (bx0 + bx1) / 2, by0 + 14, 24)
    return img, tile


# ───────────────────────── B: marcador de mapa con cono de altavoz ─────────────────────────
def variant_b():
    img, tile = new_canvas([(0, "#ff9a62"), (0.5, "#f04a62"), (1, "#a8186e")], (330, 260, 520, 420, (255, 210, 150, 120)))
    cx, cy, R = 512, 440, 238
    tip = (512, 846)
    d = tip[1] - cy
    phi = np.arccos(R / d)
    t1 = (cx - R * np.sin(phi), cy + R * np.cos(phi))
    t2 = (cx + R * np.sin(phi), cy + R * np.cos(phi))
    marker = ImageChops.lighter(ellipse(cx - R, cy - R, cx + R, cy + R), polygon([(cx, cy), t1, tip, t2]))
    # esquinas redondeadas: difuminar y umbralar
    marker = marker.filter(ImageFilter.GaussianBlur(px(10))).point(lambda v: 255 if v > 128 else int(v * 2) if v > 64 else 0)
    shadow(img, marker, 0, 26, 22, 0.40, "#3a0630")
    paste(img, gradient((0, cy - R, 0, tip[1]), [(0, "#ffffff"), (1, "#ffd9e4")]), marker)
    # ondas de sonido saliendo del marcador (arriba a la derecha)
    for k, (r, a) in enumerate([(330, 0.85), (400, 0.55), (470, 0.30)]):
        arc = Image.new("L", (W, W), 0)
        box = [px(cx - r), px(cy - r), px(cx + r), px(cy + r)]
        ImageDraw.Draw(arc).arc(box, start=-52, end=-8, fill=255, width=px(26))
        # puntas redondeadas
        for ang in (-52, -8):
            mx = cx + (r - 13) * math.cos(math.radians(ang))
            my = cy + (r - 13) * math.sin(math.radians(ang))
            ImageDraw.Draw(arc).ellipse([px(mx - 13), px(my - 13), px(mx + 13), px(my + 13)], fill=255)
        paste(img, solid((255, 255, 255, 255)), ImageChops.multiply(arc, tile), a)
    # ojo del marcador = cono de altavoz
    hole_r = 150
    hole = ellipse(cx - hole_r, cy - hole_r, cx + hole_r, cy + hole_r)
    paste(img, radial(cx, cy - 20, hole_r * 1.2, hole_r * 1.2, [(0, "#2c3aa8"), (0.7, "#161a5e"), (1, "#0a0c36")]), hole)
    inner_shadow = ImageChops.subtract(hole, ImageChops.offset(hole, 0, px(12)))
    paste(img, solid("#000020"), inner_shadow.filter(ImageFilter.GaussianBlur(px(6))), 0.6)
    for r, a in [(118, 0.28), (84, 0.38)]:
        paste(img, solid("#5ac8ff"), ring(cx, cy, r, r - 7), a)
    cap = ellipse(cx - 52, cy - 52, cx + 52, cy + 52)
    shadow(img, cap, 0, 6, 6, 0.5, "#000020")
    paste(img, radial(cx - 14, cy - 18, 70, 70, [(0, "#d6f6ff"), (0.5, "#5ac8ff"), (1, "#2a6bff")]), cap)
    return img, tile


# ───────────────────────── C: altavoz 3D con chincheta ─────────────────────────
def variant_c():
    img, tile = new_canvas([(0, "#4a4f5c"), (0.5, "#20232b"), (1, "#0b0c10")], (512, 300, 500, 300, (255, 255, 255, 40)))
    cx, cy = 512, 520
    outer = ellipse(cx - 330, cy - 330, cx + 330, cy + 330)
    shadow(img, outer, 0, 22, 22, 0.6, "#000000")
    # aro metálico
    paste(img, gradient((cx - 330, cy - 330, cx + 330, cy + 330), [(0, "#f4f6fb"), (0.5, "#8d93a3"), (1, "#3a3e4b")]), outer)
    paste(img, gradient((cx + 330, cy + 330, cx - 330, cy - 330), [(0, "#e8ebf4"), (0.5, "#6b7080"), (1, "#2a2d38")]),
          ring(cx, cy, 314, 290))
    # suspensión de goma
    paste(img, radial(cx, cy, 290, 290, [(0.78, "#16181f"), (0.88, "#2b2e38"), (1, "#0d0e12")]), ellipse(cx - 290, cy - 290, cx + 290, cy + 290))
    # cono
    cone = ellipse(cx - 232, cy - 232, cx + 232, cy + 232)
    paste(img, radial(cx - 60, cy - 80, 300, 300, [(0, "#4b5262"), (0.55, "#262a35"), (1, "#0c0d12")]), cone)
    for r in (205, 170, 135, 105):
        paste(img, solid((255, 255, 255, 255)), ring(cx, cy, r, r - 3), 0.07)
        paste(img, solid((0, 0, 0, 255)), ring(cx, cy, r - 3, r - 8), 0.35)
    # reflejo en el cono
    paste(img, gradient((cx - 200, cy - 200, cx + 100, cy + 100), [(0, (255, 255, 255, 70)), (0.5, (255, 255, 255, 0))]), cone)
    # tapa central metálica
    cap_r = 84
    cap = ellipse(cx - cap_r, cy - cap_r, cx + cap_r, cy + cap_r)
    shadow(img, cap, 0, 8, 8, 0.6, "#000000")
    paste(img, radial(cx - 26, cy - 30, 120, 120, [(0, "#ffffff"), (0.35, "#b8bfd0"), (1, "#3c4050")]), cap)
    # indicador de nivel: arco cian alrededor del aro de goma, hasta el nivel fijado
    arc = Image.new("L", (W, W), 0)
    r = 262
    ImageDraw.Draw(arc).arc([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], start=135, end=135 + 200, fill=255, width=px(14))
    for ang in (135, 335):
        mx, my = cx + (r - 7) * math.cos(math.radians(ang)), cy + (r - 7) * math.sin(math.radians(ang))
        ImageDraw.Draw(arc).ellipse([px(mx - 7), px(my - 7), px(mx + 7), px(my + 7)], fill=255)
    shadow(img, arc, 0, 0, 14, 0.9, "#2fc4ff")
    paste(img, gradient((cx - 262, cy + 262, cx + 262, cy - 262), [(0, "#6ee7ff"), (1, "#3b7bff")]), arc)
    draw_pin(img, cx + 6, cy + 4, 24)
    return img, tile


if __name__ == "__main__":
    variants = {"a": variant_a, "b": variant_b, "c": variant_c}
    if len(sys.argv) < 3 or sys.argv[1] not in variants:
        sys.exit(__doc__)
    img, tile = variants[sys.argv[1]]()
    finish(img, tile, sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    print("OK ->", *sys.argv[2:])
