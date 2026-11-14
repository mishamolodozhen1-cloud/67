"""Городская инфраструктура для РП: тротуары с бордюрами, разметка, зебры, светофоры,
таблички улиц, остановки, скамейки, урны, фонтаны, вывески заведений и адресные таблички.

Вызывается из osm_to_luau.py; возвращает словарь списков-строк для Infra.lua и список мест для навигатора.
Правостороннее движение: правая сторона для направления (ux, uz) — это (-uz, ux) (X — восток, Z — юг).
"""
import math
import random
from collections import defaultdict

S = 1 / 0.3
SIDEWALK = {"a": 4.0 * S, "r": 2.6 * S}  # ширина тротуара, стадов
CURB = 0.9

POI_CATS = {
    # категория: (подпись, цвет вывески, показывать в навигаторе, отдельный знак без здания)
    "police": ("Полиция", "1f4fa8", True, True),
    "medical": ("Медицина", "c8202c", True, True),
    "pharmacy": ("Аптека", "16884a", True, True),
    "fire": ("Пожарная часть", "c0301c", True, True),
    "bank": ("Банк", "0e5a46", True, True),
    "atm": ("Банкомат", "0e5a46", True, False),
    "food_shop": ("Продукты", "d8781a", True, True),
    "shop": ("Магазин", "6a3aa0", True, False),
    "food": ("Кафе и рестораны", "7a4a24", True, False),
    "hotel": ("Отель", "283278", True, True),
    "post": ("Почта", "0058a8", True, True),
    "culture": ("Культура", "7a1e3c", True, False),
    "education": ("Учёба", "1d6f7a", True, False),
    "gov": ("Госучреждения", "3a4a64", True, False),
    "fuel": ("Заправка", "c0392b", True, True),
}


def poi_category(t):
    a, sh, tour, off = t.get("amenity"), t.get("shop"), t.get("tourism"), t.get("office")
    if a == "police":
        return "police"
    if a in ("hospital", "clinic", "doctors", "dentist"):
        return "medical"
    if a == "pharmacy":
        return "pharmacy"
    if a == "fire_station":
        return "fire"
    if a == "bank":
        return "bank"
    if a == "atm":
        return "atm"
    if a == "fuel":
        return "fuel"
    if sh in ("supermarket", "convenience", "greengrocer", "bakery", "butcher", "deli", "confectionery", "alcohol"):
        return "food_shop"
    if sh:
        return "shop"
    if a in ("cafe", "restaurant", "fast_food", "bar", "pub", "ice_cream", "food_court"):
        return "food"
    if tour in ("hotel", "hostel", "guest_house"):
        return "hotel"
    if a == "post_office":
        return "post"
    if a in ("theatre", "cinema", "nightclub", "arts_centre") or tour in ("museum", "gallery"):
        return "culture"
    if a in ("school", "university", "college", "kindergarten", "library"):
        return "education"
    if a == "townhall" or off == "government":
        return "gov"
    return None


def unit(dx, dz):
    L = math.hypot(dx, dz)
    if L < 1e-9:
        return 0.0, 0.0
    return dx / L, dz / L


def right_of(u):
    return (-u[1], u[0])


def clean(text):
    return text.replace(",", " ").replace(";", " ").replace("|", "/").replace("\n", " ").strip()


def short_street(name):
    rep = [("улица", "ул."), ("проспект", "пр."), ("переулок", "пер."), ("площадь", "пл."),
           ("набережная", "наб."), ("бульвар", "б-р"), ("шоссе", "ш.")]
    for a, b in rep:
        if name.lower().startswith(a + " "):
            return b + name[len(a):]
        if name.lower().endswith(" " + a):
            return name[: -len(a)] + b
    return name


def trim_polyline(pts, start, end):
    def cut(p, t):
        acc = 0.0
        for i in range(len(p) - 1):
            seg = math.dist(p[i], p[i + 1])
            if acc + seg >= t:
                r = (t - acc) / seg if seg > 0 else 0
                q = (p[i][0] + (p[i + 1][0] - p[i][0]) * r, p[i][1] + (p[i + 1][1] - p[i][1]) * r)
                return [q] + p[i + 1:]
            acc += seg
        return None

    total = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    if start + end >= total - 2:
        return None
    p = cut(pts, start) if start > 0 else list(pts)
    if p and end > 0:
        p = cut(p[::-1], end)
        p = p[::-1] if p else None
    return p


