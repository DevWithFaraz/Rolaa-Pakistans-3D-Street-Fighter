import json
import math
import os
import struct
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1"
RESTORED_BLEND = os.path.join(ROOT, "blender", "asim-model1-restored-rig.blend")
FINAL_BLEND = os.path.join(ROOT, "blender", "asim-model1-final-rig.blend")
ANIM_DIR = r"C:\Users\IT\Downloads\animations"
MOTION_JSON = os.path.join(ROOT, "inspection", "motion-imports.json")
GLB_OUT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\game\assets\characters\asim_model1.glb"

FLOOR_Z_BIAS = 0.0050

# Core combat clips matching game state machine first, plus additional Mixamo pack moves.
CLIP_SPECS = [
    {"clip": "Idle", "file": "Idle.fbx", "kind": "direct", "in_place": False},
    {
        "clip": "Idle2",
        "file": "Standing Idle To Fight Idle.fbx",
        "kind": "fight_guard_loop",
        "source_frame": 31,
        "frames": 60,
        "in_place": True,
    },
    {"clip": "Punch", "file": "Punching.fbx", "kind": "direct", "in_place": False},
    {"clip": "MmaKick", "file": "Kicking.fbx", "kind": "direct", "in_place": False},
    {"clip": "Walk", "file": "Walking.fbx", "kind": "direct", "in_place": True},
    {"clip": "QuadPunch", "file": "Quad Punch.fbx", "kind": "direct", "in_place": False},
    {"clip": "RoundhouseKick", "file": "Roundhouse Kick.fbx", "kind": "direct", "in_place": False},
    {"clip": "Headbutt", "file": "Headbutt.fbx", "kind": "direct", "in_place": False},
]


def max_rest_matrix_diff(master_arm, other_arm) -> float:
    master_bones = {b.name: b.matrix_local for b in master_arm.data.bones}
    other_bones = {b.name: b.matrix_local for b in other_arm.data.bones}
    if set(master_bones) != set(other_bones):
        return 999.0
    max_diff = 0.0
    for name, m_mat in master_bones.items():
        o_mat = other_bones[name]
        for r in range(4):
            for c in range(4):
                d = abs(m_mat[r][c] - o_mat[r][c])
                if d > max_diff:
                    max_diff = d
    return max_diff


def hierarchy_order(arm):
    bones = list(arm.data.bones)
    depth = {}

    def get_depth(b):
        if b.name not in depth:
            depth[b.name] = 0 if b.parent is None else 1 + get_depth(b.parent)
        return depth[b.name]

    bones.sort(key=get_depth)
    return [b.name for b in bones]


def clear_pose_transforms(arm):
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
        pb.location = Vector((0.0, 0.0, 0.0))
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.scale = Vector((1.0, 1.0, 1.0))


def solve_retargeted_frame(
    master_arm,
    clip_arm,
    ordered_bones,
    master_rest_hip,
    clip_rest_hip,
    hip_scale,
    hip_xy_offset,
):
    master_arm_inv = master_arm.matrix_world.inverted()
    master_arm_inv_3 = master_arm_inv.to_3x3().normalized()
    arm_space_mats = {}
    out = {}

    clip_hip_w = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
    desired_hip_w = master_rest_hip + (clip_hip_w - clip_rest_hip) * hip_scale
    desired_hip_w.x += hip_xy_offset.x
    desired_hip_w.y += hip_xy_offset.y
    desired_hip_w.z += FLOOR_Z_BIAS
    desired_hip_arm = master_arm_inv @ desired_hip_w

    for bname in ordered_bones:
        pb = master_arm.pose.bones[bname]
        cpb = clip_arm.pose.bones[bname]
        B_b = pb.bone.matrix_local
        desired_rot_3 = (master_arm_inv_3 @ (clip_arm.matrix_world @ cpb.matrix).to_3x3().normalized())

        if pb.parent is None:
            M_b = Matrix.Translation(desired_hip_arm) @ desired_rot_3.to_4x4()
            b_basis = B_b.inverted() @ M_b
            loc = b_basis.translation.copy()
        else:
            p_name = pb.parent.name
            B_p = pb.parent.bone.matrix_local
            M_p = arm_space_mats[p_name]
            parent_head_arm = (M_p @ (B_p.inverted() @ B_b)).translation
            M_b = Matrix.Translation(parent_head_arm) @ desired_rot_3.to_4x4()
            b_basis = B_b.inverted() @ B_p @ M_p.inverted() @ M_b
            loc = Vector((0.0, 0.0, 0.0))

        arm_space_mats[bname] = M_b
        out[bname] = (loc, b_basis.to_quaternion().normalized())
    return out


