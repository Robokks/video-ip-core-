"""Generate project ICO file: PAL video IP core icon."""

from PIL import Image, ImageDraw
import math, os

# DAC palette: 4-bit R-2R values (0-15) mapped to 8-bit grey
def dac(n):
    v = int(n / 15 * 255)
    return (v, v, v)

SYNC   = dac(0)
BLANK  = dac(4)
WHITE  = dac(15)
GREY1  = dac(5)
GREY2  = dac(7)
GREY3  = dac(9)
GREY4  = dac(11)
GREY5  = dac(13)

# Accent colour for the frame
FRAME_DARK  = (18, 32, 58)
FRAME_MID   = (30, 52, 90)
FRAME_LIGHT = (60, 110, 180)
SYNC_AMBER  = (220, 140, 30)

def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d   = ImageDraw.Draw(img)

    s = size
    pad   = max(1, s // 16)
    r_out = max(2, s // 8)   # corner radius outer bezel

    # ---- outer bezel ----
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r_out,
                         fill=FRAME_DARK, outline=FRAME_LIGHT,
                         width=max(1, s // 32))

    # ---- screen area ----
    sx0 = pad * 2
    sy0 = pad * 2
    sx1 = s - pad * 2 - 1
    sy1 = s - pad * 3 - 1
    sw  = sx1 - sx0
    sh  = sy1 - sy0

    # screen background = blank level
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=max(1, s // 12),
                         fill=BLANK)

    # ---- PAL gradient bars on screen (10-zone staircase + 1 black) ----
    levels = [dac(v) for v in [4, 5, 6, 8, 9, 10, 11, 13, 14, 15, 4]]
    n  = len(levels)
    zw = sw / n
    for i, col in enumerate(levels):
        x0 = sx0 + int(i * zw)
        x1 = sx0 + int((i + 1) * zw)
        d.rectangle([x0, sy0 + 1, x1 - 1, sy1 - 1], fill=col)

    # ---- sync pulse indicator (bottom strip on screen) ----
    strip_h = max(2, sh // 8)
    strip_y = sy1 - strip_h
    # draw a stylised H-sync waveform: blank → sync → blank
    d.rectangle([sx0, strip_y, sx1, sy1 - 1], fill=BLANK)
    sync_w = max(2, int(sw * 0.08))
    back_w = max(2, int(sw * 0.10))
    d.rectangle([sx0, strip_y, sx0 + sync_w, sy1 - 1], fill=SYNC)
    d.rectangle([sx0 + sync_w, strip_y,
                 sx0 + sync_w + back_w, sy1 - 1], fill=GREY2)

    # ---- "PAL" label row at the bottom of the bezel ----
    dot_r = max(1, s // 24)
    cy    = s - pad - dot_r
    # three dots to suggest a signal indicator
    for i, col in enumerate([SYNC_AMBER, FRAME_LIGHT, (80, 200, 80)]):
        cx = s // 2 - dot_r * 3 + i * dot_r * 3
        d.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=col)

    return img


sizes = [16, 24, 32, 48, 64, 128, 256]
frames = [draw_icon(sz) for sz in sizes]

out_path = os.path.join(os.path.dirname(__file__), "..", "docs", "project.ico")
out_path = os.path.normpath(out_path)

# Build ICO file manually: header + directory + PNG payloads
# ICO format: 6-byte header, n*16-byte directory, then image data blobs
import io, struct

png_blobs = []
for img in frames:
    buf = io.BytesIO()
    img.convert("RGBA").save(buf, format="PNG")
    png_blobs.append(buf.getvalue())

n = len(png_blobs)
header_size = 6
dir_size    = n * 16
data_offset = header_size + dir_size

offsets = []
off = data_offset
for blob in png_blobs:
    offsets.append(off)
    off += len(blob)

with open(out_path, "wb") as f:
    # ICONDIR header
    f.write(struct.pack("<HHH", 0, 1, n))
    # ICONDIRENTRY for each image
    for i, (sz, blob) in enumerate(zip(sizes, png_blobs)):
        w = sz if sz < 256 else 0   # 0 means 256 in ICO spec
        h = w
        f.write(struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32,
                             len(blob), offsets[i]))
    # Image data
    for blob in png_blobs:
        f.write(blob)

print(f"Saved: {out_path}  ({os.path.getsize(out_path):,} bytes)  [{n} sizes]")

# 256x256 PNG preview
png_path = out_path.replace(".ico", "_preview.png")
frames[-1].save(png_path)
print(f"Preview: {png_path}")
