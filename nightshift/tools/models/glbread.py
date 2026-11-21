import json, struct, numpy as np
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
def load(path):
    d = open(path, 'rb').read()
    off = 12; chunks = []
    while off < len(d):
        clen, ctype = struct.unpack('<I4s', d[off:off+8]); chunks.append(d[off+8:off+8+clen]); off += 8 + clen
    j = json.loads(chunks[0]); binc = chunks[1] if len(chunks) > 1 else b''
    return j, binc
def accessor(j, binc, i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    n = NC[a['type']]; dt = CT[a['componentType']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride')
    itemsize = np.dtype(dt).itemsize * n
    if stride and stride != itemsize:
        raw = np.frombuffer(binc, dtype=np.uint8, count=stride * a['count'], offset=start).reshape(a['count'], stride)[:, :itemsize]
        arr = np.frombuffer(raw.tobytes(), dtype=dt).reshape(a['count'], n)
    else:
        arr = np.frombuffer(binc, dtype=dt, count=a['count'] * n, offset=start).reshape(a['count'], n)
    if a.get('normalized'):
        arr = arr.astype(np.float32) / np.iinfo(dt).max
    return arr.astype(np.float64)
def image_bytes(j, binc, i):
    im = j['images'][i]; bv = j['bufferViews'][im['bufferView']]
    s = bv.get('byteOffset', 0); return binc[s:s+bv['byteLength']]
def node_matrix(node):
    if 'matrix' in node: return np.array(node['matrix']).reshape(4, 4).T
    T = np.eye(4); R = np.eye(4); S = np.eye(4)
    if 'translation' in node: T[:3, 3] = node['translation']
    if 'rotation' in node:
        x, y, z, w = node['rotation']
        R[:3, :3] = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    if 'scale' in node: S[0,0], S[1,1], S[2,2] = node['scale']
    return T @ R @ S
def world_meshes(j):
    out = []
    def walk(n, M):
        node = j['nodes'][n]; W = M @ node_matrix(node)
        if 'mesh' in node: out.append((n, node['mesh'], W))
        for c in node.get('children', []): walk(c, W)
    for s in j['scenes']:
        for n in s['nodes']: walk(n, np.eye(4))
    return out
