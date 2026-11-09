#!/usr/bin/env python3
"""
Process, optimize, and normalize 3D character and weapon GLB models for Medieval Bergen 1360.
- Downscales massive 4K textures to WebGL-friendly resolutions (2048/1024)
- Normalizes scales, pivots, and orientations (aligns sword, bow, arrow)
- Splits helmet.glb into character_helmet.glb and character_belt.glb
- Scales man_without_cloths and cloths to realistic player height (1.75m)
- Ensures strictly valid float32 vertex buffers and uint16 index buffers
"""

import json
import struct
import io
import os
import numpy as np
from PIL import Image

def read_glb(path):
    with open(path, 'rb') as fp:
        magic, ver, length = struct.unpack('<4sII', fp.read(12))
        assert magic == b'glTF', f"Invalid glTF magic in {path}"
        chunk_len, chunk_type = struct.unpack('<I4s', fp.read(8))
        json_data = json.loads(fp.read(chunk_len).decode('utf-8'))
        
        # Read BIN chunk if present
        bin_data = b''
        if fp.tell() < length:
            bin_len, bin_type = struct.unpack('<I4s', fp.read(8))
            bin_data = fp.read(bin_len)
            
        return json_data, bin_data

def write_glb(path, json_data, bin_data):
    # Align bin_data to 4 bytes
    rem_bin = len(bin_data) % 4
    if rem_bin != 0:
        bin_data += b'\x00' * (4 - rem_bin)
        
    json_bytes = json.dumps(json_data, separators=(',', ':')).encode('utf-8')
    rem_json = len(json_bytes) % 4
    if rem_json != 0:
        json_bytes += b' ' * (4 - rem_json)
        
    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as fp:
        fp.write(struct.pack('<4sII', b'glTF', 2, total_len))
        fp.write(struct.pack('<I4s', len(json_bytes), b'JSON'))
        fp.write(json_bytes)
        fp.write(struct.pack('<I4s', len(bin_data), b'BIN\x00'))
        fp.write(bin_data)
    print(f"Wrote {path} ({total_len} bytes)")

def optimize_texture(bin_data, image_info, buffer_views, max_dim=1024, quality=85):
    bv_idx = image_info['bufferView']
    bv = buffer_views[bv_idx]
    offset = bv.get('byteOffset', 0)
    length = bv['byteLength']
    
    img_bytes = bin_data[offset:offset+length]
    img = Image.open(io.BytesIO(img_bytes))
    w, h = img.size
    
    scale = min(1.0, max_dim / max(w, h))
    if scale < 1.0:
        new_w = int(w * scale)
        new_h = int(h * scale)
        img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        print(f"  Resized image from {w}x{h} -> {new_w}x{new_h}")
    else:
        print(f"  Image kept at {w}x{h}")
        
    out_buf = io.BytesIO()
    img.save(out_buf, format='JPEG', quality=quality, optimize=True)
    return out_buf.getvalue()

