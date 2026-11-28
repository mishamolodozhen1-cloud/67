#!/usr/bin/env python3
"""Симулятор интерфейса DUMMY COMBAT: настоящий клиентский код (Luau) запускается на моках Roblox
(tools/uisim/mock.lua), дерево ScreenGui раскладывается по правилам Roblox и рисуется в PNG — так интерфейс
можно посмотреть на любом экране (телефон, планшет, ПК) без Roblox.

  python3 tools/uisim/uisim.py <сценарий.lua> <выход.png> [ширина высота [inset_top inset_left]]

Раскладка: UDim2 (Scale/Offset), AnchorPoint, UIScale (масштаб вокруг точки привязки, для потомков тоже),
UIPadding, UIListLayout (порядок LayoutOrder, отступы, выравнивание), ScrollingFrame (обрезка, AutomaticCanvasSize),
AutomaticSize, SizeConstraint, UIAspectRatioConstraint, UISizeConstraint, ScreenGui.IgnoreGuiInset / ScreenInsets.
Рисование: фон, скругления (UICorner), рамки (UIStroke), текст (Inter вместо Gotham, выравнивание, перенос,
обрезка «…», TextScaled), прозрачность, UIGradient (прозрачность слева-направо). Поверх — макет кнопок Roblox.
Чего нет: картинки (Image рисуется рамкой), поворот, RichText-теги (снимаются).
"""
import json
import math
import os
import re
import sys

from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "src")
FONT_DIR = "/usr/share/fonts/opentype/inter"
FONTS = {"Black": "Inter-Black.otf", "Bold": "Inter-Bold.otf", "Medium": "Inter-Medium.otf", "Regular": "Inter-Regular.otf",
         "SemiBold": "Inter-SemiBold.otf", "ExtraBold": "Inter-ExtraBold.otf"}


###############################################################################
# Запуск Lua
###############################################################################
def lua_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    mock = open(os.path.join(HERE, "mock.lua"), encoding="utf-8").read()
    M = lua.execute(mock)
    lua.globals().M = M
    return lua, M


def mount(lua):
    """Дерево src → экземпляры (как build.py): папки → Folder (или класс из init.meta.json), *.lua → ModuleScript."""
    make = lua.eval("""function(cls, name, parent, path)
        local o = Instance.new(cls)
        o.Name = name
        o.__path = path
        rawset(o, "__srcpath", path)
        if parent then o.Parent = parent end
        return o
    end""")
    setprop = lua.eval("function(o, k, v) o[k] = v end")

    def walk(dirpath, parent):
        for name in sorted(os.listdir(dirpath)):
            p = os.path.join(dirpath, name)
            if os.path.isdir(p):
                init = None
                for cand in ("init.lua", "init.client.lua", "init.server.lua"):
                    if os.path.exists(os.path.join(p, cand)):
                        init = os.path.join(p, cand)
                cls = "ModuleScript" if init else "Folder"
                meta = os.path.join(p, "init.meta.json")
                props = {}
                if os.path.exists(meta):
                    m = json.load(open(meta, encoding="utf-8"))
                    cls = m.get("className", cls)
                    props = m.get("properties", {})
                inst = make(cls, name, parent, init or "")
                for k, v in props.items():
                    if isinstance(v, list) and len(v) == 2:
                        t, val = v
                        if t == "bool":
                            setprop(inst, k, bool(val))
                        elif t in ("int", "float"):
                            setprop(inst, k, val)
                        elif t == "string":
                            setprop(inst, k, val)
                walk(p, inst)
            elif name.endswith(".lua") and not name.startswith("init."):
                base = name[:-4]
                cls = "ModuleScript"
                if base.endswith(".client"):
                    base, cls = base[:-7], "LocalScript"
                elif base.endswith(".server"):
                    base, cls = base[:-7], "Script"
                make(cls, base, parent, p)

    tops = {}
    for top in sorted(os.listdir(SRC)):
        p = os.path.join(SRC, top)
        if not os.path.isdir(p):
            continue
        svc = lua.eval("function(n) return game:GetService(n) end")(top)
        tops[top] = svc
        walk(p, svc)
    return tops


