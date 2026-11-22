"""Phase P3 Blender pipeline: retarget new Mixamo clips onto Khan & Asim, solve Khan kameez drape, decimate LOD0, and export GLBs."""

import json
import math
import os
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
DIR_DL = Path(r"C:\Users\IT\Downloads")
DIR_NEW = DIR_DL / "New Animations"
DIR_OLD = DIR_DL / "animations"
DIR_MORE = DIR_DL / "More Animations"
ZIP_COMBAT = DIR_MORE / "Motifect_combat_complete_v1_0.zip"
ZIP_EMOTES = DIR_MORE / "Motifect_emotes_and_social_v1_0.zip"
ZIP_FANTASY = DIR_MORE / "fantasy.zip"

BVH_TO_MIXAMO = {
    "Hips": "mixamorig:Hips",
    "Spine1": "mixamorig:Spine",
    "Spine2": "mixamorig:Spine1",
    "Chest": "mixamorig:Spine2",
    "Neck1": "mixamorig:Neck",
    "Head": "mixamorig:Head",
    "LeftShoulder": "mixamorig:LeftShoulder",
    "LeftArm": "mixamorig:LeftArm",
    "LeftForeArm": "mixamorig:LeftForeArm",
    "LeftHand": "mixamorig:LeftHand",
    "RightShoulder": "mixamorig:RightShoulder",
    "RightArm": "mixamorig:RightArm",
    "RightForeArm": "mixamorig:RightForeArm",
    "RightHand": "mixamorig:RightHand",
    "LeftLeg": "mixamorig:LeftUpLeg",
    "LeftShin": "mixamorig:LeftLeg",
    "LeftFoot": "mixamorig:LeftFoot",
    "LeftToeBase": "mixamorig:LeftToeBase",
    "RightLeg": "mixamorig:RightUpLeg",
    "RightShin": "mixamorig:RightLeg",
    "RightFoot": "mixamorig:RightFoot",
    "RightToeBase": "mixamorig:RightToeBase",
}
MIXAMO_TO_BVH = {v: k for k, v in BVH_TO_MIXAMO.items()}

KHAN_BLEND_IN = ROOT / "outputs/khan-model2/blender/khan-model2-recovery-trial.blend"
KHAN_BLEND_OUT = ROOT / "outputs/khan-model2/blender/khan-model2-p3.blend"
KHAN_GLB_OUT = ROOT / "game/assets/characters/khan_recovery_trial.glb"

ASIM_BLEND_IN = ROOT / "outputs/asim-model1/blender/asim-model1-final-rig.blend"
ASIM_BLEND_OUT = ROOT / "outputs/asim-model1/blender/asim-model1-p3.blend"
ASIM_GLB_OUT = ROOT / "game/assets/characters/asim_model1.glb"

REPORT_OUT = ROOT / "outputs/p3-animations/build-report.json"

LOW = 0.578
HIGH = 1.035
NA = 18
NZ = 10
HALF_FRONT = math.pi * 0.42
HALF_BACK = math.pi * 0.42

KHAN_NEW_CLIPS = [
    {"clip": "Idle", "path": DIR_OLD / "Idle.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Idle2", "path": DIR_DL / "Bouncing Fight Idle.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Walk", "path": DIR_NEW / "Walking.fbx", "in_place": True, "lock_xy": True},
    {"clip": "WalkBack", "path": DIR_NEW / "Step Backward.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Jump", "path": DIR_DL / "Jumping.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrouchIdle", "path": DIR_NEW / "Crouching Idle.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrouchWalk", "path": DIR_NEW / "Crouched Walking.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrouchWalkBack", "path": DIR_NEW / "Crouched Walking.fbx", "in_place": True, "lock_xy": True, "reverse": True},
    {"clip": "DashForward", "path": DIR_NEW / "Long Step Forward(two long steps maybe will need for dash).fbx", "in_place": True, "lock_xy": True},
    {"clip": "Backdash", "path": DIR_NEW / "Step Backward.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Sidestep", "path": DIR_NEW / "Short Left Side Step.fbx", "in_place": True, "lock_xy": False},
    {"clip": "Punch", "path": DIR_OLD / "Punching (1).fbx", "in_place": False, "lock_xy": False},
    {"clip": "CrossPunch", "path": DIR_NEW / "Right Hand Cross Punch.fbx", "in_place": True, "lock_xy": True},
    {"clip": "RightHook", "path": DIR_NEW / "Right Hand Hook.fbx", "in_place": True, "lock_xy": True},
    {"clip": "LeftKick", "path": DIR_NEW / "Left Kick.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrescentSweep", "path": DIR_OLD / "Inside Crescent Kick.fbx", "in_place": True, "lock_xy": True},
    {"clip": "FlipKick", "path": DIR_NEW / "Singnature Flip Kick.fbx", "in_place": True, "lock_xy": True},
    {"clip": "QuadPunch", "path": DIR_OLD / "Quad Punch.fbx", "in_place": True, "lock_xy": True},
    {"clip": "RoundhouseKick", "path": DIR_OLD / "Roundhouse Kick.fbx", "in_place": True, "lock_xy": True},
    {"clip": "ThrowRock", "path": DIR_NEW / "Throw Object.fbx", "in_place": True, "lock_xy": True},
    {"clip": "SignatureKick", "path": DIR_NEW / "Singnature Move Kicking.fbx", "in_place": True, "lock_xy": True},
    {"clip": "HitHead", "path": DIR_NEW / "Getting Head Hit.fbx", "in_place": True, "lock_xy": True},
    {"clip": "HitBody", "path": DIR_NEW / "Getting Hit.fbx", "in_place": True, "lock_xy": True},
    {"clip": "SweepFall", "path": DIR_DL / "Sweep Fall.fbx", "in_place": False, "lock_xy": False},
    {"clip": "KnockdownDeath", "path": DIR_NEW / "Character Death.fbx", "in_place": False, "lock_xy": False},
    {"clip": "BlockHit", "zip": ZIP_COMBAT, "bvh": "BVH/block_mid.bvh", "in_place": True, "lock_xy": True, "slice": (1, 55)},
    {"clip": "WakeupStand", "path": DIR_DL / "Stand Up.fbx", "in_place": False, "lock_xy": False, "end_at_origin": True, "slice": (45, 200)},
    {"clip": "Taunt", "path": DIR_DL / "Standing Taunt Battlecry.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Turn180", "path": DIR_DL / "Running Turn 180.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Entry", "path": DIR_DL / "Entry (1).fbx", "in_place": False, "lock_xy": False, "end_at_origin": True},
    {"clip": "VictoryCelebrate", "path": DIR_DL / "Rumba Dancing.fbx", "in_place": True, "lock_xy": True},
    {"clip": "JumpPunch", "path": DIR_DL / "Flying Knee Punch Combo.fbx", "in_place": True, "lock_xy": True, "lock_z": True, "slice": (19, 50)},
    {"clip": "JumpKick", "path": DIR_DL / "Drop Kick.fbx", "in_place": True, "lock_xy": True, "lock_z": True, "slice": (25, 51)},
]

