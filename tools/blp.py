"""Write WoW BLP2 textures for greyscale art (Heraldry's library icons: white art, black fill
and outline). Standard library only.

  encode_grey_dxt5   DXT5 with mipmaps: 1 byte per pixel, compressed in video memory too, the
                     layout EllesmereUI's own BLPs use. What the library ships. Checked in WoW
                     Forever on 2026-11-09.
  encode_grey        palettized (a grey ramp, so lossless) with an 8-bit alpha channel and
                     mipmaps, 2 bytes per pixel. Also loads in Forever; kept for reference.

Note: Pillow previews DXT colours without bit replication (white shows as 248,252,248);
graphics cards expand them fully, so that tint is not in the game.
"""

import struct

MAX_MIPS = 16


def _mip_chain(width, height, rgba):
    """Yields (width, height, rgba) from full size down to 1x1, each level a 2x2 box filter
    of the one before, colour weighted by alpha so transparent pixels don't darken edges."""
    yield width, height, rgba
    while width > 1 or height > 1:
        new_width, new_height = max(1, width // 2), max(1, height // 2)
        out = bytearray(new_width * new_height * 4)
        for y in range(new_height):
            for x in range(new_width):
                r = g = b = a = 0
                samples = 0
                for dy in (0, 1):
                    for dx in (0, 1):
                        sx, sy = min(2 * x + dx, width - 1), min(2 * y + dy, height - 1)
                        i = (sy * width + sx) * 4
                        alpha = rgba[i + 3]
                        r += rgba[i] * alpha
                        g += rgba[i + 1] * alpha
                        b += rgba[i + 2] * alpha
                        a += alpha
                        samples += 1
                o = (y * new_width + x) * 4
                if a:
                    out[o], out[o + 1], out[o + 2] = r // a, g // a, b // a
                out[o + 3] = a // samples
        width, height, rgba = new_width, new_height, bytes(out)
        yield width, height, rgba


def encode_grey(width, height, rgba):
    """BLP2 bytes for a greyscale RGBA image (r == g == b), any power-of-two size."""
    palette = b"".join(bytes((v, v, v, 0)) for v in range(256))  # BGRA; palette alpha unused
    levels = []
    for w, h, data in _mip_chain(width, height, rgba):
        indices = bytes(data[0::4])  # grey level = red channel
        alphas = bytes(data[3::4])
        levels.append(indices + alphas)
        if len(levels) == MAX_MIPS:
            break
    header_size = 4 + 4 + 4 + 8 + 16 * 4 * 2 + len(palette)
    offsets, sizes, position = [], [], header_size
    for level in levels:
        offsets.append(position)
        sizes.append(len(level))
        position += len(level)
    offsets += [0] * (MAX_MIPS - len(offsets))
    sizes += [0] * (MAX_MIPS - len(sizes))
    header = b"BLP2" + struct.pack("<I", 1)            # type 1: not JPEG
    header += struct.pack("<BBBB", 1, 8, 8, 1)         # palettized, 8-bit alpha, alpha type 8, has mips
    header += struct.pack("<II", width, height)
    header += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    return header + palette + b"".join(levels)


def _rgb565_grey(v):
    """A grey as RGB565 with all three channels decoding to the same level: green has a
    sixth bit, so it is derived from the 5-bit level rather than from v (no tint)."""
    level = (v * 31 + 127) // 255
    green = (level * 63 + 15) // 31
    return (level << 11) | (green << 5) | level


def _grey_of_565(c):
    return (((c >> 11) & 31) * 255 + 15) // 31  # red channel stands for the grey level


def _dxt5_block(rgba, width, height, bx, by):
    """16 bytes: one 4x4 DXT5 block of a greyscale image (edges clamp)."""
    greys, alphas = [], []
    for y in range(4):
        for x in range(4):
            i = (min(by + y, height - 1) * width + min(bx + x, width - 1)) * 4
            greys.append(rgba[i])
            alphas.append(rgba[i + 3])
    # Alpha: 8-level mode (a0 > a1), indices 0 = a0, 1 = a1, 2..7 between.
    a0, a1 = max(alphas), min(alphas)
    alpha_bits = 0
    if a0 != a1:
        levels = [a0, a1] + [((7 - k) * a0 + k * a1) // 7 for k in range(1, 7)]
        for n, a in enumerate(alphas):
            index = min(range(8), key=lambda k: abs(levels[k] - a))
            alpha_bits |= index << (3 * n)
    # Colour: endpoints from visible pixels only; transparent ones take any index.
    visible = [v for v, a in zip(greys, alphas) if a] or greys
    c0, c1 = _rgb565_grey(max(visible)), _rgb565_grey(min(visible))
    g0, g1 = _grey_of_565(c0), _grey_of_565(c1)
    palette = [g0, g1, (2 * g0 + g1) // 3, (g0 + 2 * g1) // 3]
    colour_bits = 0
    for n, v in enumerate(greys):
        index = min(range(4), key=lambda k: abs(palette[k] - v))
        colour_bits |= index << (2 * n)
    return (bytes((a0, a1)) + alpha_bits.to_bytes(6, "little")
            + struct.pack("<HHI", c0, c1, colour_bits))


def encode_grey_dxt5(width, height, rgba):
    """BLP2 bytes, DXT5 with mipmaps, for a greyscale RGBA image of power-of-two size."""
    levels = []
    for w, h, data in _mip_chain(width, height, rgba):
        blocks = bytearray()
        for by in range(0, max(h, 1), 4):
            for bx in range(0, max(w, 1), 4):
                blocks += _dxt5_block(data, w, h, bx, by)
        levels.append(bytes(blocks))
        if len(levels) == MAX_MIPS:
            break
    palette = bytes(256 * 4)
    header_size = 4 + 4 + 4 + 8 + 16 * 4 * 2 + len(palette)
    offsets, sizes, position = [], [], header_size
    for level in levels:
        offsets.append(position)
        sizes.append(len(level))
        position += len(level)
    offsets += [0] * (MAX_MIPS - len(offsets))
    sizes += [0] * (MAX_MIPS - len(sizes))
    header = b"BLP2" + struct.pack("<I", 1)
    header += struct.pack("<BBBB", 2, 8, 7, 1)         # DXT, 8-bit alpha, alpha type 7 (DXT5), has mips
    header += struct.pack("<II", width, height)
    header += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    return header + palette + b"".join(levels)


HEADER_SIZE = 4 + 4 + 4 + 8 + 16 * 4 * 2 + 256 * 4


def dxt5_problem(path, size):
    """None when `path` is a size x size DXT5 BLP2 with a full mip chain, as written here."""
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return "missing"
    if len(data) < HEADER_SIZE or data[:4] != b"BLP2":
        return "not a BLP2 file"
    compression, _, alpha_type, has_mips = data[8:12]
    width, height = struct.unpack("<II", data[12:20])
    if compression != 2 or alpha_type != 7 or not has_mips:
        return "not DXT5 with mipmaps"
    if (width, height) != (size, size):
        return f"expected {size}x{size}, found {width}x{height}"
    offsets = struct.unpack("<16I", data[20:84])
    sizes = struct.unpack("<16I", data[84:148])
    side, level = size, 0
    while True:
        blocks = max(1, (side + 3) // 4) ** 2
        if sizes[level] != blocks * 16 or offsets[level] + sizes[level] > len(data):
            return f"mip {level} is damaged"
        if side == 1:
            return None
        side, level = side // 2, level + 1
