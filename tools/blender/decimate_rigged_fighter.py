"""Reusable Blender 4.5 CLI script to decimate rigged fighters to ~60k LOD0 triangles.

Preserves high-detail regions (head/face, hands/fingers, medals/cap, footwear, and
Khan's repaired chaak/drape panels), UVs/material seams, normalized deform weights,
PBR materials, and NLA animation tracks without modifying the high-poly .blend masters.

Usage:
  blender -b -P tools/blender/decimate_rigged_fighter.py -- --character all
  blender -b -P tools/blender/decimate_rigged_fighter.py -- --character khan --target-tris 60000
"""

import argparse
import json
import os
import struct
import sys
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[2]


def _khan_collapse_weight(v, panel_group_indices: set[int]) -> float:
    x, y, z = v.co.x, v.co.y, v.co.z
    ax = abs(x)

    # 100% protect repaired Kameez front/back drape panels (chaak clearance).
    for g in v.groups:
        if g.group in panel_group_indices and g.weight > 0.01:
            return 0.0

    w = 1.0
    # Protect waist/chaak clearance zone on inner hips/trousers.
    if 0.54 <= z <= 1.06 and ax < 0.25:
        w = min(w, 0.05)
    # Protect head, face, hair.
    if z > 1.46:
        w = min(w, 0.15)
    # Protect hands & fingers.
    if z < 1.15 and ax > 0.42:
        w = min(w, 0.15)
    # Protect sandals / footwear.
    if z < 0.14:
        w = min(w, 0.15)
    return w


def _asim_collapse_weight(v, _panel_group_indices: set[int]) -> float:
    x, y, z = v.co.x, v.co.y, v.co.z
    ax = abs(x)
    w = 1.0
    # Protect face & peaked officer cap.
    if z > 1.46:
        w = min(w, 0.14)
    # Protect 5-fingered hands.
    if z < 1.08 and ax > 0.47:
        w = min(w, 0.14)
    # Protect chest medals, sash, belt, collar.
    if 1.00 <= z <= 1.44 and ax < 0.32 and y < 0.04:
        w = min(w, 0.20)
    # Protect boots / footwear.
    if z < 0.16:
        w = min(w, 0.20)
    return w


CONFIGS = {
    "khan": {
        "blend": ROOT / "outputs/khan-model2/blender/khan-model2-recovery-trial.blend",
        "glb_out": ROOT / "game/assets/characters/khan_recovery_trial.glb",
        "report_out": ROOT / "outputs/p1-tech-spikes/decimation-khan.json",
        "armature_name": "Khan_Garment_Rig",
        "mesh_name": "Khan_Garment_Body",
        "target_tris": 62000,
        "double_sided": True,
        "weight_fn": _khan_collapse_weight,
    },
    "asim": {
        "blend": ROOT / "outputs/asim-model1/blender/asim-model1-final-rig.blend",
        "glb_out": ROOT / "game/assets/characters/asim_model1.glb",
        "report_out": ROOT / "outputs/p1-tech-spikes/decimation-asim.json",
        "armature_name": "Armature",
        "mesh_name": "Asim_Model1_Restored",
        "target_tris": 62000,
        "double_sided": False,
        "weight_fn": _asim_collapse_weight,
    },
}


def inspect_glb_summary(glb_path: Path) -> dict:
    with open(glb_path, "rb") as f:
        f.read(12)
        chunk_len, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(chunk_len))
    return {
        "bytes": glb_path.stat().st_size,
        "mb": round(glb_path.stat().st_size / (1024 * 1024), 2),
        "animations": [a.get("name") for a in gltf.get("animations", [])],
        "meshes": len(gltf.get("meshes", [])),
        "skin_joints": [len(s["joints"]) for s in gltf.get("skins", [])],
        "images": len(gltf.get("images", [])),
    }