ASIM_EXTRA_CLIPS = [
    {"clip": "Idle2", "path": DIR_DL / "Bouncing Fight Idle.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Walk", "path": DIR_NEW / "Walking.fbx", "in_place": True, "lock_xy": True},
    {"clip": "WalkBack", "path": DIR_NEW / "Step Backward.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrouchIdle", "path": DIR_NEW / "Crouching Idle.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrouchWalk", "path": DIR_NEW / "Crouched Walking.fbx", "in_place": True, "lock_xy": True},
    {"clip": "CrouchWalkBack", "path": DIR_NEW / "Crouched Walking.fbx", "in_place": True, "lock_xy": True, "reverse": True},
    {"clip": "DashForward", "path": DIR_NEW / "Long Step Forward(two long steps maybe will need for dash).fbx", "in_place": True, "lock_xy": True},
    {"clip": "Backdash", "path": DIR_NEW / "Step Backward.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Sidestep", "zip": ZIP_COMBAT, "bvh": "BVH/dodge_left.bvh", "in_place": True, "lock_xy": True, "slice": (1, 55)},
    {"clip": "Jump", "path": DIR_DL / "Jumping.fbx", "in_place": True, "lock_xy": True},
    {"clip": "JabLeft", "zip": ZIP_COMBAT, "bvh": "BVH/jab_left.bvh", "in_place": True, "lock_xy": True, "slice": (1, 48)},
    {"clip": "JabCross", "zip": ZIP_COMBAT, "bvh": "BVH/combo_jab_cross.bvh", "in_place": True, "lock_xy": True, "slice": (1, 65)},
    {"clip": "CrossRight", "zip": ZIP_COMBAT, "bvh": "BVH/cross_right.bvh", "in_place": True, "lock_xy": True, "slice": (1, 65)},
    {"clip": "BodyPunch", "zip": ZIP_COMBAT, "bvh": "BVH/body_punch_right.bvh", "in_place": True, "lock_xy": True, "slice": (1, 65)},
    {"clip": "FrontKick", "zip": ZIP_COMBAT, "bvh": "BVH/front_kick.bvh", "in_place": True, "lock_xy": True, "slice": (1, 72)},
    {"clip": "SweepKick", "zip": ZIP_COMBAT, "bvh": "BVH/sweep_kick.bvh", "in_place": True, "lock_xy": True, "slice": (1, 80)},
    {"clip": "UppercutRight", "zip": ZIP_COMBAT, "bvh": "BVH/uppercut_right.bvh", "in_place": True, "lock_xy": True, "slice": (1, 75)},
    {"clip": "GrabThrow", "zip": ZIP_COMBAT, "bvh": "BVH/grab_and_throw.bvh", "in_place": True, "lock_xy": True, "slice": (1, 75)},
    {"clip": "ComboPunchKick", "zip": ZIP_COMBAT, "bvh": "BVH/combo_punch_kick.bvh", "in_place": True, "lock_xy": True, "slice": (1, 95)},
    {"clip": "BlockHit", "zip": ZIP_COMBAT, "bvh": "BVH/block_mid.bvh", "in_place": True, "lock_xy": True, "slice": (1, 55)},
    {"clip": "HitHead", "path": DIR_NEW / "Getting Head Hit.fbx", "in_place": True, "lock_xy": True},
    {"clip": "HitBody", "path": DIR_NEW / "Getting Hit.fbx", "in_place": True, "lock_xy": True},
    {"clip": "SweepFall", "path": DIR_DL / "Sweep Fall.fbx", "in_place": False, "lock_xy": False},
    {"clip": "KnockdownDeath", "path": DIR_NEW / "Character Death.fbx", "in_place": False, "lock_xy": False},
    {"clip": "WakeupStand", "path": DIR_DL / "Stand Up.fbx", "in_place": False, "lock_xy": False, "end_at_origin": True, "slice": (45, 200)},
    {"clip": "Taunt", "zip": ZIP_EMOTES, "bvh": "BVH/salute_military.bvh", "in_place": True, "lock_xy": True, "slice": (1, 100)},
    {"clip": "Turn180", "path": DIR_DL / "Running Turn 180.fbx", "in_place": True, "lock_xy": True},
    {"clip": "Entry", "path": DIR_DL / "Crouch To Stand.fbx", "in_place": True, "lock_xy": True},
    {"clip": "VictoryCelebrate", "path": DIR_DL / "Silly Dancing.fbx", "in_place": True, "lock_xy": True},
    {"clip": "ShootPistol", "path": DIR_DL / "shoot" / "Shooting.fbx", "in_place": True, "lock_xy": True},
    {"clip": "JumpPunch", "path": DIR_DL / "Flying Knee Punch Combo.fbx", "in_place": True, "lock_xy": True, "lock_z": True, "slice": (19, 50)},
    {"clip": "JumpKick", "path": DIR_DL / "Drop Kick.fbx", "in_place": True, "lock_xy": True, "lock_z": True, "slice": (25, 51)},
]


