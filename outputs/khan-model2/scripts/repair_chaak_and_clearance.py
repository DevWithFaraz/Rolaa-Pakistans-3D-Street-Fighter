"""Repair side-slit (chaak) webbing and bake clean panel-separated thigh clearance."""
import json
import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "outputs/khan-model2"

LOW = 0.578
HIGH = 1.035
NA = 18
NZ = 10
HALF_FRONT = math.pi * 0.42
HALF_BACK = math.pi * 0.42


def panel_components(faces):
    """Return edge-connected components among faces sorted largest-first."""
    face_set = set(faces)
    visited = set()
    comps = []
    for f in faces:
        if f in visited:
            continue
        comp = []
        queue = [f]
        visited.add(f)
        while queue:
            cur = queue.pop()
            comp.append(cur)
            for edge in cur.edges:
                for nf in edge.link_faces:
                    if nf in face_set and nf not in visited:
                        visited.add(nf)
                        queue.append(nf)
        comps.append(comp)
    comps.sort(key=lambda c: len(c), reverse=True)
    return comps


def clean_chaak_and_subdivide(body, mesh, tag_idx):
    """Trim scanned side-slit webbing/islands, subdivide panels, and tag front/back vertices."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    for i, f in enumerate(bm.faces):
        f.index = i

    deform = bm.verts.layers.deform.active
    ks_faces = [f for f in bm.faces if all(v[deform].get(tag_idx, 0.0) > 0.5 for v in f.verts)]
    comps = panel_components(ks_faces)
    assert len(comps) >= 2, f"Expected front & back panels, got {len(comps)} components"

    # Comp 0 = Back (902), Comp 1 = Front (698), Comp 2.. = under-hem/crotch return islands
    comp0_y = sum(f.calc_center_median().y for f in comps[0]) / len(comps[0])
    comp1_y = sum(f.calc_center_median().y for f in comps[1]) / len(comps[1])
    back_orig, front_orig = (comps[0], comps[1]) if comp0_y > comp1_y else (comps[1], comps[0])
    islands = [f for c in comps[2:] for f in c]

    # Remove Back side-slit inward pocket wall and disconnected recessed trouser pieces
    back_pocket_ids = set()
    for f in back_orig:
        c = f.calc_center_median()
        s = 1.0 if c.x >= 0.0 else -1.0
        if abs(c.x) > 0.15 and c.z < 0.88 and c.y < 0.065:
            if f.normal.x * s < 0.25 or f.normal.z < -0.35:
                back_pocket_ids.add(f.index)

    back_kept = [f for f in back_orig if f.index not in back_pocket_ids]
    back_sub = panel_components(back_kept)
    clean_back_ids = {f.index for f in back_sub[0]}
    back_drop_ids = {f.index for c in back_sub[1:] for f in c}
    front_ids = {f.index for f in front_orig}
    island_ids = {f.index for f in islands}

    layer = bm.faces.layers.int.new("panel_tag")  # 0=non-kameez, 1=front, 2=back
    bm.faces.ensure_lookup_table()
    del_ids = island_ids | back_pocket_ids | back_drop_ids
    to_del = []
    for f in bm.faces:
        if f.index in front_ids:
            f[layer] = 1
        elif f.index in clean_back_ids:
            f[layer] = 2
        else:
            f[layer] = 0
        if f.index in del_ids:
            to_del.append(f)

    bmesh.ops.delete(bm, geom=to_del, context="FACES")
    bm.faces.ensure_lookup_table()

    # Bisect Front panel cleanly ahead of the inward slit lip (y=-0.055 at z=0.578 -> y=-0.040 at z=0.89)
    side_f = [
        f for f in bm.faces
        if f[layer] == 1 and abs(f.calc_center_median().x) > 0.14 and f.calc_center_median().z < 0.90
    ]
    geom_f = list(side_f) + list({e for f in side_f for e in f.edges}) + list({v for f in side_f for v in f.verts})
    p_co = Vector((0.0, -0.055, 0.578))
    p_no = Vector((0.0, 1.0, -0.0480)).normalized()
    bmesh.ops.bisect_plane(
        bm, geom=geom_f, dist=0.0001, plane_co=p_co, plane_no=p_no,
        clear_outer=True, clear_inner=False,
    )
    bm.faces.ensure_lookup_table()

    # Bisect Back panel symmetrically behind hip axis (y=+0.035 at z=0.578 -> y=+0.020 at z=0.89)
    side_b = [
        f for f in bm.faces
        if f[layer] == 2 and abs(f.calc_center_median().x) > 0.14 and f.calc_center_median().z < 0.90
    ]
    geom_b = list(side_b) + list({e for f in side_b for e in f.edges}) + list({v for f in side_b for v in f.verts})
    bmesh.ops.bisect_plane(
        bm, geom=geom_b, dist=0.0001,
        plane_co=Vector((0.0, 0.035, 0.578)),
        plane_no=Vector((0.0, -1.0, -0.0480)).normalized(),
        clear_outer=True, clear_inner=False,
    )
    bm.faces.ensure_lookup_table()

    # Keep strictly one waist-connected sheet per panel
    f_comps = panel_components([f for f in bm.faces if f[layer] == 1])
    b_comps = panel_components([f for f in bm.faces if f[layer] == 2])
    extra_del = []
    if len(f_comps) > 1:
        extra_del.extend(f for c in f_comps[1:] for f in c)
    if len(b_comps) > 1:
        extra_del.extend(f for c in b_comps[1:] for f in c)
    if extra_del:
        bmesh.ops.delete(bm, geom=extra_del, context="FACES")
        bm.faces.ensure_lookup_table()

    # Prune any dangling single-edge ear triangles on the chaak boundaries
    while True:
        ears = [
            f for f in bm.faces
            if f[layer] in (1, 2)
            and abs(f.calc_center_median().x) > 0.15
            and f.calc_center_median().z < 0.96
            and sum(1 for e in f.edges if len(e.link_faces) > 1) <= 1
        ]
        if not ears:
            break
        bmesh.ops.delete(bm, geom=ears, context="FACES")
        bm.faces.ensure_lookup_table()

    for v in list(bm.verts):
        if not v.link_faces:
            bm.verts.remove(v)

    # Subdivide long kameez triangles in two passes so front/back bend smoothly over thighs
    for min_len, cuts in [(0.035, 2), (0.045, 1)]:
        edges = [
            e for e in bm.edges
            if any(f[layer] in (1, 2) for f in e.link_faces)
            and all(v.co.z < 0.99 for v in e.verts)
            and e.calc_length() > min_len
        ]
        if edges:
            bmesh.ops.subdivide_edges(bm, edges=edges, cuts=cuts, use_grid_fill=True)

    bm.faces.ensure_lookup_table()
    ngons = [f for f in bm.faces if f[layer] in (1, 2) and len(f.verts) > 3]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons)

    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    deform = bm.verts.layers.deform.active

    front_v_set = set()
    back_v_set = set()
    for i, v in enumerate(bm.verts):
        v.index = i
    for f in bm.faces:
        t = f[layer]
        if t == 1:
            for v in f.verts:
                front_v_set.add(v.index)
                v[deform][tag_idx] = 1.0
        elif t == 2:
            for v in f.verts:
                back_v_set.add(v.index)
                v[deform][tag_idx] = 1.0

    # Verify zero front/back sharing below the waist seam
    shared_below = {
        i for i in (front_v_set & back_v_set) if bm.verts[i].co.z < 1.034
    }
    assert len(shared_below) == 0, f"Front/Back still share {len(shared_below)} verts below waist!"

    front_faces_count = sum(1 for f in bm.faces if f[layer] == 1)
    back_faces_count = sum(1 for f in bm.faces if f[layer] == 2)
    bm.faces.layers.int.remove(layer)

    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    return front_v_set, back_v_set, front_faces_count, back_faces_count


def refit_upper_trousers(body, mesh, names, cloth):
    """De-bleed cross-leg trouser weights and clamp upper-trouser cylinder inside tunic."""
    refitted = 0
    for v in mesh.vertices:
        if v.index in cloth or not (0.42 < v.co.z < 0.98501):
            continue
        weights = {names[g.group]: g.weight for g in v.groups}
        lower_w = sum(
            weights.get(n, 0.0)
            for n in ["mixamorig:Hips", "mixamorig:LeftUpLeg", "mixamorig:RightUpLeg", "mixamorig:LeftLeg", "mixamorig:RightLeg"]
        )
        if lower_w < 0.85:
            continue

        # Eliminate opposite-leg weight bleeding on trousers
        if v.co.x < -0.005:
            w_opp_up = weights.get("mixamorig:LeftUpLeg", 0.0)
            w_opp_leg = weights.get("mixamorig:LeftLeg", 0.0)
            if w_opp_up > 0.0:
                body.vertex_groups["mixamorig:LeftUpLeg"].remove([v.index])
                body.vertex_groups["mixamorig:RightUpLeg"].add([v.index], weights.get("mixamorig:RightUpLeg", 0.0) + w_opp_up, "REPLACE")
            if w_opp_leg > 0.0:
                body.vertex_groups["mixamorig:LeftLeg"].remove([v.index])
                body.vertex_groups["mixamorig:RightLeg"].add([v.index], weights.get("mixamorig:RightLeg", 0.0) + w_opp_leg, "REPLACE")
        elif v.co.x > 0.005:
            w_opp_up = weights.get("mixamorig:RightUpLeg", 0.0)
            w_opp_leg = weights.get("mixamorig:RightLeg", 0.0)
            if w_opp_up > 0.0:
                body.vertex_groups["mixamorig:RightUpLeg"].remove([v.index])
                body.vertex_groups["mixamorig:LeftUpLeg"].add([v.index], weights.get("mixamorig:LeftUpLeg", 0.0) + w_opp_up, "REPLACE")
            if w_opp_leg > 0.0:
                body.vertex_groups["mixamorig:RightLeg"].remove([v.index])
                body.vertex_groups["mixamorig:LeftLeg"].add([v.index], weights.get("mixamorig:LeftLeg", 0.0) + w_opp_leg, "REPLACE")

        if v.co.z > 0.43:
            side = 1 if v.co.x >= 0.0 else -1
            z = v.co.z
            cx = side * (0.1256 + (0.8372 - z) * 0.0627)
            dx = v.co.x - cx
            dy = v.co.y - 0.015
            r = math.hypot(dx, dy)
            limit = 0.098
            t = max(0.0, min(1.0, (z - 0.43) / 0.085))
            t = t * t * (3.0 - 2.0 * t)
            if r > limit:
                scale = 1.0 - t + t * limit / r
                v.co.x = cx + dx * scale
                v.co.y = 0.015 + dy * scale
                refitted += 1
    mesh.update()
    return refitted


def panel_angle(side, col):
    """Control column angle in panel-local frame (Front: 0=-Y; Back: 0=+Y)."""
    span = HALF_FRONT if side == 0 else HALF_BACK
    return -span + col * (2.0 * span / 8.0)


def build_rest_grid():
    """Construct (NZ * NA, 3) rest grid matching separate Front and Back panel spans."""
    rest = []
    for j in range(NZ):
        t = j / (NZ - 1)
        z = LOW + (HIGH - LOW) * t
        rx = 0.25 - 0.052 * t
        ry = 0.166 - 0.029 * t
        for i in range(NA):
            side = 0 if i < 9 else 1
            a = panel_angle(side, i % 9)
            y_sign = -1.0 if side == 0 else 1.0
            rest.append((rx * math.sin(a), y_sign * ry * math.cos(a), z))
    return np.array(rest, dtype=np.float64)


def map_vertex_to_cage(co, side):
    """Map vertex coordinates cleanly within its explicit panel (side 0=Front, 1=Back)."""
    if side == 0:
        a = math.atan2(co.x, -co.y)
        span = HALF_FRONT
    else:
        a = math.atan2(co.x, co.y)
        span = HALF_BACK
    u = max(0.0, min(8.0, (a + span) / (2.0 * span) * 8.0))
    v = max(0.0, min(float(NZ - 1), (co.z - LOW) / (HIGH - LOW) * (NZ - 1)))
    col = min(7, int(u))
    row = min(NZ - 2, int(v))
    du = u - col
    dv = v - row
    base = side * 9 + col
    return [
        (row, base, (1.0 - du) * (1.0 - dv)),
        (row, base + 1, du * (1.0 - dv)),
        (row + 1, base, (1.0 - du) * dv),
        (row + 1, base + 1, du * dv),
    ]


def build_constraints(rest):
    """Build in-panel stretch, shear, and bending constraints (never linking across chaak)."""
    edges = []
    for j in range(NZ):
        for i in range(NA):
            n = j * NA + i
            if j < NZ - 1:
                edges.append((n, n + NA, 1.0))
            if i % 9 < 8:
                edges.append((n, n + 1, 1.0))
            if j < NZ - 1 and i % 9 < 8:
                edges.extend([(n, n + NA + 1, 0.2), (n + 1, n + NA, 0.2)])
            if j < NZ - 2:
                edges.append((n, n + 2 * NA, 0.07))
    ea = np.array([e[0] for e in edges], dtype=np.int32)
    eb = np.array([e[1] for e in edges], dtype=np.int32)
    stiff = np.array([e[2] for e in edges], dtype=np.float64)
    lengths = np.linalg.norm(rest[eb] - rest[ea], axis=1)
    mass = np.ones(len(rest), dtype=np.float64)
    mass[-NA:] = 0.0
    denom = np.maximum(mass[ea] + mass[eb], 1e-8)

    colors = []
    for e_idx, (a, b, _) in enumerate(edges):
        for used, ids in colors:
            if a not in used and b not in used:
                used.update((a, b))
                ids.append(e_idx)
                break
        else:
            colors.append(({a, b}, [e_idx]))
    colors = [np.array(ids, dtype=np.int32) for _, ids in colors]
    return ea, eb, stiff, lengths, mass, denom, colors


def get_tapered_capsules(rig):
    """Return tapered leg/groin/pelvis collision capsules with kick-lift awareness."""
    out = []
    l_hip = np.array(rig.matrix_world @ rig.pose.bones["mixamorig:LeftUpLeg"].head, dtype=np.float64)
    r_hip = np.array(rig.matrix_world @ rig.pose.bones["mixamorig:RightUpLeg"].head, dtype=np.float64)
    pelvis_mid = 0.5 * (l_hip + r_hip) + np.array([0.0, 0.0, 0.045], dtype=np.float64)
    for side in ["Left", "Right"]:
        p = rig.pose.bones["mixamorig:" + side + "UpLeg"]
        q = rig.pose.bones["mixamorig:" + side + "Leg"]
        a_up = np.array(rig.matrix_world @ p.head, dtype=np.float64)
        b_up = np.array(rig.matrix_world @ p.tail, dtype=np.float64)
        ab_up = b_up - a_up
        thigh_dir = ab_up / max(float(np.linalg.norm(ab_up)), 1e-8)
        lift = float(np.clip((thigh_dir[2] - (-0.90)) / 0.90, 0.0, 1.0))

        # Tapered capsule radius & lift-adaptive clearance + groin crease bridge
        r_hip_c = 0.148 + 0.028 * lift
        r_knee_c = 0.136 + 0.032 * lift
        out.append((a_up, b_up, r_hip_c, r_knee_c, lift, True))

        mid_thigh = 0.45 * a_up + 0.55 * b_up
        out.append((pelvis_mid, mid_thigh, 0.146 + 0.026 * lift, 0.140 + 0.028 * lift, lift, True))

        a_leg = np.array(rig.matrix_world @ q.head, dtype=np.float64)
        b_leg = np.array(rig.matrix_world @ q.tail, dtype=np.float64)
        out.append((a_leg, b_leg, 0.126 + 0.020 * lift, 0.112 + 0.014 * lift, lift, True))

    out.append((l_hip, r_hip, 0.144, 0.144, 0.0, False))
    return out


def is_front_mask():
    m = np.zeros(NZ * NA, dtype=bool)
    for j in range(NZ - 1):
        m[j * NA : j * NA + 9] = True
    return m


def is_back_mask():
    m = np.zeros(NZ * NA, dtype=bool)
    for j in range(NZ - 1):
        m[j * NA + 9 : (j + 1) * NA] = True
    return m


FRONT_MOVABLE = is_front_mask()
BACK_MOVABLE = is_back_mask()


def collide_tapered(x, caps, pin, ea, eb, mass, up_fwd_vec, back_vec):
    """Push cage nodes & edges outside tapered capsules; bias lifted-thigh contacts over top of front sheet."""
    for a, b, r0, r1, lift, is_thigh in caps:
        ab = b - a
        ab2 = max(float(np.dot(ab, ab)), 1e-8)
        t = np.clip(((x - a) * ab).sum(axis=1) / ab2, 0.0, 1.0)
        r = r0 * (1.0 - t) + r1 * t
        d = x - (a + t[:, None] * ab)
        dist = np.linalg.norm(d, axis=1)
        n = d / np.maximum(dist[:, None], 1e-8)

        # Keep Front panel on top/in front of rising thigh during high kicks/punches
        if is_thigh and lift > 0.12:
            flip = FRONT_MOVABLE & (dist < r) & (d[:, 2] < 0.25 * r)
            if np.any(flip):
                biased = n[flip] + up_fwd_vec[None, :] * (0.95 * lift)
                biased /= np.maximum(np.linalg.norm(biased, axis=1, keepdims=True), 1e-8)
                n[flip] = biased
        if is_thigh:
            b_hit = BACK_MOVABLE & (dist < r)
            if np.any(b_hit):
                biased_b = n[b_hit] + back_vec[None, :] * 0.75
                biased_b /= np.maximum(np.linalg.norm(biased_b, axis=1, keepdims=True), 1e-8)
                n[b_hit] = biased_b

        x += n * np.maximum(r - dist, 0.0)[:, None] * mass[:, None]

    # Mid-edge capsule check so edges cannot slice across a raised thigh
    for a, b, r0, r1, lift, _ in caps:
        ab = b - a
        ab2 = max(float(np.dot(ab, ab)), 1e-8)
        for fraction in (0.25, 0.5, 0.75):
            samples = x[ea] * (1.0 - fraction) + x[eb] * fraction
            t = np.clip(((samples - a) * ab).sum(axis=1) / ab2, 0.0, 1.0)
            r = r0 * (1.0 - t) + r1 * t
            d = samples - (a + t[:, None] * ab)
            dist = np.linalg.norm(d, axis=1)
            n = d / np.maximum(dist[:, None], 1e-8)
            correction = n * np.maximum(r - dist, 0.0)[:, None]
            accum = np.zeros_like(x)
            counts = np.zeros(len(x), dtype=np.float64)
            np.add.at(accum, ea, correction * mass[ea, None])
            np.add.at(accum, eb, correction * mass[eb, None])
            hit = dist < r
            np.add.at(counts, ea, hit * mass[ea])
            np.add.at(counts, eb, hit * mass[eb])
            x += accum / np.maximum(counts[:, None], 1.0)

    x[-NA:] = pin


def smooth_displacement_grid(x, target):
    """Smooth displacement (x - target) within each panel to preserve curved rest shape."""
    disp = (x - target).reshape(NZ, NA, 3)
    nxt = disp.copy()
    for j in range(NZ - 1):
        for offset in (0, 9):
            row = disp[j, offset : offset + 9]
            out_row = nxt[j, offset : offset + 9]
            out_row[1:8] = 0.84 * row[1:8] + 0.08 * row[0:7] + 0.08 * row[2:9]
            out_row[0] = 0.90 * row[0] + 0.10 * row[1]
            out_row[8] = 0.90 * row[8] + 0.10 * row[7]
    horiz = nxt.copy()
    for j in range(1, NZ - 1):
        nxt[j] = 0.90 * horiz[j] + 0.05 * horiz[j - 1] + 0.05 * horiz[j + 1]
    nxt[0] = 0.92 * horiz[0] + 0.08 * horiz[1]
    nxt[NZ - 1] = 0.0
    return target + nxt.reshape(NZ * NA, 3)


def main():
    scene = bpy.data.scenes["Khan_Garment_Prototype"]
    bpy.context.window.scene = scene
    body = bpy.data.objects["Khan_Garment_Body"]
    rig = bpy.data.objects["Khan_Garment_Rig"]
    mesh = body.data
    assert len(rig.data.bones) == 59 and mesh.shape_keys is None

    for tr in rig.animation_data.nla_tracks:
        tr.mute = True
    for slot in body.material_slots:
        if slot.material:
            slot.material.use_backface_culling = False

    rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()

    tag_idx = body.vertex_groups["Kameez_Surface"].index
    front_v_set, back_v_set, front_faces_count, back_faces_count = clean_chaak_and_subdivide(body, mesh, tag_idx)
    cloth = front_v_set | back_v_set
    names = {g.index: g.name for g in body.vertex_groups}
    saved = {
        i: {names[g.group]: g.weight for g in mesh.vertices[i].groups if names[g.group] in rig.data.bones}
        for i in cloth
    }

    refitted = refit_upper_trousers(body, mesh, names, cloth)

    uv = np.empty(len(mesh.uv_layers.active.data) * 2, dtype=np.float32)
    mesh.uv_layers.active.data.foreach_get("uv", uv)

    rest = build_rest_grid()
    ea, eb, stiff, lengths, mass, denom, colors = build_constraints(rest)

    # Create 18x10 drape bones parented to mixamorig:Hips
    for o in scene.objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    inv = rig.matrix_world.inverted()
    for j in range(NZ):
        for i in range(NA):
            b = rig.data.edit_bones.new(f"drape_{j}_{i}")
            b.head = inv @ Vector(rest[j * NA + i])
            b.tail = b.head + Vector((0.0, 0.025, 0.0))
            b.parent = rig.data.edit_bones["mixamorig:Hips"]
    bpy.ops.object.mode_set(mode="OBJECT")

    groups = {(j, i): body.vertex_groups.new(name=f"drape_{j}_{i}") for j in range(NZ) for i in range(NA)}
    for idx in cloth:
        v = mesh.vertices[idx]
        if v.co.z > 0.96:
            t_w = min(1.0, (v.co.z - 0.96) / (HIGH - 0.96))
            w_hips = t_w * t_w
        else:
            w_hips = 0.0

        for n in saved[idx]:
            body.vertex_groups[n].remove([idx])
        for n, w in saved[idx].items():
            if w_hips * w > 1e-8:
                body.vertex_groups[n].add([idx], w_hips * w, "REPLACE")

        # Explicit panel membership (Front vs Back) — NEVER use co.y <= 0!
        if idx in front_v_set and idx not in back_v_set:
            side = 0
        elif idx in back_v_set and idx not in front_v_set:
            side = 1
        else:
            # Only the 2 extreme waist corner verts at z >= 1.034 (w_hips == 1.0)
            side = 0
        for j, i, w in map_vertex_to_cage(v.co, side):
            if w * (1.0 - w_hips) > 1e-8:
                groups[j, i].add([idx], w * (1.0 - w_hips), "REPLACE")

    rig.data.pose_position = "POSE"
    hips = rig.pose.bones["mixamorig:Hips"]

    def hips_delta():
        return rig.matrix_world @ hips.matrix @ hips.bone.matrix_local.inverted() @ rig.matrix_world.inverted()

    def solve_step(x, prev, pin, caps, dt, up_fwd_vec, back_vec, target, apply_recovery=True):
        old = x.copy()
        vel = (x - prev) * 0.965
        vel *= np.minimum(1.0, 0.04 / np.maximum(np.linalg.norm(vel, axis=1), 1e-8))[:, None]
        x += vel
        x[:, 2] -= 9.81 * dt * dt
        if apply_recovery:
            x += (target - x) * 0.022 * mass[:, None]
        x = smooth_displacement_grid(x, target)
        x[-NA:] = pin
        for _ in range(16):
            for ids in colors:
                a = ea[ids]
                b = eb[ids]
                d = x[b] - x[a]
                l = np.linalg.norm(d, axis=1)
                corr = d * ((l - lengths[ids]) * stiff[ids] / np.maximum(l, 1e-8) / denom[ids])[:, None]
                x[a] += corr * mass[a, None]
                x[b] -= corr * mass[b, None]
            collide_tapered(x, caps, pin, ea, eb, mass, up_fwd_vec, back_vec)
        return x, old

    records = []
    for clip in ["Idle", "Idle2", "Punch", "MmaKick"]:
        original = bpy.data.actions["Khan_" + clip]
        action = original.copy()
        action.name = "Draped_" + clip
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        start, end = map(int, original.frame_range)
        scene.frame_set(start)
        bpy.context.view_layer.update()

        m = hips_delta()
        x_init = np.array([m @ Vector(p) for p in rest], dtype=np.float64)
        x = x_init.copy()
        caps = get_tapered_capsules(rig)
        directions = np.array([
            m.to_3x3() @ Vector((
                math.sin(panel_angle(0 if (i % NA) < 9 else 1, i % 9)),
                (-1.0 if (i % NA) < 9 else 1.0) * math.cos(panel_angle(0 if (i % NA) < 9 else 1, i % 9)),
                0.0,
            ))
            for i in range(len(rest))
        ], dtype=np.float64)
        fwd_vec = np.array((m.to_3x3() @ Vector((0.0, -0.55, 0.85))).normalized(), dtype=np.float64)
        back_vec = np.array((m.to_3x3() @ Vector((0.0, 0.90, -0.15))).normalized(), dtype=np.float64)

        for _ in range(65):
            for a, b, r0, r1, _, _ in caps:
                ab = b - a
                t = np.clip(((x - a) * ab).sum(axis=1) / max(float(np.dot(ab, ab)), 1e-8), 0.0, 1.0)
                r = r0 * (1.0 - t) + r1 * t
                dist = np.linalg.norm(x - (a + t[:, None] * ab), axis=1)
                x += directions * ((dist < r) * 0.008 * mass)[:, None]
        prev = x.copy()
        for _ in range(75):
            x, prev = solve_step(x, prev, x[-NA:].copy(), caps, 1.0 / 90.0, fwd_vec, back_vec, x_init, apply_recovery=False)

        all_offsets = []
        maxstretch = 0.0
        old_caps = caps
        old_pin = x[-NA:].copy()
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            m = hips_delta()
            mi = m.inverted()
            caps = get_tapered_capsules(rig)
            pin = np.array([m @ Vector(p) for p in rest[-NA:]], dtype=np.float64)
            fwd_vec = np.array((m.to_3x3() @ Vector((0.0, -0.55, 0.85))).normalized(), dtype=np.float64)
            back_vec = np.array((m.to_3x3() @ Vector((0.0, 0.90, -0.15))).normalized(), dtype=np.float64)
            target = np.array([m @ Vector(p) for p in rest], dtype=np.float64)
            for sub in range(3):
                frac = (sub + 1) / 3.0
                inter = [
                    (a0 * (1.0 - frac) + a * frac, b0 * (1.0 - frac) + b * frac, r0, r1, lift, is_t)
                    for (a0, b0, _, _, _, _), (a, b, r0, r1, lift, is_t) in zip(old_caps, caps)
                ]
                x, prev = solve_step(x, prev, old_pin * (1.0 - frac) + pin * frac, inter, 1.0 / 90.0, fwd_vec, back_vec, target)
            old_caps = caps
            old_pin = pin

            offset = np.array([mi @ Vector(p) for p in x], dtype=np.float64) - rest
            assert np.isfinite(offset).all() and np.abs(offset).max() < 1.0, (clip, frame)
            all_offsets.append(offset)
            maxstretch = max(maxstretch, float(np.max(np.linalg.norm(x[eb] - x[ea], axis=1) / lengths)))
            if frame % 30 == 0:
                print("DRAPE", clip, frame, flush=True)

        inv3 = inv.to_3x3()
        bone_inv = {
            (j, i): rig.pose.bones[f"drape_{j}_{i}"].bone.matrix_local.to_3x3().inverted() @ inv3
            for (j, i) in groups
        }
        for k, frame in enumerate(range(start, end + 1)):
            for (j, i) in groups:
                p = rig.pose.bones[f"drape_{j}_{i}"]
                p.location = bone_inv[j, i] @ Vector(all_offsets[k][j * NA + i])
                p.keyframe_insert("location", frame=frame, group="Draped garment")

        cb = action.layers[0].strips[0].channelbag(action.slots[0])
        for fc in cb.fcurves:
            if fc.data_path.startswith('pose.bones["drape_'):
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"

        for track in rig.animation_data.nla_tracks:
            if track.name == clip:
                track.strips[0].action = action
                track.strips[0].action_slot = action.slots[0]

        records.append({
            "clip": clip,
            "frames": len(all_offsets),
            "max_control_edge_stretch": maxstretch,
            "end_start_offset_rms_m": float(np.sqrt(np.mean((all_offsets[-1] - all_offsets[0]) ** 2))),
        })
        print(records[-1], flush=True)

    for slot in body.material_slots:
        if slot.material:
            slot.material.use_backface_culling = False

    rig.animation_data.action = None
    for tr in rig.animation_data.nla_tracks:
        tr.mute = False
    for o in scene.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    glb_path = ROOT / "game/assets/characters/khan_recovery_trial.glb"
    bpy.ops.export_scene.gltf(
        export_format="GLB",
        filepath=str(glb_path),
        use_selection=True,
        use_active_scene=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=False,
        export_rest_position_armature=True,
        export_skins=True,
        export_influence_nb=8,
        export_all_influences=False,
        export_apply=False,
    )

    for tr in rig.animation_data.nla_tracks:
        tr.mute = True
    rig.animation_data.action = bpy.data.actions["Draped_Idle2"]
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
    scene.frame_set(1)

    uv2 = np.empty_like(uv)
    mesh.uv_layers.active.data.foreach_get("uv", uv2)
    assert np.array_equal(uv, uv2)

    (OUT / "inspection/recovery-trial-build.json").write_text(
        json.dumps(
            {
                "clips": records,
                "front_faces": front_faces_count,
                "back_faces": back_faces_count,
                "front_vertices": len(front_v_set),
                "back_vertices": len(back_v_set),
                "refitted_artificial_upper_trouser_vertices": refitted,
                "uv_unchanged": True,
                "status": "Side-slit webbing removed; separated front/back control cage; awaiting visual acceptance.",
            },
            indent=2,
        )
    )
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "blender/khan-model2-recovery-trial.blend"))


if __name__ == "__main__":
    main()