REQUIRE = r"""
local cache = {}
function require(m)
    if cache[m] ~= nil then return cache[m] end
    local path = rawget(m, "__srcpath")
    assert(path and path ~= "", "require: нет исходника у " .. tostring(m))
    local f = assert(io.open(path, "r"))
    local src = f:read("a")
    f:close()
    local env = setmetatable({ script = m }, { __index = _G })
    local chunk, err = load(src, "@" .. path, "t", env)
    assert(chunk, err)
    local r = chunk()
    cache[m] = r
    return r
end
"""

SERIALIZE = r"""
function(root)
    local function conv(v)
        local t = typeof(v)
        if t == "UDim2" then return { "UDim2", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
        if t == "UDim" then return { "UDim", v.Scale, v.Offset } end
        if t == "Vector2" then return { "Vector2", v.X, v.Y } end
        if t == "Color3" then return { "Color3", v.R, v.G, v.B } end
        if t == "EnumItem" then return { "Enum", v.EnumType, v.Name } end
        if t == "NumberSequence" then
            local k = {}
            for _, kp in ipairs(v.Keypoints) do table.insert(k, { kp.Time, kp.Value }) end
            return { "NumberSequence", k }
        end
        if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then return v end
        return nil
    end
    local function ser(o)
        local props = {}
        for k, v in pairs(o.__props) do
            if k ~= "Parent" then
                local c = conv(v)
                if c ~= nil then props[k] = c end
            end
        end
        local kids = {}
        for _, c in ipairs(o.__children) do table.insert(kids, ser(c)) end
        return { class = o.__class, id = o.__id, props = props, children = kids }
    end
    return ser(root)
end
"""