def hierarchy_order(arm, prefix: str = "mixamorig:") -> list[str]:
    bones = [b for b in arm.data.bones if b.name.startswith(prefix)]
    depth = {}

    def get_depth(b):
        if b.name not in depth:
            depth[b.name] = 0 if (b.parent is None or not b.parent.name.startswith(prefix)) else 1 + get_depth(b.parent)
        return depth[b.name]

    bones.sort(key=get_depth)
    return [b.name for b in bones]


def clear_pose_transforms(arm) -> None:
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
    ordered_bones: list[str],
    master_rest_hip: Vector,
    clip_rest_hip: Vector,
    hip_scale: float,
    hip_xy_offset: Vector,
    lock_xy: bool = False,
    lock_z: bool = False,
) -> dict[str, tuple[Vector, Quaternion]]:
    master_arm_inv = master_arm.matrix_world.inverted()
    master_arm_inv_3 = master_arm_inv.to_3x3().normalized()
    arm_space_mats = {}
    out = {}

    clip_hip_w = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
    desired_hip_w = master_rest_hip + (clip_hip_w - clip_rest_hip) * hip_scale
    if lock_xy:
        desired_hip_w.x = master_rest_hip.x
        desired_hip_w.y = master_rest_hip.y
    else:
        desired_hip_w.x += hip_xy_offset.x
        desired_hip_w.y += hip_xy_offset.y
    if lock_z:
        desired_hip_w.z = master_rest_hip.z
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


def bake_fbx_to_action(
    master_arm,
    ordered_bones: list[str],
    master_rest_hip: Vector,
    action_name: str,
    fbx_path: Path,
    in_place: bool,
    frame_slice: tuple[int, int] | None = None,
    lock_xy: bool = False,
    reverse: bool = False,
    end_at_origin: bool = False,
    lock_z: bool = False,
) -> tuple[bpy.types.Action, int]:
    assert fbx_path.exists(), f"Missing FBX: {fbx_path}"
    before_objs = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx_path))
    new_objs = set(bpy.data.objects) - before_objs
    clip_arm = next(o for o in new_objs if o.type == "ARMATURE")

    clip_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    clip_rest_hip = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
    hip_scale = master_rest_hip.z / max(clip_rest_hip.z, 1e-4)
    clip_arm.data.pose_position = "POSE"

    src_act = clip_arm.animation_data.action if clip_arm.animation_data else None
    assert src_act is not None, f"No action in {fbx_path}"
    src_f0 = int(round(src_act.frame_range[0]))
    src_f1 = int(round(src_act.frame_range[1]))
    if frame_slice is not None:
        src_f0 = max(src_f0, frame_slice[0])
        src_f1 = min(src_f1, frame_slice[1])

    clear_pose_transforms(master_arm)
    act = bpy.data.actions.new(name=action_name)
    act.use_fake_user = True
    master_arm.animation_data.action = act

    frame_seq = list(range(src_f1, src_f0 - 1, -1)) if reverse else list(range(src_f0, src_f1 + 1))

    hip_drift_xy = Vector((0.0, 0.0, 0.0))
    hip_anchor_xy = Vector((0.0, 0.0, 0.0))
    if not lock_xy and end_at_origin and len(frame_seq) > 1:
        bpy.context.scene.frame_set(frame_seq[-1])
        bpy.context.view_layer.update()
        p1 = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
        hip_anchor_xy = Vector((-(p1.x - clip_rest_hip.x) * hip_scale, -(p1.y - clip_rest_hip.y) * hip_scale, 0.0))
    elif not lock_xy and in_place and len(frame_seq) > 1:
        bpy.context.scene.frame_set(frame_seq[0])
        bpy.context.view_layer.update()
        p0 = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
        bpy.context.scene.frame_set(frame_seq[-1])
        bpy.context.view_layer.update()
        p1 = (clip_arm.matrix_world @ clip_arm.pose.bones["mixamorig:Hips"].head).copy()
        hip_anchor_xy = Vector((-(p0.x - clip_rest_hip.x) * hip_scale, -(p0.y - clip_rest_hip.y) * hip_scale, 0.0))
        hip_drift_xy = Vector((-(p1.x - p0.x) * hip_scale, -(p1.y - p0.y) * hip_scale, 0.0))

    prev_quats = {}
    span = max(1, len(frame_seq) - 1)
    for idx, src_f in enumerate(frame_seq):
        out_f = idx + 1
        t = idx / float(span)
        xy_off = hip_anchor_xy + hip_drift_xy * t
        bpy.context.scene.frame_set(src_f)
        bpy.context.view_layer.update()

        solved = solve_retargeted_frame(
            master_arm,
            clip_arm,
            ordered_bones,
            master_rest_hip,
            clip_rest_hip,
            hip_scale,
            xy_off,
            lock_xy=lock_xy,
            lock_z=lock_z,
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

    for o in list(new_objs):
        bpy.data.objects.remove(o, do_unlink=True)
    if src_act and src_act.users == 0:
        bpy.data.actions.remove(src_act)

    return act, len(frame_seq)


def load_mixamo_tpose_reference() -> dict[str, Matrix]:
    ref_fbx = DIR_OLD / "Idle.fbx"
    assert ref_fbx.exists(), f"Missing Mixamo T-pose reference: {ref_fbx}"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(ref_fbx))
    ref_arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ref_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    mix_rest_rot = {
        pb.name: (ref_arm.matrix_world @ pb.matrix).to_3x3().normalized()
        for pb in ref_arm.pose.bones
        if pb.name in MIXAMO_TO_BVH
    }
    assert len(mix_rest_rot) == len(BVH_TO_MIXAMO), f"Incomplete Mixamo ref bones: {len(mix_rest_rot)}"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return mix_rest_rot


