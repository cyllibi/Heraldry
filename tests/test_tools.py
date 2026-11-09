"""Tests for the maintainer tools. Run from the repository root:

    py -3 -m unittest discover -s tests -p "test_*.py"
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))

import struct  # noqa: E402

import blp  # noqa: E402
import credits  # noqa: E402
import emote2lib  # noqa: E402
import gameicons2lib  # noqa: E402
import iconnames  # noqa: E402


class SheetMaths(unittest.TestCase):
    def test_example_emote_fits_at_full_speed(self):
        indices, fps, columns, rows = emote2lib.plan_animation(198, 25, 64, 64)
        self.assertEqual((len(indices), fps, columns, rows), (198, 25, 16, 13))

    def test_too_many_frames_halves(self):
        indices, fps, columns, rows = emote2lib.plan_animation(300, 30, 64, 64)
        self.assertEqual(len(indices), 150)
        self.assertEqual(fps, 15)
        self.assertLessEqual(rows * 64, emote2lib.MAX_SHEET)
        self.assertEqual(indices[:3], [0, 2, 4])

    def test_wide_frames(self):
        indices, _, columns, rows = emote2lib.plan_animation(100, 20, 128, 64)
        self.assertEqual(columns, 8)
        self.assertEqual(rows, 13)
        self.assertEqual(len(indices), 100)

    def test_short_animation_single_row(self):
        _, _, columns, rows = emote2lib.plan_animation(5, 10, 64, 64)
        self.assertEqual((columns, rows), (5, 1))

    def test_fit_and_power_of_two(self):
        self.assertEqual(emote2lib.fit(244, 128, 256, 128), (244, 128))
        self.assertEqual(emote2lib.fit(128, 128, 64, 64), (64, 64))
        self.assertEqual(emote2lib.fit(300, 100, 128, 64), (128, 43))
        self.assertEqual([emote2lib.power_of_two(n) for n in (1, 64, 65, 244, 832)], [1, 64, 128, 256, 1024])

    def test_opaque_box(self):
        width, height = 4, 3
        frame = bytearray(width * height * 4)
        frame[(1 * width + 2) * 4 + 3] = 255  # one pixel at x=2, y=1
        self.assertEqual(emote2lib.opaque_box([bytes(frame)], width, height), (2, 1, 1, 1))
        with self.assertRaises(emote2lib.ToolError):
            emote2lib.opaque_box([bytes(width * height * 4)], width, height)


class TgaOutput(unittest.TestCase):
    def test_header_and_channel_order(self):
        rows = emote2lib.compose([bytes([10, 20, 30, 40])], 1, 1, 1, 2, 2)
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "t.tga")
            emote2lib.write_tga(path, 2, 2, rows)
            data = open(path, "rb").read()
        self.assertEqual(data[2], 2, "uncompressed true-colour")
        self.assertEqual(data[16], 32, "32 bits per pixel")
        self.assertEqual(data[17], 0x28, "top-left origin, 8 alpha bits")
        self.assertEqual(data[18:22], bytes([30, 20, 10, 40]), "BGRA")
        self.assertEqual(len(data), 18 + 2 * 2 * 4)


class Manifest(unittest.TestCase):
    ENTRY = {
        "key": "dance", "name": 'Dance "D"', "file": "dance", "shape": "square",
        "width": 64, "height": 64, "texWidth": 1024, "texHeight": 1024, "tags": ["dance"],
        "anim": {"cols": 16, "rows": 13, "frames": 198, "fps": 12.5},
        "thumb": {"file": "dance_thumb", "texWidth": 64, "texHeight": 64},
        "credit": {"source": "7TV", "author": "someone", "license": "permission", "url": "",
                   "permission": "granted in #emotes"},
    }

    def test_entry_round_trips_through_the_credits_parser(self):
        text = "ns.LibraryManifest = {\n" + emote2lib.manifest_entry(self.ENTRY) + "\n    -- end\n}\n"
        entries = credits.Parser(credits.tokenize(text[len("ns.LibraryManifest = "):])).table()
        self.assertEqual(len(entries), 1)
        entry = entries[0]
        self.assertEqual(entry["name"], 'Dance "D"')
        self.assertEqual(entry["anim"]["fps"], 12.5)
        self.assertNotIn("url", entry["credit"], "empty credit fields are left out")
        self.assertIn("Used with permission", credits.render(entries))

    def test_shipped_manifest_parses(self):
        self.assertIsInstance(credits.read_manifest(credits.MANIFEST), list)

    def test_empty_library_credits(self):
        self.assertIn("empty", credits.render([]))


class SafeWrites(unittest.TestCase):
    """A request that can't succeed must not touch existing files."""

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        root = self.folder.name
        self.saved = (emote2lib.LIBRARY_DIR, emote2lib.MANIFEST)
        emote2lib.LIBRARY_DIR = os.path.join(root, "library")
        emote2lib.MANIFEST = os.path.join(root, "Library.lua")
        os.makedirs(emote2lib.LIBRARY_DIR)
        self.texture = os.path.join(emote2lib.LIBRARY_DIR, "dance.tga")
        with open(self.texture, "wb") as handle:
            handle.write(b"original")
        with open(emote2lib.MANIFEST, "w", encoding="utf-8") as handle:
            handle.write('ns.LibraryManifest = {\n    { key = "dance" },\n    -- @manifest-end\n}\n')
        self.source = os.path.join(root, "art.png")
        with open(self.source, "wb") as handle:
            handle.write(b"not decoded in these tests")

    def tearDown(self):
        emote2lib.LIBRARY_DIR, emote2lib.MANIFEST = self.saved
        self.folder.cleanup()

    def run_tool(self, *extra):
        return emote2lib.main([self.source, "--license", "CC0-1.0", "--source", "test", *extra])

    def untouched(self):
        with open(self.texture, "rb") as handle:
            return handle.read() == b"original"

    def test_existing_key_leaves_files_untouched(self):
        self.assertEqual(self.run_tool("--key", "dance", "--write", "--force"), 1)
        self.assertTrue(self.untouched())

    def test_existing_textures_need_force(self):
        self.assertEqual(self.run_tool("--key", "dance"), 1)
        self.assertTrue(self.untouched())

    def test_missing_source_fails_before_writing(self):
        code = emote2lib.main([self.source, "--key", "dance", "--license", "CC0-1.0", "--force"])
        self.assertEqual(code, 1)
        self.assertTrue(self.untouched())

    def test_bad_requests_download_nothing(self):
        downloads = []
        saved = emote2lib.download
        emote2lib.download = lambda url, destination: downloads.append(url)
        try:
            code = emote2lib.main(["https://example.com/art.gif", "--key", "dance", "--license", "CC0-1.0"])
        finally:
            emote2lib.download = saved
        self.assertEqual(code, 1, "no --source")
        self.assertEqual(downloads, [])

    def test_only_decode_failures_try_the_next_variant(self):
        tried = []

        def fake_convert(args, ffmpeg, ffprobe, path, emote_id, url):
            tried.append(path)
            if path == "a.avif":
                raise emote2lib.DecodeError("can't decode")
            if path == "b.gif":
                raise emote2lib.ToolError("fully transparent")
            return "converted"

        saved = emote2lib.resolve_input, emote2lib.convert, emote2lib.tool_path
        emote2lib.resolve_input = lambda source: (["a.avif", "b.gif", "c.png"], None, None)
        emote2lib.convert = fake_convert
        emote2lib.tool_path = lambda directory, name: name
        try:
            args = emote2lib.parse_args(["x", "--key", "new_key", "--license", "CC0-1.0", "--source", "test"])
            with self.assertRaises(emote2lib.ToolError):
                emote2lib.build(args)
        finally:
            emote2lib.resolve_input, emote2lib.convert, emote2lib.tool_path = saved
        self.assertEqual(tried, ["a.avif", "b.gif"], "a non-decoding error stops the loop")


