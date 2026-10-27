"""Writes the sidebar row's two textures: Media/Textures/nav-row.tga, a rounded rectangle filled white, and
Media/Textures/nav-row-edge.tga, its 1-unit inner edge. Both are white, tinted in game per state, 32 x 32 texels
drawn at half scale and nine-sliced 12 texels in. Run from the repository: python Dev/make_nav_row.py"""
import os
from PIL import Image, ImageChops, ImageDraw

SIZE, RADIUS, EDGE = 32, 6, 2  # texels: the texture, its corner radius, the edge's width (1 unit at half scale)
SUPER = 8  # supersampling for smooth corners
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media", "Textures")


def rounded(inset):
    big = Image.new("L", (SIZE * SUPER, SIZE * SUPER), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (inset * SUPER, inset * SUPER, (SIZE - inset) * SUPER - 1, (SIZE - inset) * SUPER - 1),
        radius=(RADIUS - inset) * SUPER, fill=255)

    return big.resize((SIZE, SIZE), Image.LANCZOS)


def save(mask, name):
    image = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    image.putalpha(mask)
    image.save(os.path.join(OUT, name))


fill = rounded(0)
save(fill, "nav-row.tga")
save(ImageChops.subtract(fill, rounded(EDGE)), "nav-row-edge.tga")
print("wrote nav-row.tga and nav-row-edge.tga")
