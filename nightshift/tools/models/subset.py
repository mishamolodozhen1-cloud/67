"""subset.py scene.gltf out.gltf keep1,keep2,... — оставить меши только у перечисленных узлов (по имени), остальные узлы без меша."""
import sys, json, os, shutil
src, out, keep = sys.argv[1], sys.argv[2], set(sys.argv[3].split(","))
j = json.load(open(src))
for n in j["nodes"]:
    if "mesh" in n and n.get("name") not in keep:
        del n["mesh"]
base_out = os.path.dirname(os.path.abspath(out))
base_src = os.path.dirname(os.path.abspath(src))
if base_out != base_src:
    raise SystemExit("out must be next to the source gltf")
json.dump(j, open(out, "w"))
print("kept", sum(1 for n in j["nodes"] if "mesh" in n))
