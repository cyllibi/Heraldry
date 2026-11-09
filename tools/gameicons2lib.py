#!/usr/bin/env python3
"""Build Heraldry's game-icons.net library icons.

Reads tools\\game-icons.txt, downloads each icon (white on transparent, 512x512, cached
in tools\\.cache\\game-icons), and for each one:

  * fills enclosed transparent areas (the checks on a shield, a griffin cut out of one)
    with black, so they read as solid shapes instead of showing the ground through
  * adds a round black outline, thick enough to survive scaling down to a nameplate
  * trims, fits into 128x128 and writes a 32-bit TGA to Heraldry\\media\\library\\game-icons\\

then rewrites the block between "-- @game-icons-begin" and "-- @game-icons-end" in
Heraldry\\Library.lua, and writes the add-on's own icon (Heraldry\\media\\heraldry.tga,
the brand icon below, tinted gold) used by the minimap button and the add-on list. Library
icons are always black and white.

Run tools\\credits.py afterwards to update CREDITS.md.

Needs ffmpeg (--ffmpeg-dir, the FFMPEG_DIR environment variable, or PATH) and the Python standard library.

  py tools\\gameicons2lib.py              build everything (downloads only what's missing)
  py tools\\gameicons2lib.py --check      verify the list and the manifest block agree
"""

import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emote2lib  # noqa: E402  (shared TGA writer, fitting and manifest formatting)

REPO = emote2lib.REPO
LIST = os.path.join(REPO, "tools", "game-icons.txt")
MANIFEST = emote2lib.MANIFEST
OUT_DIR = os.path.join(emote2lib.LIBRARY_DIR, "game-icons")
BRAND_TGA = os.path.join(REPO, "Heraldry", "media", "heraldry.tga")
CACHE = os.path.join(emote2lib.CACHE_DIR, "game-icons")
BEGIN, END = "-- @game-icons-begin", "-- @game-icons-end"

SOURCE_SIZE = 512
OUTLINE = 48            # outline radius at 512 px: about 10 px at 128, 1.5 px on a 20 px nameplate icon
BOX = 128
BRAND = "lorc/checked-shield"
BRAND_COLOUR = "e8c252"  # gold for the add-on's own icon only; library icons stay black and white
BRAND_SIZE = 64
LICENSE = "CC-BY-3.0"
CHANGES = "black fill and outline added, resized"
ICON_URL = "https://game-icons.net/icons/{colour}/transparent/1x1/{path}.png"
PAGE_URL = "https://game-icons.net/1x1/{path}.html"
LINE = re.compile(r"^([a-z0-9-]+)/([a-z0-9-]+)\s*(?:=\s*([^|]+?))?\s*(?:\|\s*(.+))?$")


class ListError(Exception):
    pass


def read_list(path=LIST):
    """Returns entries: dicts with path, author, name, key, title and tags."""
    entries, keys, tags = [], {}, []
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                tags = line[1:-1].split()
                continue
            match = LINE.match(line)
            if not match:
                raise ListError(f"game-icons.txt line {number}: can't read {line!r}")
            author, name, title, extra = match.groups()
            key = "gi_" + name.replace("-", "_")
            if key in keys:
                raise ListError(f"game-icons.txt line {number}: key {key} already used on line {keys[key]}")
            keys[key] = number
            entries.append({
                "path": f"{author}/{name}", "author": author, "name": name, "key": key,
                "title": title.strip() if title else name.replace("-", " ").capitalize(),
                "tags": list(tags) + [t for t in (extra or "").split() if t not in tags],
            })
    return entries


def author_name(folder):
    return " ".join(part.capitalize() for part in folder.split("-"))


def fetch(path):
    """The cached white-on-transparent PNG (the site serves only white or black)."""
    target = os.path.join(CACHE, path + ".png")
    if not os.path.isfile(target):
        os.makedirs(os.path.dirname(target), exist_ok=True)
        emote2lib.download(ICON_URL.format(colour="ffffff", path=path), target)
        # An error page or a cut-off download must not stay in the cache as an icon.
        with open(target, "rb") as handle:
            signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            os.remove(target)
            raise emote2lib.ToolError(f"{path}: the download is not a PNG")
    return target


# --------------------------------------------------------------------------- image work

def run(ffmpeg, args, data=None):
    result = subprocess.run([ffmpeg, "-v", "error", "-y"] + args, input=data, capture_output=True)
    if result.returncode != 0:
        raise emote2lib.ToolError(result.stderr.decode(errors="replace").strip())
    return result.stdout