def build_glb_buffer(sub_d, v, n, u, tri, img):
    # Ensure strict typed numpy arrays
    v = np.ascontiguousarray(v, dtype=np.float32)
    n = np.ascontiguousarray(n, dtype=np.float32)
    u = np.ascontiguousarray(u, dtype=np.float32)
    tri = np.ascontiguousarray(tri, dtype=np.uint16)
    
    # Strip any problematic extensions
    sub_d.pop('extensionsUsed', None)
    sub_d.pop('extensionsRequired', None)
    
    b = bytearray()
    def app(data, align=4):
        rem = len(b) % align
        if rem != 0:
            b.extend(b'\x00' * (align - rem))
        off = len(b)
        b.extend(data)
        return off
        
    p = sub_d['meshes'][0]['primitives'][0]
    p.pop('extensions', None)
    
    pos_a = sub_d['accessors'][p['attributes']['POSITION']]
    pos_a['componentType'] = 5126 # FLOAT
    pos_a['count'] = len(v)
    pos_a['min'] = v.min(axis=0).tolist()
    pos_a['max'] = v.max(axis=0).tolist()
    pos_a['byteOffset'] = 0
    o_pos = app(v.tobytes())
    sub_d['bufferViews'][pos_a['bufferView']] = {'buffer': 0, 'byteOffset': o_pos, 'byteLength': len(v.tobytes()), 'target': 34962}
    
    norm_a = sub_d['accessors'][p['attributes']['NORMAL']]
    norm_a['componentType'] = 5126 # FLOAT
    norm_a['count'] = len(n)
    norm_a['min'] = n.min(axis=0).tolist()
    norm_a['max'] = n.max(axis=0).tolist()
    norm_a['byteOffset'] = 0
    o_norm = app(n.tobytes())
    sub_d['bufferViews'][norm_a['bufferView']] = {'buffer': 0, 'byteOffset': o_norm, 'byteLength': len(n.tobytes()), 'target': 34962}
    
    uv_a = sub_d['accessors'][p['attributes']['TEXCOORD_0']]
    uv_a['componentType'] = 5126 # FLOAT
    uv_a['count'] = len(u)
    uv_a['min'] = u.min(axis=0).tolist()
    uv_a['max'] = u.max(axis=0).tolist()
    uv_a['byteOffset'] = 0
    o_uv = app(u.tobytes())
    sub_d['bufferViews'][uv_a['bufferView']] = {'buffer': 0, 'byteOffset': o_uv, 'byteLength': len(u.tobytes()), 'target': 34962}
    
    idx_a = sub_d['accessors'][p['indices']]
    flat_tri = tri.flatten()
    idx_a['count'] = len(flat_tri)
    idx_a['componentType'] = 5123 # UNSIGNED_SHORT
    idx_a['min'] = [int(flat_tri.min())]
    idx_a['max'] = [int(flat_tri.max())]
    idx_a['byteOffset'] = 0
    o_idx = app(flat_tri.tobytes())
    sub_d['bufferViews'][idx_a['bufferView']] = {'buffer': 0, 'byteOffset': o_idx, 'byteLength': len(flat_tri.tobytes()), 'target': 34963}
    
    o_img = app(img)
    sub_d['bufferViews'][sub_d['images'][0]['bufferView']] = {'buffer': 0, 'byteOffset': o_img, 'byteLength': len(img)}
    sub_d['buffers'][0]['byteLength'] = len(b)
    return sub_d, bytes(b)

