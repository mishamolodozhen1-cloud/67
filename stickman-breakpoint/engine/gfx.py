# -*- coding: utf-8 -*-
"""Мини-прослойка со skia-подобным API поверх cairo (pixman быстрее на CPU).
Покрывает ровно то, что использует движок: пути, заливки/обводки, градиенты,
текст, клипы, слои с прозрачностью, записи (Picture)."""
import math
import cairo
import numpy as np

# ─────────────────────────── цвет ───────────────────────────
class Color4f:
    __slots__ = ('fR', 'fG', 'fB', 'fA')
    def __init__(self, r, g, b, a=1.0):
        self.fR, self.fG, self.fB, self.fA = float(r), float(g), float(b), float(a)
    def toColor(self):
        return self

ColorBLACK = Color4f(0, 0, 0, 1)
ColorTRANSPARENT = Color4f(0, 0, 0, 0)
ColorWHITE = Color4f(1, 1, 1, 1)

def _col(c):
    if isinstance(c, Color4f):
        return c
    if isinstance(c, int):
        a = ((c >> 24) & 255) / 255.0; r = ((c >> 16) & 255) / 255.0; g = ((c >> 8) & 255) / 255.0; b = (c & 255) / 255.0
        return Color4f(r, g, b, a)
    return Color4f(*c)

# ─────────────────────────── геометрия ───────────────────────────
class Rect:
    __slots__ = ('l', 't', 'r', 'b')
    def __init__(self, l, t, r, b):
        self.l, self.t, self.r, self.b = l, t, r, b
    @staticmethod
    def MakeXYWH(x, y, w, h):
        return Rect(x, y, x + w, y + h)

class RRect:
    __slots__ = ('rect', 'rx', 'ry')
    def __init__(self, rect, rx, ry):
        self.rect, self.rx, self.ry = rect, rx, ry
    @staticmethod
    def MakeRectXY(rect, rx, ry):
        return RRect(rect, rx, ry)

class Point:
    __slots__ = ('x', 'y')
    def __init__(self, x, y):
        self.x, self.y = x, y

def _ellipse_arc(ctx, cx, cy, rx, ry, a0, a1, neg=False):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(max(rx, 1e-9), max(ry, 1e-9))
    if neg:
        ctx.arc_negative(0, 0, 1, a0, a1)
    else:
        ctx.arc(0, 0, 1, a0, a1)
    ctx.restore()

def _rrect_path(ctx, rect, rx, ry):
    l, t, r, b = rect.l, rect.t, rect.r, rect.b
    rx = min(rx, (r - l) / 2); ry = min(ry, (b - t) / 2)
    ctx.new_sub_path()
    _ellipse_arc(ctx, r - rx, t + ry, rx, ry, -math.pi / 2, 0)
    _ellipse_arc(ctx, r - rx, b - ry, rx, ry, 0, math.pi / 2)
    _ellipse_arc(ctx, l + rx, b - ry, rx, ry, math.pi / 2, math.pi)
    _ellipse_arc(ctx, l + rx, t + ry, rx, ry, math.pi, 1.5 * math.pi)
    ctx.close_path()

class Path:
    def __init__(self):
        self.ops = []
        self._cur = (0.0, 0.0)
        self._start = (0.0, 0.0)
    def moveTo(self, x, y):
        self.ops.append(('M', x, y)); self._cur = self._start = (x, y); return self
    def lineTo(self, x, y):
        self.ops.append(('L', x, y)); self._cur = (x, y); return self
    def quadTo(self, cx, cy, x, y):
        x0, y0 = self._cur
        c1 = (x0 + 2.0 / 3.0 * (cx - x0), y0 + 2.0 / 3.0 * (cy - y0))
        c2 = (x + 2.0 / 3.0 * (cx - x), y + 2.0 / 3.0 * (cy - y))
        self.ops.append(('C', c1[0], c1[1], c2[0], c2[1], x, y)); self._cur = (x, y); return self
    def cubicTo(self, x1, y1, x2, y2, x, y):
        self.ops.append(('C', x1, y1, x2, y2, x, y)); self._cur = (x, y); return self
    def close(self):
        self.ops.append(('Z',)); self._cur = self._start; return self
    def addArc(self, rect, start, sweep):
        self.ops.append(('A', rect, start, sweep, True)); return self
    def arcTo(self, rect, start, sweep, forceMoveTo=False):
        self.ops.append(('A', rect, start, sweep, forceMoveTo)); return self
    def addCircle(self, x, y, r):
        self.ops.append(('O', x, y, r)); return self
    def replay(self, ctx):
        for op in self.ops:
            k = op[0]
            if k == 'M':
                ctx.move_to(op[1], op[2])
            elif k == 'L':
                ctx.line_to(op[1], op[2])
            elif k == 'C':
                ctx.curve_to(*op[1:])
            elif k == 'Z':
                ctx.close_path()
            elif k == 'A':
                rect, start, sweep, force = op[1], op[2], op[3], op[4]
                cx, cy = (rect.l + rect.r) / 2, (rect.t + rect.b) / 2
                rx, ry = (rect.r - rect.l) / 2, (rect.b - rect.t) / 2
                a0 = math.radians(start); a1 = math.radians(start + sweep)
                if force:
                    ctx.new_sub_path()
                _ellipse_arc(ctx, cx, cy, rx, ry, a0, a1, neg=sweep < 0)
            elif k == 'O':
                ctx.new_sub_path(); ctx.arc(op[1], op[2], op[3], 0, 2 * math.pi)