def dist_point_seg(p, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    if L2 == 0:
        return math.dist(p, a), a
    t = max(0, min(1, ((p[0] - ax) * dx + (p[1] - az) * dz) / L2))
    q = (ax + dx * t, az + dz * t)
    return math.dist(p, q), q


def build(nodes, ways, proj, in_area, box_geom, bld_records, WIDTH, KIND, simplify, parse_m, fmt):
    rng = random.Random(11)
    P = {}

    def pos(n):
        if n not in P:
            P[n] = proj(nodes[n][0], nodes[n][1])
        return P[n]

    # ---------------- Граф дорог
    roads = []
    node_roads = defaultdict(list)
    degree = defaultdict(int)
    for wid, (nds, t) in ways.items():
        hw = t.get("highway")
        kind = KIND.get(hw)
        if kind not in ("a", "r", "s", "p") or t.get("area") == "yes" or t.get("tunnel") in ("yes", "building_passage"):
            continue
        nds = [n for n in nds if n in nodes]
        if len(nds) < 2:
            continue
        w = (parse_m(t.get("width")) or WIDTH[hw])
        w = min(max(w, 1.5), 30) * S
        oneway = 0
        if t.get("oneway") in ("yes", "1", "true") or t.get("junction") == "roundabout":
            oneway = 1
        elif t.get("oneway") == "-1":
            oneway = -1
        lanes = parse_m(t.get("lanes")) or 0
        idx = len(roads)
        roads.append({"id": wid, "kind": kind, "w": w, "nodes": nds, "t": t, "oneway": oneway, "lanes": lanes,
                      "name": t.get("name"), "tt": t.get("name:tt")})
        for i, n in enumerate(nds):
            node_roads[n].append((idx, i))
            if i > 0:
                degree[n] += 1
            if i < len(nds) - 1:
                degree[n] += 1

    def junction(n):
        return degree[n] >= 3

    def other_half(n, idx):
        best = 0.0
        for j, _ in node_roads[n]:
            if j != idx:
                best = max(best, roads[j]["w"] / 2 + (SIDEWALK.get(roads[j]["kind"], 0) if roads[j]["kind"] in ("a", "r") else 0))
        return best

    def other_half_road(n, idx):
        best = 0.0
        for j, _ in node_roads[n]:
            if j != idx:
                best = max(best, roads[j]["w"] / 2)
        return best

    sidewalks, curbs, markings = [], [], []
    for idx, r in enumerate(roads):
        if r["kind"] not in ("a", "r"):
            continue
        nds = r["nodes"]
        # делим на участки между перекрёстками
        cuts = [0] + [i for i in range(1, len(nds) - 1) if junction(nds[i])] + [len(nds) - 1]
        for a, b in zip(cuts[:-1], cuts[1:]):
            chain = [pos(n) for n in nds[a:b + 1]]
            if not any(in_area(*p, 60) for p in chain):
                continue
            chain = simplify(chain, 0.8, closed=False) if len(chain) > 2 else chain
            sn, en = nds[a], nds[b]
            # тротуары и бордюры
            ts = other_half(sn, idx) + 2 if junction(sn) else 0
            te = other_half(en, idx) + 2 if junction(en) else 0
            trimmed = trim_polyline(chain, ts, te)
            sw = SIDEWALK[r["kind"]]
            sides = (1, -1)
            if r["oneway"] != 0 and r["kind"] == "a":
                sides = (r["oneway"],)  # у односторонних магистралей (часто — половина бульвара) тротуар только справа
            if trimmed:
                for side in sides:
                    for i in range(len(trimmed) - 1):
                        (x1, z1), (x2, z2) = trimmed[i], trimmed[i + 1]
                        u = unit(x2 - x1, z2 - z1)
                        rn = right_of(u)
                        for off, width, out in ((r["w"] / 2 + CURB + sw / 2, sw, sidewalks), (r["w"] / 2 + CURB / 2, CURB, curbs)):
                            o = off * side
                            out.append(f"{fmt(x1 + rn[0] * o)},{fmt(z1 + rn[1] * o)},{fmt(x2 + rn[0] * o)},{fmt(z2 + rn[1] * o)},{fmt(width)}")
            # осевая разметка на магистралях
            if r["kind"] == "a" and r["w"] >= 25 and (r["oneway"] == 0 or r["lanes"] >= 2):
                ms = other_half_road(sn, idx) + 12 if junction(sn) else 0
                me = other_half_road(en, idx) + 12 if junction(en) else 0
                mt = trim_polyline(chain, ms, me)
                if mt:
                    if r["oneway"] != 0:
                        kind = "d"  # граница между полосами одного направления
                    else:
                        kind = "s" if (r["lanes"] >= 4 or r["w"] >= 45) else "d"
                    for i in range(len(mt) - 1):
                        (x1, z1), (x2, z2) = mt[i], mt[i + 1]
                        markings.append(f"{fmt(x1)},{fmt(z1)},{fmt(x2)},{fmt(z2)},{kind}")

    def road_dir_at(n):
        """Направление и ширина основной (самой широкой) проезжей дороги через узел."""
        best = None
        for j, i in node_roads[n]:
            r = roads[j]
            if r["kind"] not in ("a", "r", "s"):
                continue
            nds = r["nodes"]
            a = pos(nds[max(i - 1, 0)])
            b = pos(nds[min(i + 1, len(nds) - 1)])
            u = unit(b[0] - a[0], b[1] - a[1])
            if u == (0.0, 0.0):
                continue
            if best is None or r["w"] > best[1]:
                best = (u, r["w"], j)
        return best

    # ---------------- Пешеходные переходы
    crossings = []
    for n, (la, lo, t) in nodes.items():
        if t.get("highway") != "crossing" and t.get("railway") != "crossing":
            continue
        if t.get("crossing") in ("unmarked", "no", "informal") or t.get("crossing:markings") == "no":
            continue
        x, z = pos(n)
        if not in_area(x, z):
            continue
        rd = road_dir_at(n)
        if not rd:
            continue
        u, w, _ = rd
        crossings.append(f"{fmt(x)},{fmt(z)},{fmt(u[0], 4)},{fmt(u[1], 4)},{fmt(w)}")

    # ---------------- Светофоры
    lights, stoplines = [], []
    group = 0
    for n, (la, lo, t) in nodes.items():
        if t.get("highway") != "traffic_signals":
            continue
        x, z = pos(n)
        if not in_area(x, z):
            continue
        approaches = []
        for j, i in node_roads[n]:
            r = roads[j]
            if r["kind"] not in ("a", "r", "s"):
                continue
            nds = r["nodes"]
            for k, sign in ((i - 1, -1), (i + 1, 1)):
                if 0 <= k < len(nds):
                    # движение в узел идёт со стороны соседа k; для односторонних — только по направлению линии
                    if r["oneway"] == 1 and sign == 1:
                        continue
                    if r["oneway"] == -1 and sign == -1:
                        continue
                    q = pos(nds[k])
                    d = unit(q[0] - x, q[1] - z)
                    if d != (0.0, 0.0):
                        approaches.append((d, r["w"], r["oneway"] != 0))
        if not approaches:
            continue
        group += 1
        a0 = math.atan2(approaches[0][0][1], approaches[0][0][0])
        others = max((a[1] for a in approaches), default=0)
        for d, w, oneway in approaches:
            ang = math.atan2(d[1], d[0])
            axis = 0 if abs(math.cos(ang - a0)) > 0.707 else 1
            T = max(others / 2 + 8, 14)
            incoming = (-d[0], -d[1])
            rr = right_of(incoming)
            px = x + d[0] * T + rr[0] * (w / 2 + 3)
            pz = z + d[1] * T + rr[1] * (w / 2 + 3)
            lights.append(f"{fmt(px)},{fmt(pz)},{fmt(d[0], 3)},{fmt(d[1], 3)},{axis},{group}")
            # стоп-линия на полосах, ведущих к светофору
            inner = 0.6 if not oneway else -w / 2 + 0.6
            sx, sz = x + d[0] * (T - 2), z + d[1] * (T - 2)
            stoplines.append(f"{fmt(sx + rr[0] * inner)},{fmt(sz + rr[1] * inner)},{fmt(sx + rr[0] * (w / 2 - 0.6))},{fmt(sz + rr[1] * (w / 2 - 0.6))}")

    # ---------------- Таблички с названиями улиц (русский / татарский)
    signs = []
    placed = []
    for n in list(node_roads.keys()):
        if not junction(n):
            continue
        named = {}
        for j, i in node_roads[n]:
            r = roads[j]
            if r["kind"] in ("a", "r", "p") and r["name"] and r["name"] not in named:
                nds = r["nodes"]
                k = i + 1 if i + 1 < len(nds) else i - 1
                q = pos(nds[k])
                x, z = pos(n)
                d = unit(q[0] - x, q[1] - z)
                named[r["name"]] = (d, r["w"], r["tt"])
        if len(named) < 2:
            continue
        x, z = pos(n)
        if not in_area(x, z):
            continue
        items = list(named.items())[:2]
        (n1, (d1, w1, tt1)), (n2, (d2, w2, tt2)) = items
        key = tuple(sorted((n1, n2)))
        if any(k == key and math.dist(p, (x, z)) < 180 for k, p in placed):
            continue
        placed.append((key, (x, z)))
        bx, bz = unit(d1[0] + d2[0], d1[1] + d2[1])
        if (bx, bz) == (0.0, 0.0):
            bx, bz = right_of(d1)
        off = max(w1, w2) / 2 + 9
        label1 = clean(n1) + ("|" + clean(tt1) if tt1 else "")
        label2 = clean(n2) + ("|" + clean(tt2) if tt2 else "")
        signs.append(f"{fmt(x + bx * off)},{fmt(z + bz * off)},{label1},{fmt(d1[0], 3)},{fmt(d1[1], 3)},{label2},{fmt(d2[0], 3)},{fmt(d2[1], 3)}")

    # ---------------- Ближайшая дорога (для ориентации объектов)
    segs = []
    for r in roads:
        if r["kind"] in ("a", "r", "s", "p"):
            pts = [pos(n) for n in r["nodes"]]
            for i in range(len(pts) - 1):
                segs.append((pts[i], pts[i + 1], r["w"], r["kind"]))
    cell = 200.0
    grid = defaultdict(list)
    for sidx, (a, b, w, k) in enumerate(segs):
        for gx in range(int(min(a[0], b[0]) // cell), int(max(a[0], b[0]) // cell) + 1):
            for gz in range(int(min(a[1], b[1]) // cell), int(max(a[1], b[1]) // cell) + 1):
                grid[(gx, gz)].append(sidx)

    def nearest_road(p, kinds=("a", "r", "s", "p")):
        gx, gz = int(p[0] // cell), int(p[1] // cell)
        best = None
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for sidx in grid.get((gx + dx, gz + dz), ()):
                    a, b, w, k = segs[sidx]
                    if k not in kinds:
                        continue
                    d, q = dist_point_seg(p, a, b)
                    if best is None or d < best[0]:
                        best = (d, q, a, b, w)
        return best

    # ---------------- Остановки
    stops = []
    stop_pts = []
    for n, (la, lo, t) in nodes.items():
        is_stop = t.get("highway") == "bus_stop" or (t.get("public_transport") == "platform" and t.get("bus") != "no")
        if not is_stop:
            continue
        x, z = pos(n)
        if not in_area(x, z) or any(math.dist((x, z), q) < 45 for q in stop_pts):
            continue
        nr = nearest_road((x, z), ("a", "r"))
        if not nr:
            continue
        d, q, a, b, w = nr
        u = unit(b[0] - a[0], b[1] - a[1])
        if d < w / 2 + 4:  # точка на проезжей части — выносим на тротуар справа
            rn = right_of(u)
            x, z = q[0] + rn[0] * (w / 2 + 10), q[1] + rn[1] * (w / 2 + 10)
        f = unit(q[0] - x, q[1] - z)
        stop_pts.append((x, z))
        name = clean(t.get("name") or "Остановка")
        stops.append(f"{fmt(x)},{fmt(z)},{fmt(f[0], 3)},{fmt(f[1], 3)},{name}")

    # ---------------- Скамейки, урны, фонари, фонтаны
    props = []
    for n, (la, lo, t) in nodes.items():
        a = t.get("amenity")
        kind = None
        if a == "bench":
            kind = "b"
        elif a in ("waste_basket",):
            kind = "t"
        elif t.get("highway") == "street_lamp":
            kind = "l"
        elif a == "fountain":
            kind = "f"
        elif a == "drinking_water":
            kind = "t"
        if not kind:
            continue
        x, z = pos(n)
        if not in_area(x, z):
            continue
        nr = nearest_road((x, z))
        if nr and nr[0] < 40:
            f = unit(nr[1][0] - x, nr[1][1] - z)
        else:
            ang = rng.random() * math.tau
            f = (math.cos(ang), math.sin(ang))
        props.append(f"{kind},{fmt(x)},{fmt(z)},{fmt(f[0], 3)},{fmt(f[1], 3)}")
    for wid, (nds, t) in ways.items():
        if t.get("amenity") == "fountain" and len(nds) > 3 and all(n in nodes for n in nds):
            pts = [pos(n) for n in nds]
            cx = sum(p[0] for p in pts) / len(pts)
            cz = sum(p[1] for p in pts) / len(pts)
            rad = max(math.dist((cx, cz), p) for p in pts)
            if in_area(cx, cz):
                props.append(f"F,{fmt(cx)},{fmt(cz)},{fmt(min(rad, 60))},0")

    # ---------------- Вывески заведений и адресные таблички
    box_cell = 120.0
    box_grid = defaultdict(list)
    for bi, (x, z, w, d, phi, y0, h) in enumerate(box_geom):
        R = math.hypot(w, d) / 2
        for gx in range(int((x - R) // box_cell), int((x + R) // box_cell) + 1):
            for gz in range(int((z - R) // box_cell), int((z + R) // box_cell) + 1):
                box_grid[(gx, gz)].append(bi)

    def box_local(bi, p):
        x, z, w, d, phi, y0, h = box_geom[bi]
        # мир -> локальные координаты блока (обратный поворот CFrame.Angles(0, phi, 0))
        c, s = math.cos(phi), math.sin(phi)
        dx, dz = p[0] - x, p[1] - z
        return dx * c - dz * s, dx * s + dz * c

    def faces(bi):
        """Четыре стены блока: (центр, нормаль наружу, ширина, имя грани)."""
        x, z, w, d, phi, y0, h = box_geom[bi]
        c, s = math.cos(phi), math.sin(phi)

        def to_world(lx, lz):
            return x + lx * c + lz * s, z - lx * s + lz * c

        out = []
        for lx, lz, nx_, nz_, width in ((w / 2, 0, 1, 0, d), (-w / 2, 0, -1, 0, d), (0, d / 2, 0, 1, w), (0, -d / 2, 0, -1, w)):
            cx, cz = to_world(lx, lz)
            nwx, nwz = to_world(lx + nx_, lz + nz_)
            out.append(((cx, cz), unit(nwx - cx, nwz - cz), width))
        return out

    def find_box(p, maxd=25):
        gx, gz = int(p[0] // box_cell), int(p[1] // box_cell)
        best = None
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for bi in box_grid.get((gx + dx, gz + dz), ()):
                    x, z, w, d, phi, y0, h = box_geom[bi]
                    lx, lz = box_local(bi, p)
                    ex = max(abs(lx) - w / 2, 0)
                    ez = max(abs(lz) - d / 2, 0)
                    dd = math.hypot(ex, ez)
                    if dd <= maxd and (best is None or dd < best[0]):
                        best = (dd, bi)
        return best[1] if best else None

    def street_face(bi):
        best = None
        for (c, nrm, width) in faces(bi):
            probe = (c[0] + nrm[0] * 6, c[1] + nrm[1] * 6)
            nr = nearest_road(probe, ("a", "r", "p", "s"))
            dd = nr[0] if nr else 1e9
            if width < 10:
                dd += 200
            if best is None or dd < best[0]:
                best = (dd, c, nrm, width)
        return best

    slots = defaultdict(int)
    shop_signs, free_signs, addresses, navigator = [], [], [], []

    def poi_point(t, n=None, ring=None):
        if n is not None:
            return pos(n)
        xs = [p[0] for p in ring]
        zs = [p[1] for p in ring]
        return sum(xs) / len(xs), sum(zs) / len(zs)

    pois = []
    for n, (la, lo, t) in nodes.items():
        cat = poi_category(t)
        if cat:
            pois.append((cat, t, poi_point(t, n=n)))
    for rec in bld_records:
        cat = poi_category(rec["tags"])
        if cat:
            pois.append((cat, rec["tags"], poi_point(rec["tags"], ring=rec["ring"])))
    for wid, (nds, t) in ways.items():
        if "building" not in t and poi_category(t) and len(nds) > 2 and all(n in nodes for n in nds):
            pois.append((poi_category(t), t, poi_point(t, ring=[pos(n) for n in nds])))

    seen_names = set()
    for cat, t, p in pois:
        if not in_area(*p):
            continue
        label, color, nav, freestanding = POI_CATS[cat]
        name = clean(t.get("name") or t.get("brand") or label)
        key = (name, round(p[0] / 30), round(p[1] / 30))
        if key in seen_names:
            continue
        seen_names.add(key)
        if nav and cat != "atm":
            navigator.append((cat, name, p[0], p[1]))
        if cat == "atm":
            continue
        bi = find_box(p)
        if bi is not None:
            x, z, w, d, phi, y0, h = box_geom[bi]
            sf = street_face(bi)
            if sf and y0 < 1 and h > 14:
                _, c, nrm, width = sf
                slot = slots[(bi, round(nrm[0], 2), round(nrm[1], 2))]
                if slot < 3 and width >= 14:
                    slots[(bi, round(nrm[0], 2), round(nrm[1], 2))] += 1
                    along = (-nrm[1], nrm[0])
                    sw_ = min(width / 3.2, 26) if width < 60 else 24
                    offset = (slot - 1) * (sw_ + 4) if width >= 3 * (sw_ + 4) else 0
                    if slot > 0 and width < 3 * (sw_ + 4):
                        continue
                    sx = c[0] + along[0] * offset + nrm[0] * 0.45
                    sz = c[1] + along[1] * offset + nrm[1] * 0.45
                    store = 1 if cat in ("shop", "food_shop", "food", "pharmacy", "bank") else 0
                    shop_signs.append(f"{cat},{color},{name},{fmt(sx)},{fmt(sz)},{fmt(nrm[0], 3)},{fmt(nrm[1], 3)},{fmt(sw_)},{store}")
                    continue
        if freestanding:
            nr = nearest_road(p)
            if nr:
                f = unit(nr[1][0] - p[0], nr[1][1] - p[1])
                free_signs.append(f"{cat},{color},{name},{fmt(p[0])},{fmt(p[1])},{fmt(f[0], 3)},{fmt(f[1], 3)}")

    for rec in bld_records:
        t = rec["tags"]
        num = t.get("addr:housenumber")
        street = t.get("addr:street")
        if not num or not street or not rec["boxes"] or rec["y0"] > 1:
            continue
        best = None
        for bi in rec["boxes"]:
            sf = street_face(bi)
            if sf and (best is None or sf[0] < best[0][0]):
                best = (sf, bi)
        if not best:
            continue
        (dd, c, nrm, width), bi = best
        if width < 10 or dd > 120:
            continue
        along = (-nrm[1], nrm[0])
        ax = c[0] + along[0] * (width / 2 - 5) + nrm[0] * 0.4
        az = c[1] + along[1] * (width / 2 - 5) + nrm[1] * 0.4
        addresses.append(f"{fmt(ax)},{fmt(az)},{fmt(nrm[0], 3)},{fmt(nrm[1], 3)},{clean(short_street(street))}|{clean(num)}")

    for s in stop_pts:
        pass
    for line in stops:
        f = line.split(",")
        navigator.append(("bus", "Остановка «" + f[4] + "»", float(f[0]), float(f[1])))

    print(f"infra: sidewalks {len(sidewalks)} curbs {len(curbs)} markings {len(markings)} crossings {len(crossings)} "
          f"lights {len(lights)} stoplines {len(stoplines)} streetsigns {len(signs)} stops {len(stops)} props {len(props)} "
          f"shopsigns {len(shop_signs)} freesigns {len(free_signs)} addresses {len(addresses)} navigator {len(navigator)}")
    return {
        "Sidewalks": sidewalks, "Curbs": curbs, "Markings": markings, "Crossings": crossings,
        "Lights": lights, "StopLines": stoplines, "StreetSigns": signs, "Stops": stops, "Props": props,
        "ShopSigns": shop_signs, "FreeSigns": free_signs, "Addresses": addresses, "Navigator": navigator,
    }