def bake_bvh_to_action(
    master_arm,
    ordered_bones: list[str],
    master_rest_hip: Vector,
    mix_rest_rot: dict[str, Matrix],
    action_name: str,
    zip_path: Path,
    inner_bvh: str,
    lock_xy: bool = True,
    frame_slice: tuple[int, int] | None = None,
    reverse: bool = False,
) -> tuple[bpy.types.Action, int]:
    assert zip_path.exists(), f"Missing BVH zip: {zip_path}"
    with tempfile.TemporaryDirectory() as td:
        tmp_bvh = Path(td) / Path(inner_bvh).name
        with zipfile.ZipFile(zip_path) as z:
            tmp_bvh.write_bytes(z.read(inner_bvh))
        before_objs = set(bpy.data.objects)
        bpy.ops.import_anim.bvh(filepath=str(tmp_bvh), global_scale=0.01, axis_forward="-Z", axis_up="Y")
        new_objs = set(bpy.data.objects) - before_objs

    bpy.context.scene.render.fps = 30
    bvh_arm = next(o for o in new_objs if o.type == "ARMATURE")
    bvh_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()

    bvh_rest_hip = (bvh_arm.matrix_world @ bvh_arm.pose.bones["Hips"].head).copy()
    bvh_rest_lf = (bvh_arm.matrix_world @ bvh_arm.pose.bones["LeftFoot"].head).copy()
    bvh_rest_rf = (bvh_arm.matrix_world @ bvh_arm.pose.bones["RightFoot"].head).copy()
    bvh_hip_h = (bvh_rest_hip.z - min(bvh_rest_lf.z, bvh_rest_rf.z)) + 0.072
    hip_scale = master_rest_hip.z / max(bvh_hip_h, 1e-4)

    delta_rest = {}
    for s_name, m_name in BVH_TO_MIXAMO.items():
        if s_name in bvh_arm.pose.bones and m_name in mix_rest_rot:
            r_bvh = (bvh_arm.matrix_world @ bvh_arm.pose.bones[s_name].matrix).to_3x3().normalized()
            delta_rest[m_name] = r_bvh.inverted() @ mix_rest_rot[m_name]

    bvh_arm.data.pose_position = "POSE"
    src_act = bvh_arm.animation_data.action if bvh_arm.animation_data else None
    assert src_act is not None, f"No action in BVH {inner_bvh}"
    src_f0 = int(round(src_act.frame_range[0]))
    src_f1 = int(round(src_act.frame_range[1]))
    if frame_slice is not None:
        src_f0 = max(src_f0, frame_slice[0])
        src_f1 = min(src_f1, frame_slice[1])

    clear_pose_transforms(master_arm)
    act = bpy.data.actions.new(name=action_name)
    act.use_fake_user = True
    master_arm.animation_data.action = act

    frame_seq = list(range(src_f1, src_f0 - 1, -1)) if reverse else list(range(src_f0, src_f1 + 1))

    clip_f0_hip = Vector((0.0, 0.0, 0.0))
    if not lock_xy and len(frame_seq) > 0:
        bpy.context.scene.frame_set(frame_seq[0])
        bpy.context.view_layer.update()
        clip_f0_hip = (bvh_arm.matrix_world @ bvh_arm.pose.bones["Hips"].head).copy()

    master_arm_inv = master_arm.matrix_world.inverted()
    master_arm_inv_3 = master_arm_inv.to_3x3().normalized()
    prev_quats = {}

    for idx, src_f in enumerate(frame_seq):
        out_f = idx + 1
        bpy.context.scene.frame_set(src_f)
        bpy.context.view_layer.update()

        clip_hip_w = (bvh_arm.matrix_world @ bvh_arm.pose.bones["Hips"].head).copy()
        desired_z = master_rest_hip.z + (clip_hip_w.z - bvh_hip_h) * hip_scale
        if lock_xy:
            desired_hip_w = Vector((master_rest_hip.x, master_rest_hip.y, desired_z))
        else:
            desired_hip_w = Vector((
                master_rest_hip.x + (clip_hip_w.x - clip_f0_hip.x) * hip_scale,
                master_rest_hip.y + (clip_hip_w.y - clip_f0_hip.y) * hip_scale,
                desired_z,
            ))
        desired_hip_arm = master_arm_inv @ desired_hip_w

        arm_space_mats = {}
        for bname in ordered_bones:
            pb = master_arm.pose.bones[bname]
            B_b = pb.bone.matrix_local
            s_name = MIXAMO_TO_BVH.get(bname)
            if s_name and s_name in bvh_arm.pose.bones and bname in delta_rest:
                cpb = bvh_arm.pose.bones[s_name]
                r_world = (bvh_arm.matrix_world @ cpb.matrix).to_3x3().normalized() @ delta_rest[bname]
                desired_rot_3 = master_arm_inv_3 @ r_world
                if pb.parent is None:
                    M_b = Matrix.Translation(desired_hip_arm) @ desired_rot_3.to_4x4()
                    b_basis = B_b.inverted() @ M_b
                    loc = b_basis.translation.copy()
                else:
                    B_p = pb.parent.bone.matrix_local
                    M_p = arm_space_mats[pb.parent.name]
                    parent_head_arm = (M_p @ (B_p.inverted() @ B_b)).translation
                    M_b = Matrix.Translation(parent_head_arm) @ desired_rot_3.to_4x4()
                    b_basis = B_b.inverted() @ B_p @ M_p.inverted() @ M_b
                    loc = None
                q = b_basis.to_quaternion().normalized()
                if bname in prev_quats and prev_quats[bname].dot(q) < 0.0:
                    q = -q
                prev_quats[bname] = q.copy()
                if pb.parent is None and loc is not None:
                    pb.location = loc
                    pb.keyframe_insert(data_path="location", frame=out_f)
                pb.rotation_quaternion = q
                pb.keyframe_insert(data_path="rotation_quaternion", frame=out_f)
                arm_space_mats[bname] = M_b
            else:
                B_p = pb.parent.bone.matrix_local
                M_p = arm_space_mats[pb.parent.name]
                arm_space_mats[bname] = M_p @ B_p.inverted() @ B_b

    for o in list(new_objs):
        bpy.data.objects.remove(o, do_unlink=True)
    if src_act and src_act.users == 0:
        bpy.data.actions.remove(src_act)

    return act, len(frame_seq)


