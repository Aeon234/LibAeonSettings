# Makes the Shadow module's shaped glows: Blizzard's outline of a frame's art with the suite's glow profile laid along
# it, so a portrait frame's ring, a metal frame's chamfered corners and a side tab get the same soft shadow as every
# other frame. Development only (not packaged).
#
#   python3 Dev/make_shadow_shapes.py <wow.export interface folder> <GlowTex.tga>
#
# The outlines come from Blizzard's own art, exported at 2x (two texels per unit):
#   - each piece of the metal frame (framegeneral/uiframemetal*2xc60, Forever's art): only its outer side gets a glow,
#     and the library lays each glow over the frame's own NineSlice piece, so it follows the art wherever it is drawn
#     (Blizzard's gamepad focus outlines were tried first and sat inside Forever's border, Alex, 2026-10-13);
#   - the side tab (common/commonsidetab2xc60 for Forever, commonsidetab2x for Retail): its opaque art is the tab.
# The glow is GlowTex.tga's edge profile (16 texels over 5 units in the square shadow: 1 unit under the frame's edge,
# 4 outside), measured from the outline's edge: 2 texels in, 8 texels out.
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Media", "Textures")
# Each shape is made for every shadow size the module offers (units outside the art): the glow reaches 1 unit under
# the edge and `size` units out, as the square shadow's does (its edge is size + 1 wide). Worked out at the art's 2x,
# then written at half that (one texel per unit): a soft glow needs no more, and it keeps the files small.
SIZES = (2, 4, 6, 8, 10)
INSIDE, OUTSIDE = 2, 8  # texels at 2x of glow under the edge, and outside it (set per size in main)
PAD = 12                # texels at 2x added on each outward side, room for the glow (set per size in main)


def read_png(path):
    data = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(data):
        length, = struct.unpack(">I", data[pos:pos + 4])
        kind, chunk = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, _, color = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length
    raw = zlib.decompress(idat)
    bpp = {6: 4, 2: 3}[color]
    stride = width * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if kind == 1:
                line[x] = (line[x] + a) & 255
            elif kind == 2:
                line[x] = (line[x] + b) & 255
            elif kind == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append([line[x * bpp + 3] if bpp == 4 else 255 for x in range(width)])
        prev = line
    return width, height, rows


def glow_profile(path):
    """GlowTex.tga's left segment, outer (0) to inner (15), averaged down its rows (an RLE TGA, top-left origin)."""
    data = open(path, "rb").read()
    width, height = struct.unpack("<HH", data[12:16])
    pos, pixels = 18 + data[0], []
    while len(pixels) < width * height:
        count = data[pos]
        pos += 1
        if count & 0x80:
            pixels += [data[pos:pos + 4]] * ((count & 0x7F) + 1)
            pos += 4
        else:
            for _ in range((count & 0x7F) + 1):
                pixels.append(data[pos:pos + 4])
                pos += 4
    return [sum(pixels[y * width + x][3] for y in range(1, 15)) / 14 for x in range(16)]


def distance(mask, width, height):
    """Euclidean-ish distance (3-4 chamfer, in texels) from every texel to the nearest texel where mask is true."""
    far = 10 ** 6
    d = [[0 if mask[y][x] else far for x in range(width)] for y in range(height)]
    for y in range(height):
        row, up = d[y], d[y - 1] if y else None
        for x in range(width):
            v = row[x]
            if x:
                v = min(v, row[x - 1] + 3)
            if up:
                v = min(v, up[x] + 3)
                if x:
                    v = min(v, up[x - 1] + 4)
                if x + 1 < width:
                    v = min(v, up[x + 1] + 4)
            row[x] = v
    for y in range(height - 1, -1, -1):
        row, down = d[y], d[y + 1] if y + 1 < height else None
        for x in range(width - 1, -1, -1):
            v = row[x]
            if x + 1 < width:
                v = min(v, row[x + 1] + 3)
            if down:
                v = min(v, down[x] + 3)
                if x + 1 < width:
                    v = min(v, down[x + 1] + 4)
                if x:
                    v = min(v, down[x - 1] + 4)
            row[x] = v
    return [[v / 3 for v in row] for row in d]


