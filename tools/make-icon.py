"""Genera el ícono de PinVol: un parlante con una chincheta clavada que fija el nivel.

Uso:
    python3 tools/make-icon.py                       # escribe Resources/AppIcon.icns
    python3 tools/make-icon.py salida.png [salida.icns] [--indicador arco|ondas]

Requiere Pillow (pip3 install pillow). Todo está dibujado a mano con formas planas,
así que el resultado es idéntico en cualquier plataforma.
"""
import io
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024            # tamaño final
SS = 3              # supermuestreo para suavizar bordes
W = S * SS

C = dict(tile=("#3bdc8e", "#0f9660"), aro="#f3fff8", cono="#0b5a3c", tapa="#f3fff8",
         pin="#ff5b4d", cuello="#e03f3b", aguja="#8a99a2", nivel="#4be39a", sombra="#032a1a")


def px(v):
    """Coordenada del lienzo de 1024 → píxeles del lienzo supermuestreado."""
    return round(v * SS)


def rgb(h):
    return tuple(int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))


def mask():
    return Image.new("L", (W, W), 0)


def squircle(cx, cy, half, n=5.0):
    """Máscara de la losa: superelipse, más cercana a la forma de Apple que un rectángulo redondeado."""
    pts = []
    for i in range(1440):
        t = 2 * math.pi * i / 1440
        c, s = math.cos(t), math.sin(t)
        pts.append((px(cx + half * math.copysign(abs(c) ** (2 / n), c)),
                    px(cy + half * math.copysign(abs(s) ** (2 / n), s))))
    m = mask()
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def vertical_gradient(top, bottom):
    g = Image.linear_gradient("L").resize((W, W), Image.BILINEAR)    # negro arriba → blanco abajo
    return Image.composite(Image.new("RGB", (W, W), rgb(bottom)), Image.new("RGB", (W, W), rgb(top)), g)


def fill(dst, color, m, alpha=1.0):
    """Pinta `color` sobre `dst` (RGBA) a través de la máscara `m`."""
    if alpha < 1:
        m = m.point(lambda v: round(v * alpha))
    dst.paste(Image.new("RGB", (W, W), rgb(color)), (0, 0), m)


def circle(cx, cy, r):
    m = mask()
    ImageDraw.Draw(m).ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=255)
    return m


def arc(cx, cy, r, a0, a1, width):
    """Arco grueso con extremos redondos. Ángulos en grados, en sentido horario desde las 3 en punto."""
    ro, ri = r + width / 2, r - width / 2
    sector = mask()
    ImageDraw.Draw(sector).pieslice([px(cx - ro), px(cy - ro), px(cx + ro), px(cy + ro)], a0, a1, fill=255)
    m = ImageChops.subtract(sector, circle(cx, cy, ri))
    d = ImageDraw.Draw(m)
    for a in (a0, a1):
        x, y = cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))
        d.ellipse([px(x - width / 2), px(y - width / 2), px(x + width / 2), px(y + width / 2)], fill=255)
    return m


def pin_layer(tip_x, tip_y, angle, k, st):
    """Chincheta de perfil: vertical con la punta en (tip_x, tip_y) y luego girada `angle` grados.

    `k` escala toda la pieza. Devuelve una capa RGBA.
    """
    def y(d):                                  # altura sobre la punta
        return tip_y - d * k

    def box(half, lo, hi):
        return [px(tip_x - half * k), px(y(hi)), px(tip_x + half * k), px(y(lo))]

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(px(tip_x - 12 * k), px(y(80))), (px(tip_x + 12 * k), px(y(80))),
               (px(tip_x + 2 * k), px(y(0))), (px(tip_x - 2 * k), px(y(0)))], fill=rgb(st["aguja"]))
    d.rounded_rectangle(box(52, 100, 200), radius=px(8 * k), fill=rgb(st["cuello"]))        # cuello
    d.rounded_rectangle(box(88, 70, 118), radius=px(15 * k), fill=rgb(st["pin"]))           # base
    d.rounded_rectangle(box(94, 188, 246), radius=px(29 * k), fill=rgb(st["pin"]))          # cabeza
    return layer.rotate(angle, resample=Image.BICUBIC, center=(px(tip_x), px(tip_y)))


def make_icon(indicador="arco"):
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    # Losa con sombra suave
    tile = squircle(512, 512, 412)                           # 824 px, como pide Apple
    sh = ImageChops.offset(tile, 0, px(14)).filter(ImageFilter.GaussianBlur(px(16)))
    fill(img, "#000000", sh, 0.40)
    img.paste(vertical_gradient(*C["tile"]), (0, 0), tile)

    angulo = 28                                              # inclinación de la chincheta
    if indicador == "arco":
        cx, cy, R, r_cono, r_tapa = 512, 520, 312, 250, 90
    else:
        cx, cy, R, r_cono, r_tapa = 422, 540, 252, 196, 72

    # Sombra proyectada hacia abajo y sombreado en el borde inferior del aro
    cast = circle(cx, cy + 30, R).filter(ImageFilter.GaussianBlur(px(24)))
    fill(img, C["sombra"], ImageChops.multiply(cast, tile), 0.36)
    fill(img, C["aro"], circle(cx, cy, R))
    media_luna = ImageChops.subtract(circle(cx, cy, R), circle(cx, cy - 20, R))
    fill(img, C["sombra"], media_luna, 0.16)
    fill(img, C["cono"], circle(cx, cy, r_cono))
    fill(img, C["tapa"], circle(cx, cy, r_tapa))

    # Indicador de volumen
    if indicador == "arco":
        # Dial de 270° que se llena hasta donde apunta la chincheta (el nivel fijado)
        r_g = 0.82 * r_cono
        fin = 270 - angulo
        fill(img, "#ffffff", arc(cx, cy, r_g, 135, 45, 28), 0.16)
        fill(img, C["nivel"], arc(cx, cy, r_g, 135, fin, 28))
    else:
        for r_w, a in ((R + 44, 1.0), (R + 92, 0.75), (R + 140, 0.5)):
            fill(img, C["aro"], arc(cx, cy, r_w, -36, 36, 26), a)

    # Chincheta clavada en la tapa; la cabeza sobresale del parlante
    img.alpha_composite(pin_layer(cx, cy, angulo, 1.42 * R / 320, C))

    return img.resize((S, S), Image.LANCZOS)


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


def main(argv):
    indicador = "arco"
    if "--indicador" in argv:
        i = argv.index("--indicador")
        indicador = argv[i + 1]
        del argv[i:i + 2]
    if indicador not in ("arco", "ondas"):
        sys.exit(f"indicador desconocido: {indicador} (opciones: arco, ondas)")
    icon = make_icon(indicador)
    if not argv:
        destino = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.icns"
        write_icns(icon, destino)
        print("OK ->", destino)
        return
    icon.save(argv[0])
    if len(argv) > 1:
        write_icns(icon, argv[1])
    print("OK ->", *argv)


if __name__ == "__main__":
    main(sys.argv[1:])
