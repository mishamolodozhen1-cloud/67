"""Запись плейса Roblox в бинарном формате .rbxl (его принимает Open Cloud и открывает Roblox Studio).

Взято из nightshift/build.py (проверено на публикациях NIGHT SHIFT) и дополнено:
  • список служб расширен (StarterGui, ServerStorage, ...);
  • write_binary сам дополняет у экземпляров одного класса недостающие свойства значениями по умолчанию
    (в бинарном формате у всех экземпляров класса должен быть одинаковый набор свойств).
"""
import struct

SERVICES = {"Workspace", "Lighting", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPlayer", "MaterialService", "SoundService", "Players"}

# Значения по умолчанию для свойств, которые заданы не у всех экземпляров класса: (тип, значение)
CLASS_DEFAULTS = {
    "ScreenGui": {
        "ResetOnSpawn": ("bool", True),
        "IgnoreGuiInset": ("bool", False),
        "ZIndexBehavior": ("token", 0),
        "Enabled": ("bool", True),
        "DisplayOrder": ("int", 0),
    },
}

TYPE_IDS = {
    "string": 0x01,
    "source": 0x01,
    "bool": 0x02,
    "int": 0x03,
    "float": 0x04,
    "Vector3": 0x0E,
    "CFrame": 0x10,
    "token": 0x12,
    "Color3uint8": 0x1A,
}


def _u32(n):
    return struct.pack("<I", n)


def _bstr(s):
    b = s.encode("utf-8") if isinstance(s, str) else s
    return _u32(len(b)) + b


def _interleave(words):
    """words: список 4-байтовых big-endian значений -> байты, разложенные по позициям."""
    if not words:
        return b""
    return bytes(w[i] for i in range(4) for w in words)


def _zigzag(n):
    return ((n << 1) ^ (n >> 31)) & 0xFFFFFFFF


def _i32_array(values):
    return _interleave([struct.pack(">I", _zigzag(v)) for v in values])


def _ref_array(refs):
    deltas, prev = [], 0
    for r in refs:
        deltas.append(r - prev)
        prev = r
    return _i32_array(deltas)


def _rot_float(f):
    bits = struct.unpack(">I", struct.pack(">f", f))[0]
    return struct.pack(">I", ((bits << 1) | (bits >> 31)) & 0xFFFFFFFF)


def _float_array(values):
    return _interleave([_rot_float(v) for v in values])


def _encode_values(kind, values):
    if kind in ("string", "source"):
        return b"".join(_bstr(v) for v in values)
    if kind == "bool":
        return bytes(1 if v else 0 for v in values)
    if kind == "int":
        return _i32_array(values)
    if kind == "float":
        return _float_array(values)
    if kind == "token":
        return _interleave([struct.pack(">I", v) for v in values])
    if kind == "Vector3":
        return b"".join(_float_array([v[i] for v in values]) for i in range(3))
    if kind == "CFrame":
        rot = b""
        for v in values:
            rot += b"\x00" + struct.pack("<9f", *v[3:])
        pos = b"".join(_float_array([v[i] for v in values]) for i in range(3))
        return rot + pos
    if kind == "Color3uint8":
        rgb = [((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF) for v in values]
        return bytes(c[0] for c in rgb) + bytes(c[1] for c in rgb) + bytes(c[2] for c in rgb)
    raise ValueError(kind)


def _chunk(name, payload):
    return name + struct.pack("<III", 0, len(payload), 0) + payload


def write_binary(roots):
    # Обход дерева: присваиваем референты, запоминаем родителей.
    order, parents = [], []

    def visit(inst, parent_ref):
        ref_id = len(order)
        order.append(inst)
        parents.append(parent_ref)
        for c in inst.children:
            visit(c, ref_id)

    for r in roots:
        visit(r, -1)

    classes = sorted({i.cls for i in order})
    class_id = {c: n for n, c in enumerate(classes)}
    by_class = {c: [n for n, i in enumerate(order) if i.cls == c] for c in classes}

    out = b"<roblox!\x89\xff\r\n\x1a\n" + struct.pack("<Hii", 0, len(classes), len(order)) + b"\x00" * 8

    for c in classes:
        refs = by_class[c]
        is_service = c in SERVICES
        payload = _u32(class_id[c]) + _bstr(c) + bytes([1 if is_service else 0]) + _u32(len(refs)) + _ref_array(refs)
        if is_service:
            payload += b"\x01" * len(refs)
        out += _chunk(b"INST", payload)

    for c in classes:
        refs = by_class[c]
        insts = [order[r] for r in refs]
        prop_sets = []
        for inst in insts:
            props = {"Name": ("string", inst.name)}
            for kind, name, value in inst.props:
                props[name] = (kind, value)
            prop_sets.append(props)
        names = sorted(set().union(*[set(p) for p in prop_sets]))
        for pname in names:
            if not all(pname in p for p in prop_sets):
                default = CLASS_DEFAULTS.get(c, {}).get(pname)
                if default is None:
                    raise ValueError(f"{c}.{pname} задан не у всех экземпляров, а значения по умолчанию нет")
                for p in prop_sets:
                    p.setdefault(pname, default)
            kind = prop_sets[0][pname][0]
            values = [p[pname][1] for p in prop_sets]
            payload = _u32(class_id[c]) + _bstr(pname) + bytes([TYPE_IDS[kind]]) + _encode_values(kind, values)
            out += _chunk(b"PROP", payload)

    children = list(range(len(order)))
    payload = b"\x00" + _u32(len(order)) + _ref_array(children) + _ref_array(parents)
    out += _chunk(b"PRNT", payload)
    out += _chunk(b"END\x00", b"</roblox>")
    return out