# ─────────────────────────── краска ───────────────────────────
class _Blur:
    def __init__(self, sigma):
        self.sigma = sigma

class MaskFilter:
    @staticmethod
    def MakeBlur(style, sigma):
        return _Blur(sigma)

kNormal_BlurStyle = 0

class _Grad:
    def __init__(self, kind, args, colors, pos):
        self.kind, self.args, self.colors, self.pos = kind, args, [_col(c) for c in colors], pos
    def pattern(self):
        if self.kind == 'lin':
            p0, p1 = self.args
            pat = cairo.LinearGradient(p0.x, p0.y, p1.x, p1.y)
        else:
            c, r = self.args
            pat = cairo.RadialGradient(c.x, c.y, 0, c.x, c.y, max(r, 1e-6))
        n = len(self.colors)
        pos = self.pos or [i / (n - 1) if n > 1 else 0 for i in range(n)]
        for p, c in zip(pos, self.colors):
            pat.add_color_stop_rgba(p, c.fR, c.fG, c.fB, c.fA)
        return pat

class GradientShader:
    @staticmethod
    def MakeLinear(pts, colors, pos=None, *a, **k):
        return _Grad('lin', pts, colors, pos)
    @staticmethod
    def MakeRadial(center, r, colors, pos=None, *a, **k):
        return _Grad('rad', (center, r), colors, pos)

class _Dash:
    def __init__(self, iv, phase):
        self.iv, self.phase = iv, phase

class DashPathEffect:
    @staticmethod
    def Make(iv, phase):
        return _Dash(iv, phase)

class BlendMode:
    kSrcOver = cairo.OPERATOR_OVER
    kOverlay = cairo.OPERATOR_OVERLAY
    kMultiply = cairo.OPERATOR_MULTIPLY
    kScreen = cairo.OPERATOR_SCREEN
    kSoftLight = cairo.OPERATOR_SOFT_LIGHT
    kColor = cairo.OPERATOR_HSL_COLOR
    kPlus = cairo.OPERATOR_ADD
    kLighten = cairo.OPERATOR_LIGHTEN
    kDarken = cairo.OPERATOR_DARKEN
    kColorDodge = cairo.OPERATOR_COLOR_DODGE
    kDifference = cairo.OPERATOR_DIFFERENCE

class Paint:
    kFill_Style = 0
    kStroke_Style = 1
    kRound_Cap = cairo.LINE_CAP_ROUND
    kButt_Cap = cairo.LINE_CAP_BUTT
    kSquare_Cap = cairo.LINE_CAP_SQUARE
    kRound_Join = cairo.LINE_JOIN_ROUND
    kMiter_Join = cairo.LINE_JOIN_MITER
    __slots__ = ('color', 'style', 'width', 'cap', 'join', 'blur', 'shader', 'dash', 'op', 'alpha', 'imgfilter', 'colorfilter')
    def __init__(self, AntiAlias=True, Color4f=None, Color=None, Style=0, StrokeWidth=1.0, StrokeJoin=None, StrokeCap=None):
        self.color = _col(Color4f) if Color4f is not None else (_col(Color) if Color is not None else ColorBLACK)
        self.style = Style
        self.width = StrokeWidth
        self.cap = StrokeCap if StrokeCap is not None else cairo.LINE_CAP_BUTT
        self.join = StrokeJoin if StrokeJoin is not None else cairo.LINE_JOIN_MITER
        self.blur = None; self.shader = None; self.dash = None; self.op = None; self.alpha = 1.0
        self.imgfilter = None; self.colorfilter = None
    def setColor4f(self, c): self.color = _col(c)
    def setColor(self, c): self.color = _col(c)
    def setStyle(self, s): self.style = s
    def setStrokeWidth(self, w): self.width = w
    def setStrokeCap(self, c): self.cap = c
    def setStrokeJoin(self, j): self.join = j
    def setMaskFilter(self, m): self.blur = m
    def setShader(self, s): self.shader = s
    def setPathEffect(self, d): self.dash = d
    def setBlendMode(self, m): self.op = m
    def setAlphaf(self, a): self.alpha = a
    def setImageFilter(self, f): self.imgfilter = f
    def setColorFilter(self, f): self.colorfilter = f

