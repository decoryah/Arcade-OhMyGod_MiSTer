#!/usr/bin/env python3
"""MAME's memory regions for the Atlus ohmygod.cpp driver (Oh My God!, Naname de Magic!), built straight from the
ROM_START lists in src/mame/atlus/ohmygod.cpp (MAME 0.289), and packed into the core's flat image.

Independent of the .mra files: the two (this and tools/mra_build.py on the MRA) must agree byte for byte
(tools/omg_rom.py check).

Image layout (docs/hardware.md, rtl/omg_mem.sv); the loader packs the stream little-endian (first byte = low half
of the SDRAM word), so every region is simply the ROM file(s) in order:

    000000  080000  68000 program (ROM_LOAD16_WORD_SWAP: the file's byte pairs are in little-endian order, which is
                    exactly the order the loader needs: the file's first byte is the low byte of the 68000's word 0)
    080000  080000  character ROM (8x8, 4bpp, two pixels to a byte, the left one in the high nibble)
    100000  080000  sprite ROM (16x16, 4bpp, same packing)
    180000  200000  OKI M6295 samples (0..1FFFF fixed, 20000..3FFFF banked in 16 banks of 128 KB)
    380000  000010  configuration: [0] game (0 ohmygod, 1 naname)

    python tools/omg_rom.py build <set> <zip[|zip]> <out.rom>
    python tools/omg_rom.py check <set> <zip[|zip]> <dir with maincpu.bin chars.bin sprites.bin oki.bin>
"""
import sys, os, zipfile, zlib

# set -> (game number, [(region, file, crc, size)])
SETS = {
    "ohmygod": (0, [("maincpu", "omg-p.114", 0x48fa40ca, 0x80000),
                    ("chars",   "omg-b.117", 0x73621fa6, 0x80000),
                    ("sprites", "omg-s.120", 0x6413bd36, 0x80000),
                    ("oki",     "omg-g.107", 0x7405573c, 0x200000)]),
    "naname":  (1, [("maincpu", "036-prg.114", 0x3b7362f7, 0x80000),
                    ("chars",   "036-bg.117",  0xf53e8da5, 0x80000),
                    ("sprites", "036-spr.120", 0xe36d8731, 0x80000),
                    ("oki",     "036-snd.107", 0xa3e0caf4, 0x200000)]),
}
LAYOUT = {"maincpu": 0x000000, "chars": 0x080000, "sprites": 0x100000, "oki": 0x180000, "cfg": 0x380000, "end": 0x380010}


def load_zips(spec):
    files = []
    for path in spec.split("|"):
        with zipfile.ZipFile(path) as z:
            for i in z.infolist():
                if not i.is_dir():
                    files.append((i.filename, z.read(i)))
    return files


def find(files, name, crc):
    for fn, data in files:
        if os.path.basename(fn).lower() == name.lower() and (zlib.crc32(data) & 0xffffffff) == crc:
            return data
    for fn, data in files:                       # renamed copies are known by their CRC
        if (zlib.crc32(data) & 0xffffffff) == crc:
            return data
    raise SystemExit("missing %s crc %08x" % (name, crc))


def regions(files, setname):
    """MAME's regions: maincpu as the 68000 sees it (big-endian words), the others as loaded."""
    out = {}
    for region, name, crc, size in SETS[setname][1]:
        data = find(files, name, crc)
        assert len(data) == size, (name, len(data), size)
        if region == "maincpu":                  # ROM_LOAD16_WORD_SWAP
            sw = bytearray(size)
            sw[0::2] = data[1::2]
            sw[1::2] = data[0::2]
            data = bytes(sw)
        out[region] = data
    return out


def image(files, setname):
    game, defs = SETS[setname]
    img = bytearray(LAYOUT["end"])
    for region, name, crc, size in defs:
        data = find(files, name, crc)
        assert len(data) == size
        img[LAYOUT[region]:LAYOUT[region] + size] = data
    img[LAYOUT["cfg"]] = game
    return bytes(img)


def main(argv):
    if len(argv) < 4 or argv[1] not in ("build", "check"):
        print(__doc__)
        return 2
    cmd, setname, spec = argv[1], argv[2], argv[3]
    files = load_zips(spec)
    if cmd == "build":
        img = image(files, setname)
        with open(argv[4], "wb") as f:
            f.write(img)
        print("wrote %s: %d bytes, crc32 %08x" % (argv[4], len(img), zlib.crc32(img) & 0xffffffff))
        return 0
    # check against a MAME region dump
    reg = regions(files, setname)
    ok = True
    for r, data in reg.items():
        with open(os.path.join(argv[4], r + ".bin"), "rb") as f:
            mame = f.read()
        same = mame == data
        ok &= same
        print("%-8s %s (%d bytes)" % (r, "identical to MAME's region" if same else "DIFFERENT", len(mame)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