def bake_clip_from_spec(
    master_arm,
    ordered_bones: list[str],
    master_rest_hip: Vector,
    mix_rest_rot: dict[str, Matrix],
    prefix: str,
    spec: dict,
) -> tuple[bpy.types.Action, int]:
    clip_name = spec["clip"]
    lock_xy = bool(spec.get("lock_xy", False))
    lock_z = bool(spec.get("lock_z", False))
    reverse = bool(spec.get("reverse", False))
    frame_slice = spec.get("slice")
    if "zip" in spec:
        return bake_bvh_to_action(
            master_arm,
            ordered_bones,
            master_rest_hip,
            mix_rest_rot,
            f"{prefix}_{clip_name}",
            spec["zip"],
            spec["bvh"],
            lock_xy=lock_xy,
            frame_slice=frame_slice,
            reverse=reverse,
        )
    return bake_fbx_to_action(
        master_arm,
        ordered_bones,
        master_rest_hip,
        f"{prefix}_{clip_name}",
        spec["path"],
        spec.get("in_place", True),
        frame_slice=frame_slice,
        lock_xy=lock_xy,
        reverse=reverse,
        end_at_origin=bool(spec.get("end_at_origin", False)),
        lock_z=lock_z,
    )


def sample_action_poses(master_arm, ordered_bones: list[str], act: bpy.types.Action, num_frames: int) -> list[dict]:
    master_arm.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots) > 0:
        master_arm.animation_data.action_slot = act.slots[0]
    samples = []
    for f in range(1, num_frames + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        frame_data = {}
        for bname in ordered_bones:
            pb = master_arm.pose.bones[bname]
            frame_data[bname] = (pb.location.copy() if pb.parent is None else None, pb.rotation_quaternion.copy())
        samples.append(frame_data)
    return samples


def build_composite_jalwa_action(
    master_arm,
    ordered_bones: list[str],
    master_rest_hip: Vector,
    mix_rest_rot: dict[str, Matrix],
) -> tuple[bpy.types.Action, int]:
    """Reworked Kaptaan Jalwa: sky lightning summon (cast_lightning_bolt 26..54) + 5-frame SLERP + double-fist slam (cast_area_explosion 38..104)."""
    act_a, n_a = bake_bvh_to_action(
        master_arm,
        ordered_bones,
        master_rest_hip,
        mix_rest_rot,
        "_TmpLightningSummon",
        ZIP_FANTASY,
        "Motifect_fantasy_and_magic_v1_0/BVH/cast_lightning_bolt.bvh",
        lock_xy=True,
        frame_slice=(26, 54),
    )
    act_b, n_b = bake_bvh_to_action(
        master_arm,
        ordered_bones,
        master_rest_hip,
        mix_rest_rot,
        "_TmpAreaSlam",
        ZIP_FANTASY,
        "Motifect_fantasy_and_magic_v1_0/BVH/cast_area_explosion.bvh",
        lock_xy=True,
        frame_slice=(38, 104),
    )
    samples_a = sample_action_poses(master_arm, ordered_bones, act_a, n_a)
    samples_b = sample_action_poses(master_arm, ordered_bones, act_b, n_b)

    blend_n = 5
    combined = list(samples_a[:-1])
    end_a = samples_a[-1]
    start_b = samples_b[0]
    for k in range(1, blend_n + 1):
        alpha = k / float(blend_n + 1)
        blended = {}
        for bname in ordered_bones:
            loc_a, qa = end_a[bname]
            loc_b, qb = start_b[bname]
            if qa.dot(qb) < 0.0:
                qb = -qb
            q = qa.slerp(qb, alpha).normalized()
            loc = loc_a.lerp(loc_b, alpha) if (loc_a is not None and loc_b is not None) else None
            blended[bname] = (loc, q)
        combined.append(blended)
    combined.extend(samples_b)

    clear_pose_transforms(master_arm)
    act = bpy.data.actions.new(name="Khan_JalwaSuper")
    act.use_fake_user = True
    master_arm.animation_data.action = act
    prev_quats = {}
    for idx, frame_pose in enumerate(combined, start=1):
        for bname in ordered_bones:
            pb = master_arm.pose.bones[bname]
            loc, q = frame_pose[bname]
            if bname in prev_quats and prev_quats[bname].dot(q) < 0.0:
                q = -q
            prev_quats[bname] = q.copy()
            if pb.parent is None and loc is not None:
                pb.location = loc
                pb.keyframe_insert(data_path="location", frame=idx)
            pb.rotation_quaternion = q
            pb.keyframe_insert(data_path="rotation_quaternion", frame=idx)

    bpy.data.actions.remove(act_a)
    bpy.data.actions.remove(act_b)
    return act, len(combined)


# ---- Khan Vectorized Kameez Drape Solver (adapted from repair_chaak_and_clearance.py) ----
def panel_angle(side: int, col: int) -> float:
    span = HALF_FRONT if side == 0 else HALF_BACK
    return -span + col * (2.0 * span / 8.0)


def build_rest_grid() -> np.ndarray:
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


def build_constraints(rest: np.ndarray):
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


def _front_mask():
    m = np.zeros(NZ * NA, dtype=bool)
    for j in range(NZ - 1):
        m[j * NA : j * NA + 9] = True
    return m


def _back_mask():
    m = np.zeros(NZ * NA, dtype=bool)
    for j in range(NZ - 1):
        m[j * NA + 9 : (j + 1) * NA] = True
    return m


FRONT_MOVABLE = _front_mask()
BACK_MOVABLE = _back_mask()


def get_tapered_capsules(rig):
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

        out.append((a_up, b_up, 0.148 + 0.028 * lift, 0.136 + 0.032 * lift, lift, True))
        mid_thigh = 0.45 * a_up + 0.55 * b_up
        out.append((pelvis_mid, mid_thigh, 0.146 + 0.026 * lift, 0.140 + 0.028 * lift, lift, True))

        a_leg = np.array(rig.matrix_world @ q.head, dtype=np.float64)
        b_leg = np.array(rig.matrix_world @ q.tail, dtype=np.float64)
        out.append((a_leg, b_leg, 0.126 + 0.020 * lift, 0.112 + 0.014 * lift, lift, True))
    out.append((l_hip, r_hip, 0.144, 0.144, 0.0, False))
    return out


def collide_tapered(x, caps, pin, ea, eb, mass, up_fwd_vec, back_vec):
    for a, b, r0, r1, lift, is_thigh in caps:
        ab = b - a
        ab2 = max(float(np.dot(ab, ab)), 1e-8)
        t = np.clip(((x - a) * ab).sum(axis=1) / ab2, 0.0, 1.0)
        r = r0 * (1.0 - t) + r1 * t
        d = x - (a + t[:, None] * ab)
        dist = np.linalg.norm(d, axis=1)
        n = d / np.maximum(dist[:, None], 1e-8)
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
    x[-NA:] = pin


def solve_drape_for_action(rig, action: bpy.types.Action, num_frames: int, drape_ctx: dict) -> None:
    rest = drape_ctx["rest"]
    ea, eb, stiff, lengths, mass, denom, colors = drape_ctx["constraints"]
    bone_inv = drape_ctx["bone_inv"]
    hips = rig.pose.bones["mixamorig:Hips"]

    def hips_delta():
        return rig.matrix_world @ hips.matrix @ hips.bone.matrix_local.inverted() @ rig.matrix_world.inverted()

    def solve_step(x, prev, pin, caps, dt, up_fwd_vec, back_vec, target, apply_recovery=True):
        old = x.copy()
        vel = (x - prev) * 0.94
        vel *= np.minimum(1.0, 0.045 / np.maximum(np.linalg.norm(vel, axis=1), 1e-8))[:, None]
        x += vel
        x[:, 2] -= 9.81 * dt * dt
        if apply_recovery:
            x += (target - x) * 0.032 * mass[:, None]
        x[-NA:] = pin
        for _ in range(8):
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

    rig.animation_data.action = action
    if hasattr(action, "slots") and len(action.slots) > 0:
        rig.animation_data.action_slot = action.slots[0]

    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    m = hips_delta()
    x_init = np.array([m @ Vector(p) for p in rest], dtype=np.float64)
    x = x_init.copy()
    prev = x.copy()
    caps = get_tapered_capsules(rig)
    fwd_vec = np.array((m.to_3x3() @ Vector((0.0, -0.55, 0.85))).normalized(), dtype=np.float64)
    back_vec = np.array((m.to_3x3() @ Vector((0.0, 0.90, -0.15))).normalized(), dtype=np.float64)
    for _ in range(24):
        x, prev = solve_step(x, prev, x[-NA:].copy(), caps, 1.0 / 60.0, fwd_vec, back_vec, x_init, apply_recovery=False)

    all_offsets = []
    old_caps = caps
    old_pin = x[-NA:].copy()
    for frame in range(1, num_frames + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        m = hips_delta()
        mi = m.inverted()
        caps = get_tapered_capsules(rig)
        pin = np.array([m @ Vector(p) for p in rest[-NA:]], dtype=np.float64)
        fwd_vec = np.array((m.to_3x3() @ Vector((0.0, -0.55, 0.85))).normalized(), dtype=np.float64)
        back_vec = np.array((m.to_3x3() @ Vector((0.0, 0.90, -0.15))).normalized(), dtype=np.float64)
        target = np.array([m @ Vector(p) for p in rest], dtype=np.float64)
        for sub in range(2):
            frac = (sub + 1) / 2.0
            inter = [
                (a0 * (1.0 - frac) + a * frac, b0 * (1.0 - frac) + b * frac, r0, r1, lift, is_t)
                for (a0, b0, _, _, _, _), (a, b, r0, r1, lift, is_t) in zip(old_caps, caps)
            ]
            x, prev = solve_step(x, prev, old_pin * (1.0 - frac) + pin * frac, inter, 1.0 / 60.0, fwd_vec, back_vec, target)
        old_caps = caps
        old_pin = pin
        offset = np.array([mi @ Vector(p) for p in x], dtype=np.float64) - rest
        offset = np.clip(offset, -0.95, 0.95)
        all_offsets.append(offset)

    for k, frame in enumerate(range(1, num_frames + 1)):
        for (j, i), inv_mat in bone_inv.items():
            p = rig.pose.bones[f"drape_{j}_{i}"]
            p.location = inv_mat @ Vector(all_offsets[k][j * NA + i])
            p.keyframe_insert("location", frame=frame, group="Draped garment")


def decimate_and_export(rig, body, weight_fn, target_tris: int, double_sided: bool, glb_out: Path) -> dict:
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()

    panel_group_indices = {
        g.index for g in body.vertex_groups if g.name in ("Kameez_Surface", "kameez_skirt") or g.name.startswith("drape_")
    }
    vg = body.vertex_groups.get("CollapsePriority") or body.vertex_groups.new(name="CollapsePriority")
    for v in body.data.vertices:
        vg.add([v.index], weight_fn(v, panel_group_indices), "REPLACE")

    bpy.ops.object.select_all(action="DESELECT")
    body.hide_viewport = False
    rig.hide_viewport = False
    body.select_set(True)
    bpy.context.view_layer.objects.active = body

    source_tris = len(body.data.polygons)
    ratio = max(0.05, min(1.0, float(target_tris) / float(source_tris)))
    mod = body.modifiers.new(name="LOD0_Decimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.vertex_group = vg.name
    mod.invert_vertex_group = False
    mod.vertex_group_factor = 4.0
    mod.use_collapse_triangulate = True
    mod.delimit = {"UV", "MATERIAL"}
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)

    vg_after = body.vertex_groups.get("CollapsePriority")
    if vg_after is not None:
        body.vertex_groups.remove(vg_after)

    if body.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for poly in body.data.polygons:
        poly.use_smooth = True
    body.data.update()
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)

    if double_sided:
        for slot in body.material_slots:
            if slot.material:
                slot.material.use_backface_culling = False

    rig.data.pose_position = "POSE"
    clear_pose_transforms(rig)
    if rig.animation_data:
        rig.animation_data.action = None
        for trk in rig.animation_data.nla_tracks:
            trk.mute = False

    if body.parent != rig:
        mw = body.matrix_world.copy()
        body.parent = rig
        body.matrix_world = mw

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(glb_out.parent, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(glb_out),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
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

    with open(glb_out, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(clen))
    return {
        "source_tris": source_tris,
        "final_tris": len(body.data.polygons),
        "mb": round(glb_out.stat().st_size / (1024 * 1024), 2),
        "animations": [a.get("name") for a in gltf.get("animations", [])],
        "skin_joints": [len(s["joints"]) for s in gltf.get("skins", [])],
    }


def _khan_collapse_weight(v, panel_group_indices: set[int]) -> float:
    x, y, z = v.co.x, v.co.y, v.co.z
    ax = abs(x)
    for g in v.groups:
        if g.group in panel_group_indices and g.weight > 0.01:
            return 0.0
    w = 1.0
    if 0.54 <= z <= 1.06 and ax < 0.25:
        w = min(w, 0.05)
    if z > 1.46:
        w = min(w, 0.15)
    if z < 1.15 and ax > 0.42:
        w = min(w, 0.15)
    if z < 0.14:
        w = min(w, 0.15)
    return w


def _asim_collapse_weight(v, _panel_group_indices: set[int]) -> float:
    x, y, z = v.co.x, v.co.y, v.co.z
    ax = abs(x)
    w = 1.0
    if z > 1.46:
        w = min(w, 0.14)
    if z < 1.08 and ax > 0.47:
        w = min(w, 0.14)
    if 1.00 <= z <= 1.44 and ax < 0.32 and y < 0.04:
        w = min(w, 0.20)
    if z < 0.16:
        w = min(w, 0.20)
    return w


def _iter_action_fcurves(act: bpy.types.Action):
    if hasattr(act, "fcurves") and act.fcurves:
        for fc in act.fcurves:
            yield fc
    for layer in getattr(act, "layers", ()):
        for strip in getattr(layer, "strips", ()):
            for cb in getattr(strip, "channelbags", ()):
                for fc in getattr(cb, "fcurves", ()):
                    yield fc


def verify_actions_and_lock_xy(
    rig,
    tracks: list[tuple[str, bpy.types.Action]],
    master_rest_hip: Vector,
    lock_xy_clips: set[str],
    clip_frames: dict[str, int],
) -> dict:
    nan_count = 0
    max_locked_drift = 0.0
    for clip_name, act in tracks:
        for fc in _iter_action_fcurves(act):
            for kp in fc.keyframe_points:
                if not math.isfinite(kp.co[0]) or not math.isfinite(kp.co[1]):
                    nan_count += 1
        if clip_name in lock_xy_clips:
            n_frames = clip_frames.get(clip_name, int(round(act.frame_range[1])))
            rig.animation_data.action = act
            if hasattr(act, "slots") and len(act.slots) > 0:
                rig.animation_data.action_slot = act.slots[0]
            for f in range(1, n_frames + 1):
                bpy.context.scene.frame_set(f)
                bpy.context.view_layer.update()
                hip = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
                drift = math.hypot(hip.x - master_rest_hip.x, hip.y - master_rest_hip.y)
                if drift > max_locked_drift:
                    max_locked_drift = drift
    rig.animation_data.action = None
    assert nan_count == 0, f"Detected {nan_count} non-finite keyframes"
    assert max_locked_drift < 0.005, f"lock_xy drift too high: {max_locked_drift:.4f}m"
    return {
        "nan_keyframes": nan_count,
        "max_locked_hips_xy_drift_m": round(max_locked_drift, 6),
        "clip_frames": clip_frames,
    }


def build_khan(mix_rest_rot: dict[str, Matrix]) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(KHAN_BLEND_IN))
    bpy.context.scene.render.fps = 30
    rig = bpy.data.objects["Khan_Garment_Rig"]
    body = bpy.data.objects["Khan_Garment_Body"]

    for trk in rig.animation_data.nla_tracks:
        trk.mute = True
    rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    master_rest_hip = (rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head).copy()
    rig.data.pose_position = "POSE"

    ordered_bones = hierarchy_order(rig, "mixamorig:")
    rest = build_rest_grid()
    constraints = build_constraints(rest)
    inv3 = rig.matrix_world.inverted().to_3x3()
    bone_inv = {
        (j, i): rig.pose.bones[f"drape_{j}_{i}"].bone.matrix_local.to_3x3().inverted() @ inv3
        for j in range(NZ)
        for i in range(NA)
    }
    drape_ctx = {"rest": rest, "constraints": constraints, "bone_inv": bone_inv}

    # Keep the proven existing draped actions for LightCombo (old Punch) and MmaKick;
    # Idle2 is now rebuilt from Bouncing Fight Idle.fbx via KHAN_NEW_CLIPS.
    tracks_to_pack: list[tuple[str, bpy.types.Action]] = [
        ("LightCombo", bpy.data.actions["Draped_Punch"]),
        ("MmaKick", bpy.data.actions["Draped_MmaKick"]),
    ]
    clip_frames: dict[str, int] = {
        "LightCombo": int(round(bpy.data.actions["Draped_Punch"].frame_range[1])),
        "MmaKick": int(round(bpy.data.actions["Draped_MmaKick"].frame_range[1])),
    }
    lock_xy_clips: set[str] = {"JalwaSuper"}

    for spec in KHAN_NEW_CLIPS:
        clip_name = spec["clip"]
        lock_xy = bool(spec.get("lock_xy", False))
        reverse = bool(spec.get("reverse", False))
        if lock_xy:
            lock_xy_clips.add(clip_name)
        act, n_frames = bake_clip_from_spec(
            rig, ordered_bones, master_rest_hip, mix_rest_rot, "KhanP3", spec
        )
        solve_drape_for_action(rig, act, n_frames, drape_ctx)
        tracks_to_pack.append((clip_name, act))
        clip_frames[clip_name] = n_frames
        print(f"KHAN_CLIP_BAKED: {clip_name} ({n_frames} frames, lock_xy={lock_xy}, reverse={reverse})", flush=True)

    jalwa_act, jalwa_frames = build_composite_jalwa_action(rig, ordered_bones, master_rest_hip, mix_rest_rot)
    solve_drape_for_action(rig, jalwa_act, jalwa_frames, drape_ctx)
    tracks_to_pack.append(("JalwaSuper", jalwa_act))
    clip_frames["JalwaSuper"] = jalwa_frames
    print(f"KHAN_CLIP_BAKED: JalwaSuper ({jalwa_frames} frames, lock_xy=True)", flush=True)

    qa_stats = verify_actions_and_lock_xy(rig, tracks_to_pack, master_rest_hip, lock_xy_clips, clip_frames)

    clear_pose_transforms(rig)
    rig.animation_data.action = None
    for trk in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(trk)
    for clip_name, act in tracks_to_pack:
        trk = rig.animation_data.nla_tracks.new()
        trk.name = clip_name
        strip = trk.strips.new(clip_name, 1, act)
        strip.name = clip_name
        if hasattr(act, "slots") and len(act.slots) > 0:
            strip.action_slot = act.slots[0]
        trk.mute = False

    bpy.ops.wm.save_as_mainfile(filepath=str(KHAN_BLEND_OUT))
    out = decimate_and_export(rig, body, _khan_collapse_weight, 62000, True, KHAN_GLB_OUT)
    out.update(qa_stats)
    return out


def build_asim(mix_rest_rot: dict[str, Matrix]) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(ASIM_BLEND_IN))
    bpy.context.scene.render.fps = 30
    rig = bpy.data.objects["Armature"]
    body = bpy.data.objects["Asim_Model1_Restored"]

    for trk in rig.animation_data.nla_tracks:
        trk.mute = True
    rig.animation_data.action = None
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    master_rest_hip = (rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head).copy()
    rig.data.pose_position = "POSE"

    ordered_bones = hierarchy_order(rig, "mixamorig:")
    replace_clips = {spec["clip"] for spec in ASIM_EXTRA_CLIPS}
    existing_tracks = []
    clip_frames: dict[str, int] = {}
    for trk in rig.animation_data.nla_tracks:
        if trk.name in replace_clips:
            continue
        if trk.strips and trk.strips[0].action:
            act = trk.strips[0].action
            existing_tracks.append((trk.name, act))
            clip_frames[trk.name] = int(round(act.frame_range[1]))

    lock_xy_clips: set[str] = set()
    for spec in ASIM_EXTRA_CLIPS:
        clip_name = spec["clip"]
        if any(name == clip_name for name, _ in existing_tracks):
            continue
        lock_xy = bool(spec.get("lock_xy", False))
        reverse = bool(spec.get("reverse", False))
        if lock_xy:
            lock_xy_clips.add(clip_name)
        act, n_frames = bake_clip_from_spec(
            rig, ordered_bones, master_rest_hip, mix_rest_rot, "AsimP3", spec
        )
        existing_tracks.append((clip_name, act))
        clip_frames[clip_name] = n_frames
        print(f"ASIM_CLIP_BAKED: {clip_name} ({n_frames} frames, lock_xy={lock_xy}, reverse={reverse})", flush=True)

    qa_stats = verify_actions_and_lock_xy(rig, existing_tracks, master_rest_hip, lock_xy_clips, clip_frames)

    clear_pose_transforms(rig)
    rig.animation_data.action = None
    for trk in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(trk)
    for clip_name, act in existing_tracks:
        trk = rig.animation_data.nla_tracks.new()
        trk.name = clip_name
        strip = trk.strips.new(clip_name, 1, act)
        strip.name = clip_name
        if hasattr(act, "slots") and len(act.slots) > 0:
            strip.action_slot = act.slots[0]
        trk.mute = False

    bpy.ops.wm.save_as_mainfile(filepath=str(ASIM_BLEND_OUT))
    out = decimate_and_export(rig, body, _asim_collapse_weight, 62000, False, ASIM_GLB_OUT)
    out.update(qa_stats)
    return out


def main() -> None:
    mix_rest_rot = load_mixamo_tpose_reference()
    only = os.environ.get("P3_ONLY", "").strip().lower()
    report: dict = {}
    if only in ("khan", "asim") and REPORT_OUT.exists():
        try:
            report = json.loads(REPORT_OUT.read_text(encoding="utf-8"))
        except Exception:
            report = {}
    if only in ("", "khan"):
        report["khan"] = build_khan(mix_rest_rot)
    if only in ("", "asim"):
        report["asim"] = build_asim(mix_rest_rot)
    os.makedirs(REPORT_OUT.parent, exist_ok=True)
    REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("P3_CHARACTERS_EXPORTED:", json.dumps(report))


if __name__ == "__main__":
    main()
