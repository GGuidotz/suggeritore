#!/usr/bin/env python3
"""Disegna l'icona classica di Suggeritore: un foglio chiaro con tre righe di testo scritte (scure), il cursore e,
dopo il cursore, il seguito suggerito in grigio chiaro. Fondo che sfuma dal bianco al grigio perla come nelle altre app
della famiglia, con la forma arrotondata delle icone di macOS.
    python3 -I tools/render-icon.py        Resources/Icon/AppIcon-1024.png
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 3
N = 1024 * S

BG_TOP = (255, 255, 255)
BG_BOTTOM = (222, 227, 234)
INK = (38, 44, 54)
GHOST = (176, 182, 192)
CURSOR = (46, 124, 246)
EDGE = (0, 0, 0, 40)

def px(v):
    return int(round(v * S))

def gradient(w, h, top, bottom):
    img = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        img.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img.resize((w, h))

def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
    return m

# La forma: il quadrato arrotondato di macOS occupa circa l'80% della tela, il resto è trasparente.
inset = px(100)
side = N - 2 * inset
radius = int(side * 0.2237)
canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((inset, inset + px(14), N - inset, N - inset + px(14)), radius=radius, fill=(0, 0, 0, 70))
shadow = shadow.filter(ImageFilter.GaussianBlur(px(18)))
canvas.alpha_composite(shadow)

tile = gradient(side, side, BG_TOP, BG_BOTTOM).convert("RGBA")
tile.putalpha(rounded_mask(side, side, radius))
canvas.alpha_composite(tile, (inset, inset))

d = ImageDraw.Draw(canvas)
# Bordo sottile per staccare dal fondo chiaro.
d.rounded_rectangle((inset, inset, N - inset, N - inset), radius=radius, outline=EDGE, width=px(2))

# Tre righe di testo: le prime due scritte, la terza scritta a metà e poi suggerita.
x0 = inset + px(150)
x1 = N - inset - px(150)
h = px(58)
r = h // 2
rows = [inset + px(250), inset + px(390), inset + px(530)]
widths = [(0.0, 0.82), (0.0, 0.62), (0.0, 0.36)]
for y, (a, b) in zip(rows, widths):
    d.rounded_rectangle((x0 + (x1 - x0) * a, y, x0 + (x1 - x0) * b, y + h), radius=r, fill=INK)
# Il cursore, subito dopo il testo della terza riga.
cx = x0 + (x1 - x0) * 0.36 + px(26)
d.rounded_rectangle((cx, rows[2] - px(16), cx + px(14), rows[2] + h + px(16)), radius=px(7), fill=CURSOR)
# Il seguito suggerito, in grigio chiaro: due pezzi sulla terza riga e uno sulla quarta.
gx = cx + px(40)
d.rounded_rectangle((gx, rows[2], gx + (x1 - x0) * 0.22, rows[2] + h), radius=r, fill=GHOST)
d.rounded_rectangle((gx + (x1 - x0) * 0.26, rows[2], x1, rows[2] + h), radius=r, fill=GHOST)
y4 = inset + px(670)
d.rounded_rectangle((x0, y4, x0 + (x1 - x0) * 0.48, y4 + h), radius=r, fill=GHOST)

out = canvas.resize((1024, 1024), Image.LANCZOS)
path = os.path.join(ROOT, "Resources", "Icon", "AppIcon-1024.png")
out.save(path)
print(path)
