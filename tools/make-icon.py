"""Genera los gráficos de PinVol: el ícono de la app y el glifo de la barra de menús.

Uso:
    python3 tools/make-icon.py                  # escribe Resources/AppIcon.icns y Resources/MenuBar*Template*.png
    python3 tools/make-icon.py salida.png [salida.icns]    # solo el ícono, para previsualizarlo

Requiere Pillow (pip3 install pillow). Todo está dibujado a mano con formas planas,
así que el resultado es idéntico en cualquier plataforma.
"""
import io
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

RESOURCES = Path(__file__).resolve().parent.parent / "Resources"


class Lienzo:
    """Lienzo cuadrado de `lado` unidades, dibujado a `ss` veces su tamaño para suavizar los bordes."""

    def __init__(self, lado, ss):
        self.lado, self.ss, self.n = lado, ss, lado * ss

    def px(self, v):
        """Coordenada del lienzo → píxeles del lienzo supermuestreado."""
        return round(v * self.ss)

    def mask(self):
        return Image.new("L", (self.n, self.n), 0)

    def circle(self, cx, cy, r):
        m = self.mask()
        ImageDraw.Draw(m).ellipse([self.px(cx - r), self.px(cy - r), self.px(cx + r), self.px(cy + r)], fill=255)
        return m

    def arc(self, cx, cy, r, a0, a1, width):
        """Arco grueso con extremos redondos. Ángulos en grados, en sentido horario desde las 3 en punto."""
        ro, ri = r + width / 2, r - width / 2
        sector = self.mask()
        ImageDraw.Draw(sector).pieslice(
            [self.px(cx - ro), self.px(cy - ro), self.px(cx + ro), self.px(cy + ro)], a0, a1, fill=255)
        m = ImageChops.subtract(sector, self.circle(cx, cy, ri))
        d = ImageDraw.Draw(m)
        for a in (a0, a1):
            x, y = cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
            d.ellipse([self.px(x - width / 2), self.px(y - width / 2),
                       self.px(x + width / 2), self.px(y + width / 2)], fill=255)
        return m


def rgb(h):
    return tuple(int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))


# ───────────────────────── Ícono de la app ─────────────────────────

L = Lienzo(1024, 3)

# Colores. La losa va de arriba a abajo; la sombra sale del color de abajo, oscurecido.
TILE = ("#3b62d6", "#0e1c58")
ARO = "#f3fff8"
CONO = "#0b5a3c"
NIVEL = "#4be39a"
PIN = dict(pin="#ff5b4d", cuello="#e03f3b", aguja="#8a99a2")


def oscurecer(h, f=0.28):
    return "#%02x%02x%02x" % tuple(round(c * f) for c in rgb(h))


def squircle(cx, cy, half, n=5.0):
    """Máscara de la losa: superelipse, más cercana a la forma de Apple que un rectángulo redondeado."""
    pts = []
    for i in range(1440):
        t = 2 * math.pi * i / 1440
        c, s = math.cos(t), math.sin(t)
        pts.append((L.px(cx + half * math.copysign(abs(c) ** (2 / n), c)),
                    L.px(cy + half * math.copysign(abs(s) ** (2 / n), s))))
    m = L.mask()
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def vertical_gradient(top, bottom):
    g = Image.linear_gradient("L").resize((L.n, L.n), Image.BILINEAR)    # negro arriba → blanco abajo
    return Image.composite(Image.new("RGB", (L.n, L.n), rgb(bottom)), Image.new("RGB", (L.n, L.n), rgb(top)), g)


def bottom_ramp(start=0.45, strength=0.34):
    """Máscara que va de 0 (hasta `start` de la altura) a `strength` en el borde inferior."""
    g = Image.linear_gradient("L").resize((L.n, L.n), Image.BILINEAR)
    k = 255 * strength / (1 - start)
    return g.point(lambda v: min(255, max(0, round((v / 255 - start) * k))))


def fill(dst, color, m, alpha=1.0):
    """Pinta `color` sobre `dst` (RGBA) a través de la máscara `m`."""
    if alpha < 1:
        m = m.point(lambda v: round(v * alpha))
    dst.paste(Image.new("RGB", m.size, rgb(color)), (0, 0), m)


def pin_layer(tip_x, tip_y, angle, k, st):
    """Chincheta de perfil: vertical con la punta en (tip_x, tip_y) y luego girada `angle` grados.

    `k` escala toda la pieza. Devuelve una capa RGBA.
    """
    px = L.px

    def y(d):                                  # altura sobre la punta
        return tip_y - d * k

    def box(half, lo, hi):
        return [px(tip_x - half * k), px(y(hi)), px(tip_x + half * k), px(y(lo))]

    layer = Image.new("RGBA", (L.n, L.n), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(px(tip_x - 12 * k), px(y(80))), (px(tip_x + 12 * k), px(y(80))),
               (px(tip_x + 2 * k), px(y(0))), (px(tip_x - 2 * k), px(y(0)))], fill=rgb(st["aguja"]))
    d.rounded_rectangle(box(52, 100, 200), radius=px(8 * k), fill=rgb(st["cuello"]))        # cuello
    d.rounded_rectangle(box(88, 70, 118), radius=px(15 * k), fill=rgb(st["pin"]))           # base
    d.rounded_rectangle(box(94, 188, 246), radius=px(29 * k), fill=rgb(st["pin"]))          # cabeza
    return layer.rotate(angle, resample=Image.BICUBIC, center=(px(tip_x), px(tip_y)))


