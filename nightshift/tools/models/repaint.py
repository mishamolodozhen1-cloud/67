"""repaint.py <sf7 dir> — убрать с текстур чужие надписи: табличка «мокрый пол» по-русски, подпись модели на корпусе ПК."""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter
D = sys.argv[1]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# 1) Табличка: стереть WET FLOOR / CAUTION / JANITE чистой жёлтой полосой и написать по-русски
p = os.path.join(D, "m_wetfloor/src/textures/lambert1_baseColor.png")
im = Image.open(p).convert("RGB")
clean = im.crop((610, 282, 930, 340))  # чистый жёлтый участок той же грани
def wipe(box):
    x0, y0, x1, y1 = box
    y = y0
    while y < y1:
        h = min(clean.size[1], y1 - y)
        im.paste(clean.resize((x1 - x0, clean.size[1])).crop((0, 0, x1 - x0, h)), (x0, y))
        y += h
for box in ((600, 380, 935, 452), (630, 722, 912, 790), (712, 792, 840, 838)):
    wipe(box)
def text(center, txt, size, width):
    font = ImageFont.truetype(FONT, size)
    while font.getbbox(txt)[2] > width and size > 10:
        size -= 2
        font = ImageFont.truetype(FONT, size)
    b = font.getbbox(txt)
    w, h = b[2] - b[0], b[3] - b[1]
    tmp = Image.new("RGBA", (w + 8, h + 8), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((4 - b[0], 4 - b[1]), txt, font=font, fill=(18, 18, 18, 255))
    tmp = ImageOps.flip(tmp)  # текстура перевёрнута по вертикали (так её читает модель)
    im.paste(tmp, (int(center[0] - tmp.size[0] / 2), int(center[1] - tmp.size[1] / 2)), tmp)
text((768, 416), "МОКРЫЙ ПОЛ", 58, 330)
text((771, 756), "ОСТОРОЖНО", 58, 300)
im.save(p)

# 2) Корпус ПК: стереть подпись модели (вертикальная надпись справа на передней панели)
p = os.path.join(D, "m_crtpc/src/textures/PC_Front_Cream_baseColor.png")
im = Image.open(p).convert("RGB")
patch = im.crop((548, 600, 646, 660))  # чистая кремовая панель над надписью
y = 664
while y < 958:
    h = min(patch.size[1], 958 - y)
    im.paste(patch.crop((0, 0, patch.size[0], h)), (548, y))
    y += h
im.save(p)
print("ok")
