#!/usr/bin/env python3
"""Turn an image or emote into a Heraldry library icon.

Reads a local file or a URL (GIF, APNG, PNG, AVIF, static WebP; anything ffmpeg
decodes), or a 7TV emote by URL or ID, and writes:

  * the texture: 32-bit uncompressed TGA, power-of-two size, at most 1024x1024
      static square  art fitted into 128x128     static wide  256x128
      animated       frames fitted into 64x64 (square) or 128x64 (wide), packed left to
                     right, top to bottom on one sprite sheet
  * for animated icons, a static first-frame thumbnail for the picker grid
  * the manifest entry for Heraldry/Library.lua, printed, or inserted with --write

Animations with more frames than a 1024x1024 sheet holds drop every other frame (and
halve the frame rate) until they fit. Fully transparent borders are trimmed first.

Needs ffmpeg and ffprobe (--ffmpeg-dir, the FFMPEG_DIR environment variable, or on PATH) and
Python 3 standard library only.

Examples:
  py tools\\emote2lib.py 01F6MZGCNG000255K4X1K7NTHR --key dance --name "Dance" \\
      --author "someone" --license permission --permission "granted in #emotes, 2026-11-08"
  py tools\\emote2lib.py art\\banner.png --key banner --name "Banner" --source "Kenney" \\
      --license CC0-1.0 --url https://kenney.nl --write
"""

import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(REPO, "Heraldry")
LIBRARY_DIR = os.path.join(ADDON, "media", "library")
MANIFEST = os.path.join(ADDON, "Library.lua")
DEV_ADDON = os.path.join(REPO, "HeraldryDev")
DEV_MEDIA_DIR = os.path.join(DEV_ADDON, "media")
DEV_MANIFEST = os.path.join(DEV_ADDON, "Library.lua")
DEV_TOC = os.path.join(DEV_ADDON, "HeraldryDev.toc")
CACHE_DIR = os.path.join(REPO, "tools", ".cache")
MANIFEST_MARKER = "-- @manifest-end"

MAX_SHEET = 1024
STATIC_BOX = {"square": (128, 128), "wide": (256, 128)}
FRAME_BOX = {"square": (64, 64), "wide": (128, 64)}
WIDE_ASPECT = 1.5          # art at least this much wider than tall is "wide"
MAX_FPS = 60
SEVENTV_ID = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$|^[0-9a-f]{24}$", re.IGNORECASE)
SEVENTV_URL = re.compile(r"7tv\.(?:app|io)/(?:v\d+/)?emotes?/([0-9A-Za-z]+)")
KEY_PATTERN = re.compile(r"^[a-z0-9_]+$")
DOWNLOAD_LIMIT = 20 * 1024 * 1024


class ToolError(Exception):
    pass


class DecodeError(ToolError):
    """ffprobe or ffmpeg could not read the input; another variant of it may work."""


# --------------------------------------------------------------------------- input

def tool_path(directory, name):
    exe = name + (".exe" if os.name == "nt" else "")
    if directory:
        path = os.path.join(directory, exe)
        if os.path.isfile(path):
            return path
    found = shutil.which(name)
    if not found:
        raise ToolError(f"{name} not found; pass --ffmpeg-dir")
    return found