def to_py(obj):
    """Lua-таблицу → Python (dict/list)."""
    if hasattr(obj, "items"):
        keys = list(obj.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(obj[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in obj.items()}
    return obj


###############################################################################
# Раскладка
###############################################################################
DEF = {
    "Frame": {"Size": ["UDim2", 0, 100, 0, 100], "BackgroundColor3": ["Color3", .64, .64, .65], "BackgroundTransparency": 0},
    "TextLabel": {"Size": ["UDim2", 0, 200, 0, 50], "BackgroundColor3": ["Color3", .64, .64, .65], "BackgroundTransparency": 0, "Text": "Label",
                  "TextSize": 14, "TextColor3": ["Color3", .1, .16, .2]},
    "TextButton": {"Size": ["UDim2", 0, 200, 0, 50], "BackgroundColor3": ["Color3", .64, .64, .65], "BackgroundTransparency": 0, "Text": "Button",
                   "TextSize": 14, "TextColor3": ["Color3", .1, .16, .2]},
    "ImageLabel": {"Size": ["UDim2", 0, 100, 0, 100], "BackgroundColor3": ["Color3", .64, .64, .65], "BackgroundTransparency": 0},
    "ImageButton": {"Size": ["UDim2", 0, 100, 0, 100], "BackgroundColor3": ["Color3", .64, .64, .65], "BackgroundTransparency": 0},
    "ScrollingFrame": {"Size": ["UDim2", 0, 100, 0, 100], "BackgroundColor3": ["Color3", .64, .64, .65], "BackgroundTransparency": 0,
                       "ScrollBarThickness": 12, "CanvasSize": ["UDim2", 0, 0, 2, 0]},
    "TextBox": {"Size": ["UDim2", 0, 200, 0, 50], "BackgroundColor3": ["Color3", 1, 1, 1], "BackgroundTransparency": 0, "Text": "", "TextSize": 14},
}
GUI = set(DEF)


def P(node, key, default=None):
    v = node["props"].get(key)
    if v is None:
        v = DEF.get(node["class"], {}).get(key, default)
    return v


def enum(node, key, default):
    v = node["props"].get(key)
    return v[2] if isinstance(v, list) and v and v[0] == "Enum" else default


def comp(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def udim(u, size, s):
    return u[1] * size + u[2] * s


class Box:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h


def text_width(text, size, font):
    try:
        return font_for(font, size).getlength(text)
    except Exception:
        return len(text) * size * 0.55


_font_cache = {}


def font_for(font_enum, size):
    weight = "Medium"
    if font_enum:
        n = font_enum
        if "Black" in n or "Heavy" in n:
            weight = "Black"
        elif "Bold" in n:
            weight = "Bold"
        elif "Medium" in n or "SemiBold" in n:
            weight = "Medium" if "Medium" in n else "SemiBold"
        else:
            weight = "Regular"
    px = max(1, int(round(size)))
    key = (weight, px)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(os.path.join(FONT_DIR, FONTS[weight]), px)
    return _font_cache[key]


def layout(node, parent_box, scale, out, clip, z_parent, order):
    """Вычислить коробку node (в пикселях экрана) и потомков. out — список отрисовки."""
    cls = node["class"]
    if cls not in GUI:
        return
    if P(node, "Visible", True) is False:
        return
    u = comp(node, "UIScale")
    own = (u["props"].get("Scale", 1) if u else 1)
    pos = P(node, "Position", ["UDim2", 0, 0, 0, 0])
    size = P(node, "Size", ["UDim2", 0, 100, 0, 100])
    anchor = P(node, "AnchorPoint", ["Vector2", 0, 0])
    sc = enum(node, "SizeConstraint", "RelativeXY")
    pw, ph = parent_box.w, parent_box.h
    rw, rh = pw, ph
    if sc == "RelativeYY":
        rw = ph
    elif sc == "RelativeXX":
        rh = pw
    w = (udim(size[0:3], rw, scale) if False else size[1] * rw + size[2] * scale) * own
    h = (size[3] * rh + size[4] * scale) * own
    ar = comp(node, "UIAspectRatioConstraint")
    if ar:
        a = ar["props"].get("AspectRatio", 1)
        dom = enum(ar, "DominantAxis", "Width")
        if dom == "Width":
            h = w / a
        else:
            w = h * a
    szc = comp(node, "UISizeConstraint")
    if szc:
        mn = szc["props"].get("MinSize", ["Vector2", 0, 0])
        mx = szc["props"].get("MaxSize", ["Vector2", 1e9, 1e9])
        w = min(max(w, mn[1] * scale), mx[2 - 1] * scale if mx[1] < 1e8 else w)
        h = min(max(h, mn[2] * scale), mx[2] * scale if mx[2] < 1e8 else h)
    # AutomaticSize у текста — по ширине/высоте строки
    auto0 = enum(node, "AutomaticSize", "None")
    if cls in ("TextLabel", "TextButton") and auto0 != "None":
        fe = P(node, "Font")
        fe = fe[2] if isinstance(fe, list) else "Legacy"
        ts = P(node, "TextSize", 14) * scale * own
        tw = font_for(fe, ts).getlength(strip_rich(str(P(node, "Text", "")))) if ts >= 1 else 0
        padn = comp(node, "UIPadding")
        extra = 0
        if padn:
            extra = udim(padn["props"].get("PaddingLeft", ["UDim", 0, 0]), 0, scale) + udim(padn["props"].get("PaddingRight", ["UDim", 0, 0]), 0, scale)
        if auto0 in ("X", "XY"):
            w = max(w, tw + extra)
        if auto0 in ("Y", "XY"):
            h = max(h, ts * 1.2)
    node["_forced"] = node.get("_forced")
    if node.get("_forced"):
        x, y = node["_forced"]
    else:
        px = parent_box.x + pos[1] * pw + pos[2] * scale
        py = parent_box.y + pos[3] * ph + pos[4] * scale
        x, y = px - anchor[1] * w, py - anchor[2] * h
    s_child = scale * own
    # автоматический размер (по содержимому) — грубо: после раскладки детей
    box = Box(x, y, w, h)
    node["_box"] = box
    node["_clip"] = clip
    z = P(node, "ZIndex", 1)
    entry = {"node": node, "box": box, "clip": clip, "order": order, "z": z_parent + [z, len(out)], "scale": s_child}
    out.append(entry)
    # содержимое
    inner = Box(x, y, w, h)
    pad = comp(node, "UIPadding")
    if pad:
        g = pad["props"]
        pl = udim(g.get("PaddingLeft", ["UDim", 0, 0]), w, s_child)
        pr = udim(g.get("PaddingRight", ["UDim", 0, 0]), w, s_child)
        pt = udim(g.get("PaddingTop", ["UDim", 0, 0]), h, s_child)
        pb = udim(g.get("PaddingBottom", ["UDim", 0, 0]), h, s_child)
        inner = Box(x + pl, y + pt, w - pl - pr, h - pt - pb)
    child_clip = clip
    canvas = inner
    if cls == "ScrollingFrame":
        sb = P(node, "ScrollBarThickness", 12) * s_child
        child_clip = intersect(clip, Box(x, y, w, h))
        canvas = Box(inner.x, inner.y, inner.w - sb, inner.h)
    elif P(node, "ClipsDescendants", False):
        child_clip = intersect(clip, Box(x, y, w, h))
    kids = [c for c in node["children"] if c["class"] in GUI]
    lst = comp(node, "UIListLayout")
    if lst:
        lay_list(node, lst, kids, canvas, s_child, out, child_clip, entry["z"], order)
    else:
        for i, c in enumerate(kids):
            layout(c, canvas, s_child, out, child_clip, entry["z"], order)
    # AutomaticSize
    auto = enum(node, "AutomaticSize", "None")
    if auto != "None":
        ext = extent(node, kids)
        if ext:
            if auto in ("Y", "XY"):
                box.h = max(box.h, ext[3] - y + (h - inner.h - (inner.y - y)))
            if auto in ("X", "XY"):
                box.w = max(box.w, ext[2] - x + (w - inner.w - (inner.x - x)))


def extent(node, kids):
    xs = [c["_box"] for c in kids if "_box" in c and P(c, "Visible", True) is not False]
    if not xs:
        return None
    return (min(b.x for b in xs), min(b.y for b in xs), max(b.x + b.w for b in xs), max(b.y + b.h for b in xs))


def lay_list(node, lst, kids, canvas, s, out, clip, z, order):
    g = lst["props"]
    horiz = (g.get("FillDirection") or ["", "", "Vertical"])[2] == "Horizontal"
    padding = g.get("Padding", ["UDim", 0, 0])
    pad = udim(padding, canvas.w if horiz else canvas.h, s)
    sort = (g.get("SortOrder") or ["", "", "LayoutOrder"])[2]
    visible = [c for c in kids if P(c, "Visible", True) is not False]
    if sort == "LayoutOrder":
        visible.sort(key=lambda c: (c["props"].get("LayoutOrder", 0), c["id"]))
    else:
        visible.sort(key=lambda c: (c["props"].get("Name", ""), c["id"]))
    ha = (g.get("HorizontalAlignment") or ["", "", "Left"])[2]
    va = (g.get("VerticalAlignment") or ["", "", "Top"])[2]
    # сначала размеры
    sizes = []
    for c in visible:
        tmp = []
        c.pop("_forced", None)
        layout(c, canvas, s, tmp, clip, z, order)
        sizes.append((c["_box"].w, c["_box"].h))
    total = sum(sz[0] if horiz else sz[1] for sz in sizes) + pad * max(0, len(sizes) - 1)
    if horiz:
        cur = canvas.x + {"Left": 0, "Center": (canvas.w - total) / 2, "Right": canvas.w - total}.get(ha, 0)
    else:
        cur = canvas.y + {"Top": 0, "Center": (canvas.h - total) / 2, "Bottom": canvas.h - total}.get(va, 0)
    for c, (w, h) in zip(visible, sizes):
        if horiz:
            yy = canvas.y + {"Top": 0, "Center": (canvas.h - h) / 2, "Bottom": canvas.h - h}.get(va, 0)
            c["_forced"] = (cur, yy)
            cur += w + pad
        else:
            xx = canvas.x + {"Left": 0, "Center": (canvas.w - w) / 2, "Right": canvas.w - w}.get(ha, 0)
            c["_forced"] = (xx, cur)
            cur += h + pad
        layout(c, canvas, s, out, clip, z, order)
        c.pop("_forced", None)


def intersect(a, b):
    if a is None:
        return b
    x0, y0 = max(a.x, b.x), max(a.y, b.y)
    x1, y1 = min(a.x + a.w, b.x + b.w), min(a.y + a.h, b.y + b.h)
    return Box(x0, y0, max(0, x1 - x0), max(0, y1 - y0))


###############################################################################
# Рисование
###############################################################################
def rgba(c, transparency):
    a = int(round(255 * (1 - max(0, min(1, transparency)))))
    return (int(c[1] * 255), int(c[2] * 255), int(c[3] * 255), a)


def strip_rich(t):
    return re.sub(r"<[^>]+>", "", t)


def draw_entry(img, e, ss):
    node, b, clip = e["node"], e["box"], e["clip"]
    cls = node["class"]
    s = e["scale"]
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    corner = comp(node, "UICorner")
    radius = 0
    if corner:
        cr = corner["props"].get("CornerRadius", ["UDim", 0, 8])
        radius = cr[1] * min(b.w, b.h) + cr[2] * s
        radius = min(radius, min(b.w, b.h) / 2)
    rect = [b.x * ss, b.y * ss, (b.x + b.w) * ss, (b.y + b.h) * ss]
    if rect[2] - rect[0] < 0.5 or rect[3] - rect[1] < 0.5:
        return
    bt = P(node, "BackgroundTransparency", 0)
    if bt < 1:
        col = rgba(P(node, "BackgroundColor3"), bt)
        grad = comp(node, "UIGradient")
        if grad and grad["props"].get("Transparency"):
            # прозрачность по горизонтали (Rotation 0)
            keys = grad["props"]["Transparency"][1]
            x0, x1 = int(rect[0]), int(rect[2])
            for xi in range(x0, max(x0 + 1, x1)):
                t = (xi - rect[0]) / max(1, rect[2] - rect[0])
                tv = interp(keys, t)
                a = int(col[3] * (1 - tv))
                d.line([(xi, rect[1]), (xi, rect[3])], fill=col[:3] + (a,))
        else:
            d.rounded_rectangle(rect, radius=radius * ss, fill=col)
    for st in node["children"]:
        if st["class"] == "UIStroke" and st["props"].get("Enabled", True) is not False:
            mode = (st["props"].get("ApplyStrokeMode") or ["", "", "Contextual"])[2]
            if cls in ("TextLabel", "TextButton") and mode == "Contextual":
                continue
            th = st["props"].get("Thickness", 1) * s * ss
            col = rgba(st["props"].get("Color", ["Color3", 0, 0, 0]), st["props"].get("Transparency", 0))
            if th > 200:  # огромная обводка — маска вокруг (оптический прицел)
                outer = Image.new("RGBA", img.size, col)
                hole = Image.new("L", img.size, 255)
                ImageDraw.Draw(hole).rounded_rectangle(rect, radius=radius * ss, fill=0)
                layer.paste(outer, (0, 0), hole)
            else:
                d.rounded_rectangle([rect[0] - th, rect[1] - th, rect[2] + th, rect[3] + th], radius=(radius * ss + th), outline=col, width=max(1, int(round(th))))
    if cls in ("TextLabel", "TextButton", "TextBox"):
        text = strip_rich(str(P(node, "Text", "") or ""))
        if text:
            draw_text(d, node, b, s, ss)
    if cls in ("ImageLabel", "ImageButton") and P(node, "Image", ""):
        d.rectangle(rect, outline=(200, 200, 200, 120))
    if clip is not None:
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).rectangle([clip.x * ss, clip.y * ss, (clip.x + clip.w) * ss, (clip.y + clip.h) * ss], fill=255)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), m))
    img.alpha_composite(layer)