class ImageFilters:
    @staticmethod
    def Blur(sx, sy, *a):
        return ('blur', sx)

class ColorFilters:
    @staticmethod
    def Matrix(m):
        return ('matrix', m)

# ─────────────────────────── шрифты ───────────────────────────
FONTMAP = {
    'RussoOne': ('Russo One', 0, 0), 'RubikMonoOne': ('Rubik Mono One', 0, 0),
    'Unbounded-ExtraBold': ('Unbounded', 0, 1), 'Unbounded-Medium': ('Unbounded', 0, 0),
    'Neucha': ('Neucha', 0, 0), 'Oswald-Bold': ('Oswald', 0, 1),
    'Inter-Bold': ('Inter', 0, 1), 'Inter-SemiBold': ('Inter', 0, 1), 'Inter-ExtraBold': ('Inter', 0, 1),
    'Inter-SemiBoldItalic': ('Inter', 1, 1), 'Inter-Medium': ('Inter', 0, 0),
}

class Typeface:
    def __init__(self, name):
        self.name = name
        fam, it, bd = FONTMAP.get(name, (name, 0, 0))
        self.face = cairo.ToyFontFace(fam, cairo.FONT_SLANT_ITALIC if it else cairo.FONT_SLANT_NORMAL,
                                      cairo.FONT_WEIGHT_BOLD if bd else cairo.FONT_WEIGHT_NORMAL)
    @staticmethod
    def MakeFromName(name):
        return Typeface(name)

_measure_surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 4, 4)
_measure_ctx = cairo.Context(_measure_surf)

class Font:
    class Edging:
        kAntiAlias = 1
    def __init__(self, tf, size):
        self.tf, self.size = tf, size
        self._sf = None
    def setEdging(self, e): pass
    def setSubpixel(self, s): pass
    def scaled(self):
        if self._sf is None:
            fo = cairo.FontOptions()
            fo.set_hint_style(cairo.HINT_STYLE_NONE); fo.set_hint_metrics(cairo.HINT_METRICS_OFF)
            fo.set_antialias(cairo.ANTIALIAS_GRAY)
            self._sf = (fo,)
        return self._sf
    def apply(self, ctx):
        ctx.set_font_face(self.tf.face)
        ctx.set_font_size(self.size)
        ctx.set_font_options(self.scaled()[0])
    def measureText(self, txt):
        # метрики масштабируем от 100 px, чтобы мелкие размеры не теряли точность
        ctx = _measure_ctx
        ctx.set_font_face(self.tf.face)
        ctx.set_font_size(100.0)
        ctx.set_font_options(self.scaled()[0])
        return ctx.text_extents(txt).x_advance * self.size / 100.0

