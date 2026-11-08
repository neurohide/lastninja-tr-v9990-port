#!/usr/bin/env python3
"""Print the centroid of black pixels inside the playfield of openMSX screenshots
(mostly the ninja): rough 'did he move' check without opening images.
Sprites are found as pixels that differ from a sprite-free reference shot.
usage: ninjapos.py ref.png shot.png ..."""
import os, struct, subprocess, sys, tempfile
def load(png):
    bmp = os.path.join(tempfile.gettempdir(), 'np.bmp')
    subprocess.run(['sips', '-s', 'format', 'bmp', png, '--out', bmp], capture_output=True, check=True)
    d = open(bmp, 'rb').read()
    off = struct.unpack_from('<I', d, 10)[0]; w, h = struct.unpack_from('<ii', d, 18); bpp = struct.unpack_from('<H', d, 28)[0]
    row = (w * bpp // 8 + 3) & ~3; bp = bpp // 8
    return d, off, w, h, row, bp
ref = load(sys.argv[1])
for png in sys.argv[2:]:
    d, off, w, h, row, bp = load(png)
    rd = ref[0]
    sx = sy = n = 0
    for y in range(90, 640):                 # playfield in a 1280x960 shot: x 90-905, y 80-650
        yy = (abs(h) - 1 - y) if h > 0 else y
        base = off + yy * row
        for x in range(95, 900, 2):
            p = base + x * bp
            if d[p:p + 3] != rd[p:p + 3]:
                sx += x; sy += y; n += 1
    print('%s: sprite px %d centroid (%d, %d)' % (os.path.basename(png), n, sx // max(n, 1), sy // max(n, 1)))