def interp(keys, t):
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / max(1e-6, t1 - t0)
            return v0 + (v1 - v0) * k
    return keys[-1][1]


def wrap(text, font, width):
    lines = []
    for para in text.split("\n"):
        words = para.split(" ")
        cur = ""
        for wd in words:
            test = (cur + " " + wd).strip()
            if font.getlength(test) <= width or not cur:
                cur = test
            else:
                lines.append(cur)
                cur = wd
        lines.append(cur)
    return lines


def draw_text(d, node, b, s, ss):
    text = strip_rich(str(P(node, "Text", "")))
    font_enum = (P(node, "Font") or ["", "", "Legacy"])[2] if isinstance(P(node, "Font"), list) else "Legacy"
    size = P(node, "TextSize", 14) * s
    pad = comp(node, "UIPadding")
    x0, y0, w, h = b.x, b.y, b.w, b.h
    if pad:
        g = pad["props"]
        pl = udim(g.get("PaddingLeft", ["UDim", 0, 0]), w, s)
        pr = udim(g.get("PaddingRight", ["UDim", 0, 0]), w, s)
        pt = udim(g.get("PaddingTop", ["UDim", 0, 0]), h, s)
        pb = udim(g.get("PaddingBottom", ["UDim", 0, 0]), h, s)
        x0, y0, w, h = x0 + pl, y0 + pt, w - pl - pr, h - pt - pb
    if P(node, "TextScaled", False):
        size = min(h * 0.9, 100 * s)
        while size > 4 and font_for(font_enum, size * ss).getlength(text) > w * ss:
            size -= 1
    font = font_for(font_enum, size * ss)
    if P(node, "TextWrapped", False) or P(node, "TextScaled", False):
        lines = wrap(text, font, w * ss)
    else:
        lines = text.split("\n")
    if (P(node, "TextTruncate") or ["", "", "None"])[2] == "AtEnd":
        new = []
        for ln in lines:
            if font.getlength(ln) > w * ss:
                while ln and font.getlength(ln + "…") > w * ss:
                    ln = ln[:-1]
                ln = ln + "…"
            new.append(ln)
        lines = new
    lh = size * ss * 1.15
    total = lh * len(lines)
    ya = (P(node, "TextYAlignment") or ["", "", "Center"])[2]
    xa = (P(node, "TextXAlignment") or ["", "", "Center"])[2]
    ty = {"Top": y0 * ss, "Center": y0 * ss + (h * ss - total) / 2, "Bottom": (y0 + h) * ss - total}.get(ya, y0 * ss)
    col = rgba(P(node, "TextColor3", ["Color3", 0, 0, 0]), P(node, "TextTransparency", 0))
    stroke = None
    for st in node["children"]:
        if st["class"] == "UIStroke" and (st["props"].get("ApplyStrokeMode") or ["", "", "Contextual"])[2] == "Contextual":
            stroke = (max(1, int(round(st["props"].get("Thickness", 1) * s * ss))), rgba(st["props"].get("Color", ["Color3", 0, 0, 0]), st["props"].get("Transparency", 0)))
    if P(node, "TextStrokeTransparency", 1) < 1:
        stroke = (max(1, int(ss)), rgba(P(node, "TextStrokeColor3", ["Color3", 0, 0, 0]), P(node, "TextStrokeTransparency", 1)))
    for i, ln in enumerate(lines):
        lw = font.getlength(ln)
        tx = {"Left": x0 * ss, "Center": x0 * ss + (w * ss - lw) / 2, "Right": (x0 + w) * ss - lw}.get(xa, x0 * ss)
        yy = ty + i * lh + (lh - size * ss) / 2 - size * ss * 0.08
        if stroke:
            d.text((tx, yy), ln, font=font, fill=col, stroke_width=stroke[0], stroke_fill=stroke[1])
        else:
            d.text((tx, yy), ln, font=font, fill=col)