def verify_retargeted_axes(master_arm, clip_arm):
    bpy.context.view_layer.update()
    min_dot = 1.0
    worst_bone = ""
    for pb in master_arm.pose.bones:
        cpb = clip_arm.pose.bones[pb.name]
        ma = (master_arm.matrix_world @ pb.matrix).to_3x3().normalized()
        mc = (clip_arm.matrix_world @ cpb.matrix).to_3x3().normalized()
        d = min(ma.col[i].dot(mc.col[i]) for i in range(3))
        if d < min_dot:
            min_dot = d
            worst_bone = pb.name
    return min_dot, worst_bone


def lowest_shoe_z(mesh_obj, shoe_vids, depsgraph):
    eo = mesh_obj.evaluated_get(depsgraph)
    me = eo.to_mesh()
    mw = eo.matrix_world
    mz = min((mw @ me.vertices[i].co).z for i in shoe_vids)
    eo.to_mesh_clear()
    return mz


def bake_spec_to_action(
    spec,
    master_arm,
    restored_mesh,
    ordered_bones,
    master_rest_hip,
    shoe_vids,
):
    clip_name = spec["clip"]
    fname = spec["file"]
    fpath = os.path.join(ANIM_DIR, fname)
    if not os.path.exists(fpath):
        raise FileNotFoundError(f"Missing Mixamo animation file: {fpath}")

    before_objs = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fpath)
    new_objs = set(bpy.data.objects) - before_objs
    clip_arm = next(o for o in new_objs if o.type == "ARMATURE")

    clip_names = [b.name for b in clip_arm.data.bones]
    master_names = [b.name for b in master_arm.data.bones]
    same_bones = set(master_names) == set(clip_names) and len(master_names) == len(clip_names)
    assert same_bones, f"Bone mismatch in {fname}: {len(clip_names)} vs {len(master_names)}"
    src_rest_diff = max_rest_matrix_diff(master_arm, clip_arm)

    clip_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    clip_rest_hip = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
    hip_scale = master_rest_hip.z / clip_rest_hip.z
    clip_arm.data.pose_position = "POSE"

    src_act = clip_arm.animation_data.action if clip_arm.animation_data else None
    assert src_act is not None, f"No action in {fpath}"
    src_f0 = int(round(src_act.frame_range[0]))
    src_f1 = int(round(src_act.frame_range[1]))

    clear_pose_transforms(master_arm)
    act = bpy.data.actions.new(name=f"Asim_{clip_name}")
    act.use_fake_user = True
    master_arm.animation_data.action = act

    # Linear horizontal drift cancellation if requested (keeps loop seam exact at 0)
    hip_start_xy = Vector((0.0, 0.0, 0.0))
    hip_drift_xy = Vector((0.0, 0.0, 0.0))
    if spec.get("in_place", False) and spec["kind"] == "direct" and src_f1 > src_f0:
        bpy.context.scene.frame_set(src_f0)
        bpy.context.view_layer.update()
        p0 = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
        bpy.context.scene.frame_set(src_f1)
        bpy.context.view_layer.update()
        p1 = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
        hip_start_xy = Vector((0.0, 0.0, 0.0))
        hip_drift_xy = Vector((-(p1.x - p0.x) * hip_scale, -(p1.y - p0.y) * hip_scale, 0.0))

    prev_quats = {}
    worst_axis_dot = 1.0
    worst_axis_bone = ""
    min_floor_z = 999.0

    if spec["kind"] == "fight_guard_loop":
        src_f = int(spec["source_frame"])
        out_f1 = int(spec["frames"])
        bpy.context.scene.frame_set(src_f)
        bpy.context.view_layer.update()
        base_pose = solve_retargeted_frame(
            master_arm, clip_arm, ordered_bones, master_rest_hip, clip_rest_hip, hip_scale, Vector((0, 0, 0))
        )
        # Apply base pose first to check exact retarget axis match
        for bname, (loc, q) in base_pose.items():
            pb = master_arm.pose.bones[bname]
            if pb.parent is None:
                pb.location = loc
            pb.rotation_quaternion = q
        min_d, wb = verify_retargeted_axes(master_arm, clip_arm)
        worst_axis_dot, worst_axis_bone = min_d, wb

        # Add gentle breathing cycle around guard pose (loop_q == 0 at f=1 and f=out_f1)
        breath_deltas = {
            "mixamorig:Spine": (-0.014, 0.0, 0.0),
            "mixamorig:Spine1": (-0.016, 0.0, 0.0),
            "mixamorig:Spine2": (-0.020, 0.0, 0.0),
            "mixamorig:Neck": (0.018, 0.0, 0.0),
            "mixamorig:Head": (0.015, 0.0, 0.0),
            "mixamorig:LeftShoulder": (0.0, 0.0, 0.022),
            "mixamorig:RightShoulder": (0.0, 0.0, -0.022),
            "mixamorig:LeftArm": (0.022, 0.0, -0.014),
            "mixamorig:RightArm": (0.022, 0.0, 0.014),
        }

        for out_f in range(1, out_f1 + 1):
            phase = 2.0 * math.pi * (out_f - 1) / float(out_f1 - 1)
            breath = 0.5 * (1.0 - math.cos(phase))
            for bname in ordered_bones:
                pb = master_arm.pose.bones[bname]
                loc, q = base_pose[bname]
                if bname in breath_deltas:
                    rx, ry, rz = breath_deltas[bname]
                    dq = Euler((rx * breath, ry * breath, rz * breath), "XYZ").to_quaternion()
                    q = (q @ dq).normalized()
                if bname in prev_quats and prev_quats[bname].dot(q) < 0.0:
                    q = -q
                prev_quats[bname] = q.copy()
                if pb.parent is None:
                    pb.location = loc
                    pb.keyframe_insert(data_path="location", frame=out_f)
                pb.rotation_quaternion = q
                pb.keyframe_insert(data_path="rotation_quaternion", frame=out_f)
            if out_f in (1, 30, out_f1):
                bpy.context.view_layer.update()
                deps = bpy.context.evaluated_depsgraph_get()
                min_floor_z = min(min_floor_z, lowest_shoe_z(restored_mesh, shoe_vids, deps))
        frame_start, frame_end = 1.0, float(out_f1)
    else:
        span = max(1, src_f1 - src_f0)
        for src_f in range(src_f0, src_f1 + 1):
            out_f = src_f - src_f0 + 1
            t = (src_f - src_f0) / float(span)
            xy_off = hip_start_xy + hip_drift_xy * t
            bpy.context.scene.frame_set(src_f)
            bpy.context.view_layer.update()

            solved = solve_retargeted_frame(
                master_arm, clip_arm, ordered_bones, master_rest_hip, clip_rest_hip, hip_scale, xy_off
            )
            for bname in ordered_bones:
                pb = master_arm.pose.bones[bname]
                loc, q = solved[bname]
                if bname in prev_quats and prev_quats[bname].dot(q) < 0.0:
                    q = -q
                prev_quats[bname] = q.copy()
                if pb.parent is None:
                    pb.location = loc
                    pb.keyframe_insert(data_path="location", frame=out_f)
                pb.rotation_quaternion = q
                pb.keyframe_insert(data_path="rotation_quaternion", frame=out_f)

            if src_f in (src_f0, (src_f0 + src_f1) // 2, src_f1):
                min_d, wb = verify_retargeted_axes(master_arm, clip_arm)
                if min_d < worst_axis_dot:
                    worst_axis_dot, worst_axis_bone = min_d, wb
                deps = bpy.context.evaluated_depsgraph_get()
                min_floor_z = min(min_floor_z, lowest_shoe_z(restored_mesh, shoe_vids, deps))

        frame_start, frame_end = 1.0, float(src_f1 - src_f0 + 1)

    # Set linear/bezier clean handles & compute loop continuity check on quaternions
    bpy.context.scene.frame_set(int(round(frame_start)))
    q0 = {b: master_arm.pose.bones[b].rotation_quaternion.copy() for b in ordered_bones}
    bpy.context.scene.frame_set(int(round(frame_end)))
    q1 = {b: master_arm.pose.bones[b].rotation_quaternion.copy() for b in ordered_bones}
    loop_q_diff = max(
        1.0 - abs(q0[b].dot(q1[b])) for b in ordered_bones
    )

    # Remove imported temp clip objects and orphaned temp actions
    for o in list(new_objs):
        bpy.data.objects.remove(o, do_unlink=True)
    if src_act and src_act.users == 0:
        bpy.data.actions.remove(src_act)

    slots = []
    if hasattr(act, "slots"):
        slots = [[s.name_display, s.target_id_type] for s in act.slots]

    info = {
        "file": fname,
        "clip": clip_name,
        "action": act.name,
        "frames": [frame_start, frame_end],
        "duration_s": round((frame_end - frame_start) / 30.0, 4),
        "scene_fps": bpy.context.scene.render.fps,
        "retargeted": True,
        "source_rest_matrix_max_difference": round(float(src_rest_diff), 6),
        "baked_rest_matrix_max_difference": 0.0,
        "retarget_min_axis_dot": round(float(worst_axis_dot), 6),
        "retarget_worst_bone": worst_axis_bone,
        "in_place_drift_removed": bool(spec.get("in_place", False)),
        "min_shoe_z_m": round(float(min_floor_z), 5),
        "loop_quat_delta": round(float(loop_q_diff), 6),
        "same_bone_names": same_bones,
        "bone_count": len(clip_names),
        "slots": slots,
    }
    assert worst_axis_dot > 0.9999, f"Retarget axis error on {clip_name}: {worst_axis_dot} ({worst_axis_bone})"
    return act, info


def main():
    bpy.ops.wm.open_mainfile(filepath=RESTORED_BLEND)
    master_arm = bpy.data.objects["Armature"]
    restored_mesh = bpy.data.objects["Asim_Model1_Restored"]
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_start = 1

    # Remove unneeded working/backup objects before clean final save & GLB export
    for obj in list(bpy.data.objects):
        if obj not in (master_arm, restored_mesh) and obj.type in ("MESH", "ARMATURE"):
            bpy.data.objects.remove(obj, do_unlink=True)

    master_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    master_rest_hip = (master_arm.matrix_world @ master_arm.pose.bones["mixamorig:Hips"].head).copy()
    shoe_vids = [v.index for v in restored_mesh.data.vertices if (restored_mesh.matrix_world @ v.co).z < 0.03]
    master_arm.data.pose_position = "POSE"

    ordered_bones = hierarchy_order(master_arm)

    if master_arm.animation_data is None:
        master_arm.animation_data_create()
    for trk in list(master_arm.animation_data.nla_tracks):
        master_arm.animation_data.nla_tracks.remove(trk)
    master_arm.animation_data.action = None

    motion_report = []
    packed_actions = []

    for spec in CLIP_SPECS:
        act, info = bake_spec_to_action(
            spec, master_arm, restored_mesh, ordered_bones, master_rest_hip, shoe_vids
        )
        motion_report.append(info)
        packed_actions.append((spec["clip"], act, int(round(info["frames"][0]))))
        print("BAKED:", json.dumps(info))

    clear_pose_transforms(master_arm)
    master_arm.animation_data.action = None
    for trk in list(master_arm.animation_data.nla_tracks):
        master_arm.animation_data.nla_tracks.remove(trk)

    for clip_name, act, fstart in packed_actions:
        trk = master_arm.animation_data.nla_tracks.new()
        trk.name = clip_name
        strip = trk.strips.new(clip_name, fstart, act)
        strip.name = clip_name
        trk.mute = False

    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=FINAL_BLEND)
    with open(MOTION_JSON, "w", encoding="utf-8") as f:
        json.dump(motion_report, f, indent=2)

    # Export clean GLB for Godot 4 gl_compatibility (match Khan export flags)
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    master_arm.hide_viewport = False
    restored_mesh.hide_viewport = False
    if restored_mesh.parent != master_arm:
        mw = restored_mesh.matrix_world.copy()
        restored_mesh.parent = master_arm
        restored_mesh.matrix_world = mw
    master_arm.select_set(True)
    restored_mesh.select_set(True)
    bpy.context.view_layer.objects.active = master_arm
    master_arm.data.pose_position = "POSE"
    master_arm.animation_data.action = None
    for trk in master_arm.animation_data.nla_tracks:
        trk.mute = False

    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_force_sampling=True,
        export_frame_range=False,
        export_rest_position_armature=True,
        export_skins=True,
        export_influence_nb=8,
        export_all_influences=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_tangents=True,
        export_def_bones=False,
        export_apply=False,
    )

    with open(GLB_OUT, "rb") as f:
        f.read(12)
        length, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(length))
    print(
        "GLB_EXPORTED:",
        json.dumps(
            {
                "path": GLB_OUT,
                "bytes": os.path.getsize(GLB_OUT),
                "animations": [a.get("name") for a in gltf.get("animations", [])],
                "meshes": len(gltf.get("meshes", [])),
                "skin_joints": [len(s["joints"]) for s in gltf.get("skins", [])],
                "images": len(gltf.get("images", [])),
            }
        ),
    )


if __name__ == "__main__":
    main()
