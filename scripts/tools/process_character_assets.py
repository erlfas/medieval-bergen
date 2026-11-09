#!/usr/bin/env python3
"""
Process, optimize, and normalize 3D character and weapon GLB models for Medieval Bergen 1360.
- Downscales massive 4K textures to WebGL-friendly resolutions (1024x1024)
- Normalizes scales, pivots, and orientations (aligns sword, bow, arrow)
- Splits character meshes into modular, animatable pieces matching the BoxManModel bone pivots:
  - Head (man_without_cloths + helmet) attached to head_node
  - Torso (cloths / naked + belt) attached to torso_node
  - Sleeves & hands (cloths / naked) attached to left_arm_pivot and right_arm_pivot (rotated to hang down)
  - Legs (cloths / naked) attached to left_leg_pivot and right_leg_pivot
- Hides placeholder greybox cubes so the character is completely rendered by the 3D models.
- Default state is fully clothed medieval settler (not naked).
"""

import json
import struct
import io
import os
import copy
import numpy as np
from PIL import Image

def read_glb(path):
    with open(path, 'rb') as fp:
        magic, ver, length = struct.unpack('<4sII', fp.read(12))
        assert magic == b'glTF', f"Invalid glTF magic in {path}"
        chunk_len, chunk_type = struct.unpack('<I4s', fp.read(8))
        json_data = json.loads(fp.read(chunk_len).decode('utf-8'))
        
        bin_data = b''
        if fp.tell() < length:
            bin_len, bin_type = struct.unpack('<I4s', fp.read(8))
            bin_data = fp.read(bin_len)
            
        return json_data, bin_data

def write_glb(path, json_data, bin_data):
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
    
    out_buf = io.BytesIO()
    img.save(out_buf, format='JPEG', quality=quality, optimize=True)
    return out_buf.getvalue()

def build_glb_buffer(sub_d, v, n, u, tri, img):
    v = np.ascontiguousarray(v, dtype=np.float32)
    n = np.ascontiguousarray(n, dtype=np.float32)
    u = np.ascontiguousarray(u, dtype=np.float32)
    tri = np.ascontiguousarray(tri, dtype=np.uint16)
    
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

def extract_submesh(v, n, u, tri, tri_mask):
    sub_tri = tri[tri_mask]
    unique_v_indices, new_tri_indices = np.unique(sub_tri, return_inverse=True)
    new_tri = new_tri_indices.reshape(-1, 3).astype(np.uint16)
    new_v = v[unique_v_indices].copy()
    new_n = n[unique_v_indices].copy()
    new_u = u[unique_v_indices].copy()
    return new_v, new_n, new_u, new_tri

def load_glb_arrays(path):
    d, bin_data = read_glb(path)
    prim = d['meshes'][0]['primitives'][0]
    def read_acc(acc_id, dtype, mul=1):
        acc = d['accessors'][acc_id]
        bv = d['bufferViews'][acc['bufferView']]
        off = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
        return np.frombuffer(bin_data, dtype=dtype, count=acc['count']*mul, offset=off)
    v = read_acc(prim['attributes']['POSITION'], np.float32, 3).reshape(-1, 3).copy()
    n = read_acc(prim['attributes']['NORMAL'], np.float32, 3).reshape(-1, 3).copy()
    u = read_acc(prim['attributes']['TEXCOORD_0'], np.float32, 2).reshape(-1, 2).copy()
    idx_acc = d['accessors'][prim['indices']]
    idx_type = np.uint16 if idx_acc['componentType'] == 5123 else np.uint32
    tri = read_acc(prim['indices'], idx_type, 1).reshape(-1, 3).copy()
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=1024)
    return d, v, n, u, tri, new_img

def save_submesh_glb(base_d, v, n, u, tri, img, out_path):
    sub_d = copy.deepcopy(base_d)
    sub_d, bin_sub = build_glb_buffer(sub_d, v, n, u, tri, img)
    write_glb(out_path, sub_d, bin_sub)

