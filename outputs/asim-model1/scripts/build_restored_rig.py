import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc
from mathutils.kdtree import KDTree

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from build_optimization_trial import compute_collapse_weight
from fix_arm_pronation import apply_forearm_pronation

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1"
WORKING_BLEND = os.path.join(ROOT, "blender", "asim-model1-working.blend")
TPOSE_FBX = os.path.join(ROOT, "mixamo", "downloads", "Asim_Model1_Rigging_Trial (1).fbx")
RESTORED_BLEND = os.path.join(ROOT, "blender", "asim-model1-restored-rig.blend")
REVIEW_JSON = os.path.join(ROOT, "inspection", "restored-rig-review.json")
INSP_DIR = os.path.join(ROOT, "inspection")

TARGET_TRIS = 285000


def build_high_detail_candidate(src_obj):
    if "Asim_Model1_Restored" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["Asim_Model1_Restored"], do_unlink=True)

    obj = src_obj.copy()
    obj.data = src_obj.data.copy()
    obj.name = "Asim_Model1_Restored"
    obj.data.name = "Asim_Model1_Restored_Mesh"
    for col in src_obj.users_collection:
        col.objects.link(obj)

    src_obj.hide_viewport = True
    src_obj.hide_render = True
    src_obj.select_set(False)
    obj.hide_viewport = False
    obj.hide_render = False

    # Weighted Collapse to ~285K game-ready detail while keeping full facial, cap, badge, hand, and boot fidelity
    for existing in list(obj.vertex_groups):
        obj.vertex_groups.remove(existing)
    vg = obj.vertex_groups.new(name="CollapsePriority")
    buckets = {}
    for v in obj.data.vertices:
        w_key = round(compute_collapse_weight(v.co), 2)
        buckets.setdefault(w_key, []).append(v.index)
    for w_val, indices in buckets.items():
        vg.add(indices, w_val, 'REPLACE')

    source_tris = len(obj.data.polygons)
    ratio = float(TARGET_TRIS) / float(source_tris)

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)

    mod = obj.modifiers.new(name="DetailRestoreDecimate", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    mod.vertex_group = vg.name
    mod.invert_vertex_group = False
    mod.vertex_group_factor = 1.0
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)

    for existing in list(obj.vertex_groups):
        obj.vertex_groups.remove(existing)

    if obj.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.data.update()

    # Match the exact forearm pronation uploaded to Mixamo so REST pose palms/fingers align sub-millimeter
    moved_verts = apply_forearm_pronation(obj, angle_deg=90.0)
    tris_after = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    print(f"[CANDIDATE] {source_tris} -> {tris_after} tris ({len(obj.data.vertices)} verts), pronated_verts={moved_verts}", flush=True)
    return obj


def extract_mixamo_weights(mixamo_obj):
    group_names = [vg.name for vg in mixamo_obj.vertex_groups]
    idx_to_name = {vg.index: vg.name for vg in mixamo_obj.vertex_groups}
    vert_weights = []
    for v in mixamo_obj.data.vertices:
        w = {}
        for g in v.groups:
            if g.weight > 1e-6:
                w[idx_to_name[g.group]] = float(g.weight)
        s = sum(w.values())
        if s > 0.0:
            for k in w:
                w[k] /= s
        vert_weights.append(w)

    bm = bmesh.new()
    bm.from_mesh(mixamo_obj.data)
    bm.verts.ensure_lookup_table()
    # Record original vertex index on each BMVert via index before triangulation
    for i, v in enumerate(bm.verts):
        v.index = i
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    mw = mixamo_obj.matrix_world.copy()
    ws_verts = [mw @ v.co for v in bm.verts]
    tri_polys = [[v.index for v in f.verts] for f in bm.faces if len(f.verts) == 3]
    bm.free()

    return group_names, vert_weights, ws_verts, tri_polys


def apply_rigid_and_anatomical_guards(co: Vector, weights: dict) -> dict:
    # 1. Officer peak cap & crown rigid lock -> mixamorig:Head
    if co.z >= 1.595:
        return {"mixamorig:Head": 1.0}

    cleaned = dict(weights)

    # 2. Cross-side isolation on footwear & legs (zero opposite-leg bleed)
    if co.z < 0.78:
        if co.x >= 0.02 or (co.z < 0.20 and co.x >= 0.0):
            for k in list(cleaned.keys()):
                if k.startswith("mixamorig:Right"):
                    del cleaned[k]
        elif co.x <= -0.02 or (co.z < 0.20 and co.x < 0.0):
            for k in list(cleaned.keys()):
                if k.startswith("mixamorig:Left"):
                    del cleaned[k]

    # 3. Hand / finger cross-side isolation
    if co.x >= 0.35:
        for k in list(cleaned.keys()):
            if k.startswith("mixamorig:Right"):
                del cleaned[k]
    elif co.x <= -0.35:
        for k in list(cleaned.keys()):
            if k.startswith("mixamorig:Left"):
                del cleaned[k]

    # 4. Prevent arm bone bleed onto front chest medals, ribbons, buckle & central cord
    if 1.04 <= co.z <= 1.44 and abs(co.x) <= 0.145 and co.y < -0.05:
        arm_tokens = ("Arm", "ForeArm", "Hand", "Thumb", "Index", "Middle", "Ring", "Pinky")
        candidate = {k: v for k, v in cleaned.items() if not any(tok in k for tok in arm_tokens)}
        if candidate:
            cleaned = candidate

    if not cleaned:
        cleaned = dict(weights)

    # Keep top 4 influences for clean glTF/Godot GPU skinning & re-normalize
    top4 = sorted(cleaned.items(), key=lambda kv: kv[1], reverse=True)[:4]
    total = sum(val for _, val in top4)
    if total <= 1e-8:
        return {}
    return {k: v / total for k, v in top4}