def fill_enclosed(alpha, size):
    """Alpha with every transparent area that doesn't reach the image edge made opaque."""
    open_ = bytearray(1 if a < 128 else 0 for a in alpha)
    seen = bytearray(size * size)
    queue = deque()
    for i in range(size):
        for index in (i, (size - 1) * size + i, i * size, i * size + size - 1):
            if open_[index] and not seen[index]:
                seen[index] = 1
                queue.append(index)
    while queue:
        index = queue.popleft()
        x, y = index % size, index // size
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < size and 0 <= ny < size:
                n = ny * size + nx
                if open_[n] and not seen[n]:
                    seen[n] = 1
                    queue.append(n)
    filled = bytearray(alpha)
    for index in range(size * size):
        if open_[index] and not seen[index]:
            filled[index] = 255
    return bytes(filled)


def outlined_rgba(ffmpeg, source, colour="ffffff"):
    """The icon on a transparent square with holes filled and a black outline, as RGBA bytes.
    `colour` tints the white art; only the add-on's own icon uses anything but white."""
    pad = OUTLINE + 2
    size = SOURCE_SIZE + 2 * pad
    r, g, b = (int(colour[i:i + 2], 16) / 255 for i in (0, 2, 4))
    rgba = run(ffmpeg, ["-i", source, "-vf",
                        f"scale={SOURCE_SIZE}:{SOURCE_SIZE},format=rgba,"
                        f"colorchannelmixer=rr={r:.4f}:gg={g:.4f}:bb={b:.4f},"
                        f"pad={size}:{size}:{pad}:{pad}:color=0x00000000",
                        "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"])
    backing = fill_enclosed(rgba[3::4], size)
    # Black backing: the filled shape grown by a disc of radius OUTLINE; the icon goes on top.
    disc = 2 * OUTLINE + 1
    graph = (f"[0:v]format=gray[back];"
             f"color=black:s={disc}x{disc},format=gray,"
             f"geq=lum='if(lte(hypot(X-{OUTLINE},Y-{OUTLINE}),{OUTLINE}+0.5),255,0)'[disc];"
             f"[back][disc]morpho=mode=dilate:structure=first[grown];"
             f"color=black:s={size}x{size},format=rgba[black];"
             f"[black][grown]alphamerge[outline];"
             f"[outline][1:v]overlay=format=auto,format=rgba")
    # ffmpeg reads the backing on stdin and the icon from a file: it can't take two pipes.
    with tempfile.NamedTemporaryFile("wb", suffix=".rgba", dir=CACHE, delete=False) as handle:
        handle.write(rgba)
        raw = handle.name
    try:
        return size, run(ffmpeg, ["-f", "rawvideo", "-pix_fmt", "gray", "-s", f"{size}x{size}", "-i", "pipe:0",
                                  "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{size}x{size}", "-i", raw,
                                  "-filter_complex", graph, "-frames:v", "1",
                                  "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"], data=backing)
    finally:
        os.remove(raw)


def fitted(ffmpeg, rgba, size, box):
    """Trims transparent borders and scales into box x box. Returns width, height, rows."""
    left, top, width, height = emote2lib.opaque_box([rgba], size, size)
    out_width, out_height = emote2lib.fit(width, height, box, box)
    data = run(ffmpeg, ["-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{size}x{size}", "-i", "pipe:0",
                        "-vf", f"crop={width}:{height}:{left}:{top},scale={out_width}:{out_height}:flags=lanczos",
                        "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"], data=rgba)
    texture = emote2lib.power_of_two(max(out_width, out_height))
    frame = emote2lib.split_frames(data, out_width, out_height)[0]
    # Centre the art on the square texture so every icon sits the same way in a cell.
    x0, y0 = (texture - out_width) // 2, (texture - out_height) // 2
    rows = [bytearray(texture * 4) for _ in range(texture)]
    for y in range(out_height):
        rows[y0 + y][x0 * 4:(x0 + out_width) * 4] = frame[y * out_width * 4:(y + 1) * out_width * 4]
    return texture, rows


# --------------------------------------------------------------------------- manifest

def entry_text(item):
    return emote2lib.manifest_entry({
        "key": item["key"], "name": item["title"], "file": "game-icons/" + item["key"], "shape": "square",
        "width": BOX, "height": BOX, "texWidth": BOX, "texHeight": BOX, "tags": item["tags"],
        "credit": {"source": "game-icons.net", "author": author_name(item["author"]), "license": LICENSE,
                   "url": PAGE_URL.format(path=item["path"]), "changes": CHANGES},
    })


def manifest_block(entries):
    lines = [f"    {BEGIN} (written by tools\\gameicons2lib.py from tools\\game-icons.txt; don't edit)"]
    lines += [entry_text(item) for item in entries]
    lines.append(f"    {END}")
    return "\n".join(lines)