def download(url, destination):
    request = urllib.request.Request(url, headers={"User-Agent": "Heraldry-emote2lib"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(DOWNLOAD_LIMIT + 1)
    if len(data) > DOWNLOAD_LIMIT:
        raise ToolError(f"{url} is larger than {DOWNLOAD_LIMIT // (1024 * 1024)} MB")
    with open(destination, "wb") as handle:
        handle.write(data)


def seventv_variants(emote_id):
    """Yields the cached or downloaded files of a 7TV emote, best first. AVIF keeps
    animation and alpha (as a second stream); GIF and PNG are the fallbacks. 7TV's
    animated WebP is not used: ffmpeg can't decode animated WebP."""
    folder = os.path.join(CACHE_DIR, "7tv-" + emote_id)
    os.makedirs(folder, exist_ok=True)
    for variant in ("4x.avif", "4x.gif", "4x.png"):
        path = os.path.join(folder, variant)
        if not os.path.isfile(path):
            try:
                download(f"https://cdn.7tv.app/emote/{emote_id}/{variant}", path)
            except OSError:
                continue
        yield path


def seventv_id(source):
    """The 7TV emote id in a 7TV URL or bare id, or None (also for local files)."""
    if os.path.isfile(source):
        return None
    match = SEVENTV_URL.search(source)
    return match.group(1) if match else (source if SEVENTV_ID.match(source) else None)


def resolve_input(source):
    """Returns (candidate local files, 7TV emote id or None, source URL or None).
    Downloads (into tools\\.cache) happen here, so callers check the request first."""
    if os.path.isfile(source):
        return [source], None, None
    emote_id = seventv_id(source)
    if emote_id:
        return seventv_variants(emote_id), emote_id, f"https://7tv.app/emotes/{emote_id}"
    parsed = urllib.parse.urlparse(source)
    if parsed.scheme in ("http", "https"):
        name = os.path.basename(parsed.path) or "download"
        folder = os.path.join(CACHE_DIR, "url-" + re.sub(r"[^A-Za-z0-9]+", "_", parsed.netloc + parsed.path)[:80])
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            download(source, path)
        return [path], None, source
    raise ToolError(f"{source}: not a file, URL or 7TV emote id")


# --------------------------------------------------------------------------- probing

def probe(ffprobe, path):
    result = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries",
         "stream=index,codec_type,width,height,pix_fmt,nb_frames,avg_frame_rate,r_frame_rate",
         "-of", "json", path],
        capture_output=True, text=True)
    if result.returncode != 0:
        raise DecodeError(f"ffprobe can't read {path}: {result.stderr.strip()}")
    streams = [s for s in json.loads(result.stdout).get("streams", []) if s.get("codec_type") == "video"]
    if not streams:
        raise DecodeError(f"{path} has no image stream")
    return streams


def frame_rate(stream):
    for field in ("avg_frame_rate", "r_frame_rate"):
        text = stream.get(field) or "0/1"
        num, _, den = text.partition("/")
        try:
            rate = float(num) / float(den or 1)
        except (ValueError, ZeroDivisionError):
            continue
        if 0 < rate <= 1000:
            return rate
    return 0


def frame_count(stream):
    try:
        return int(stream.get("nb_frames") or 0)
    except ValueError:
        return 0


def pick_streams(streams):
    """Colour stream and optional separate alpha stream. AVIF stores alpha as a second,
    gray stream: animated files carry a still pair first, then the animated pair."""
    colour = [s for s in streams if s.get("pix_fmt") != "gray"] or streams
    main = max(colour, key=frame_count)
    alpha = None
    for stream in streams:
        if stream is not main and stream.get("pix_fmt") == "gray" and frame_count(stream) == frame_count(main) \
                and stream.get("width") == main.get("width"):
            alpha = stream
    return main, alpha


# --------------------------------------------------------------------------- decoding

