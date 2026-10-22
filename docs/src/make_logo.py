"""Draws the win11-optimizer logo (a gauge pushed into the red zone) everywhere it is used:
    docs/img/banner.svg          the README banner
    docs/img/social-preview.png  the GitHub social preview (1280 x 640)
    app/icon.ico                 the icon of Win11 Optimizer.exe
The logo inside the window (app/MainWindow.cs) is the same drawing written out in XAML.
Needs Pillow for the icon and Microsoft Edge for the PNG:   python docs/src/make_logo.py [banner|social|icon]
"""
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

BLUE, CYAN, RED = '#1769ff', '#19d3ff', '#ff7a3d'

# the mark in its own 120 x 120 square: arc centre (60, 66), radius 38, from the lower left over the top to the lower right,
# the last quarter (from the angle of 40 degrees on) in the red zone, a needle pointing into the red zone
CX, CY, R = 60.0, 66.0, 38.0
A_START, A_RED, A_END = 210.0, 40.0, -30.0      # degrees, counter-clockwise from 3 o'clock (maths convention)
NEEDLE_ANGLE, NEEDLE_LEN = 55.0, 30.0


def pt(angle, radius=R):
    a = math.radians(angle)
    return CX + radius * math.cos(a), CY - radius * math.sin(a)


def mark_svg(x, y, size=120):
    """The mark as SVG elements, its top left corner at (x, y)."""
    k = size / 120.0
    sx, sy = pt(A_START)
    rx, ry = pt(A_RED)
    ex, ey = pt(A_END)
    nx, ny = pt(NEEDLE_ANGLE, NEEDLE_LEN)

    def p(a, b):
        return '%.2f %.2f' % (x + a * k, y + b * k)

    return (
        '<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="url(#mk)"/>\n' % (x, y, size, size, 28 * k)
        + '<path d="M%s A%.2f %.2f 0 0 1 %s" fill="none" stroke="#ffffff" stroke-width="%.2f" stroke-linecap="round" stroke-opacity="0.95"/>\n' % (p(sx, sy), R * k, R * k, p(rx, ry), 9 * k)
        + '<path d="M%s A%.2f %.2f 0 0 1 %s" fill="none" stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>\n' % (p(rx, ry), R * k, R * k, p(ex, ey), RED, 9 * k)
        + '<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="#ffffff" stroke-width="%.2f" stroke-linecap="round"/>\n' % (x + CX * k, y + CY * k, x + nx * k, y + ny * k, 7 * k)
        + '<circle cx="%g" cy="%g" r="%.2f" fill="#ffffff"/>\n' % (x + CX * k, y + CY * k, 8 * k)
    )


def page_svg(width, height, dy):
    """The banner layout; the social preview is the same drawing, moved down by dy to sit in the middle of a taller picture."""
    font = "font-family=\"'Segoe UI', 'Helvetica Neue', Arial, sans-serif\""
    pills = [('Restore point first', 203), ('Undo for every change', 249), ('Thai + English', 169), ('Open source, MIT', 203)]
    out = []
    out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="win11-optimizer: safe, reversible tuning for Windows 11 gaming PCs">\n' % (width, height, width, height))
    out.append('<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#080d19"/><stop offset="1" stop-color="#13243f"/></linearGradient>'
               '<linearGradient id="mk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>'
               '<linearGradient id="bar" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>'
               '<pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M40 0H0V40" fill="none" stroke="#ffffff" stroke-opacity="0.045" stroke-width="1"/></pattern></defs>\n' % (BLUE, CYAN, BLUE, CYAN))
    out.append('<rect width="%d" height="%d" fill="url(#bg)"/>\n<rect width="%d" height="%d" fill="url(#grid)"/>\n' % (width, height, width, height))
    out.append('<rect x="0" y="%d" width="%d" height="6" fill="url(#bar)"/>\n' % (height - 6, width))
    out.append(mark_svg(80, 68 + dy))
    out.append('<text x="244" y="%d" %s font-size="74" font-weight="700" fill="#ffffff" letter-spacing="-1.5">win11-optimizer</text>\n' % (128 + dy, font))
    out.append('<text x="246" y="%d" %s font-size="30" fill="#a9bde0">Safe, reversible tuning for Windows 11 gaming PCs</text>\n' % (182 + dy, font))
    x = 246.0
    for text, w in pills:
        out.append('<rect x="%.1f" y="%d" width="%d" height="40" rx="20" fill="#0d1a30" stroke="#2f5da8" stroke-width="1.5"/>\n' % (x, 213 + dy, w))
        out.append('<text x="%.1f" y="%d" %s font-size="21" fill="#d6e6ff">%s</text>\n' % (x + 19, 240 + dy, font, text))
        x += w + 14
    out.append('</svg>\n')
    return ''.join(out)