class BlpOutput(unittest.TestCase):
    def test_dxt5_header_and_mips(self):
        size = 16
        data = bytes([200, 200, 200, 255] * size * size)
        encoded = blp.encode_grey_dxt5(size, size, data)
        self.assertEqual(encoded[:4], b"BLP2")
        self.assertEqual(tuple(encoded[8:12]), (2, 8, 7, 1), "DXT, 8-bit alpha, DXT5, mipmaps")
        self.assertEqual(struct.unpack("<II", encoded[12:20]), (16, 16))
        sizes = struct.unpack("<16I", encoded[84:148])
        self.assertEqual(sizes[:5], (256, 64, 16, 16, 16), "16x16, 8x8, 4x4, 2x2 and 1x1 levels")
        self.assertEqual(struct.unpack("<16I", encoded[20:84])[0], blp.HEADER_SIZE)
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "t.blp")
            with open(path, "wb") as handle:
                handle.write(encoded)
            self.assertIsNone(blp.dxt5_problem(path, size))
            self.assertIn("expected", blp.dxt5_problem(path, 32))
            with open(path, "wb") as handle:
                handle.write(encoded[:-10])
            self.assertIn("damaged", blp.dxt5_problem(path, size))

    def test_dxt5_block_keeps_black_white_and_alpha(self):
        # Left half white, right half black; top rows opaque, bottom transparent.
        pixels = []
        for y in range(4):
            for x in range(4):
                v = 255 if x < 2 else 0
                pixels += [v, v, v, 255 if y < 2 else 0]
        block = blp._dxt5_block(bytes(pixels), 4, 4, 0, 0)
        self.assertEqual(block[:2], bytes((255, 0)), "alpha endpoints")
        c0, c1, bits = struct.unpack("<HHI", block[8:16])
        self.assertEqual((c0, c1), (0xFFFF, 0x0000), "pure white and black endpoints, no tint")
        self.assertEqual(bits & 0b11111111, 0b01010000, "row 1: white, white (index 0), black, black (index 1)")

    def test_grey_565_has_equal_channels(self):
        for v in range(256):
            c = blp._rgb565_grey(v)
            red, green = (c >> 11) & 31, (c >> 5) & 63
            self.assertEqual(c & 31, red)
            self.assertLessEqual(abs(red * 255 / 31 - green * 255 / 63), 4.1)