def render(tree_roots, W, H, inset_top, inset_left, out_path, ss=2, background=None):
    img = Image.new("RGBA", (W * ss, H * ss), (60, 64, 70, 255))
    if background and os.path.exists(background):
        bg = Image.open(background).convert("RGBA").resize((W * ss, H * ss))
        img.alpha_composite(bg)
    else:
        # нейтральный фон «сцены»: небо, пол
        d = ImageDraw.Draw(img)
        for yy in range(H * ss):
            t = yy / (H * ss)
            c = (int(120 - 60 * t), int(130 - 60 * t), int(140 - 60 * t), 255) if t < 0.55 else (70, 72, 76, 255)
            d.line([(0, yy), (W * ss, yy)], fill=c)
    guis = sorted([g for g in tree_roots if g["class"] == "ScreenGui" and g["props"].get("Enabled", True) is not False],
                  key=lambda g: (g["props"].get("DisplayOrder", 0), g["id"]))
    report = []
    for g in guis:
        ins = g["props"].get("ScreenInsets")
        if ins:
            name = ins[2]
            screen = {"None": Box(0, 0, W, H), "DeviceSafeInsets": Box(inset_left, 0, W - 2 * inset_left, H),
                      "TopbarSafeInsets": Box(0, 0, W, inset_top)}.get(name, Box(inset_left, inset_top, W - 2 * inset_left, H - inset_top))
        elif g["props"].get("IgnoreGuiInset", False):
            screen = Box(0, 0, W, H)
        else:
            screen = Box(0, inset_top, W, H - inset_top)
        out = []
        for c in g["children"]:
            layout(c, screen, 1.0, out, None, [], 0)
        out.sort(key=lambda e: e["z"])
        for e in out:
            draw_entry(img, e, ss)
        report.append((g["props"].get("Name"), len(out)))
    # кнопки Roblox (макет): слева сверху — логотип, меню, чат; справа — «…»
    d = ImageDraw.Draw(img)
    for i, x in enumerate((12, 64, 116)):
        d.rounded_rectangle([x * ss, 12 * ss, (x + 44) * ss, 56 * ss], radius=22 * ss, fill=(18, 18, 22, 200), outline=(255, 255, 255, 60))
    d.rounded_rectangle([(W - 56) * ss, 12 * ss, (W - 12) * ss, 56 * ss], radius=22 * ss, fill=(18, 18, 22, 200), outline=(255, 255, 255, 60))
    img.convert("RGB").save(out_path)
    return report


