"""Writes the search field's three textures, all white and tinted in game, drawn at half scale:
Media/Textures/search-field.tga, the field's square shape with softened corners (32 x 32, sliced 8);
Media/Textures/search-field-edge.tga, its 1-unit inner edge (same size and slices);
Media/Textures/search-field-ring.tga, the focus glow (48 x 48, sliced 16): full under the field's edge and fading
outward over 4 units, so it reads as the edge lit rather than a second border.
Run from the repository: python Dev/make_search_field.py"""
import os
import numpy as np
from PIL import Image, ImageChops, ImageDraw

SIZE, RADIUS, EDGE = 32, 3, 2  # texels: the field texture, its corner radius, the edge's width (1 unit)
GLOW = 8  # texels: how far the focus glow reaches outside the field (4 units)
SUPER = 8  # supersampling for smooth corners
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media", "Textures")


def rounded(size, inset, radius):
    big = Image.new("L", (size * SUPER, size * SUPER), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (inset * SUPER, inset * SUPER, (size - inset) * SUPER - 1, (size - inset) * SUPER - 1),
        radius=max(radius, 0) * SUPER, fill=255)

    return big.resize((size, size), Image.LANCZOS)


def glow():
    """The field's signed distance (outside positive), sampled at each texel center, mapped to the glow's alpha."""
    size = SIZE + 2 * GLOW
    centers = (np.arange(size * SUPER) + 0.5) / SUPER - size / 2
    x, y = np.meshgrid(centers, centers)
    half = SIZE / 2 - RADIUS
    qx, qy = np.abs(x) - half, np.abs(y) - half
    distance = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - RADIUS
    outside = np.clip(1 - distance / GLOW, 0, 1) ** 2
    alpha = np.where(distance > 0, outside, np.where(distance > -EDGE, 1.0, 0.0))
    image = Image.fromarray((alpha * 255).astype(np.uint8), "L")

    return image.resize((size, size), Image.LANCZOS)


def save(mask, name):
    image = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    image.putalpha(mask)
    image.save(os.path.join(OUT, name))


field = rounded(SIZE, 0, RADIUS)
save(field, "search-field.tga")
save(ImageChops.subtract(field, rounded(SIZE, EDGE, RADIUS - EDGE)), "search-field-edge.tga")
save(glow(), "search-field-ring.tga")
print("wrote search-field.tga, search-field-edge.tga and search-field-ring.tga")
