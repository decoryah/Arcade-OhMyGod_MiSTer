#!/usr/bin/env python3
"""The screen flip of Naname de Magic! (its Flip Screen DIP): build the test states and check the reference renderer's flip model.

    omg_flipstates.py [on-folder] [off-folder]        (defaults: work/flip/on, work/flip/off)

Both folders are MAME state dumps of the same scripted play (sim/bench/mame/run_flip.sh): `off` with the DIP off, `on` with it on
(tools/lua/dump_state.lua DIPSET).  MAME ignores the hardware's flip (bit 14 of the sprite bank register), so its picture of the `on`
run is broken; but the game's data in that run are the unflipped ones moved by fixed amounts (docs/hardware.md), so the picture it
would show unflipped is MAME's own picture of the `off` run, turned 180 degrees.  This
  * writes work/states/naname_flip/: the `on` states with that turned picture as the expected one (f<N>.rgb), the input of
    sim/bench/corpus_rtl.sh naname_flip (the RTL's picture of every flip-mode state), and
  * renders every `on` state with tools/omg_ref.py (flip model: scroll words -39 / -273, sprite words +57 / -17, picture turned
    180 degrees) and counts the pixels that differ from that expected picture (16 states of 16: none).
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # <root>/mister/tools -> <root>
sys.path.insert(0, HERE)
import omg_ref

W, H = 320, 240


def main(argv):
    src_on = argv[0] if argv else os.path.join(ROOT, 'work', 'flip', 'on')
    src_off = argv[1] if len(argv) > 1 else os.path.join(ROOT, 'work', 'flip', 'off')
    dst = os.path.join(ROOT, 'work', 'states', 'naname_flip')
    os.makedirs(dst, exist_ok=True)
    gfx = omg_ref.load_image(os.path.join(ROOT, 'work', 'naname.rom'))
    names = sorted(n[:-5] for n in os.listdir(src_on) if n.endswith('.regs'))
    bad = 0
    for n in names:
        for ext in ('regs', 'ram300', 'ram700', 'pal', 'pal1'):
            shutil.copyfile(os.path.join(src_on, n + '.' + ext), os.path.join(dst, n + '.' + ext))
        off = open(os.path.join(src_off, n + '.rgb'), 'rb').read()
        rot = b''.join(off[i * 3:i * 3 + 3] for i in range(W * H - 1, -1, -1))        # turned 180 degrees
        open(os.path.join(dst, n + '.rgb'), 'wb').write(rot)
        st = omg_ref.load_state(os.path.join(dst, n))
        out = omg_ref.render(st, gfx, 1, "pal1")
        diff = sum(1 for i in range(0, len(rot), 3) if rot[i:i + 3] != bytes(out[i:i + 3]))
        print("%s: flip %d; reference renderer (flip model) vs the unflipped MAME picture turned 180 degrees: %d of %d pixels differ" % (n, st["flip"], diff, W * H))
        bad += diff != 0
    print("%d states, %d differ" % (len(names), bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
