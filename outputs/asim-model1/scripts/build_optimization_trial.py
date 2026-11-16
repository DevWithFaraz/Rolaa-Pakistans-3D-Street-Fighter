import bpy
import bmesh
import json
import os

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1"
WORKING_BLEND = os.path.join(ROOT, "blender", "asim-model1-working.blend")
OPT_BLEND = os.path.join(ROOT, "blender", "asim-model1-optimization-trial.blend")
REPORT_OUT = os.path.join(ROOT, "inspection", "optimization-trial.json")


def compute_collapse_weight(co):
    x, y, z = co.x, co.y, co.z
    ax = abs(x)
    # Keep trousers/sleeves dense enough for clean knee/hip/elbow deformation (~0.65 max vs 0.16 min).
    w = 0.65

    # Articulation & uniform trim transitions (knees, tunic hem, belt/sash/medals, elbows, shoulders, shoes).
    if z < 0.16:
        w = min(w, 0.32)
    if 0.35 <= z <= 0.58 and ax < 0.30:  # knees + surrounding leg band
        w = min(w, 0.38)
    if 0.70 <= z <= 1.12 and ax < 0.36:  # hips, tunic hem, belt
        w = min(w, 0.36)
    if 1.00 <= z <= 1.44 and ax < 0.32 and y < 0.04:  # front medals, sash, cord, collar
        w = min(w, 0.28)
    if 1.15 <= z <= 1.48 and 0.18 <= ax <= 0.48:  # shoulders & elbows
        w = min(w, 0.38)

    # Hands and 5 separated fingers (in A-pose: z ~ 0.68..1.05, |x| > 0.47).
    if z < 1.08 and ax > 0.47:
        t = min(1.0, max(0.0, (ax - 0.47) / 0.05))
        w = min(w, 0.38 * (1.0 - t) + 0.16 * t)

    # Neck, face, and peaked officer cap (z > 1.46).
    if z > 1.46:
        t = min(1.0, max(0.0, (z - 1.46) / 0.05))
        cap_face_w = 0.15 if y < 0.03 else 0.24
        w = min(w, 0.38 * (1.0 - t) + cap_face_w * t)

    return max(0.15, min(0.65, w))


def run(target_tris=152000):
    if "Asim_Model1_Working" not in bpy.data.objects:
        bpy.ops.wm.open_mainfile(filepath=WORKING_BLEND)

    src = bpy.data.objects["Asim_Model1_Working"]
    # Remove any previous optimization trial copy.
    if "Asim_Model1_Optimization_Trial" in bpy.data.objects:
        old = bpy.data.objects["Asim_Model1_Optimization_Trial"]
        bpy.data.objects.remove(old, do_unlink=True)

    trial = src.copy()
    trial.data = src.data.copy()
    trial.name = "Asim_Model1_Optimization_Trial"
    trial.data.name = "Asim_Model1_Optimization_Trial_Mesh"
    bpy.context.collection.objects.link(trial)

    # Keep high-detail working master untouched & hidden in trial file.
    src.hide_viewport = True
    src.hide_render = True
    trial.hide_viewport = False
    trial.hide_render = False

    vg = trial.vertex_groups.get("CollapsePriority") or trial.vertex_groups.new(name="CollapsePriority")
    for v in trial.data.vertices:
        vg.add([v.index], compute_collapse_weight(v.co), 'REPLACE')

    source_tris = len(trial.data.polygons)
    ratio = round(float(target_tris) / float(source_tris), 5)

    mod = trial.modifiers.new(name="TargetedDecimate", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    mod.vertex_group = vg.name
    mod.invert_vertex_group = False
    mod.vertex_group_factor = 1.0
    mod.use_collapse_triangulate = True

    bpy.context.view_layer.objects.active = trial
    trial.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    # Clear stale custom split normals baked before decimation so smooth shading + normal map shade cleanly.
    if trial.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in trial.data.polygons:
        p.use_smooth = True
    trial.data.update()

    # Inspect post-decimation geometry and UVs.
    bm = bmesh.new()
    bm.from_mesh(trial.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    trial_verts = len(bm.verts)
    trial_tris = len(bm.faces)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    nonmanifold = sum(1 for e in bm.edges if not e.is_manifold)

    region_counts = {
        "footwear (z<0.16)": sum(1 for f in bm.faces if f.calc_center_median().z < 0.16),
        "legs (0.16..0.75)": sum(1 for f in bm.faces if 0.16 <= f.calc_center_median().z < 0.75),
        "torso_tunic (0.75..1.48, |x|<0.47)": sum(1 for f in bm.faces if 0.75 <= f.calc_center_median().z < 1.48 and abs(f.calc_center_median().x) < 0.47),
        "hands_5fingers (z<1.08, |x|>=0.47)": sum(1 for f in bm.faces if f.calc_center_median().z < 1.08 and abs(f.calc_center_median().x) >= 0.47),
        "head_cap (z>=1.48)": sum(1 for f in bm.faces if f.calc_center_median().z >= 1.48),
    }
    bm.free()

    bpy.ops.wm.save_as_mainfile(filepath=OPT_BLEND)

    report = {
        "source_triangles": source_tris,
        "trial_triangles": trial_tris,
        "trial_vertices": trial_verts,
        "triangle_reduction_percent": round((1.0 - float(trial_tris) / float(source_tris)) * 100.0, 2),
        "target_ratio": ratio,
        "dimensions_m": [round(v, 6) for v in trial.dimensions],
        "uv_layers": [u.name for u in trial.data.uv_layers],
        "boundary_edges": boundary,
        "nonmanifold_edges": nonmanifold,
        "region_triangle_counts": region_counts,
        "images": [
            {"name": im.name, "size": list(im.size), "packed": im.packed_file is not None}
            for im in bpy.data.images if im.size[0] > 0 and im.name not in ("Viewer Node",)
        ],
        "method": "Targeted weighted Decimate collapse preserving face/cap, 5-fingered hands, medals/belt/sash, shoulders/knees, and footwear while collapsing high-density uniform cloth.",
        "blend_saved": OPT_BLEND,
    }
    with open(REPORT_OUT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    run()