class GameIcons(unittest.TestCase):
    def test_enclosed_areas_fill_and_open_ones_do_not(self):
        # 5x5: an opaque ring around one transparent pixel, plus the transparent border.
        size, rows = 5, ["00000", "0XXX0", "0X.X0", "0XXX0", "00000"]
        alpha = bytes(255 if c == "X" else 0 for row in rows for c in row)
        filled = gameicons2lib.fill_enclosed(alpha, size)
        self.assertEqual(filled[2 * size + 2], 255, "the enclosed hole is filled")
        self.assertEqual(filled[0], 0, "the outside stays transparent")
        rows[1] = "0X.X0"  # open the ring at the top: the hole now reaches the edge
        rows[0] = "00.00"
        alpha = bytes(255 if c == "X" else 0 for row in rows for c in row)
        self.assertEqual(gameicons2lib.fill_enclosed(alpha, size)[2 * size + 2], 0)

    def test_list_reading(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "list.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("# comment\n[shield heraldry]\nlorc/checked-shield\nlorc/crown = Royal crown\n")
            entries = gameicons2lib.read_list(path)
            self.assertEqual([e["key"] for e in entries], ["gi_checked_shield", "gi_crown"])
            self.assertEqual(entries[0]["title"], "Checked shield")
            self.assertEqual(entries[1]["title"], "Royal crown")
            self.assertEqual(entries[0]["tags"], ["shield", "heraldry"])
            with open(path, "a", encoding="utf-8") as handle:
                handle.write("delapouite/crown\n")
            with self.assertRaises(gameicons2lib.ListError):
                gameicons2lib.read_list(path)

    def test_addon_icon_credit_names_the_brand_icon(self):
        self.assertIn(gameicons2lib.BRAND, credits.ADDON_ICON)
        self.assertIn(gameicons2lib.BRAND, credits.render([]))

    def test_every_shipped_texture_exists(self):
        for entry in credits.read_manifest(credits.MANIFEST):
            # The game finds either format from the extensionless path.
            base = os.path.join(emote2lib.LIBRARY_DIR, *entry["file"].split("/"))
            self.assertTrue(os.path.isfile(base + ".blp") or os.path.isfile(base + ".tga"), entry["key"])

    def test_markers_mentioned_in_prose_are_ignored(self):
        text = ('--[[ the block between "' + gameicons2lib.BEGIN + '" and "' + gameicons2lib.END + '" ]]\n'
                "ns.LibraryManifest = {\n    -- @manifest-end\n}\n")
        once = gameicons2lib.replace_block(text, "    " + gameicons2lib.BEGIN + "\n    " + gameicons2lib.END)
        self.assertTrue(once.startswith(text.split("\n")[0]), "the comment is untouched")
        twice = gameicons2lib.replace_block(once, "    " + gameicons2lib.BEGIN + "\n    " + gameicons2lib.END)
        self.assertEqual(once, twice)

    def test_damaged_markers_are_refused(self):
        with self.assertRaises(emote2lib.ToolError):
            gameicons2lib.replace_block("x\n    " + gameicons2lib.END + "\n", "block")

    def test_damaged_markers_leave_the_manifest_intact(self):
        with tempfile.TemporaryDirectory() as folder:
            manifest = os.path.join(folder, "Library.lua")
            original = "ns.LibraryManifest = {\n    " + gameicons2lib.END + "\n}\n"
            with open(manifest, "w", encoding="utf-8") as handle:
                handle.write(original)
            saved = (gameicons2lib.MANIFEST, gameicons2lib.OUT_DIR, gameicons2lib.read_list,
                     gameicons2lib.build_brand, emote2lib.tool_path)
            gameicons2lib.MANIFEST, gameicons2lib.OUT_DIR = manifest, folder
            gameicons2lib.read_list = lambda: []
            gameicons2lib.build_brand = lambda ffmpeg: None
            emote2lib.tool_path = lambda directory, name: name  # no ffmpeg needed: nothing converts
            args = gameicons2lib.argparse.Namespace(ffmpeg_dir=None)
            try:
                with self.assertRaisesRegex(emote2lib.ToolError, "markers are damaged"):
                    gameicons2lib.build(args)
            finally:
                (gameicons2lib.MANIFEST, gameicons2lib.OUT_DIR, gameicons2lib.read_list,
                 gameicons2lib.build_brand, emote2lib.tool_path) = saved
            with open(manifest, encoding="utf-8") as handle:
                self.assertEqual(handle.read(), original)
            self.assertFalse(os.path.exists(manifest + ".partial"))

    def test_categories_and_stop_tags(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "list.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("{Weapons}\n[weapon gui]\nlorc/crown | science-fiction symbol weapon stone-age\n"
                             "{Animals}\nlorc/lion\n")
            crown, lion = gameicons2lib.read_list(path)
        self.assertEqual(crown["category"], "Weapons")
        self.assertEqual(crown["tags"], ["weapon", "science fiction"], "stop tags dropped, hyphens spaced, no repeats")
        self.assertEqual(lion["category"], "Animals")
        self.assertIn('category = "Weapons"', gameicons2lib.entry_text(crown))

    def test_per_icon_tags_and_names(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "list.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("[weapon]\ndelapouite/bow-arrow = Bow and arrow | hunter weapon\n")
            entry = gameicons2lib.read_list(path)[0]
        self.assertEqual(entry["title"], "Bow and arrow")
        self.assertEqual(entry["tags"], ["weapon", "hunter"])

    def test_block_is_replaced_not_duplicated(self):
        text = "ns.LibraryManifest = {\n    -- @manifest-end\n}\n"
        entry = [{"path": "lorc/crown", "author": "lorc", "name": "crown", "key": "gi_crown",
                  "title": "Crown", "tags": []}]
        once = gameicons2lib.replace_block(text, gameicons2lib.manifest_block(entry))
        twice = gameicons2lib.replace_block(once, gameicons2lib.manifest_block(entry))
        self.assertEqual(once, twice)
        entries = credits.Parser(credits.tokenize(once[len("ns.LibraryManifest = "):])).table()
        self.assertEqual(entries[0]["credit"]["license"], "CC-BY-3.0")
        self.assertIn("creativecommons.org/licenses/by/3.0", credits.render(entries))


class IconNames(unittest.TestCase):
    def test_labels_read_as_words(self):
        self.assertEqual(iconnames.label("INV_Misc_Gem_Ruby_01"), "gem ruby")
        self.assertEqual(iconnames.label("Spell_Fire_Fireball02"), "fire fireball")
        self.assertEqual(iconnames.label("INV_Misc_QuestionMark"), "question mark")
        self.assertEqual(iconnames.label("INV_Leather_PvPDruid_O_01Bracer"), "leather pvp druid bracer")
        self.assertEqual(iconnames.label("INV_MISC_6oRing_BlueLv3"), "ring blue lv")
        self.assertEqual(iconnames.label("INV_Misc_Food_94_GaradarSharp "), "food garadar sharp")
        self.assertIsNone(iconnames.label("INV_10_0_01"))
        self.assertEqual(iconnames.label("Ability_Druid_TreeofLife"), "druid tree of life")
        self.assertEqual(iconnames.label("INV_Misc_Hoof"), "hoof")
        self.assertEqual(iconnames.label("Spell_Holy_PrayerOfMendingtga"), "holy prayer of mending")
        self.assertEqual(iconnames.label("Ability_Druid_Mangle.tga"), "druid mangle")
        self.assertEqual(iconnames.label("inv_10xp_worldevent_special"), "worldevent special")

    def test_long_labels_stop_at_a_word(self):
        text = iconnames.label("_".join(["Abcdefgh"] * 3 + ["Ijklmnop", "Qrstuvwx"] * 4))
        self.assertLessEqual(len(text), iconnames.MAX_LABEL)
        self.assertFalse(text.endswith(" "))

    def test_listfile_keeps_only_icons(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "listfile.csv")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("132089;Interface/ICONS/Ability_Ambush.blp\n"
                             "3598764;INTERFACE/ICONS/NewPlayerHelp_Newcomer.m2\n"
                             "123;World/Maps/Azeroth/Azeroth.wdt\n"
                             "5149947;Interface/Icons/inv_10xp_worldevent_special_murlocfigure.blp\n")
            self.assertEqual(iconnames.read_listfile(path),
                             {132089: "ambush", 5149947: "worldevent special murlocfigure"})

    def test_render_and_parse_round_trip(self):
        labels = {132089: "ambush", 132090: "back stab", 134400: "question mark"}
        spells = {132089: [20580, 5215], 200000: [48707]}
        text = iconnames.render(labels, spells, "1.60.1.70862")
        self.assertIn("build 1.60.1.70862's", text)
        self.assertIn("\n132089 ambush|20580|5215\n1 back stab\n2310 question mark\n65600 |48707\n", text)
        self.assertEqual(iconnames.parse(text), (labels, spells, "1.60.1.70862"))

    def test_damaged_data_is_refused(self):
        good = iconnames.render({132089: "ambush"}, {}, "1.60.1")
        for damaged in (good.replace("132089 ambush", "x ambush"), good.replace("132089 ambush", "132089 "),
                        good.replace("132089 ambush", "132089 ambush|Shadowmeld"), good.replace("1.60.1", "?")):
            with self.assertRaises(emote2lib.ToolError):
                iconnames.parse(damaged)
        with self.assertRaises(emote2lib.ToolError):
            iconnames.render({1: "bad ]] label"})

    def test_player_spells_keep_every_ability_and_drop_the_rest(self):
        tables = {
            "SpellName": ("ID,Name_lang", [
                "370,Purge", "12051,Evocation", "12321,Booming Voice", "78,Heroic Strike", "284,Heroic Strike",
                "20580,Shadowmeld", "17253,Bite", "9999,Fireball", "177242,Barnaby", "5,Frost Nova (OLD)",
                "400,Engrave Gloves - Mutilate", "401,Instant Poison"]),
            "SpellMisc": ("SpellID,SpellIconFileDataID,DifficultyID", [
                "12051,1,2", "12051,136075,0", "370,136075,0", "12321,136075,0", "78,132282,0", "284,132282,0",
                "20580,132089,0", "17253,132278,0", "9999,136075,0", "177242,652131,0", "5,777,0",
                "400,133816,0", "401,132273,0"]),
            "SkillLine": ("ID,CategoryID,DisplayName_lang", [
                "8,7,Fire", "26,7,Arms", "375,7,Shamanism", "777,7,Companions", "778,7,Engraving",
                "270,7,Pet - Bat", "126,9,Night Elf Racial", "40,9,Poisons", "185,9,Cooking"]),
            "SkillLineAbility": ("SkillLine,Spell", [
                "8,5", "26,78", "26,284", "375,370", "777,177242", "778,400", "126,20580", "270,17253",
                "40,401", "185,9999"]),
            "Talent": ("ID,SpellRank_0,SpellRank_1", ["1,12051,", "2,12321,0"]),
        }
        self.assertEqual(set(tables), set(iconnames.TABLES))
        with tempfile.TemporaryDirectory() as folder:
            for table, (header, rows) in tables.items():
                with open(os.path.join(folder, table + ".csv"), "w", encoding="utf-8", newline="") as handle:
                    handle.write("\n".join([header] + rows) + "\n")
            spells = iconnames.player_spells(folder)
        self.assertEqual(spells, {
            136075: [370, 12051, 12321],  # Purge (baseline) before the talents; not the NPC Fireball
            132282: [78],                 # Heroic Strike's ranks collapse to the first
            132089: [20580],              # racial
            132278: [17253],              # pet ability
            132273: [401],                # poison
        })                                # no companion, engraving helper, cooking or (OLD) spell

    def test_shipped_names_are_forevers(self):
        with open(iconnames.OUTPUT, encoding="utf-8", newline="") as handle:
            _, spells, build = iconnames.parse(handle.read())
        self.assertTrue(build.startswith("1."), "built from WoW Forever (wowf), not retail")
        shipped = {spell for ids in spells.values() for spell in ids}
        self.assertIn(78, spells.get(132282, []), "Heroic Strike (rank 1) names its icon")
        self.assertTrue({12051, 12321} <= set(spells.get(136075, [])), "Evocation and Booming Voice share an icon")
        self.assertFalse({1219093, 49576} & shipped, "no Death Grip: Forever has no death knights")

if __name__ == "__main__":
    unittest.main()