def transfer_weights(restored_obj, mixamo_obj):
    group_names, src_weights, ws_verts, tri_polys = extract_mixamo_weights(mixamo_obj)

    bvh = BVHTree.FromPolygons(ws_verts, tri_polys)
    kd = KDTree(len(ws_verts))
    for i, co in enumerate(ws_verts):
        kd.insert(co, i)
    kd.balance()

    # Recreate ordered bone vertex groups on restored_obj
    for existing in list(restored_obj.vertex_groups):
        restored_obj.vertex_groups.remove(existing)
    vg_map = {name: restored_obj.vertex_groups.new(name=name) for name in group_names}

    exact_copies = 0
    max_dist = 0.0
    unweighted = 0
    max_sum_err = 0.0
    rmw = restored_obj.matrix_world.copy()

    for v in restored_obj.data.vertices:
        wco = rmw @ v.co
        _, kd_idx, kd_dist = kd.find(wco)
        raw_w = None

        if kd_dist <= 1e-4 and src_weights[kd_idx]:
            raw_w = src_weights[kd_idx]
            exact_copies += 1
        else:
            loc, _, face_idx, dist = bvh.find_nearest(wco)
            if dist is not None and dist > max_dist:
                max_dist = float(dist)
            if face_idx is not None:
                i0, i1, i2 = tri_polys[face_idx]
                bary = poly_3d_calc([ws_verts[i0], ws_verts[i1], ws_verts[i2]], loc)
                blended = {}
                for b_idx, factor in ((i0, bary[0]), (i1, bary[1]), (i2, bary[2])):
                    if factor <= 1e-6:
                        continue
                    for bname, bw in src_weights[b_idx].items():
                        blended[bname] = blended.get(bname, 0.0) + bw * factor
                raw_w = blended

        if not raw_w:
            raw_w = src_weights[kd_idx] if src_weights[kd_idx] else {"mixamorig:Hips": 1.0}

        final_w = apply_rigid_and_anatomical_guards(wco, raw_w)
        if not final_w:
            unweighted += 1
            final_w = {"mixamorig:Hips": 1.0}

        sum_err = abs(sum(final_w.values()) - 1.0)
        if sum_err > max_sum_err:
            max_sum_err = sum_err

        for bname, bw in final_w.items():
            if bw > 1e-5:
                vg_map[bname].add([v.index], bw, 'REPLACE')

    return exact_copies, max_dist, unweighted, max_sum_err


