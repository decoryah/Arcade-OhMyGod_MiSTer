#!/usr/bin/env python3
"""Writes the MRAs of the core (Oh My God!, Naname de Magic!) from the set definitions in tools/omg_rom.py (MAME's
ROM_START lists), so the MRAs and the independent reference image cannot disagree.

The image layout is shared by both sets (docs/hardware.md, rtl/omg_mem.sv):

    0x000000  0x080000  68000 program (the file as it is: first byte = low byte of the 68000's first word)
    0x080000  0x080000  character ROM
    0x100000  0x080000  sprite ROM
    0x180000  0x200000  OKI M6295 samples
    0x380000  0x000010  configuration: [0] game (0 Oh My God!, 1 Naname de Magic!)

    python tools/make_mra.py        # writes mra/ (the CRCs come from omg_rom.py; no ROM files are read)
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import omg_rom

TITLES = {
    "ohmygod": ("Oh My God! (Japan)",       "1993", "ohmygod.zip"),
    "naname":  ("Naname de Magic! (Japan)", "1994", "naname.zip"),
}

COIN = "Free Play,2C/3C,4C/5C,5C/6C,4C/3C,6C/3C,2C/3C (alt),4C/1C,3C/1C,2C/1C,1C/6C,1C/5C,1C/4C,1C/3C,1C/2C,1C/1C"

# DIP switches: byte 0 = the high byte of MAME's DSW1, byte 1 = the high byte of DSW2 (a 1 is MAME's default); the low
# bytes of both ports read FF (unused bits, active low).  The service / test switch is DSW2 bit 15 on Oh My God!
# ("Test Mode") and the service button's input line on both.
SW = {
    "ohmygod": f"""    <switches default="FF,FF" base="16">
        <dip bits="0,1,2,3" name="Coin A" ids="{COIN}"/>
        <dip bits="4,5,6,7" name="Coin B" ids="{COIN}"/>
        <dip bits="8,9" name="1P Difficulty" ids="Very Hard,Hard,Easy,Normal"/>
        <dip bits="10,11" name="VS Difficulty" ids="Hard,Normal,Hard Jake,Normal Jake"/>
        <dip bits="12" name="Vs Matches/Credit" ids="1,3"/>
        <dip bits="13" name="Demo Sounds" ids="Off,On"/>
        <dip bits="14" name="Balls Have Eyes" ids="No,Yes"/>
        <dip bits="15" name="Test Mode" ids="On,Off"/>
    </switches>""",
    "naname": f"""    <switches default="FF,FF" base="16">
        <dip bits="0,1,2,3" name="Coin A" ids="{COIN}"/>
        <dip bits="4,5,6,7" name="Coin B" ids="{COIN}"/>
        <dip bits="8,9" name="Difficulty" ids="Hardest,Hard,Easy,Normal"/>
        <dip bits="10,11" name="Time Difficulty" ids="Hardest,Hard,Easy,Normal"/>
        <dip bits="12" name="Vs Matches/Credit" ids="3,1"/>
        <dip bits="13" name="Demo Sounds" ids="Off,On"/>
        <dip bits="14" name="Flip Screen" ids="On,Off"/>
        <dip bits="15" name="Freeze" ids="On,Off"/>
    </switches>""",
}


def mra(setname):
    game, defs = omg_rom.SETS[setname]
    title, year, zipname = TITLES[setname]
    parts = []
    for region, name, crc, size in defs:
        parts.append(f'        <!-- {region}: {size // 1024} KB -->')
        parts.append(f'        <part name="{name}" crc="{crc:08x}"/>')
    cfg = [game] + [0] * 15
    parts.append("        <!-- configuration: game (0 Oh My God!, 1 Naname de Magic!) -->")
    parts.append("        <part>" + " ".join("%02X" % b for b in cfg) + "</part>")
    body = "\n".join(parts)
    return f"""<misterromdescription>
    <rotation>horizontal</rotation>
    <name>{title}</name>
    <setname>{setname}</setname>
    <mameversion>0289</mameversion>
    <year>{year}</year>
    <manufacturer>Atlus</manufacturer>
    <players>2</players>
    <joystick>8</joystick>
    <rbf>ohmygod</rbf>
    <region>Japan</region>
    <platform>Atlus</platform>

    <!--
      Flat image for the OhMyGod core (rtl/omg_mem.sv), the same for both sets:

        0x000000  0x080000  68000 program
        0x080000  0x080000  character ROM, 8x8 4bpp packed
        0x100000  0x080000  sprite ROM, 16x16 4bpp packed
        0x180000  0x200000  OKI M6295 samples
        0x380000  0x000010  configuration
        0x380010            end

      Expects the MAME 0.289 merged romset or the split sets: parts are found by name and CRC,
      whatever zip or folder holds them.

      DIP switches (ioctl index 254): byte 0 is the high byte of MAME's DSW1 port, byte 1 the high byte of DSW2
      (bit 0 is the lowest bit of the byte; a 1 is MAME's default setting).
    -->
{SW[setname]}

    <rom index="0" zip="{zipname}" md5="None">

{body}

    </rom>

    <buttons names="Button,Start,Coin,Service" default="A,Start,Select,R"/>
</misterromdescription>
"""


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mra")
    os.makedirs(out, exist_ok=True)
    for old in os.listdir(out):
        if old.endswith(".mra"):
            os.remove(os.path.join(out, old))
    for setname in omg_rom.SETS:
        path = os.path.join(out, TITLES[setname][0] + ".mra")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(mra(setname))
        print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    sys.exit(main())