# ─────────────────────────── холст ───────────────────────────
class Canvas:
    def __init__(self, ctx, surface=None):
        self.ctx = ctx
        self.surface = surface
        self._layers = []

    # трансформации
    def save(self): self.ctx.save(); self._layers.append(None)
    def restore(self):
        kind = self._layers.pop() if self._layers else None
        if kind is None:
            self.ctx.restore()
        elif kind[0] == 'alpha':
            self.ctx.pop_group_to_source()
            self.ctx.paint_with_alpha(kind[1])
            self.ctx.restore()
        elif kind[0] == 'paint':
            paint = kind[1]
            pat = self.ctx.pop_group()
            self.ctx.set_source(pat)
            if paint.op is not None:
                self.ctx.set_operator(paint.op)
            self.ctx.paint_with_alpha(paint.alpha)
            self.ctx.restore()
    def translate(self, x, y): self.ctx.translate(x, y)
    def scale(self, sx, sy=None): self.ctx.scale(sx, sx if sy is None else sy)
    def rotate(self, deg): self.ctx.rotate(math.radians(deg))
    def saveLayer(self, bounds=None, paint=None):
        self.ctx.save()
        self.ctx.push_group()
        self._layers.append(('paint', paint or Paint()))
    def saveLayerAlpha(self, bounds, alpha):
        self.ctx.save()
        self.ctx.push_group()
        self._layers.append(('alpha', alpha / 255.0))
    def clipRect(self, r, *a):
        self.ctx.rectangle(r.l, r.t, r.r - r.l, r.b - r.t); self.ctx.clip()
    def clipRRect(self, rr, *a):
        self.ctx.new_path(); _rrect_path(self.ctx, rr.rect, rr.rx, rr.ry); self.ctx.clip()
    def clipPath(self, path, *a):
        self.ctx.new_path(); path.replay(self.ctx); self.ctx.clip()
    def clear(self, c=None):
        c = _col(c) if c is not None else ColorTRANSPARENT
        ctx = self.ctx
        ctx.save(); ctx.identity_matrix(); ctx.reset_clip()
        ctx.set_operator(cairo.OPERATOR_SOURCE)
        ctx.set_source_rgba(c.fR, c.fG, c.fB, c.fA); ctx.paint()
        ctx.restore()

    # рендер
    def _source(self, paint):
        ctx = self.ctx
        if paint.shader is not None:
            ctx.set_source(paint.shader.pattern())
        else:
            c = paint.color
            ctx.set_source_rgba(c.fR, c.fG, c.fB, c.fA * paint.alpha)

    def _finish(self, paint, fill_rule=None):
        ctx = self.ctx
        if paint.op is not None:
            ctx.set_operator(paint.op)
        self._source(paint)
        if paint.style == Paint.kStroke_Style:
            ctx.set_line_width(paint.width)
            ctx.set_line_cap(paint.cap)
            ctx.set_line_join(paint.join)
            if paint.dash is not None:
                ctx.set_dash(paint.dash.iv, paint.dash.phase)
            ctx.stroke()
            if paint.dash is not None:
                ctx.set_dash([])
        else:
            ctx.fill()
        if paint.op is not None:
            ctx.set_operator(cairo.OPERATOR_OVER)

    def _soft(self, paint):
        return paint.blur is not None and paint.blur.sigma > 0 and paint.shader is None

    def drawRect(self, r, paint):
        ctx = self.ctx
        ctx.new_path()
        if self._soft(paint) and paint.style != Paint.kStroke_Style:
            # мягкий прямоугольник: заливаем без размытия, но с пониженной альфой по краям нет — упрощение
            pass
        ctx.rectangle(r.l, r.t, r.r - r.l, r.b - r.t)
        self._finish(paint)
    def drawRRect(self, rr, paint):
        self.ctx.new_path(); _rrect_path(self.ctx, rr.rect, rr.rx, rr.ry); self._finish(paint)
    def drawRoundRect(self, r, rx, ry, paint):
        self.ctx.new_path(); _rrect_path(self.ctx, r, rx, ry); self._finish(paint)
    def drawCircle(self, x, y, rad, paint):
        if self._soft(paint) and paint.style != Paint.kStroke_Style:
            return self._soft_oval(x, y, rad, rad, paint)
        self.ctx.new_path(); self.ctx.arc(x, y, max(rad, 1e-9), 0, 2 * math.pi); self._finish(paint)
    def drawOval(self, r, paint):
        cx, cy, rx, ry = (r.l + r.r) / 2, (r.t + r.b) / 2, (r.r - r.l) / 2, (r.b - r.t) / 2
        if self._soft(paint) and paint.style != Paint.kStroke_Style:
            return self._soft_oval(cx, cy, rx, ry, paint)
        self.ctx.new_path(); self.ctx.new_sub_path(); _ellipse_arc(self.ctx, cx, cy, rx, ry, 0, 2 * math.pi)
        self._finish(paint)
    def _soft_oval(self, cx, cy, rx, ry, paint):
        """Замена гауссовой маски: радиальный градиент с мягким краем."""
        s = paint.blur.sigma
        c = paint.color
        ctx = self.ctx
        R = max(rx, ry) + 2.2 * s
        inner = max(0.0, (max(rx, ry) - 1.2 * s) / R)
        ctx.save()
        ctx.translate(cx, cy)
        k = (ry + 2.2 * s) / R if rx >= ry else 1.0
        kx = (rx + 2.2 * s) / R if ry > rx else 1.0
        ctx.scale(kx, k)
        pat = cairo.RadialGradient(0, 0, 0, 0, 0, R)
        a = c.fA * paint.alpha
        pat.add_color_stop_rgba(0, c.fR, c.fG, c.fB, a)
        pat.add_color_stop_rgba(inner, c.fR, c.fG, c.fB, a)
        pat.add_color_stop_rgba(min(1.0, inner + (1 - inner) * 0.5), c.fR, c.fG, c.fB, a * 0.35)
        pat.add_color_stop_rgba(1.0, c.fR, c.fG, c.fB, 0)
        if paint.op is not None:
            ctx.set_operator(paint.op)
        ctx.set_source(pat)
        ctx.new_path(); ctx.arc(0, 0, R, 0, 2 * math.pi); ctx.fill()
        ctx.restore()
    def drawArc(self, r, start, sweep, useCenter, paint):
        ctx = self.ctx
        cx, cy, rx, ry = (r.l + r.r) / 2, (r.t + r.b) / 2, (r.r - r.l) / 2, (r.b - r.t) / 2
        ctx.new_path()
        if useCenter:
            ctx.move_to(cx, cy)
        _ellipse_arc(ctx, cx, cy, rx, ry, math.radians(start), math.radians(start + sweep), neg=sweep < 0)
        if useCenter:
            ctx.close_path()
        self._finish(paint)
    def drawLine(self, x0, y0, x1, y1, paint):
        ctx = self.ctx
        ctx.new_path(); ctx.move_to(x0, y0); ctx.line_to(x1, y1)
        st = paint.style
        paint.style = Paint.kStroke_Style
        self._finish(paint)
        paint.style = st
    def drawPath(self, path, paint):
        self.ctx.new_path(); path.replay(self.ctx); self._finish(paint)
    def drawPicture(self, pic):
        ctx = self.ctx
        ctx.save()
        ctx.set_source_surface(pic.surf, 0, 0)
        ctx.paint()
        ctx.restore()
    def drawString(self, txt, x, y, fnt, paint):
        ctx = self.ctx
        ctx.save()
        fnt.apply(ctx)
        ctx.new_path()
        ctx.move_to(x, y)
        if paint.style == Paint.kStroke_Style:
            ctx.text_path(txt)
            self._finish(paint)
        else:
            if paint.op is not None:
                ctx.set_operator(paint.op)
            self._source(paint)
            ctx.show_text(txt)
        ctx.restore()
    def drawSurface(self, surf, x, y, w=None, h=None, alpha=1.0, filt=cairo.FILTER_BILINEAR):
        ctx = self.ctx
        ctx.save()
        ctx.translate(x, y)
        if w is not None:
            ctx.scale(w / surf.get_width(), h / surf.get_height())
        ctx.set_source_surface(surf, 0, 0)
        ctx.get_source().set_filter(filt)
        ctx.paint_with_alpha(alpha)
        ctx.restore()
    def flush(self):
        pass

class Picture:
    def __init__(self, surf):
        self.surf = surf

class PictureRecorder:
    def beginRecording(self, rect=None):
        self.surf = cairo.RecordingSurface(cairo.CONTENT_COLOR_ALPHA, None)
        self.ctx = cairo.Context(self.surf)
        return Canvas(self.ctx, self.surf)
    def finishRecordingAsPicture(self):
        return Picture(self.surf)

class _Snapshot:
    def __init__(self, surf):
        self.surf = surf
    def save(self, path):
        self.surf.write_to_png(path)

class Surface:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        self.ctx = cairo.Context(self.surf)
        self.ctx.set_antialias(cairo.ANTIALIAS_GRAY)
        self.cv = Canvas(self.ctx, self.surf)
    def getCanvas(self):
        return self.cv
    def makeImageSnapshot(self):
        self.surf.flush()
        return _Snapshot(self.surf)
    def array(self):
        """BGRA uint8 (H, W, 4), без копирования."""
        self.surf.flush()
        buf = self.surf.get_data()
        return np.ndarray((self.h, self.w, 4), np.uint8, buf, strides=(self.surf.get_stride(), 4, 1))

class ClipOp:
    kIntersect = 0

class TileMode:
    kRepeat = 0
    kClamp = 1