def write_banner():
    path = os.path.join(REPO, 'docs', 'img', 'banner.svg')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(page_svg(1280, 300, 0))
    print('wrote', path)


def write_social():
    svg = page_svg(1280, 640, 170)
    tmp = tempfile.mkdtemp(prefix='logo_')
    html = os.path.join(tmp, 'social.html')
    with open(html, 'w', encoding='utf-8') as f:
        f.write('<!doctype html><html><body style="margin:0;background:#080d19">' + svg + '</body></html>')
    out = os.path.join(REPO, 'docs', 'img', 'social-preview.png')
    subprocess.run([EDGE, '--headless', '--disable-gpu', '--hide-scrollbars', '--user-data-dir=' + os.path.join(tmp, 'p'),
                    '--window-size=1280,640', '--screenshot=' + out, 'file:///' + html.replace('\\', '/')], check=True, timeout=120)
    print('wrote', out)


def write_icon():
    from PIL import Image, ImageDraw
    S = 2048
    k = S / 120.0
    grad = Image.new('RGB', (S, S))
    px = grad.load()
    c0, c1 = (0x17, 0x69, 0xFF), (0x19, 0xD3, 0xFF)
    for yy in range(S):
        for xx in range(S):
            t = (xx + yy) / (2.0 * (S - 1))
            px[xx, yy] = tuple(int(round(c0[i] + (c1[i] - c0[i]) * t)) for i in range(3))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(28 * k), fill=255)
    mark = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    mark.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(mark, 'RGBA')
    w = int(round(9 * k))
    cx, cy, r = CX * k, CY * k, R * k
    box = (cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2)   # Pillow draws a stroke inside the box: widen it so the stroke sits on the radius

    def cap(angle, colour):
        x, y = pt(angle)
        d.ellipse((x * k - w / 2, y * k - w / 2, x * k + w / 2, y * k + w / 2), fill=colour)

    white, red = (255, 255, 255, 242), (0xFF, 0x7A, 0x3D, 255)
    # Pillow angles run clockwise from 3 o'clock, the maths angles above run counter-clockwise
    d.arc(box, start=-A_START % 360, end=-A_RED % 360, fill=white, width=w)
    cap(A_START, white)
    cap(A_RED, white)
    d.arc(box, start=-A_RED % 360, end=-A_END % 360, fill=red, width=w)
    cap(A_RED, red)
    cap(A_END, red)
    nx, ny = pt(NEEDLE_ANGLE, NEEDLE_LEN)
    nw = int(round(7 * k))
    d.line((cx, cy, nx * k, ny * k), fill=(255, 255, 255, 255), width=nw)
    for ex, ey in ((cx, cy), (nx * k, ny * k)):
        d.ellipse((ex - nw / 2, ey - nw / 2, ex + nw / 2, ey + nw / 2), fill=(255, 255, 255, 255))
    d.ellipse((cx - 8 * k, cy - 8 * k, cx + 8 * k, cy + 8 * k), fill=(255, 255, 255, 255))
    sizes = [16, 24, 32, 48, 64, 128, 256]
    big = mark.resize((256, 256), Image.LANCZOS)
    out = os.path.join(REPO, 'app', 'icon.ico')
    big.save(out, format='ICO', sizes=[(n, n) for n in sizes])
    print('wrote', out)


if __name__ == '__main__':
    what = sys.argv[1:] or ['banner', 'social', 'icon']
    if 'banner' in what:
        write_banner()
    if 'social' in what:
        write_social()
    if 'icon' in what:
        write_icon()