def fill_inside(rows, width, height, solid):
    """The texels enclosed by the solid line, flooded from the middle."""
    inside = [[False] * width for _ in range(height)]
    stack = [(width // 2, height // 2)]
    while stack:
        x, y = stack.pop()
        if 0 <= x < width and 0 <= y < height and not inside[y][x] and rows[y][x] < solid:
            inside[y][x] = True
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return inside


def paint(inside, width, height, profile):
    """The glow: GlowTex's profile from INSIDE texels under the edge to OUTSIDE texels beyond it."""
    out_d = distance(inside, width, height)
    in_d = distance([[not v for v in row] for row in inside], width, height)
    span = INSIDE + OUTSIDE
    pixels = []
    for y in range(height):
        row = []
        for x in range(width):
            signed = out_d[y][x] if not inside[y][x] else -in_d[y][x] + 1
            t = (signed + INSIDE) / span  # 0 at the inner end, 1 at the outer end
            if t < 0 or t > 1:
                row.append(0)
                continue
            index = (1 - t) * 15
            low = int(index)
            high = min(15, low + 1)
            row.append(round(profile[low] + (profile[high] - profile[low]) * (index - low)))
        pixels.append(row)
    return pixels


def write_tga(path, width, height, alphas):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    body = b"".join(bytes(v for a in row for v in (255, 255, 255, a)) for row in alphas)
    open(path, "wb").write(header + body)


def write_half(path, width, height, alphas):
    """Writes the glow at half size, each texel the average of four."""
    half = [[(alphas[2 * y][2 * x] + alphas[2 * y][2 * x + 1] + alphas[2 * y + 1][2 * x] + alphas[2 * y + 1][2 * x + 1] + 2) // 4
             for x in range(width // 2)] for y in range(height // 2)]
    write_tga(path, width // 2, height // 2, half)


def outside_glow(rows, width, height, sides, pad, profile, collapse=None):
    """A border piece's glow: the transparent texels reached from its outward sides are outside; the glow is painted
    there (and INSIDE texels into the art next to them), on a texture grown by `pad` on each outward side. An edge
    piece is collapsed across its length first (`collapse` = "rows" or "columns"), its silhouette the union."""
    if collapse == "columns":  # a top or bottom edge: one column, the most opaque texel of each row
        rows = [[max(row)] * 4 for row in rows]
        width = 4
    elif collapse == "rows":  # a left or right edge: one row, the most opaque texel of each column
        rows = [[max(rows[y][x] for y in range(height)) for x in range(width)]] * 4
        height = 4
    left, top = pad if "left" in sides else 0, pad if "top" in sides else 0
    right, bottom = pad if "right" in sides else 0, pad if "bottom" in sides else 0
    w, h = width + left + right, height + top + bottom
    solid = [[False] * w for _ in range(h)]
    for y in range(height):
        for x in range(width):
            solid[y + top][x + left] = rows[y][x] >= 128
    outside = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        if "top" in sides:
            stack.append((x, 0))
        if "bottom" in sides:
            stack.append((x, h - 1))
    for y in range(h):
        if "left" in sides:
            stack.append((0, y))
        if "right" in sides:
            stack.append((w - 1, y))
    while stack:
        x, y = stack.pop()
        if 0 <= x < w and 0 <= y < h and not outside[y][x] and not solid[y][x]:
            outside[y][x] = True
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    out_d = distance([[not v for v in row] for row in outside], w, h)  # outside texels: distance to the art
    in_d = distance(outside, w, h)                                     # art texels: distance to the outside
    span = INSIDE + OUTSIDE
    pixels = []
    for y in range(h):
        row = []
        for x in range(w):
            if outside[y][x]:
                signed = out_d[y][x] - 1
            elif solid[y][x]:
                signed = -in_d[y][x]
            else:
                row.append(0)  # inside the frame
                continue
            t = (signed + INSIDE) / span
            if t < 0 or t > 1:
                row.append(0)
                continue
            index = (1 - t) * 15
            low = int(index)
            high = min(15, low + 1)
            row.append(round(profile[low] + (profile[high] - profile[low]) * (index - low)))
        pixels.append(row)
    return w, h, pixels


METAL = (  # (exported file, glow name, outward sides, collapse)
    ("uiframemetal2xc60/ui-frame-metal-cornertopleft-c60-2x.png", "cornertopleft", ("top", "left"), None),
    ("uiframemetal2xc60/ui-frame-portraitmetal-cornertopleft-c60-2x.png", "portraitcornertopleft", ("top", "left"), None),
    ("uiframemetal2xc60/ui-frame-portraitmetal-cornertopleftsmall-c60-2x.png", "portraitcornertopleftsmall", ("top", "left"), None),
    ("uiframemetal2xc60/ui-frame-metal-cornertopright-c60-2x.png", "cornertopright", ("top", "right"), None),
    ("uiframemetal2xc60/ui-frame-metal-cornertoprightdouble-c60-2x.png", "cornertoprightdouble", ("top", "right"), None),
    ("uiframemetal2xc60/ui-frame-metal-cornerbottomleft-c60-2x.png", "cornerbottomleft", ("bottom", "left"), None),
    ("uiframemetal2xc60/ui-frame-metal-cornerbottomright-c60-2x.png", "cornerbottomright", ("bottom", "right"), None),
    ("uiframemetalhorizontal2xc60/_ui-frame-metal-edgetop-c60-2x.png", "edgetop", ("top",), "columns"),
    ("uiframemetalhorizontal2xc60/_ui-frame-metal-edgebottom-c60-2x.png", "edgebottom", ("bottom",), "columns"),
    ("uiframemetalvertical2xc60/!ui-frame-metal-edgeleft-c60-2x.png", "edgeleft", ("left",), "rows"),
    ("uiframemetalvertical2xc60/!ui-frame-metal-edgeright-c60-2x.png", "edgeright", ("right",), "rows"),
)


def main():
    global INSIDE, OUTSIDE, PAD
    interface, glowtex = sys.argv[1], sys.argv[2]
    profile = glow_profile(glowtex)
    general = os.path.join(interface, "framegeneral")
    pieces = [(read_png(os.path.join(general, source)), name, sides, collapse) for source, name, sides, collapse in METAL]
    tabs = [(read_png(os.path.join(interface, "common", folder, source)), name)
            for folder, source, name in (("commonsidetab2xc60", "common-sidetab-c60-2x.png", "shadow-shape-sidetab"),
                                         ("commonsidetab2x", "common-sidetab-2x.png", "shadow-shape-sidetab-retail"))]
    for size in SIZES:
        INSIDE, OUTSIDE, PAD = 2, 2 * size, 2 * (size + 2)
        for (width, height, rows), name, sides, collapse in pieces:
            w, h, pixels = outside_glow(rows, width, height, sides, PAD, profile, collapse)
            write_half(os.path.join(OUT, "shadow-metal-%s-%d.tga" % (name, size)), w, h, pixels)
        for (width, height, rows), name in tabs:
            padded_w, padded_h = width + 2 * PAD, height + 2 * PAD
            inside = [[False] * padded_w for _ in range(padded_h)]
            for y in range(height):
                for x in range(width):
                    inside[y + PAD][x + PAD] = rows[y][x] >= 128
            write_half(os.path.join(OUT, "%s-%d.tga" % (name, size)), padded_w, padded_h,
                       paint(inside, padded_w, padded_h, profile))
        print("size", size, "done")


main()
