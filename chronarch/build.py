#!/usr/bin/env python3
"""Собирает плейс Roblox (.rbxlx) из исходников в src/.

Структура:
  src/ReplicatedStorage/Shared/*.lua        -> ReplicatedStorage.Shared (ModuleScript)
  src/ServerScriptService/*.server.lua      -> ServerScriptService (Script)
  src/ServerScriptService/*.lua             -> ServerScriptService (ModuleScript)
  src/StarterPlayerScripts/StandClient/     -> StarterPlayer.StarterPlayerScripts.StandClient
      init.client.lua — сам LocalScript, остальные .lua — его дочерние ModuleScript.

Запуск: python3 build.py  ->  build/ArrowOfFate.rbxlx
"""
import os
import struct
import uuid
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
OUT_DIR = os.path.join(ROOT, "build")
OUT = os.path.join(OUT_DIR, "ArrowOfFate.rbxlx")


class Inst:
    def __init__(self, cls, name, props=None, children=None):
        self.cls = cls
        self.name = name
        self.props = props or []
        self.children = children or []

    def add(self, child):
        self.children.append(child)
        return child


def ref():
    return "RBX" + uuid.uuid4().hex.upper()


def color(r, g, b):
    return 0xFF000000 | (r << 16) | (g << 8) | b


def cframe(x, y, z):
    return (x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)


def prop_xml(kind, name, value):
    if kind == "string":
        return f'<string name="{name}">{escape(value)}</string>'
    if kind == "bool":
        return f'<bool name="{name}">{"true" if value else "false"}</bool>'
    if kind in ("token", "int", "float"):
        return f'<{kind} name="{name}">{value}</{kind}>'
    if kind == "Vector3":
        x, y, z = value
        return f'<Vector3 name="{name}"><X>{x}</X><Y>{y}</Y><Z>{z}</Z></Vector3>'
    if kind == "CFrame":
        x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value
        return (
            f'<CoordinateFrame name="{name}"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>'
            f"<R00>{r00}</R00><R01>{r01}</R01><R02>{r02}</R02>"
            f"<R10>{r10}</R10><R11>{r11}</R11><R12>{r12}</R12>"
            f"<R20>{r20}</R20><R21>{r21}</R21><R22>{r22}</R22></CoordinateFrame>"
        )
    if kind == "Color3uint8":
        return f'<Color3uint8 name="{name}">{value}</Color3uint8>'
    if kind == "source":
        if "]]>" in value:
            raise ValueError("Source contains ']]>'")
        return f'<ProtectedString name="{name}"><![CDATA[{value}]]></ProtectedString>'
    raise ValueError(kind)


def inst_xml(inst, out, depth=1):
    pad = "  " * depth
    out.append(f'{pad}<Item class="{inst.cls}" referent="{ref()}">')
    out.append(f"{pad}  <Properties>")
    out.append(f"{pad}    " + prop_xml("string", "Name", inst.name))
    for kind, name, value in inst.props:
        out.append(f"{pad}    " + prop_xml(kind, name, value))
    out.append(f"{pad}  </Properties>")
    for c in inst.children:
        inst_xml(c, out, depth + 1)
    out.append(f"{pad}</Item>")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def script(cls, name, path):
    props = [("source", "Source", read(path))]
    if cls == "Script":
        props.append(("token", "RunContext", 0))
    return Inst(cls, name, props)


def lua_name(filename):
    for suffix in (".server.lua", ".client.lua", ".lua"):
        if filename.endswith(suffix):
            return filename[: -len(suffix)]
    return filename