def overlaps(tree_roots, W, H, inset_top, inset_left):
    """Проверка: видимые тексты/кнопки, залезающие под кнопки Roblox или за край экрана, и тексты, не влезающие в рамку."""
    problems = []
    for g in tree_roots:
        if g["class"] != "ScreenGui":
            continue
        for e in walk_boxes(g):
            node, b = e
            cl = node.get("_clip")
            if cl is not None and (b.y >= cl.y + cl.h - 1 or b.y + b.h <= cl.y + 1):
                continue  # прокручиваемое содержимое за краем списка — это нормально
            if node["class"] in ("TextLabel", "TextButton") and str(P(node, "Text", "")).strip():
                if b.y < 58 and (b.x < 170 or b.x + b.w > W - 70) and b.w > 2:
                    problems.append("под кнопками Roblox: %s «%s»" % (node["props"].get("Name"), P(node, "Text")))
                if b.x < -1 or b.y < -1 or b.x + b.w > W + 1 or b.y + b.h > H + 1:
                    problems.append("за краем экрана: «%s» (%.0f, %.0f, %.0f×%.0f)" % (P(node, "Text"), b.x, b.y, b.w, b.h))
    return problems


def walk_boxes(n):
    for c in n["children"]:
        if "_box" in c:
            yield c, c["_box"]
            yield from walk_boxes(c)


