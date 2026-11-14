import sys, glob, json, collections
import xml.etree.ElementTree as ET
d = sys.argv[1]
nodes, ways, rels = {}, {}, {}
for f in sorted(glob.glob(d + "/tile_*.osm")):
    root = ET.parse(f).getroot()
    for el in root:
        tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
        if el.tag == "node":
            nodes[el.get("id")] = (float(el.get("lat")), float(el.get("lon")), tags)
        elif el.tag == "way":
            ways[el.get("id")] = ([n.get("ref") for n in el.findall("nd")], tags)
        elif el.tag == "relation":
            rels[el.get("id")] = ([(m.get("type"), m.get("ref"), m.get("role")) for m in el.findall("member")], tags)
json.dump({"nodes": nodes, "ways": ways, "rels": rels}, open(d + "/merged.json", "w"), ensure_ascii=False)
c = collections.Counter()
for wid, (nds, t) in ways.items():
    if "building" in t: c["building"] += 1
    elif "building:part" in t: c["building:part"] += 1
    elif "highway" in t: c["hw:" + t["highway"]] += 1
    elif t.get("natural") == "water" or t.get("waterway") == "riverbank": c["water_way"] += 1
    elif "barrier" in t: c["barrier:" + t["barrier"]] += 1
print(len(nodes), "nodes", len(ways), "ways", len(rels), "rels")
print(sorted(c.items(), key=lambda x: -x[1])[:40])
print("trees", sum(1 for n in nodes.values() if n[2].get("natural") == "tree"))
for rid, (mem, t) in rels.items():
    if t.get("type") == "multipolygon" and (t.get("natural") == "water" or t.get("waterway") == "riverbank" or "water" in t):
        have = sum(1 for m in mem if m[0] == "way" and m[1] in ways)
        print("WATER REL", rid, t.get("name"), len(mem), "members, have", have)
for wid, (nds, t) in ways.items():
    if t.get("natural") == "water":
        print("WATER WAY", wid, t.get("name"), len(nds), nds[0] == nds[-1])
names = ["Сююмбике", "Кул", "Благовещен", "Спасская", "Президент", "Богоявлен", "Казан", "Земледель", "Петропавлов", "Тайницкая", "Кремл"]
for wid, (nds, t) in ways.items():
    n = t.get("name", "")
    if any(k in n for k in names) and ("building" in t or "man_made" in t or "historic" in t or "tourism" in t or "amenity" in t):
        print("LANDMARK way", wid, n, {k: t[k] for k in t if k in ("building", "height", "building:levels", "man_made", "historic", "amenity", "religion", "building:colour", "roof:colour", "roof:shape")})
for rid, (mem, t) in rels.items():
    n = t.get("name", "")
    if any(k in n for k in names):
        print("LANDMARK rel", rid, n, t.get("type"), {k: t[k] for k in t if k in ("building", "height", "building:levels", "historic", "amenity")})