def make_icon():
    px = L.px
    sombra = oscurecer(TILE[1])
    img = Image.new("RGBA", (L.n, L.n), (0, 0, 0, 0))

    # Losa con sombra suave, que se oscurece hacia abajo
    tile = squircle(512, 512, 412)                           # 824 px, como pide Apple
    sh = ImageChops.offset(tile, 0, px(14)).filter(ImageFilter.GaussianBlur(px(16)))
    fill(img, "#000000", sh, 0.40)
    img.paste(vertical_gradient(*TILE), (0, 0), tile)
    fill(img, sombra, ImageChops.multiply(bottom_ramp(), tile))

    cx, cy, R, r_cono, r_tapa = 512, 520, 312, 250, 90
    angulo = 28                                              # inclinación de la chincheta

    # Parlante: sombra proyectada hacia abajo, aro con borde inferior sombreado, cono y tapa
    cast = L.circle(cx, cy + 44, R).filter(ImageFilter.GaussianBlur(px(28)))
    fill(img, sombra, ImageChops.multiply(cast, tile), 0.60)
    fill(img, ARO, L.circle(cx, cy, R))
    media_luna = ImageChops.subtract(L.circle(cx, cy, R), L.circle(cx, cy - 26, R))
    fill(img, sombra, media_luna, 0.30)
    fill(img, CONO, L.circle(cx, cy, r_cono))
    fill(img, ARO, L.circle(cx, cy, r_tapa))

    # Indicador de volumen: dial de 270° que se llena hasta donde apunta la chincheta (el nivel fijado)
    r_g = 0.82 * r_cono
    fill(img, "#ffffff", L.arc(cx, cy, r_g, 135, 45, 28), 0.16)
    fill(img, NIVEL, L.arc(cx, cy, r_g, 135, 270 - angulo, 28))

    # Chincheta clavada en la tapa; la cabeza sobresale del parlante
    img.alpha_composite(pin_layer(cx, cy, angulo, 1.42 * R / 320, PIN))

    return img.resize((L.lado, L.lado), Image.LANCZOS)


def write_icns(icon, path):
    """Escribe un .icns con PNGs en los tamaños que genera iconutil (más 16 y 32 px a 1x)."""
    tipos = [(b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64), (b"ic07", 128), (b"ic13", 256),
             (b"ic08", 256), (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024)]
    cache, entradas = {}, []
    for tipo, lado in tipos:
        if lado not in cache:
            buf = io.BytesIO()
            icon.resize((lado, lado), Image.LANCZOS).save(buf, "PNG", optimize=True)
            cache[lado] = buf.getvalue()
        entradas.append(tipo + struct.pack(">I", 8 + len(cache[lado])) + cache[lado])
    cuerpo = b"".join(entradas)
    Path(path).write_bytes(b"icns" + struct.pack(">I", 8 + len(cuerpo)) + cuerpo)


# ───────────────────────── Glifo de la barra de menús ─────────────────────────

# Imagen plantilla (negro con transparencia): macOS la tiñe según el tema. Es el aro, el punto central
# y la chincheta del ícono, simplificados para verse bien a 18 pt. Activo a opacidad completa; inactivo, atenuado.
GLIFO = 36          # lado en píxeles (18 pt a 2x)
ATENUADO = 0.42


def glifo(activo):
    """Máscara del glifo a GLIFO × GLIFO px (supermuestreada)."""
    g = Lienzo(GLIFO, 16)
    px = g.px
    c = 21.4                                   # centro del aro y punta de la chincheta
    ang, hueco = 40, 1.25                      # inclinación y separación entre la chincheta y el aro

    def y(d):                                  # altura sobre la punta
        return c - d

    def caja(medio, d0, d1):
        return [px(c - medio), px(y(d1)), px(c + medio), px(y(d0))]

    pin = g.mask()
    d = ImageDraw.Draw(pin)
    d.polygon([(px(c - 1.15), px(y(4.8))), (px(c + 1.15), px(y(4.8))),
               (px(c + 0.3), px(y(0))), (px(c - 0.3), px(y(0)))], fill=255)                  # aguja
    d.rounded_rectangle(caja(5.3, 4.5, 7.8), radius=px(1.0), fill=255)                       # base
    d.rounded_rectangle(caja(3.1, 7.4, 15.5), radius=px(0.8), fill=255)                      # cuello
    d.rounded_rectangle(caja(6.6, 15.0, 19.6), radius=px(2.1), fill=255)                     # cabeza
    pin = pin.rotate(ang, resample=Image.BICUBIC, center=(px(c), px(c)))

    # Aro y punto central, con un recorte redondo alrededor de la chincheta
    base = ImageChops.lighter(ImageChops.subtract(g.circle(c, c, 11.6), g.circle(c, c, 8.5)), g.circle(c, c, 2.9))
    recorte = pin.filter(ImageFilter.GaussianBlur(px(hueco) * 0.55)).point(lambda v: 255 if v > 18 else 0)
    m = ImageChops.lighter(ImageChops.subtract(base, recorte), pin)
    return m if activo else m.point(lambda v: round(v * ATENUADO))


def write_glifo(activo, nombre):
    """Escribe `nombre`.png (18 px) y `nombre`@2x.png (36 px) en Resources."""
    m = glifo(activo)
    for lado, sufijo in ((GLIFO // 2, ""), (GLIFO, "@2x")):
        img = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
        img.putalpha(m.resize((lado, lado), Image.LANCZOS))
        img.save(RESOURCES / f"{nombre}{sufijo}.png", optimize=True)


def main(argv):
    icon = make_icon()
    if argv:
        icon.save(argv[0])
        if len(argv) > 1:
            write_icns(icon, argv[1])
        print("OK ->", *argv)
        return
    write_icns(icon, RESOURCES / "AppIcon.icns")
    write_glifo(True, "MenuBarActiveTemplate")
    write_glifo(False, "MenuBarIdleTemplate")
    print("OK ->", RESOURCES)


if __name__ == "__main__":
    main(sys.argv[1:])