def main():
    bpy.ops.wm.open_mainfile(filepath=WORKING_BLEND)
    src = bpy.data.objects["Asim_Model1_Working"]

    restored = build_high_detail_candidate(src)

    # Import Mixamo T-Pose rig + skinning source
    before_objs = set(bpy.data.objects)
    before_mats = set(bpy.data.materials)
    before_imgs = set(bpy.data.images)

    bpy.ops.import_scene.fbx(filepath=TPOSE_FBX)

    new_objs = set(bpy.data.objects) - before_objs
    arm = next(o for o in new_objs if o.type == 'ARMATURE')
    mixamo_mesh = next(o for o in new_objs if o.type == 'MESH')
    arm.name = "Armature"

    # Put Armature into REST pose so Mixamo source mesh & restored mesh sit identically in 1.319m A-pose
    arm.data.pose_position = 'REST'
    bpy.context.view_layer.update()

    exact_copies, max_dist, unweighted, max_sum_err = transfer_weights(restored, mixamo_mesh)

    # Parent restored mesh to Mixamo Armature and hook Armature modifier
    for m in list(restored.modifiers):
        if m.type == 'ARMATURE':
            restored.modifiers.remove(m)
    restored.parent = arm
    restored.matrix_parent_inverse = arm.matrix_world.inverted()
    arm_mod = restored.modifiers.new(name="Armature", type='ARMATURE')
    arm_mod.object = arm
    arm_mod.use_vertex_groups = True

    # Preserve T-Pose action with fake user, detach from runtime slot so rest/animations stay clean
    if arm.animation_data and arm.animation_data.action:
        tpose_act = arm.animation_data.action
        tpose_act.name = "Asim_TPose_Mixamo"
        tpose_act.use_fake_user = True
        arm.animation_data.action = None

    # Clean up temporary duplicate Mixamo decimated mesh & its stripped FBX material/images
    bpy.data.objects.remove(mixamo_mesh, do_unlink=True)
    for mat in list(set(bpy.data.materials) - before_mats):
        if mat.users == 0:
            bpy.data.materials.remove(mat)
    for img in list(set(bpy.data.images) - before_imgs):
        if img.users == 0:
            bpy.data.images.remove(img)

    # Switch back to POSE position cleanly (neutral rest pose when no action active)
    arm.data.pose_position = 'POSE'
    for pb in arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

    # Check PBR material images (must keep basecolor, rm, normal)
    mat_images = []
    for mat in restored.data.materials:
        if mat and mat.use_nodes and mat.node_tree:
            for n in mat.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image:
                    mat_images.append({
                        "name": n.image.name,
                        "size": list(n.image.size),
                        "packed": n.image.packed_file is not None,
                    })

    restored_tris = sum(max(1, len(p.vertices) - 2) for p in restored.data.polygons)
    report = {
        "triangles": restored_tris,
        "vertices": len(restored.data.vertices),
        "exact_weight_copies": exact_copies,
        "max_interpolation_distance_m": round(max_dist, 6),
        "unweighted_vertices": unweighted,
        "max_weight_sum_error": max_sum_err,
        "skeleton_bones": len(arm.data.bones),
        "finger_chains_per_hand": ["thumb", "index", "middle", "ring", "pinky"],
        "rigid_cap_lock_z_m": 1.595,
        "footwear_protection_z_m": 0.2,
        "dimensions_m": [round(float(d), 6) for d in restored.dimensions],
        "pbr_images": mat_images,
        "blend_saved": RESTORED_BLEND,
    }

    bpy.ops.wm.save_as_mainfile(filepath=RESTORED_BLEND)
    with open(REVIEW_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    print(f"[RESTORED_RIG] tris={restored_tris} verts={len(restored.data.vertices)} exact={exact_copies} max_dist={max_dist:.5f}m unweighted={unweighted} imgs={len(mat_images)}", flush=True)

    # Render fast visual verification: rest A-pose (showing restored rm metallic/roughness & details) + guard pose
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.eevee.taa_render_samples = 16
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'Standard'

    w = bpy.data.worlds.new("RestoredWorld")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.17, 0.20, 1.0)
    scene.world = w

    for nm, rdeg, eng in [("Key", (45, 0, 22), 2.1), ("Fill", (50, 0, -140), 1.0)]:
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.energy = eng
        lo = bpy.data.objects.new(nm, ld)
        scene.collection.objects.link(lo)
        lo.rotation_euler = [math.radians(a) for a in rdeg]

    cd = bpy.data.cameras.new("Cam")
    co = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(co)
    scene.camera = co
    scene.render.resolution_x, scene.render.resolution_y = 750, 950

    cd.type = 'ORTHO'
    cd.ortho_scale = 2.0
    co.location = Vector((0.0, -3.5, 0.90))
    co.rotation_euler = (Vector((0.0, 0.0, 0.90)) - co.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(INSP_DIR, "restored-front-rm.png")
    bpy.ops.render.render(write_still=True)

    # Pose test combat guard + curled 5 fingers (non-destructive, not saved to .blend)
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
    arm.pose.bones["mixamorig:Spine1"].rotation_euler = (math.radians(14), 0, 0)
    arm.pose.bones["mixamorig:LeftArm"].rotation_euler = (0, math.radians(-20), math.radians(52))
    arm.pose.bones["mixamorig:LeftForeArm"].rotation_euler = (math.radians(-70), 0, 0)
    arm.pose.bones["mixamorig:RightArm"].rotation_euler = (0, math.radians(20), math.radians(-52))
    arm.pose.bones["mixamorig:RightForeArm"].rotation_euler = (math.radians(-70), 0, 0)
    arm.pose.bones["mixamorig:LeftUpLeg"].rotation_euler = (math.radians(-28), 0, 0)
    arm.pose.bones["mixamorig:LeftLeg"].rotation_euler = (math.radians(46), 0, 0)
    for side_p in ("LeftHand", "RightHand"):
        for f_name in ("Index", "Middle", "Ring", "Pinky"):
            for seg in ("1", "2", "3"):
                pb = arm.pose.bones.get(f"mixamorig:{side_p}{f_name}{seg}")
                if pb:
                    pb.rotation_euler = (math.radians(65), 0, 0)
        pb_t = arm.pose.bones.get(f"mixamorig:{side_p}Thumb2")
        if pb_t:
            pb_t.rotation_euler = (math.radians(35), 0, math.radians(25 if side_p == "LeftHand" else -25))

    bpy.context.view_layer.update()
    co.location = Vector((-2.2, -2.8, 0.95))
    co.rotation_euler = (Vector((0.0, 0.0, 0.90)) - co.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(INSP_DIR, "restored-guard-fist.png")
    bpy.ops.render.render(write_still=True)
    print("RESTORED_RIG_COMPLETE")


if __name__ == "__main__":
    main()