def build():
    services = []

    # Workspace: только пол площади и точка появления, остальное строит сервер.
    ws = Inst("Workspace", "Workspace", [("bool", "StreamingEnabled", False)])
    ws.add(Inst("Part", "Plaza", [
        ("bool", "Anchored", True),
        ("bool", "Locked", True),
        ("Vector3", "size", (200, 4, 200)),
        ("CFrame", "CFrame", cframe(0, -2, 0)),
        ("Color3uint8", "Color3uint8", color(128, 118, 104)),
        ("token", "TopSurface", 0),
        ("token", "BottomSurface", 0),
    ]))
    ws.add(Inst("SpawnLocation", "SpawnLocation", [
        ("bool", "Anchored", True),
        ("bool", "Locked", True),
        ("bool", "CanCollide", False),
        ("float", "Transparency", 1),
        ("Vector3", "size", (6, 0.2, 6)),
        ("CFrame", "CFrame", cframe(0, 0.12, 0)),
        ("int", "Duration", 0),
        ("bool", "Neutral", True),
        ("token", "TopSurface", 0),
        ("token", "BottomSurface", 0),
    ]))
    services.append(ws)

    # Lighting: технология Future (4) задаётся в файле — из скриптов её менять нельзя.
    services.append(Inst("Lighting", "Lighting", [("token", "Technology", 4)]))

    # ReplicatedStorage.Shared
    rs = Inst("ReplicatedStorage", "ReplicatedStorage")
    shared = rs.add(Inst("Folder", "Shared"))
    shared_dir = os.path.join(SRC, "ReplicatedStorage", "Shared")
    for fn in sorted(os.listdir(shared_dir)):
        if fn.endswith(".lua"):
            shared.add(script("ModuleScript", lua_name(fn), os.path.join(shared_dir, fn)))
    services.append(rs)

    # ServerScriptService
    sss = Inst("ServerScriptService", "ServerScriptService")
    sss_dir = os.path.join(SRC, "ServerScriptService")
    for fn in sorted(os.listdir(sss_dir)):
        path = os.path.join(sss_dir, fn)
        if fn.endswith(".server.lua"):
            sss.add(script("Script", lua_name(fn), path))
        elif fn.endswith(".lua"):
            sss.add(script("ModuleScript", lua_name(fn), path))
    services.append(sss)

    # StarterPlayer.StarterPlayerScripts
    sp = Inst("StarterPlayer", "StarterPlayer")
    sps = sp.add(Inst("StarterPlayerScripts", "StarterPlayerScripts"))
    sps_dir = os.path.join(SRC, "StarterPlayerScripts")
    for entry in sorted(os.listdir(sps_dir)):
        path = os.path.join(sps_dir, entry)
        if os.path.isdir(path):
            local = script("LocalScript", entry, os.path.join(path, "init.client.lua"))
            for fn in sorted(os.listdir(path)):
                if fn.endswith(".lua") and fn != "init.client.lua":
                    local.add(script("ModuleScript", lua_name(fn), os.path.join(path, fn)))
            sps.add(local)
        elif entry.endswith(".client.lua"):
            sps.add(script("LocalScript", lua_name(entry), path))
    services.append(sp)

    out = [
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        "  <External>null</External>",
        "  <External>nil</External>",
    ]
    for s in services:
        inst_xml(s, out)
    out.append("</roblox>")

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"Собрано: {OUT} ({os.path.getsize(OUT)} байт)")

    data = write_binary(services)
    with open(OUT_BIN, "wb") as f:
        f.write(data)
    print(f"Собрано: {OUT_BIN} ({len(data)} байт)")


###############################################################################
# Бинарный формат .rbxl (именно его принимает Open Cloud при публикации).
###############################################################################
OUT_BIN = os.path.join(OUT_DIR, "ArrowOfFate.rbxl")

SERVICES = {"Workspace", "Lighting", "ReplicatedStorage", "ServerScriptService", "StarterPlayer"}

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
                raise ValueError(f"{c}.{pname} задан не у всех экземпляров")
            kind = prop_sets[0][pname][0]
            values = [p[pname][1] for p in prop_sets]
            payload = _u32(class_id[c]) + _bstr(pname) + bytes([TYPE_IDS[kind]]) + _encode_values(kind, values)
            out += _chunk(b"PROP", payload)

    children = list(range(len(order)))
    payload = b"\x00" + _u32(len(order)) + _ref_array(children) + _ref_array(parents)
    out += _chunk(b"PRNT", payload)
    out += _chunk(b"END\x00", b"</roblox>")
    return out


if __name__ == "__main__":
    build()
