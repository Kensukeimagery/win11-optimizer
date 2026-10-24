"""Draws docs/img/main-menu.png from the text of the main menu itself (the echo lines of :MENU in 1_Start_Here ... .bat), in the
look of a Windows console, so that the picture always shows the keys that the menu really has.
Needs Pillow and the font Consolas (part of Windows):   python docs/src/make_menu_image.py
"""
import os
import re

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
BAT = os.path.join(REPO, '1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat')
OUT = os.path.join(REPO, 'docs', 'img', 'main-menu.png')
FONT = r'C:\Windows\Fonts\consola.ttf'

text = open(BAT, 'rb').read().decode('ascii').replace('\r\n', '\n')
start = text.index('\n:MENU\n')
end = text.index('set "CHOICE="', start)
version = open(os.path.join(REPO, 'VERSION')).read().strip()

lines = []
for raw in text[start:end].split('\n'):
    m = re.match(r'^echo(?:\.|\s(.*))?$', raw.rstrip())
    if not m:
        continue                                   # cls, if, set ... lines are not printed
    s = m.group(1) if m.group(1) is not None else ''
    s = s.replace('%TS%', '20261025_100000').replace('%UPDMSG%', '')
    lines.append(s)
# the menu has a few lines that appear only in some cases (laptop, update notice): they are written with "if" and not drawn here
lines.append('')
lines.append('Select an option: ')

font = ImageFont.truetype(FONT, 17)
cw = font.getlength('M')
lh = 18
width = int(max(len(l) for l in lines) * cw) + 24
width = max(width, 960)
height = lh * len(lines) + 20
img = Image.new('RGB', (width, height), (12, 12, 12))
d = ImageDraw.Draw(img)
y = 10
for l in lines:
    d.text((10, y), l, font=font, fill=(204, 204, 204))
    y += lh
img.save(OUT, optimize=True)
print('wrote', OUT, img.size, 'lines', len(lines), 'version', version)