def main():
    scenario, out_path = sys.argv[1], sys.argv[2]
    W = int(sys.argv[3]) if len(sys.argv) > 3 else 844
    H = int(sys.argv[4]) if len(sys.argv) > 4 else 390
    inset_top = int(sys.argv[5]) if len(sys.argv) > 5 else 58
    inset_left = int(sys.argv[6]) if len(sys.argv) > 6 else 0
    lua, M = lua_runtime()
    lua.execute(REQUIRE)
    mount(lua)
    lua.globals().SCREEN = lua.table(W=W, H=H, InsetTop=inset_top, InsetLeft=inset_left, Touch=int(os.environ.get("UISIM_TOUCH", "1")))
    for k, v in os.environ.items():
        if k.startswith("UISIM_SET_"):
            lua.globals()[k[10:]] = v
    setup = open(os.path.join(HERE, "setup.lua"), encoding="utf-8").read()
    lua.execute(setup)
    src = open(scenario, encoding="utf-8").read()
    lua.execute(src)
    errs = M.errors
    if errs:
        for e in to_py(errs) if hasattr(errs, "items") else []:
            print("ОШИБКА LUA:", e)
    ser = lua.eval(SERIALIZE)
    pg = lua.eval("game:GetService('Players').LocalPlayer.PlayerGui")
    tree = to_py(ser(pg))
    roots = tree["children"]
    report = render(roots, W, H, inset_top, inset_left, out_path, background=os.environ.get("UISIM_BG"))
    for p in overlaps(roots, W, H, inset_top, inset_left)[:30]:
        print("ПРОБЛЕМА:", p)
    print(out_path, report)


if __name__ == "__main__":
    main()