def decode(ffmpeg, path, main, alpha, fps, filters):
    """Decodes every frame to RGBA bytes after `filters` (a list of ffmpeg filters)."""
    chain = []
    if fps:
        chain.append(f"fps={fps}")
    chain += filters + ["format=rgba"]
    if alpha is not None:
        graph = f"[0:{main['index']}][0:{alpha['index']}]alphamerge," + ",".join(chain) + "[out]"
    else:
        graph = f"[0:{main['index']}]" + ",".join(chain) + "[out]"
    command = [ffmpeg, "-v", "error", "-i", path, "-filter_complex", graph, "-map", "[out]",
               "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"]
    result = subprocess.run(command, capture_output=True)
    if result.returncode != 0:
        raise DecodeError(f"ffmpeg failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def split_frames(data, width, height):
    size = width * height * 4
    if size == 0 or len(data) % size:
        raise DecodeError("unexpected decoder output size")
    return [data[i:i + size] for i in range(0, len(data), size)]


def opaque_box(frames, width, height):
    """Smallest rectangle holding every non-transparent pixel of every frame."""
    left, top, right, bottom = width, height, -1, -1
    for frame in frames:
        alpha = frame[3::4]
        for y in range(height):
            row = alpha[y * width:(y + 1) * width]
            if any(row):
                top, bottom = min(top, y), max(bottom, y)
                first = next(i for i, a in enumerate(row) if a)
                last = width - 1 - next(i for i, a in enumerate(reversed(row)) if a)
                left, right = min(left, first), max(right, last)
    if right < 0:
        raise ToolError("the image is fully transparent")
    return left, top, right - left + 1, bottom - top + 1


def fit(width, height, box_width, box_height):
    scale = min(box_width / width, box_height / height)
    return max(1, round(width * scale)), max(1, round(height * scale))


def power_of_two(n):
    return 1 << max(0, math.ceil(math.log2(n)))


# --------------------------------------------------------------------------- output

def write_tga(path, width, height, rgba_rows):
    """32-bit uncompressed TGA, top-left origin (descriptor 0x28): the layout the game
    reads for Heraldry's other textures. rgba_rows: list of `height` byte rows."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    body = bytearray()
    for row in rgba_rows:
        pixels = bytearray(row)
        pixels[0::4], pixels[2::4] = row[2::4], row[0::4]   # RGBA -> BGRA
        body += pixels
    data = header + bytes(body)
    # Unchanged files are left alone: the running game may hold them open (Windows then
    # refuses to replace them), and an untouched file needs no game restart.
    if os.path.isfile(path):
        with open(path, "rb") as handle:
            if handle.read() == data:
                return
    # Written beside the target and swapped in, so an interrupted run never leaves half a file.
    partial = path + ".partial"
    with open(partial, "wb") as handle:
        handle.write(data)
    for attempt in range(5):
        try:
            os.replace(partial, path)
            return
        except PermissionError:
            if attempt == 4:
                os.remove(partial)
                raise ToolError(f"can't replace {os.path.basename(path)}: another program (the game?) "
                                "has it open; close it and run again")
            time.sleep(0.5)


def compose(frames, frame_width, frame_height, columns, sheet_width, sheet_height):
    """Packs frames into a transparent sheet; returns its rows."""
    rows = [bytearray(sheet_width * 4) for _ in range(sheet_height)]
    stride = frame_width * 4
    for index, frame in enumerate(frames):
        x0 = (index % columns) * frame_width * 4
        y0 = (index // columns) * frame_height
        for y in range(frame_height):
            rows[y0 + y][x0:x0 + stride] = frame[y * stride:(y + 1) * stride]
    return rows


def plan_animation(count, fps, frame_width, frame_height):
    """Drops every other frame until the sheet fits. Returns kept indices, fps, columns, rows."""
    indices = list(range(count))
    capacity = (MAX_SHEET // frame_width) * (MAX_SHEET // frame_height)
    while len(indices) > capacity:
        indices = indices[::2]
        fps /= 2
    columns = min(len(indices), MAX_SHEET // frame_width)
    rows = math.ceil(len(indices) / columns)
    return indices, fps, columns, rows


# --------------------------------------------------------------------------- manifest

def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_number(value):
    return str(int(value)) if float(value).is_integer() else f"{value:.3f}".rstrip("0")


def manifest_entry(fields):
    lines = ["    {"]
    for key in ("key", "name", "file", "shape"):
        lines.append(f"        {key} = {lua_string(fields[key])},")
    lines.append(f"        width = {fields['width']}, height = {fields['height']}, "
                 f"texWidth = {fields['texWidth']}, texHeight = {fields['texHeight']},")
    if fields.get("tags"):
        lines.append("        tags = { " + ", ".join(lua_string(t) for t in fields["tags"]) + " },")
    anim = fields.get("anim")
    if anim:
        lines.append(f"        anim = {{ cols = {anim['cols']}, rows = {anim['rows']}, "
                     f"frames = {anim['frames']}, fps = {lua_number(anim['fps'])} }},")
        thumb = fields["thumb"]
        lines.append(f"        thumb = {{ file = {lua_string(thumb['file'])}, "
                     f"texWidth = {thumb['texWidth']}, texHeight = {thumb['texHeight']} }},")
    # One field per line: URLs and permission notes would overrun the line length limit.
    lines.append("        credit = {")
    lines += [f"            {k} = {lua_string(v)}," for k, v in fields["credit"].items() if v]
    lines.append("        },")
    lines.append("    },")
    return "\n".join(lines)


DEV_HEADER = """--[[ HeraldryDev\\Library.lua
  Development-only library entries for in-game testing, written by tools\\emote2lib.py
  --dev. This add-on is gitignored and never packaged: the art here is not licensed for
  release. Heraldry reads HeraldryDevLibrary when this add-on is installed. ]]

HeraldryDevLibrary = {
    -- @manifest-end (tools\\emote2lib.py --dev --write inserts new entries above this line)
}
"""

DEV_TOC_TEXT = """## Interface: 16001
## Title: Heraldry (development library)
## Notes: Test icons for Heraldry development. Never distribute.
## OptionalDeps: Heraldry

Library.lua
"""


def ensure_dev_addon():
    os.makedirs(DEV_MEDIA_DIR, exist_ok=True)
    if not os.path.isfile(DEV_TOC):
        with open(DEV_TOC, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(DEV_TOC_TEXT)
    if not os.path.isfile(DEV_MANIFEST):
        with open(DEV_MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(DEV_HEADER)


def insert_entry(path, entry, key):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if re.search(r'key\s*=\s*"' + re.escape(key) + '"', text):
        raise ToolError(f"{os.path.basename(path)} already has an entry with key {key!r}")
    marker = text.find(MANIFEST_MARKER)
    if marker < 0:
        raise ToolError(f"{os.path.basename(path)} has no '{MANIFEST_MARKER}' line")
    line_start = text.rfind("\n", 0, marker) + 1
    text = text[:line_start] + entry + "\n" + text[line_start:]
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


# --------------------------------------------------------------------------- main

def output_paths(args):
    """Texture folder and the manifest an entry would go to."""
    if args.dev:
        return DEV_MEDIA_DIR, DEV_MANIFEST
    return LIBRARY_DIR, MANIFEST


def precheck(args, emote_id):
    """Everything that can be checked without decoding, before anything is written:
    a bad request never touches existing files."""
    if not KEY_PATTERN.match(args.key):
        raise ToolError("--key must be lowercase letters, digits and _")
    if args.license == "permission" and not args.permission:
        raise ToolError("--license permission needs --permission (who granted it, where, when)")
    if not (args.source or emote_id):
        raise ToolError("--source is required (where the art comes from)")
    folder, manifest = output_paths(args)
    if args.write and os.path.isfile(manifest):
        with open(manifest, encoding="utf-8") as handle:
            if re.search(r'key\s*=\s*"' + re.escape(args.key) + '"', handle.read()):
                raise ToolError(f"{os.path.basename(manifest)} already has an entry with key {args.key!r}; "
                                "choose another key (keys never change once shipped)")
    existing = [name for name in (args.key + ".tga", args.key + "_thumb.tga")
                if os.path.isfile(os.path.join(folder, name))]
    if existing and not args.force:
        raise ToolError(f"would overwrite {', '.join(existing)} in {os.path.relpath(folder, REPO)}; "
                        "pass --force to replace them")


def build(args):
    # Check the request before anything is downloaded, decoded or written.
    precheck(args, seventv_id(args.input))
    candidates, emote_id, url = resolve_input(args.input)
    ffmpeg = tool_path(args.ffmpeg_dir, "ffmpeg")
    ffprobe = tool_path(args.ffmpeg_dir, "ffprobe")
    # Try each candidate file until one decodes (a cached 7TV AVIF ffmpeg can't read
    # falls through to the GIF). Any other error stops at once.
    problems = []
    for path in candidates:
        try:
            return convert(args, ffmpeg, ffprobe, path, emote_id, url)
        except DecodeError as error:
            problems.append(f"{os.path.basename(path)}: {error}")
    raise ToolError("; ".join(problems) or f"could not download {args.input}")


def convert(args, ffmpeg, ffprobe, path, emote_id, url):

    main, alpha = pick_streams(probe(ffprobe, path))
    width, height = int(main["width"]), int(main["height"])
    count = frame_count(main)
    rate = args.fps or frame_rate(main)
    animated = not args.static and count > 1 and rate > 0
    fps = min(rate, MAX_FPS) if animated else 0

    # Pass 1, native size: find the art's bounding box (all frames).
    frames = split_frames(decode(ffmpeg, path, main, alpha, fps, []), width, height)
    if not animated:
        frames = frames[:1]
    if args.no_trim:
        box = (0, 0, width, height)
    else:
        box = opaque_box(frames, width, height)
    art_width, art_height = box[2], box[3]
    shape = args.shape if args.shape != "auto" else ("wide" if art_width / art_height >= WIDE_ASPECT else "square")
    target = FRAME_BOX[shape] if animated else STATIC_BOX[shape]
    out_width, out_height = fit(art_width, art_height, *target)

    # Pass 2: crop and scale with ffmpeg's resampler.
    filters = [f"crop={box[2]}:{box[3]}:{box[0]}:{box[1]}", f"scale={out_width}:{out_height}:flags=lanczos"]
    frames = split_frames(decode(ffmpeg, path, main, alpha, fps, filters), out_width, out_height)

    folder, target_manifest = output_paths(args)
    if args.dev:
        ensure_dev_addon()
    os.makedirs(folder, exist_ok=True)
    file_key = args.key
    fields = {
        "key": args.key, "name": args.name or args.key, "file": file_key, "shape": shape,
        "width": out_width, "height": out_height, "tags": args.tags or [],
        "credit": {
            "source": args.source or "7TV", "author": args.author or "",
            "license": args.license, "url": args.url or url or "", "permission": args.permission or "",
        },
    }
    if animated:
        indices, fps, columns, rows = plan_animation(len(frames), fps, out_width, out_height)
        kept = [frames[i] for i in indices]
        sheet_width, sheet_height = power_of_two(columns * out_width), power_of_two(rows * out_height)
        write_tga(os.path.join(folder, args.key + ".tga"), sheet_width, sheet_height,
                  compose(kept, out_width, out_height, columns, sheet_width, sheet_height))
        thumb_width, thumb_height = power_of_two(out_width), power_of_two(out_height)
        write_tga(os.path.join(folder, args.key + "_thumb.tga"), thumb_width, thumb_height,
                  compose(kept[:1], out_width, out_height, 1, thumb_width, thumb_height))
        fields.update(texWidth=sheet_width, texHeight=sheet_height,
                      anim={"cols": columns, "rows": rows, "frames": len(kept), "fps": round(fps, 3)},
                      thumb={"file": file_key + "_thumb", "texWidth": thumb_width, "texHeight": thumb_height})
        dropped = len(frames) - len(kept)
        summary = (f"animated {shape}: {len(kept)} frames of {out_width}x{out_height} at {fps:g} fps"
                   + (f" ({dropped} dropped to fit)" if dropped else "")
                   + f", sheet {sheet_width}x{sheet_height}, {columns}x{rows} grid")
        vram = sheet_width * sheet_height * 4 + thumb_width * thumb_height * 4
    else:
        tex_width, tex_height = power_of_two(out_width), power_of_two(out_height)
        write_tga(os.path.join(folder, args.key + ".tga"), tex_width, tex_height,
                  compose(frames[:1], out_width, out_height, 1, tex_width, tex_height))
        fields.update(texWidth=tex_width, texHeight=tex_height)
        summary = f"static {shape}: {out_width}x{out_height} on {tex_width}x{tex_height}"
        vram = tex_width * tex_height * 4

    entry = manifest_entry(fields)
    print(f"{args.key}: {summary}; {vram / 1048576:.2f} MB of video memory while shown", file=sys.stderr)
    if args.write:
        insert_entry(target_manifest, entry, args.key)
        print(f"added to {os.path.relpath(target_manifest, REPO)}", file=sys.stderr)
    else:
        print(entry)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog=__doc__.split("\n\n", 1)[1])
    parser.add_argument("input", help="image file, image URL, 7TV emote URL or 7TV emote id")
    parser.add_argument("--key", required=True, help="library key: lowercase letters, digits, _ (never change it later)")
    parser.add_argument("--name", help="display name (default: the key)")
    parser.add_argument("--tags", nargs="*", help="search words")
    parser.add_argument("--shape", choices=("auto", "square", "wide"), default="auto")
    parser.add_argument("--static", action="store_true", help="use only the first frame")
    parser.add_argument("--fps", type=float, help="override the source frame rate")
    parser.add_argument("--no-trim", action="store_true", help="keep transparent borders")
    parser.add_argument("--source", help='where the art comes from, e.g. "7TV", "Fluent Emoji" (7TV ids set it)')
    parser.add_argument("--author", help="artist or uploader")
    parser.add_argument("--license", required=True,
                        help='SPDX id (MIT, CC-BY-4.0, CC0-1.0, ...) or "permission"')
    parser.add_argument("--permission", help='with --license permission: who granted it, where and when')
    parser.add_argument("--url", help="page to credit (7TV ids set it)")
    parser.add_argument("--dev", action="store_true",
                        help="development-only: write to the HeraldryDev add-on (gitignored, never packaged)")
    parser.add_argument("--write", action="store_true", help="insert the entry into the manifest")
    parser.add_argument("--force", action="store_true", help="replace existing texture files for this key")
    parser.add_argument("--ffmpeg-dir", default=os.environ.get("FFMPEG_DIR"))
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        build(args)
    except ToolError as error:
        print(f"emote2lib: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