def marker_at_line_start(text, marker):
    """Offset of `marker` where it starts a line (after indentation), or -1. Mentions of the
    markers elsewhere (in a comment's prose) don't count."""
    match = re.search(r"^[ \t]*" + re.escape(marker), text, re.MULTILINE)
    return match.start() + len(match.group()) - len(marker) if match else -1


def replace_block(text, block):
    start, end = marker_at_line_start(text, BEGIN), marker_at_line_start(text, END)
    if (start < 0) != (end < 0) or end < start:
        raise emote2lib.ToolError("Library.lua's game-icons markers are damaged: fix or remove both "
                                  f"'{BEGIN}' and '{END}'")
    if start < 0:
        marker = text.find(emote2lib.MANIFEST_MARKER)
        if marker < 0:
            raise emote2lib.ToolError("Library.lua has neither a game-icons block nor the manifest end marker")
        line_start = text.rfind("\n", 0, marker) + 1
        return text[:line_start] + block + "\n" + text[line_start:]
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", end)
    return text[:line_start] + block + (text[line_end:] if line_end >= 0 else "\n")


# --------------------------------------------------------------------------- main

def stray_textures(entries):
    """Textures in the output folder that no listed icon uses (they would still ship)."""
    wanted = {item["key"] + ".tga" for item in entries}
    return sorted(name for name in os.listdir(OUT_DIR) if name not in wanted)


def build(args):
    # Each texture is replaced atomically and the manifest is written last, so a run that
    # stops halfway leaves the previous manifest pointing at textures that still exist.
    entries = read_list()
    ffmpeg = emote2lib.tool_path(args.ffmpeg_dir, "ffmpeg")
    os.makedirs(OUT_DIR, exist_ok=True)
    for number, item in enumerate(entries, 1):
        size, rgba = outlined_rgba(ffmpeg, fetch(item["path"]))
        texture, rows = fitted(ffmpeg, rgba, size, BOX)
        emote2lib.write_tga(os.path.join(OUT_DIR, item["key"] + ".tga"), texture, texture, rows)
        print(f"[{number}/{len(entries)}] {item['key']}", file=sys.stderr)

    build_brand(ffmpeg)

    with open(MANIFEST, encoding="utf-8") as handle:
        text = handle.read()
    # Build the new text first (replace_block refuses damaged markers), then swap it in.
    updated = replace_block(text, manifest_block(entries))
    partial = MANIFEST + ".partial"
    with open(partial, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(updated)
    os.replace(partial, MANIFEST)
    for name in stray_textures(entries):
        try:
            os.remove(os.path.join(OUT_DIR, name))
        except PermissionError:
            print(f"couldn't delete {name} (the game may have it open); run again after closing it",
                  file=sys.stderr)
    print(f"{len(entries)} icons; run tools\\credits.py next", file=sys.stderr)


def build_brand(ffmpeg):
    size, rgba = outlined_rgba(ffmpeg, fetch(BRAND), BRAND_COLOUR)
    texture, rows = fitted(ffmpeg, rgba, size, BRAND_SIZE)
    emote2lib.write_tga(BRAND_TGA, texture, texture, rows)


def check():
    entries = read_list()
    with open(MANIFEST, encoding="utf-8") as handle:
        text = handle.read()
    if manifest_block(entries) not in text:
        raise emote2lib.ToolError("Library.lua's game-icons block doesn't match tools\\game-icons.txt; "
                                  "run tools\\gameicons2lib.py")
    problems = []
    for item in entries:
        problem = tga_problem(os.path.join(OUT_DIR, item["key"] + ".tga"), BOX)
        if problem:
            problems.append(f"{item['key']}: {problem}")
    problem = tga_problem(BRAND_TGA, BRAND_SIZE)
    if problem:
        problems.append(f"heraldry.tga: {problem}")
    problems += [f"{name}: not in the list (would ship anyway)" for name in stray_textures(entries)]
    if problems:
        raise emote2lib.ToolError("; ".join(problems))


def tga_problem(path, size):
    """None when `path` is the 32-bit, top-left origin TGA of size x size the game expects."""
    try:
        with open(path, "rb") as handle:
            header = handle.read(18)
            length = os.fstat(handle.fileno()).st_size
    except OSError:
        return "missing"
    if len(header) < 18 or header[2] != 2 or header[16] != 32 or header[17] != 0x28:
        return "not a 32-bit uncompressed top-left TGA"
    width, height = struct.unpack("<HH", header[12:16])
    if (width, height) != (size, size) or length != 18 + size * size * 4:
        return f"expected {size}x{size}, found {width}x{height}"
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="verify the manifest block and textures")
    parser.add_argument("--ffmpeg-dir", default=os.environ.get("FFMPEG_DIR"))
    args = parser.parse_args(argv)
    try:
        check() if args.check else build(args)
    except (emote2lib.ToolError, ListError, OSError) as error:
        print(f"gameicons2lib: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