def process_character_models():
    os.makedirs('assets/character', exist_ok=True)
    os.makedirs('assets/weapons', exist_ok=True)
    
    # -------------------------------------------------------------
    # 1. man_without_cloths.glb
    # -------------------------------------------------------------
    print("\n--- Processing man_without_cloths.glb ---")
    d, bin_data = read_glb('3dmodels/man_without_cloths.glb')
    
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    
    bv_pos = d['bufferViews'][pos_acc['bufferView']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_pos.get('byteOffset', 0)).reshape(count, 3).copy()
    verts *= 1.75 # Scale: height 1.0 -> 1.75m
    
    bv_norm = d['bufferViews'][norm_acc['bufferView']]
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_norm.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_uv = d['bufferViews'][uv_acc['bufferView']]
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=bv_uv.get('byteOffset', 0)).reshape(count, 2).copy()
    
    bv_idx = d['bufferViews'][idx_acc['bufferView']]
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=bv_idx.get('byteOffset', 0)).copy()
    
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=2048)
    
    d_man, bin_man = build_glb_buffer(d, verts, normals, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/character/man_without_cloths.glb', d_man, bin_man)

    # -------------------------------------------------------------
    # 2. cloths.glb
    # -------------------------------------------------------------
    print("\n--- Processing cloths.glb ---")
    d, bin_data = read_glb('3dmodels/cloths.glb')
    
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    
    bv_pos = d['bufferViews'][pos_acc['bufferView']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_pos.get('byteOffset', 0)).reshape(count, 3).copy()
    verts *= 1.75
    
    bv_norm = d['bufferViews'][norm_acc['bufferView']]
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_norm.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_uv = d['bufferViews'][uv_acc['bufferView']]
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=bv_uv.get('byteOffset', 0)).reshape(count, 2).copy()
    
    bv_idx = d['bufferViews'][idx_acc['bufferView']]
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=bv_idx.get('byteOffset', 0)).copy()
    
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=2048)
    
    d_cloth, bin_cloth = build_glb_buffer(d, verts, normals, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/character/cloths.glb', d_cloth, bin_cloth)

    # -------------------------------------------------------------
    # 3. helmet.glb -> split into character_helmet.glb and character_belt.glb
    # -------------------------------------------------------------
    print("\n--- Processing helmet.glb (Splitting into helmet and belt) ---")
    d, bin_data = read_glb('3dmodels/helmet.glb')
    
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    
    bv_p = d['bufferViews'][pos_acc['bufferView']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_p.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_n = d['bufferViews'][norm_acc['bufferView']]
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_n.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_u = d['bufferViews'][uv_acc['bufferView']]
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=bv_u.get('byteOffset', 0)).reshape(count, 2).copy()
    
    bv_i = d['bufferViews'][idx_acc['bufferView']]
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=bv_i.get('byteOffset', 0)).copy()
    
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=1024)
    
    triangles = indices.reshape(-1, 3)
    tri_y_mean = verts[triangles, 1].mean(axis=1)
    
    helmet_tri_mask = tri_y_mean >= 0.70
    helmet_tris = triangles[helmet_tri_mask]
    
    belt_tri_mask = (tri_y_mean >= 0.35) & (tri_y_mean < 0.70)
    belt_tris = triangles[belt_tri_mask]
    
    def extract_submesh(sub_tris, center_y_ref, scale=1.75):
        unique_v_indices, new_tri_indices = np.unique(sub_tris, return_inverse=True)
        new_tris = new_tri_indices.reshape(-1, 3)
        
        sub_verts = verts[unique_v_indices].copy() * scale
        sub_normals = normals[unique_v_indices].copy()
        sub_uvs = uvs[unique_v_indices].copy()
        
        sub_verts[:, 1] -= (center_y_ref * scale)
        sub_verts[:, 0] -= sub_verts[:, 0].mean()
        sub_verts[:, 2] -= sub_verts[:, 2].mean()
        
        return sub_verts.astype(np.float32), sub_normals.astype(np.float32), sub_uvs.astype(np.float32), new_tris.astype(np.uint16)
    
    h_verts, h_normals, h_uvs, h_tris = extract_submesh(helmet_tris, center_y_ref=0.88)
    d_helm = json.loads(json.dumps(d))
    d_helm, bin_helm = build_glb_buffer(d_helm, h_verts, h_normals, h_uvs, h_tris, new_img)
    write_glb('assets/character/character_helmet.glb', d_helm, bin_helm)
    
    b_verts, b_normals, b_uvs, b_tris = extract_submesh(belt_tris, center_y_ref=0.50)
    d_belt = json.loads(json.dumps(d))
    d_belt, bin_belt = build_glb_buffer(d_belt, b_verts, b_normals, b_uvs, b_tris, new_img)
    write_glb('assets/character/character_belt.glb', d_belt, bin_belt)

    # -------------------------------------------------------------
    # 4. sword.glb -> rotate to +Y blade, -Z edge, hilt at (0,0,0)
    # -------------------------------------------------------------
    print("\n--- Processing sword.glb ---")
    d, bin_data = read_glb('3dmodels/sword.glb')
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    
    bv_p = d['bufferViews'][pos_acc['bufferView']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_p.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_n = d['bufferViews'][norm_acc['bufferView']]
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_n.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_u = d['bufferViews'][uv_acc['bufferView']]
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=bv_u.get('byteOffset', 0)).reshape(count, 2).copy()
    
    bv_i = d['bufferViews'][idx_acc['bufferView']]
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=bv_i.get('byteOffset', 0)).copy()
    
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=1024)
    
    p_hilt = np.array([-0.4997, 0.0005, -0.1257])
    p_tip = np.array([0.4875, 0.8496, 0.0969])
    
    blade_vec = p_tip - p_hilt
    blade_dir = blade_vec / np.linalg.norm(blade_vec)
    target_y = np.array([0.0, 1.0, 0.0])
    
    rot_axis = np.cross(blade_dir, target_y)
    rot_axis = rot_axis / np.linalg.norm(rot_axis)
    rot_angle = np.arccos(np.clip(np.dot(blade_dir, target_y), -1.0, 1.0))
    
    K = np.array([
        [0, -rot_axis[2], rot_axis[1]],
        [rot_axis[2], 0, -rot_axis[0]],
        [-rot_axis[1], rot_axis[0], 0]
    ])
    R = np.eye(3) + np.sin(rot_angle) * K + (1 - np.cos(rot_angle)) * (K @ K)
    
    p_grip = p_hilt + blade_dir * 0.09
    verts_trans = verts - p_grip
    verts_rot = verts_trans @ R.T
    normals_rot = normals @ R.T
    
    current_len = np.linalg.norm(blade_vec)
    sword_scale = 0.90 / current_len
    verts_rot *= sword_scale
    
    var_x = np.var(verts_rot[:, 0])
    var_z = np.var(verts_rot[:, 2])
    if var_x < var_z:
        R90 = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]])
        verts_rot = verts_rot @ R90.T
        normals_rot = normals_rot @ R90.T
        
    d_sword = json.loads(json.dumps(d))
    d_sword, bin_sword = build_glb_buffer(d_sword, verts_rot, normals_rot, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/weapons/sword.glb', d_sword, bin_sword)

    # -------------------------------------------------------------
    # 5. bow.glb -> center grip at (0,0,0), scale height to 1.25m
    # -------------------------------------------------------------
    print("\n--- Processing bow.glb ---")
    d, bin_data = read_glb('3dmodels/bow.glb')
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    
    bv_p = d['bufferViews'][pos_acc['bufferView']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_p.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_n = d['bufferViews'][norm_acc['bufferView']]
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_n.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_u = d['bufferViews'][uv_acc['bufferView']]
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=bv_u.get('byteOffset', 0)).reshape(count, 2).copy()
    
    bv_i = d['bufferViews'][idx_acc['bufferView']]
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=bv_i.get('byteOffset', 0)).copy()
    
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=1024)
    
    grip_y = 0.495
    verts[:, 1] -= grip_y
    verts[:, 0] -= verts[:, 0].mean()
    verts[:, 2] -= verts[:, 2].mean()
    verts *= 1.25
    
    d_bow = json.loads(json.dumps(d))
    d_bow, bin_bow = build_glb_buffer(d_bow, verts, normals, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/weapons/bow.glb', d_bow, bin_bow)

    # -------------------------------------------------------------
    # 6. arrow.glb -> tip at (0, 0, -0.05), shaft extending to +Z ~ 0.72m
    # -------------------------------------------------------------
    print("\n--- Processing arrow.glb ---")
    d, bin_data = read_glb('3dmodels/arrow.glb')
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    
    bv_p = d['bufferViews'][pos_acc['bufferView']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_p.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_n = d['bufferViews'][norm_acc['bufferView']]
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=bv_n.get('byteOffset', 0)).reshape(count, 3).copy()
    
    bv_u = d['bufferViews'][uv_acc['bufferView']]
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=bv_u.get('byteOffset', 0)).reshape(count, 2).copy()
    
    bv_i = d['bufferViews'][idx_acc['bufferView']]
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=bv_i.get('byteOffset', 0)).copy()
    
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=512)
    
    p_tip = np.array([-0.4998, 0.0000, 0.0022])
    p_nock = np.array([0.4983, 0.6245, -0.0022])
    
    arrow_vec = p_nock - p_tip
    arrow_dir = arrow_vec / np.linalg.norm(arrow_vec)
    target_z = np.array([0.0, 0.0, 1.0])
    
    rot_axis = np.cross(arrow_dir, target_z)
    rot_axis = rot_axis / np.linalg.norm(rot_axis)
    rot_angle = np.arccos(np.clip(np.dot(arrow_dir, target_z), -1.0, 1.0))
    
    K = np.array([
        [0, -rot_axis[2], rot_axis[1]],
        [rot_axis[2], 0, -rot_axis[0]],
        [-rot_axis[1], rot_axis[0], 0]
    ])
    R = np.eye(3) + np.sin(rot_angle) * K + (1 - np.cos(rot_angle)) * (K @ K)
    
    verts_trans = verts - p_tip
    verts_rot = verts_trans @ R.T
    normals_rot = normals @ R.T
    
    arrow_len = np.linalg.norm(arrow_vec)
    arrow_scale = 0.75 / arrow_len
    verts_rot *= arrow_scale
    
    d_arrow = json.loads(json.dumps(d))
    d_arrow, bin_arrow = build_glb_buffer(d_arrow, verts_rot, normals_rot, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/weapons/arrow.glb', d_arrow, bin_arrow)

    print("\n✓ Successfully processed all models into assets/character and assets/weapons!")

if __name__ == '__main__':
    process_character_models()
