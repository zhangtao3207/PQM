"""把 dump_fb.tcl 导出的帧缓存还原成 PNG。

官方比特流的帧缓存是每像素 3 字节的 24 位色，stride = 800*3 B。
LVGL 的 disp_flush 按 lv_color32_t 的字节序（B,G,R,A）写前三个字节，所以内存里
三字节的顺序是 B,G,R；默认按此解释。加 --rgb 可按 R,G,B 解释以便对比确认。

用法：python scripts/render_fb.py export/fb_dump.txt export/fb.png [--rgb]
"""

import re
import sys

from PIL import Image

WIDTH = 800
HEIGHT = 480
LINE = re.compile(r"^\s*([0-9A-Fa-f]+):\s+([0-9A-Fa-f]+)\s*$")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rgb_order = "--rgb" in sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    src, dst = args[0], args[1]

    raw = bytearray()
    with open(src, "r", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            m = LINE.match(line)
            if m:
                raw += int(m.group(2), 16).to_bytes(4, "little")
            elif line.strip():
                raw += int(line.strip(), 16).to_bytes(4, "little")

    need = WIDTH * HEIGHT * 3
    print(f"读到 {len(raw)} 字节，需要 {need} 字节")
    if len(raw) < need:
        return 1

    img = Image.new("RGB", (WIDTH, HEIGHT))
    px = img.load()
    i = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            b0, b1, b2 = raw[i], raw[i + 1], raw[i + 2]
            i += 3
            px[x, y] = (b0, b1, b2) if rgb_order else (b2, b1, b0)

    img.save(dst)
    colors = img.getcolors(maxcolors=1 << 22)
    print(f"已写出 {dst}；不同颜色数 = {len(colors) if colors else '>4M'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