def process_character(key: str, target_override: int | None = None) -> dict:
    cfg = CONFIGS[key]
    target_tris = target_override if target_override is not None else int(cfg["target_tris"])

    bpy.ops.wm.open_mainfile(filepath=str(cfg["blend"]))
    rig = bpy.data.objects[cfg["armature_name"]]
    body = bpy.data.objects[cfg["mesh_name"]]

    source_tris = len(body.data.polygons)
    source_verts = len(body.data.vertices)
    panel_group_indices = {
        g.index
        for g in body.vertex_groups
        if g.name in ("Kameez_Surface", "kameez_skirt") or g.name.startswith("drape_")
    }
    source_panel_verts = sum(
        1
        for v in body.data.vertices
        if any(g.group in panel_group_indices and g.weight > 0.01 for g in v.groups)
    )

    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()

    vg = body.vertex_groups.get("CollapsePriority") or body.vertex_groups.new(name="CollapsePriority")
    weight_fn = cfg["weight_fn"]
    for v in body.data.vertices:
        vg.add([v.index], weight_fn(v, panel_group_indices), "REPLACE")

    bpy.ops.object.select_all(action="DESELECT")
    body.hide_viewport = False
    body.hide_render = False
    rig.hide_viewport = False
    rig.hide_render = False
    body.select_set(True)
    bpy.context.view_layer.objects.active = body

    ratio = max(0.05, min(1.0, float(target_tris) / float(source_tris)))
    mod = body.modifiers.new(name="LOD0_Decimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.vertex_group = vg.name
    mod.invert_vertex_group = False
    mod.vertex_group_factor = 4.0
    mod.use_collapse_triangulate = True
    mod.delimit = {"UV", "MATERIAL"}

    # Place Decimate before Armature so collapse evaluates in bind/rest space.
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

    # Normalize skin weights for bone deform groups only.
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)

    if cfg["double_sided"]:
        for slot in body.material_slots:
            if slot.material:
                slot.material.use_backface_culling = False

    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    final_tris = len(bm.faces)
    final_verts = len(bm.verts)
    nonmanifold_edges = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()

    deform_names = {b.name for b in rig.data.bones if b.use_deform}
    deform_indices = {g.index for g in body.vertex_groups if g.name in deform_names}
    unweighted_verts = sum(
        1
        for v in body.data.vertices
        if sum(g.weight for g in v.groups if g.group in deform_indices) <= 1e-4
    )
    final_panel_verts = sum(
        1
        for v in body.data.vertices
        if any(g.group in panel_group_indices and g.weight > 0.01 for g in v.groups)
    )

    rig.data.pose_position = "POSE"
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

    glb_out: Path = cfg["glb_out"]
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

    glb_info = inspect_glb_summary(glb_out)
    report = {
        "character": key,
        "source_blend": str(cfg["blend"].relative_to(ROOT)),
        "glb_out": str(glb_out.relative_to(ROOT)),
        "source_triangles": source_tris,
        "source_vertices": source_verts,
        "target_triangles": target_tris,
        "final_triangles": final_tris,
        "final_vertices": final_verts,
        "reduction_percent": round((1.0 - float(final_tris) / float(source_tris)) * 100.0, 2),
        "unweighted_vertices": unweighted_verts,
        "nonmanifold_edges": nonmanifold_edges,
        "source_panel_vertices": source_panel_verts,
        "final_panel_vertices": final_panel_verts,
        "uv_layers": [uv.name for uv in body.data.uv_layers],
        "glb": glb_info,
    }
    report_out: Path = cfg["report_out"]
    os.makedirs(report_out.parent, exist_ok=True)
    report_out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("DECIMATE_RESULT", json.dumps(report), flush=True)
    assert unweighted_verts == 0, f"Unweighted vertices on {key}: {unweighted_verts}"
    assert 40000 <= final_tris <= 70000, f"Final triangles {final_tris} outside 40k-70k budget"
    return report


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--character", choices=["all", "khan", "asim"], default="all")
    parser.add_argument("--target-tris", type=int, default=None)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    targets = ["khan", "asim"] if args.character == "all" else [args.character]
    for char_key in targets:
        process_character(char_key, args.target_tris)


if __name__ == "__main__":
    main()
