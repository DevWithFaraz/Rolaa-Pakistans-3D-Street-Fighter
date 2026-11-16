import bpy
import bmesh
import json
import math
import os
from collections import deque
from mathutils import Matrix, Vector

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model2"
WORK_BLEND = os.path.join(ROOT, "blender", "asim-model2-working.blend")
OPT_BLEND = os.path.join(ROOT, "blender", "asim-model2-optimization-trial.blend")
OPT_JSON = os.path.join(ROOT, "inspection", "optimization-trial.json")
INSP_DIR = os.path.join(ROOT, "inspection")

TARGET_TRIANGLES = 152000
ABDUCT_DEG = 36.0


def smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def calibrate_decimate_invert_flag() -> bool:
    """Verify invert_vertex_group setting so low CollapsePriority (0.16) stays denser than high (0.68)."""
    mesh = bpy.data.meshes.new("_cal_mesh")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=12, y_segments=12, size=1.0)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("_cal_obj", mesh)
    bpy.context.scene.collection.objects.link(obj)
    vg = obj.vertex_groups.new(name="CollapsePriority")
    left = [v.index for v in mesh.vertices if v.co.x < 0.0]
    right = [v.index for v in mesh.vertices if v.co.x >= 0.0]
    vg.add(left, 0.16, 'REPLACE')
    vg.add(right, 0.68, 'REPLACE')

    mod = obj.modifiers.new(name="Dec", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = 0.25
    mod.vertex_group = "CollapsePriority"
    mod.vertex_group_factor = 1.0
    mod.invert_vertex_group = False

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    left_after = sum(1 for v in obj.data.vertices if v.co.x < 0.0)
    right_after = sum(1 for v in obj.data.vertices if v.co.x >= 0.0)

    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    invert_needed = left_after < right_after
    print(f"[CALIBRATE] left(w=0.16)={left_after}, right(w=0.68)={right_after} -> invert_vertex_group={invert_needed}")
    return invert_needed


def collapse_priority_weight(p: Vector, is_arm: bool) -> float:
    """Bounded CollapsePriority in [0.16, 0.68]: low preserves detail, high collapses uniform cloth."""
    ax = abs(p.x)
    # 1. Head, cap dome/visor, emblems, face, neck
    if p.z >= 1.50:
        return 0.16 if (p.y < 0.04 or p.z >= 1.62) else 0.36
    if p.z >= 1.455:
        return 0.24

    # 2. A-posed (measured pre-abduction) 5-fingered hands & cuffs
    if is_arm:
        if p.z <= 0.80:
            return 0.16  # 5 fingers & palm highest protection
        if p.z <= 0.865:
            return 0.26  # wrist cuff
        if 1.02 <= p.z <= 1.18:
            return 0.36  # elbow joint bend
        if p.z >= 1.24:
            return 0.24  # arm patch & deltoid shoulder cap
        return 0.56      # mid-forearm / upper-sleeve cloth

    # 3. Torso, epaulettes, medals, sash, belt, tunic hem
    if p.z >= 1.36 and ax >= 0.08:
        return 0.22      # epaulettes / collar tabs
    if 1.06 <= p.z <= 1.455:
        if p.y < 0.03 and ax <= 0.18:
            return 0.24  # chest medals, ribbons, collar, tie, sash
        return 0.68      # plain upper back / side cloth
    if 0.84 <= p.z < 1.06:
        if p.y < 0.06 or p.z <= 1.01:
            return 0.28  # belt, sash dangle, pocket flaps
        return 0.60
    if 0.68 <= p.z < 0.84:
        return 0.42      # lower tunic hem / hip bend seam

    # 4. Trousers, knees, boots
    if p.z <= 0.165:
        return 0.22      # boots, laces & soles
    if 0.38 <= p.z <= 0.56:
        return 0.38      # knee bend density
    return 0.64          # straight thigh/calf trouser cloth


def apply_apose_and_measure_landmarks(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.active
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Sample khaki cloth UV for cap micro-UV
    sample_uvs = []
    for f in bm.faces:
        c = f.calc_center_median()
        if 1.12 <= c.z <= 1.20 and 0.14 <= c.x <= 0.17 and -0.02 <= c.y <= 0.08:
            for lp in f.loops:
                sample_uvs.append(lp[uv_layer].uv.copy())
            if len(sample_uvs) > 20:
                break
    khaki_uv = Vector((
        sum(u.x for u in sample_uvs) / len(sample_uvs),
        sum(u.y for u in sample_uvs) / len(sample_uvs),
    ))

    def planar_khaki_uv(co: Vector) -> Vector:
        return Vector((
            khaki_uv.x + (co.y - 0.04) * 0.015,
            khaki_uv.y + (co.z - 1.20) * 0.015,
        ))

    torso_cap_faces = set()
    arm_cap_faces = set()
    cap_interior_verts = set()
    rim_verts_smooth = set()
    shared_rim_verts = set()
    torso_tuck_pairs = []  # (torso_only_rim, torso_1ring)

    for side in (+1.0, -1.0):
        # Medial bisect seam so no rib lip protrudes and front/back exit cleanly into free air
        p_bot = Vector((side * 0.180, 0.0, 1.130))
        p_top = Vector((side * 0.186, 0.0, 1.285))
        tangent = (p_top - p_bot).normalized()
        n_vec = Vector((side * tangent.z, 0.0, -side * tangent.x)).normalized()

        def seam_x(z: float) -> float:
            t = (z - 1.130) / (1.285 - 1.130)
            return 0.180 + t * (0.186 - 0.180)

        cut_geom = [
            f for f in bm.faces
            if (lambda c: 1.100 <= c.z <= 1.295 and 0.155 <= side * c.x <= 0.220 and -0.22 <= c.y <= 0.22)(
                f.calc_center_median()
            )
        ]
        cut_edges = {e for f in cut_geom for e in f.edges}
        cut_verts = {v for f in cut_geom for v in f.verts}

        res = bmesh.ops.bisect_plane(
            bm,
            geom=list(cut_geom) + list(cut_edges) + list(cut_verts),
            dist=1e-5,
            plane_co=p_bot,
            plane_no=n_vec,
            use_snap_center=False,
            clear_outer=False,
            clear_inner=False,
        )
        bm.verts.ensure_lookup_table()
        bm.edges.ensure_lookup_table()

        split_edges = []
        for elem in res.get("geom_cut", []):
            if isinstance(elem, bmesh.types.BMEdge):
                m = (elem.verts[0].co + elem.verts[1].co) * 0.5
                if 1.105 <= m.z <= 1.285 and 0.155 <= side * m.x <= 0.218 and -0.22 <= m.y <= 0.22:
                    split_edges.append(elem)

        before_b = {e for e in bm.edges if e.is_boundary}
        bmesh.ops.split_edges(bm, edges=split_edges)
        bm.verts.ensure_lookup_table()
        bm.edges.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        new_b = [e for e in bm.edges if e.is_boundary and e not in before_b]

        torso_e, arm_e = [], []
        for e in new_b:
            if not e.link_faces:
                continue
            fc = e.link_faces[0].calc_center_median()
            if side * fc.x < seam_x(fc.z):
                torso_e.append(e)
            else:
                arm_e.append(e)

        torso_bverts = {v for e in torso_e for v in e.verts}
        arm_bverts = {v for e in arm_e for v in e.verts}
        shared_here = torso_bverts & arm_bverts
        shared_rim_verts.update(shared_here)
        rim_verts_smooth.update((torso_bverts | arm_bverts) - shared_here)

        torso_only_rim = torso_bverts - shared_here
        torso_1ring = set()
        for rv in torso_only_rim:
            for e in rv.link_edges:
                nb = e.other_vert(rv)
                if nb not in torso_bverts and nb not in arm_bverts:
                    if side * nb.co.x < seam_x(nb.co.z) + 0.002:
                        torso_1ring.add(nb)
        torso_tuck_pairs.append((side, torso_only_rim, torso_1ring))

        for is_torso, group_e, offset_x in [(True, torso_e, -side * 0.008), (False, arm_e, +side * 0.008)]:
            if not group_e:
                continue
            bverts = list({v for e in group_e for v in e.verts})
            center = sum((v.co for v in bverts), Vector((0, 0, 0))) / len(bverts)
            center.x += offset_x
            v_c = bm.verts.new(center)
            cap_interior_verts.add(v_c)
            spoke_edges = set()
            target_fset = torso_cap_faces if is_torso else arm_cap_faces

            for e in group_e:
                lf = e.link_faces[0]
                v0, v1 = e.verts[0], e.verts[1]
                lp_verts = [lp.vert for lp in lf.loops]
                idx0 = lp_verts.index(v0)
                next_v = lp_verts[(idx0 + 1) % len(lp_verts)]
                tri = (v1, v0, v_c) if next_v == v1 else (v0, v1, v_c)
                try:
                    nf = bm.faces.new(tri)
                    target_fset.add(nf)
                    for ne in nf.edges:
                        if v_c in ne.verts:
                            spoke_edges.add(ne)
                    if uv_layer:
                        for lp in nf.loops:
                            lp[uv_layer].uv = planar_khaki_uv(lp.vert.co)
                except ValueError:
                    pass

            if spoke_edges:
                before_faces = set(bm.faces)
                sub_res = bmesh.ops.subdivide_edges(bm, edges=list(spoke_edges), cuts=3, use_grid_fill=False)
                bm.faces.ensure_lookup_table()
                added_faces = set(bm.faces) - before_faces
                target_fset.update(added_faces)
                for f in list(target_fset):
                    if not f.is_valid:
                        target_fset.discard(f)
                for f in added_faces:
                    if uv_layer and f.is_valid:
                        for lp in f.loops:
                            lp[uv_layer].uv = planar_khaki_uv(lp.vert.co)
                for k in ("geom", "geom_inner", "geom_split"):
                    for g in sub_res.get(k, []):
                        if isinstance(g, bmesh.types.BMVert) and g.is_valid:
                            cap_interior_verts.add(g)

    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Tuck torso rim & 1-ring border slightly inward (feathered < 1.275) so rib stays clean
    for side, torso_only_rim, torso_1ring in torso_tuck_pairs:
        for rv in torso_only_rim:
            if rv.is_valid and rv.co.z < 1.275:
                fade = smoothstep((1.275 - rv.co.z) / (1.275 - 1.220))
                rv.co.x += (-side * 0.008) * fade
        for rv in torso_1ring:
            if rv.is_valid and rv.co.z < 1.275:
                fade = smoothstep((1.275 - rv.co.z) / (1.275 - 1.220))
                rv.co.x += (-side * 0.004) * fade

    torso_cap_faces = {f for f in torso_cap_faces if f.is_valid}
    arm_cap_faces = {f for f in arm_cap_faces if f.is_valid}
    all_cap_faces = torso_cap_faces | arm_cap_faces

    for _ in range(2):
        bmesh.ops.smooth_vert(
            bm, verts=[v for v in rim_verts_smooth if v.is_valid],
            factor=0.35, use_axis_x=True, use_axis_y=True, use_axis_z=True
        )
    for _ in range(10):
        bmesh.ops.smooth_vert(
            bm, verts=[v for v in cap_interior_verts if v.is_valid],
            factor=0.50, use_axis_x=True, use_axis_y=True, use_axis_z=True
        )

    if uv_layer:
        for f in all_cap_faces:
            if f.is_valid:
                f.smooth = True
                for lp in f.loops:
                    lp[uv_layer].uv = planar_khaki_uv(lp.vert.co)

    bmesh.ops.recalc_face_normals(bm, faces=[f for f in all_cap_faces if f.is_valid])

    b_count = sum(1 for e in bm.edges if e.is_boundary)
    nm_count = sum(1 for e in bm.edges if not e.is_manifold)
    print(f"[ARMPIT_CAPS] boundary_edges={b_count}, nonmanifold_edges={nm_count}")

    all_torso_cap_verts = {v for f in torso_cap_faces if f.is_valid for v in f.verts}
    all_arm_cap_verts = {v for f in arm_cap_faces if f.is_valid for v in f.verts}
    pure_torso_block = all_torso_cap_verts - shared_rim_verts

    orig_co = {v: v.co.copy() for v in bm.verts}
    all_arm_verts = set()

    for side in (+1.0, -1.0):
        arm_verts = set()
        q = deque()
        for v in bm.verts:
            p = orig_co[v]
            if side * p.x > 0.265 and 0.65 <= p.z <= 0.92:
                arm_verts.add(v)
                q.append(v)
        while q:
            cur = q.popleft()
            for e in cur.link_edges:
                if any(f in torso_cap_faces for f in e.link_faces):
                    continue
                nb = e.other_vert(cur)
                if nb not in arm_verts:
                    p = orig_co[nb]
                    if nb in pure_torso_block or nb in shared_rim_verts:
                        continue
                    if p.z < 1.125 and side * p.x < 0.200:
                        continue
                    sx_cut = 0.180 + max(0.0, (p.z - 1.130) / (1.285 - 1.130)) * (0.186 - 0.180)
                    if p.z < 1.285 and (
                        nb in all_arm_cap_verts or not (p.z >= 1.125 and side * p.x < sx_cut - 0.002)
                    ):
                        arm_verts.add(nb)
                        q.append(nb)

        zs_a = [orig_co[v].z for v in arm_verts]
        assert min(zs_a) > 0.65, f"Arm flood leaked to z={min(zs_a):.3f}"
        all_arm_verts.update(arm_verts)

        pivot = Vector((side * 0.192, 0.028, 1.355))
        angle = (-side) * math.radians(ABDUCT_DEG)
        moved = 0
        for v in bm.verts:
            p = orig_co[v]
            w = 0.0
            if v in arm_verts:
                if p.z <= 1.210:
                    w = 1.0
                else:
                    t_z = smoothstep((1.285 - p.z) / (1.285 - 1.210))
                    s_x = smoothstep((side * p.x - 0.186) / (0.256 - 0.186))
                    w = t_z + (1.0 - t_z) * s_x
            elif 1.285 <= p.z <= 1.448 and side * p.x >= 0.186:
                s_x = smoothstep((side * p.x - 0.186) / (0.256 - 0.186))
                s_z = smoothstep((1.448 - p.z) / (1.448 - 1.330))
                w = s_x * s_z

            if w > 0.001:
                local_rot = Matrix.Rotation(angle * w, 4, 'Y')
                v.co = pivot + (local_rot @ (p - pivot))
                moved += 1
        print(f"[ABDUCT] side={side:+.0f} arm_verts={len(arm_verts)} moved={moved}")

    stretched = [
        (e.verts[0].co - e.verts[1].co).length - (orig_co[e.verts[0]] - orig_co[e.verts[1]]).length
        for e in bm.edges
    ]
    max_growth = max(stretched) if stretched else 0.0
    print(f"[STRETCH] Max edge growth={max_growth:.4f}m, count>3cm={sum(1 for d in stretched if d > 0.03)}")
    assert max_growth < 0.025, f"Unexpected armpit stretch: {max_growth:.4f}"

    # Measure Mixamo landmarks in A-pose using known pre-abduction anatomical regions
    bm.verts.ensure_lookup_table()
    weights_by_idx = {}
    chin_pts = []
    wrists = {+1.0: [], -1.0: []}
    elbows = {+1.0: [], -1.0: []}
    knees = {+1.0: [], -1.0: []}

    for idx, v in enumerate(bm.verts):
        p = orig_co[v]
        is_arm = v in all_arm_verts
        weights_by_idx[idx] = collapse_priority_weight(p, is_arm)

        if 1.495 <= p.z <= 1.525 and abs(p.x) <= 0.025 and p.y < -0.055:
            chin_pts.append(v.co.copy())
        if is_arm:
            s = +1.0 if p.x > 0.0 else -1.0
            if 0.785 <= p.z <= 0.815:
                wrists[s].append(v.co.copy())
            elif 1.075 <= p.z <= 1.115:
                elbows[s].append(v.co.copy())
        else:
            if 0.455 <= p.z <= 0.495 and abs(p.x) >= 0.045:
                s = +1.0 if p.x > 0.0 else -1.0
                knees[s].append(v.co.copy())

    def avg_pt(pts, fallback):
        if not pts:
            return fallback
        c = sum(pts, Vector((0, 0, 0))) / len(pts)
        return [round(c.x, 4), round(c.y, 4), round(c.z, 4)]

    landmarks = {
        "chin": avg_pt(chin_pts, [0.0, -0.09, 1.505]),
        "wrist_char_left_posX": avg_pt(wrists[+1.0], [0.58, 0.0, 0.97]),
        "wrist_char_right_negX": avg_pt(wrists[-1.0], [-0.58, 0.0, 0.97]),
        "elbow_char_left_posX": avg_pt(elbows[+1.0], [0.40, 0.04, 1.19]),
        "elbow_char_right_negX": avg_pt(elbows[-1.0], [-0.40, 0.04, 1.19]),
        "knee_char_left_posX": avg_pt(knees[+1.0], [0.14, 0.01, 0.475]),
        "knee_char_right_negX": avg_pt(knees[-1.0], [-0.14, 0.01, 0.475]),
        "groin": [0.0, -0.02, 0.86],
    }

    for f in bm.faces:
        f.smooth = True
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    # Assign CollapsePriority vertex group cleanly by index
    for existing in list(obj.vertex_groups):
        obj.vertex_groups.remove(existing)
    vg = obj.vertex_groups.new(name="CollapsePriority")
    for idx, w in weights_by_idx.items():
        vg.add([idx], w, 'REPLACE')

    return b_count, nm_count, round(max_growth, 4), landmarks


def count_region_tris(obj) -> dict:
    buckets = {
        "footwear (z<0.16)": 0,
        "legs (0.16..0.75)": 0,
        "torso_tunic (0.75..1.46, |x|<0.47)": 0,
        "arms_hands_abducted (z<1.12, |x|>=0.45)": 0,
        "head_cap (z>=1.46)": 0,
        "shoulders_upper_sleeves_other": 0,
    }
    verts = obj.data.vertices
    for p in obj.data.polygons:
        c = sum((verts[vi].co for vi in p.vertices), Vector((0, 0, 0))) / len(p.vertices)
        ntris = max(1, len(p.vertices) - 2)
        if c.z < 0.16:
            buckets["footwear (z<0.16)"] += ntris
        elif c.z >= 1.46:
            buckets["head_cap (z>=1.46)"] += ntris
        elif c.z < 0.75 and abs(c.x) < 0.45:
            buckets["legs (0.16..0.75)"] += ntris
        elif c.z < 1.12 and abs(c.x) >= 0.45:
            buckets["arms_hands_abducted (z<1.12, |x|>=0.45)"] += ntris
        elif abs(c.x) < 0.47:
            buckets["torso_tunic (0.75..1.46, |x|<0.47)"] += ntris
        else:
            buckets["shoulders_upper_sleeves_other"] += ntris
    return buckets


def main():
    bpy.ops.wm.open_mainfile(filepath=WORK_BLEND)
    src = bpy.data.objects["Asim_Model2_Working"]

    # Remove old trial if regenerating
    if "Asim_Model2_Optimization_Trial" in bpy.data.objects:
        old = bpy.data.objects["Asim_Model2_Optimization_Trial"]
        bpy.data.objects.remove(old, do_unlink=True)

    trial = src.copy()
    trial.data = src.data.copy()
    trial.name = "Asim_Model2_Optimization_Trial"
    trial.data.name = "Asim_Model2_Optimization_Trial_Mesh"
    for col in src.users_collection:
        col.objects.link(trial)
    src.hide_viewport = True
    src.hide_render = True
    src.select_set(False)
    trial.hide_viewport = False
    trial.hide_render = False

    b_caps, nm_caps, max_growth, landmarks = apply_apose_and_measure_landmarks(trial)

    source_tris = sum(max(1, len(p.vertices) - 2) for p in trial.data.polygons)
    invert_flag = calibrate_decimate_invert_flag()
    ratio = TARGET_TRIANGLES / float(source_tris)

    bpy.context.view_layer.objects.active = trial
    trial.select_set(True)
    dec = trial.modifiers.new(name="TargetedDecimate", type='DECIMATE')
    dec.decimate_type = 'COLLAPSE'
    dec.ratio = ratio
    dec.vertex_group = "CollapsePriority"
    dec.vertex_group_factor = 1.0
    dec.invert_vertex_group = invert_flag
    bpy.ops.object.modifier_apply(modifier=dec.name)

    if trial.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in trial.data.polygons:
        p.use_smooth = True
    trial.data.update()

    # Check post-decimate topology & boundary count
    bm_chk = bmesh.new()
    bm_chk.from_mesh(trial.data)
    b_final = sum(1 for e in bm_chk.edges if e.is_boundary)
    nm_final = sum(1 for e in bm_chk.edges if not e.is_manifold)
    bm_chk.free()

    trial_tris = sum(max(1, len(p.vertices) - 2) for p in trial.data.polygons)
    trial_verts = len(trial.data.vertices)
    regions = count_region_tris(trial)

    print(f"[DECIMATE] {source_tris} -> {trial_tris} tris ({trial_verts} verts), boundary={b_final}, nonmanifold={nm_final}", flush=True)
    print(f"[REGIONS] {regions}", flush=True)
    assert abs(trial_tris - TARGET_TRIANGLES) <= 3000, f"Unexpected trial_tris={trial_tris}"
    assert regions["footwear (z<0.16)"] >= 5000, f"Footwear over-collapsed: {regions}"
    assert regions["legs (0.16..0.75)"] >= 12000, f"Legs over-collapsed: {regions}"
    assert regions["torso_tunic (0.75..1.46, |x|<0.47)"] >= 40000, f"Torso over-collapsed: {regions}"
    assert regions["arms_hands_abducted (z<1.12, |x|>=0.45)"] >= 10000, f"Hands over-collapsed: {regions}"
    assert regions["head_cap (z>=1.46)"] >= 15000, f"Head/cap over-collapsed: {regions}"

    # Remove vertex group helper after applying so mesh stays clean for FBX
    for vg in list(trial.vertex_groups):
        trial.vertex_groups.remove(vg)

    # Save optimization trial .blend
    bpy.ops.wm.save_as_mainfile(filepath=OPT_BLEND)

    # Render 2 fast EEVEE Next inspection shots (24 samples)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.eevee.taa_render_samples = 24
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'Standard'

    w = bpy.data.worlds.new("TrialWorld")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.17, 0.19, 1.0)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = w

    for nm, rdeg, eng in [
        ("KeyLight", (48, 0, 25), 1.5),
        ("BackFill", (48, 0, -145), 1.1),
        ("RimLow", (82, 0, 0), 0.55),
    ]:
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.energy = eng
        lo = bpy.data.objects.new(nm, ld)
        scene.collection.objects.link(lo)
        lo.rotation_euler = [math.radians(a) for a in rdeg]

    cd = bpy.data.cameras.new("TrialCam")
    co = bpy.data.objects.new("TrialCam", cd)
    scene.collection.objects.link(co)
    scene.camera = co

    def snap(fname, loc, tgt, ortho=False, scale=1.98, lens=55.0, res=(750, 750)):
        scene.render.resolution_x, scene.render.resolution_y = res
        cd.type = 'ORTHO' if ortho else 'PERSP'
        if ortho:
            cd.ortho_scale = scale
        else:
            cd.lens = lens
        co.location = Vector(loc)
        co.rotation_euler = (Vector(tgt) - co.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(INSP_DIR, fname)
        bpy.ops.render.render(write_still=True)

    # Front ortho 1200x1600 with exact documented projection for Mixamo Marker Guide
    ortho_cam = {
        "loc": [0.0, -3.5, 0.90],
        "tgt": [0.0, 0.0, 0.90],
        "ortho_scale": 1.98,
        "res": [1200, 1600],
    }
    snap("trial-front-ortho.png", ortho_cam["loc"], ortho_cam["tgt"], ortho=True, scale=1.98, res=(1200, 1600))
    snap("trial-armpit-hand.png", (0.50, -1.05, 1.05), (0.38, 0.02, 1.05), lens=42.0, res=(900, 750))

    images_meta = [
        {"name": img.name, "size": list(img.size), "packed": img.packed_file is not None}
        for img in bpy.data.images
        if img.name.startswith("Asim2_Working")
    ]
    report = {
        "source_triangles_after_apose": source_tris,
        "trial_triangles": trial_tris,
        "trial_vertices": trial_verts,
        "triangle_reduction_percent": round((1.0 - trial_tris / float(source_tris)) * 100.0, 2),
        "target_ratio": round(ratio, 6),
        "abduction_deg_per_arm": ABDUCT_DEG,
        "max_armpit_edge_growth_m": max_growth,
        "armpit_caps_boundary_edges": b_caps,
        "armpit_caps_nonmanifold_edges": nm_caps,
        "dimensions_m": [round(float(d), 6) for d in trial.dimensions],
        "uv_layers": [uv.name for uv in trial.data.uv_layers],
        "boundary_edges": b_final,
        "nonmanifold_edges": nm_final,
        "region_triangle_counts": regions,
        "landmarks_world": landmarks,
        "ortho_camera": ortho_cam,
        "images": images_meta,
        "method": "Surgical medial armpit seam release + 36deg A-pose abduction + targeted PreserveDetail Decimate collapse preserving face/cap, 5-fingered hands, medals/belt/sash, shoulders/knees, and boots.",
        "blend_saved": OPT_BLEND,
    }
    with open(OPT_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print("OPTIMIZATION_TRIAL_COMPLETE")


if __name__ == "__main__":
    main()
