"""Разрезать glTF-сцену на отдельные GLB (по одному мешу), центр рамки — в начале координат.
argv: input, outdir, keep_textures(0/1)"""
import sys, os, json, numpy as np, trimesh
src, out, keep = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
os.makedirs(out, exist_ok=True)
scene = trimesh.load(src, force='scene')
info = {}
for node in scene.graph.nodes_geometry:
    T, gname = scene.graph[node]
    g = scene.geometry[gname].copy()
    g.apply_transform(T)
    if not keep and hasattr(g.visual, 'material'):
        uv = g.visual.uv
        g.visual = trimesh.visual.TextureVisuals(uv=uv)
    lo, hi = g.bounds
    g.apply_translation(-(lo + hi) / 2)
    name = gname.split('_Asset')[0].split('_SimplePolygon')[0]
    base = name
    k = 2
    while name in info:
        name = '%s_%d' % (base, k); k += 1
    path = os.path.join(out, name + '.glb')
    g.export(path)
    info[name] = {'size_m': [round(float(x), 4) for x in (hi - lo)], 'tris': int(len(g.faces)), 'bytes': os.path.getsize(path), 'material': getattr(getattr(scene.geometry[gname].visual, 'material', None), 'name', None)}
json.dump(info, open(os.path.join(out, 'info.json'), 'w'), indent=1, ensure_ascii=False)
print(len(info), 'meshes')
