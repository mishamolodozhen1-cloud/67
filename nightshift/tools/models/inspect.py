"""inspect.py scene.gltf — узлы с мешами: имя, мировой bbox (min/max) и общий размер сцены."""
import sys, numpy as np, trimesh
scene = trimesh.load(sys.argv[1], force='scene')
allV = []
rows = []
for node in scene.graph.nodes_geometry:
    T, gname = scene.graph[node]
    g = scene.geometry[gname]
    if not hasattr(g, 'vertices') or len(g.vertices) == 0: continue
    V = trimesh.transform_points(g.vertices, T)
    allV.append(V)
    rows.append((node, gname, V.min(0), V.max(0), len(g.faces)))
allV = np.vstack(allV)
mn, mx = allV.min(0), allV.max(0)
print("SCENE size", np.round(mx - mn, 3), "min", np.round(mn, 3), "max", np.round(mx, 3), "nodes", len(rows))
for r in rows[:40]:
    print(f"  {r[0][:40]:40} {r[1][:30]:30} min {np.round(r[2],2)} max {np.round(r[3],2)} f {r[4]}")