def process_all():
    os.makedirs('assets/character', exist_ok=True)
    os.makedirs('assets/weapons', exist_ok=True)
    
    # -------------------------------------------------------------
    # 1. Load source models
    # -------------------------------------------------------------
    print("\n=== Reading source 3D models ===")
    d_man, v_m, n_m, u_m, tri_m, img_m = load_glb_arrays('3dmodels/man_without_cloths.glb')
    v_m *= 1.75 # Scale man to 1.75m total height
    
    d_cloth, v_c, n_c, u_c, tri_c, img_c = load_glb_arrays('3dmodels/cloths.glb')
    v_c *= 1.50 # Scale cloths to match shoulders at 1.36m, collar at 1.45m, and waist at 0.88m
    
    d_helm, v_h, n_h, u_h, tri_h, img_h = load_glb_arrays('3dmodels/helmet.glb')
    
    tri_m_c = v_m[tri_m].mean(axis=1)
    tri_c_c = v_c[tri_c].mean(axis=1)
    tri_h_c = v_h[tri_h].mean(axis=1)

    # -------------------------------------------------------------
    # 2. Extract Head & Helmet (Pivot at head_node: Vector3(0, 1.52, 0))
    # -------------------------------------------------------------
    print("\n--- Generating Head and Helmet ---")
    # Head from man_without_cloths
    mask_head = (tri_m_c[:, 1] >= 1.42) & (np.abs(tri_m_c[:, 0]) <= 0.20)
    v_head, n_head, u_head, tri_head = extract_submesh(v_m, n_m, u_m, tri_m, mask_head)
    v_head -= np.array([0.0, 1.52, 0.0], dtype=np.float32)
    save_submesh_glb(d_man, v_head, n_head, u_head, tri_head, img_m, 'assets/character/character_head.glb')

    # Helmet / cap from helmet.glb (rescaled 0.70x to snugly fit 22cm human head)
    mask_helm = tri_h_c[:, 1] >= 0.74
    v_helm, n_helm, u_helm, tri_helm = extract_submesh(v_h, n_h, u_h, tri_h, mask_helm)
    v_helm = (v_helm - np.array([0.0, 1.0, 0.0], dtype=np.float32)) * 0.70 + np.array([0.0, 0.24, -0.02], dtype=np.float32)
    save_submesh_glb(d_helm, v_helm, n_helm, u_helm, tri_helm, img_h, 'assets/character/character_helmet.glb')

    # -------------------------------------------------------------
    # 3. Extract Torso & Belt (Pivot at torso_node: Vector3(0, 1.05, 0))
    # -------------------------------------------------------------
    print("\n--- Generating Torso and Belt ---")
    # Cloths tunic
    mask_torso_c = (tri_c_c[:, 1] >= 0.70) & (np.abs(tri_c_c[:, 0]) <= 0.21)
    v_tc, n_tc, u_tc, tri_tc = extract_submesh(v_c, n_c, u_c, tri_c, mask_torso_c)
    v_tc -= np.array([0.0, 1.05, 0.0], dtype=np.float32)
    save_submesh_glb(d_cloth, v_tc, n_tc, u_tc, tri_tc, img_c, 'assets/character/character_torso.glb')

    # Belt from helmet.glb (scaled to fit waist: 42cm width, 31cm depth at Y=0.88m)
    mask_belt = (tri_h_c[:, 1] >= 0.0) & (tri_h_c[:, 1] < 0.65)
    v_belt, n_belt, u_belt, tri_belt = extract_submesh(v_h, n_h, u_h, tri_h, mask_belt)
    v_belt[:, 0] *= 0.83
    v_belt[:, 2] = v_belt[:, 2] * 0.55 - 0.02
    v_belt[:, 1] = (v_belt[:, 1] - 0.48) * 0.83 - 0.17
    n_belt = n_belt * np.array([1.0/0.83, 1.0/0.83, 1.0/0.55], dtype=np.float32)
    n_belt /= np.maximum(1e-6, np.linalg.norm(n_belt, axis=1, keepdims=True))
    save_submesh_glb(d_helm, v_belt, n_belt, u_belt, tri_belt, img_h, 'assets/character/character_belt.glb')

    # Naked chest from man_without_cloths
    mask_torso_m = (tri_m_c[:, 1] >= 0.70) & (tri_m_c[:, 1] < 1.42) & (np.abs(tri_m_c[:, 0]) <= 0.21)
    v_tm, n_tm, u_tm, tri_tm = extract_submesh(v_m, n_m, u_m, tri_m, mask_torso_m)
    v_tm -= np.array([0.0, 1.05, 0.0], dtype=np.float32)
    save_submesh_glb(d_man, v_tm, n_tm, u_tm, tri_tm, img_m, 'assets/character/character_torso_naked.glb')

    # -------------------------------------------------------------
    # 4. Extract Sleeves & Hands (Pivots at left_arm_pivot and right_arm_pivot)
    #    Rotate 90 deg around Z from horizontal T-pose to hang down
    #    Shoulder joints precisely at X = +-0.21, Y = 1.36, Z = -0.02
    # -------------------------------------------------------------
    print("\n--- Generating Sleeves and Hands ---")
    p_sl = np.array([-0.21, 1.36, -0.02], dtype=np.float32)
    p_sr = np.array([ 0.21, 1.36, -0.02], dtype=np.float32)

    # Left sleeve (cloths)
    mask_slv_l = (tri_c_c[:, 0] < -0.21) & (tri_c_c[:, 1] >= 1.20)
    v_sl_l, n_sl_l, u_sl_l, tri_sl_l = extract_submesh(v_c, n_c, u_c, tri_c, mask_slv_l)
    v_rel = v_sl_l - p_sl
    v_rot = np.column_stack([-v_rel[:, 1], v_rel[:, 0], v_rel[:, 2]])
    n_rot = np.column_stack([-n_sl_l[:, 1], n_sl_l[:, 0], n_sl_l[:, 2]])
    save_submesh_glb(d_cloth, v_rot, n_rot, u_sl_l, tri_sl_l, img_c, 'assets/character/character_sleeve_l.glb')

    # Right sleeve (cloths)
    mask_slv_r = (tri_c_c[:, 0] > 0.21) & (tri_c_c[:, 1] >= 1.20)
    v_sl_r, n_sl_r, u_sl_r, tri_sl_r = extract_submesh(v_c, n_c, u_c, tri_c, mask_slv_r)
    v_rel_r = v_sl_r - p_sr
    v_rot_r = np.column_stack([v_rel_r[:, 1], -v_rel_r[:, 0], v_rel_r[:, 2]])
    n_rot_r = np.column_stack([n_sl_r[:, 1], -n_sl_r[:, 0], n_sl_r[:, 2]])
    save_submesh_glb(d_cloth, v_rot_r, n_rot_r, u_sl_r, tri_sl_r, img_c, 'assets/character/character_sleeve_r.glb')

    # Left hand (man_without_cloths)
    mask_hnd_l = (tri_m_c[:, 0] < -0.68) & (tri_m_c[:, 1] >= 1.25)
    v_hl, n_hl, u_hl, tri_hl = extract_submesh(v_m, n_m, u_m, tri_m, mask_hnd_l)
    v_rel_hl = v_hl - p_sl
    v_rot_hl = np.column_stack([-v_rel_hl[:, 1], v_rel_hl[:, 0], v_rel_hl[:, 2]])
    n_rot_hl = np.column_stack([-n_hl[:, 1], n_hl[:, 0], n_hl[:, 2]])
    save_submesh_glb(d_man, v_rot_hl, n_rot_hl, u_hl, tri_hl, img_m, 'assets/character/character_hand_l.glb')

    # Right hand (man_without_cloths)
    mask_hnd_r = (tri_m_c[:, 0] > 0.68) & (tri_m_c[:, 1] >= 1.25)
    v_hr, n_hr, u_hr, tri_hr = extract_submesh(v_m, n_m, u_m, tri_m, mask_hnd_r)
    v_rel_hr = v_hr - p_sr
    v_rot_hr = np.column_stack([v_rel_hr[:, 1], -v_rel_hr[:, 0], v_rel_hr[:, 2]])
    n_rot_hr = np.column_stack([n_hr[:, 1], -n_hr[:, 0], n_hr[:, 2]])
    save_submesh_glb(d_man, v_rot_hr, n_rot_hr, u_hr, tri_hr, img_m, 'assets/character/character_hand_r.glb')

    # Naked left arm (entire arm including hand)
    mask_arm_m_l = (tri_m_c[:, 0] < -0.21) & (tri_m_c[:, 1] >= 1.20)
    v_aml, n_aml, u_aml, tri_aml = extract_submesh(v_m, n_m, u_m, tri_m, mask_arm_m_l)
    v_rel_aml = v_aml - p_sl
    v_rot_aml = np.column_stack([-v_rel_aml[:, 1], v_rel_aml[:, 0], v_rel_aml[:, 2]])
    n_rot_aml = np.column_stack([-n_aml[:, 1], n_aml[:, 0], n_aml[:, 2]])
    save_submesh_glb(d_man, v_rot_aml, n_rot_aml, u_aml, tri_aml, img_m, 'assets/character/character_arm_l_naked.glb')

    # Naked right arm
    mask_arm_m_r = (tri_m_c[:, 0] > 0.21) & (tri_m_c[:, 1] >= 1.20)
    v_amr, n_amr, u_amr, tri_amr = extract_submesh(v_m, n_m, u_m, tri_m, mask_arm_m_r)
    v_rel_amr = v_amr - p_sr
    v_rot_amr = np.column_stack([v_rel_amr[:, 1], -v_rel_amr[:, 0], v_rel_amr[:, 2]])
    n_rot_amr = np.column_stack([n_amr[:, 1], -n_amr[:, 0], n_amr[:, 2]])
    save_submesh_glb(d_man, v_rot_amr, n_rot_amr, u_amr, tri_amr, img_m, 'assets/character/character_arm_r_naked.glb')

    # -------------------------------------------------------------
    # 5. Extract Legs & Boots (Pivots at left_leg_pivot and right_leg_pivot)
    # -------------------------------------------------------------
    print("\n--- Generating Legs and Boots ---")
    p_hl = np.array([-0.15, 0.70, -0.04], dtype=np.float32)
    p_hr = np.array([ 0.15, 0.70, -0.04], dtype=np.float32)

    # Clothed left leg
    mask_leg_cl = (tri_c_c[:, 0] < 0.0) & (tri_c_c[:, 1] < 0.70)
    v_lcl, n_lcl, u_lcl, tri_lcl = extract_submesh(v_c, n_c, u_c, tri_c, mask_leg_cl)
    v_lcl -= p_hl
    save_submesh_glb(d_cloth, v_lcl, n_lcl, u_lcl, tri_lcl, img_c, 'assets/character/character_leg_l.glb')

    # Clothed right leg
    mask_leg_cr = (tri_c_c[:, 0] >= 0.0) & (tri_c_c[:, 1] < 0.70)
    v_lcr, n_lcr, u_lcr, tri_lcr = extract_submesh(v_c, n_c, u_c, tri_c, mask_leg_cr)
    v_lcr -= p_hr
    save_submesh_glb(d_cloth, v_lcr, n_lcr, u_lcr, tri_lcr, img_c, 'assets/character/character_leg_r.glb')

    # Naked left leg
    mask_leg_ml = (tri_m_c[:, 0] < 0.0) & (tri_m_c[:, 1] < 0.70)
    v_lml, n_lml, u_lml, tri_lml = extract_submesh(v_m, n_m, u_m, tri_m, mask_leg_ml)
    v_lml -= p_hl
    save_submesh_glb(d_man, v_lml, n_lml, u_lml, tri_lml, img_m, 'assets/character/character_leg_l_naked.glb')

    # Naked right leg
    mask_leg_mr = (tri_m_c[:, 0] >= 0.0) & (tri_m_c[:, 1] < 0.70)
    v_lmr, n_lmr, u_lmr, tri_lmr = extract_submesh(v_m, n_m, u_m, tri_m, mask_leg_mr)
    v_lmr -= p_hr
    save_submesh_glb(d_man, v_lmr, n_lmr, u_lmr, tri_lmr, img_m, 'assets/character/character_leg_r_naked.glb')

    # Also save full compatibility GLBs
    save_submesh_glb(d_man, v_m, n_m, u_m, tri_m, img_m, 'assets/character/man_without_cloths.glb')
    save_submesh_glb(d_cloth, v_c, n_c, u_c, tri_c, img_c, 'assets/character/cloths.glb')

    # -------------------------------------------------------------
    # 6. Weapons: sword.glb, bow.glb, arrow.glb
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
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=d['bufferViews'][norm_acc['bufferView']].get('byteOffset', 0)).reshape(count, 3).copy()
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=d['bufferViews'][uv_acc['bufferView']].get('byteOffset', 0)).reshape(count, 2).copy()
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=d['bufferViews'][idx_acc['bufferView']].get('byteOffset', 0)).copy()
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
    
    # Rotate edge towards -Z
    R_edge = np.array([
        [np.cos(np.pi/4), 0, np.sin(np.pi/4)],
        [0, 1, 0],
        [-np.sin(np.pi/4), 0, np.cos(np.pi/4)]
    ])
    verts_rot = verts_rot @ R_edge.T
    normals_rot = normals_rot @ R_edge.T
    
    d_sw = copy.deepcopy(d)
    d_sw, bin_sw = build_glb_buffer(d_sw, verts_rot, normals_rot, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/weapons/sword.glb', d_sw, bin_sw)

    print("\n--- Processing bow.glb ---")
    d, bin_data = read_glb('3dmodels/bow.glb')
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=d['bufferViews'][pos_acc['bufferView']].get('byteOffset', 0)).reshape(count, 3).copy()
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=d['bufferViews'][norm_acc['bufferView']].get('byteOffset', 0)).reshape(count, 3).copy()
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=d['bufferViews'][uv_acc['bufferView']].get('byteOffset', 0)).reshape(count, 2).copy()
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=d['bufferViews'][idx_acc['bufferView']].get('byteOffset', 0)).copy()
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=1024)
    
    bow_h = verts[:, 1].max() - verts[:, 1].min()
    bow_scale = 1.25 / bow_h
    verts *= bow_scale
    verts[:, 0] -= verts[:, 0].mean()
    verts[:, 1] -= (verts[:, 1].max() + verts[:, 1].min()) * 0.5
    verts[:, 2] -= (verts[:, 2].max() + verts[:, 2].min()) * 0.5
    
    d_bw = copy.deepcopy(d)
    d_bw, bin_bw = build_glb_buffer(d_bw, verts, normals, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/weapons/bow.glb', d_bw, bin_bw)

    print("\n--- Processing arrow.glb ---")
    d, bin_data = read_glb('3dmodels/arrow.glb')
    prim = d['meshes'][0]['primitives'][0]
    pos_acc = d['accessors'][prim['attributes']['POSITION']]
    norm_acc = d['accessors'][prim['attributes']['NORMAL']]
    uv_acc = d['accessors'][prim['attributes']['TEXCOORD_0']]
    idx_acc = d['accessors'][prim['indices']]
    count = pos_acc['count']
    verts = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=d['bufferViews'][pos_acc['bufferView']].get('byteOffset', 0)).reshape(count, 3).copy()
    normals = np.frombuffer(bin_data, dtype=np.float32, count=count*3, offset=d['bufferViews'][norm_acc['bufferView']].get('byteOffset', 0)).reshape(count, 3).copy()
    uvs = np.frombuffer(bin_data, dtype=np.float32, count=count*2, offset=d['bufferViews'][uv_acc['bufferView']].get('byteOffset', 0)).reshape(count, 2).copy()
    indices = np.frombuffer(bin_data, dtype=np.uint16 if idx_acc['componentType']==5123 else np.uint32, count=idx_acc['count'], offset=d['bufferViews'][idx_acc['bufferView']].get('byteOffset', 0)).copy()
    new_img = optimize_texture(bin_data, d['images'][0], d['bufferViews'], max_dim=512)
    
    # Arrow along Z axis with tip pointing at -Z
    pca_cov = np.cov(verts, rowvar=False)
    eigvals, eigvecs = np.linalg.eigh(pca_cov)
    shaft_axis = eigvecs[:, 2]
    target_axis = np.array([0.0, 0.0, 1.0])
    
    axis = np.cross(shaft_axis, target_axis)
    axis_norm = np.linalg.norm(axis)
    if axis_norm > 1e-4:
        axis = axis / axis_norm
        angle = np.arccos(np.clip(np.dot(shaft_axis, target_axis), -1.0, 1.0))
        K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
        R = np.eye(3) + np.sin(angle)*K + (1 - np.cos(angle))*(K @ K)
        verts = verts @ R.T
        normals = normals @ R.T
        
    verts[:, 0] -= verts[:, 0].mean()
    verts[:, 1] -= verts[:, 1].mean()
    verts[:, 2] -= verts[:, 2].min()
    
    curr_len = verts[:, 2].max()
    arrow_scale = 0.70 / curr_len
    verts *= arrow_scale
    
    # Tip forward (-Z)
    verts[:, 2] = 0.70 - verts[:, 2]
    verts[:, 2] -= 0.70
    normals[:, 2] = -normals[:, 2]
    
    d_ar = copy.deepcopy(d)
    d_ar, bin_ar = build_glb_buffer(d_ar, verts, normals, uvs, indices.reshape(-1, 3), new_img)
    write_glb('assets/weapons/arrow.glb', d_ar, bin_ar)

    print("\n✓ ALL CHARACTER AND WEAPON ASSETS SUCCESSFULLY PROCESSED!")

if __name__ == '__main__':
    process_all()
