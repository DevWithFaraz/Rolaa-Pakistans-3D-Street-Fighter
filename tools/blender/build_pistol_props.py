"""Build M1911 pistol (m1911_pistol.glb) and .45 ACP bullet (bullet_45acp.glb) props."""

import json
import math
import os
import struct
import tempfile
import zipfile
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SHOOT_DIR = Path(r"C:\Users\IT\Downloads\shoot")
FBX_ZIP = SHOOT_DIR / "fbx.zip"
PISTOL_GLB_OUT = ROOT / "game/assets/props/m1911_pistol.glb"
BULLET_GLB_OUT = ROOT / "game/assets/props/bullet_45acp.glb"
REPORT_OUT = ROOT / "outputs/p3-animations/pistol-props-report.json"

PISTOL_MATERIALS = {
    "Slide": {"base_color": (0.18, 0.20, 0.23, 1.0), "metallic": 0.65, "roughness": 0.28},
    "Frame": {"base_color": (0.08, 0.09, 0.105, 1.0), "metallic": 0.45, "roughness": 0.42},
    "Barrel": {"base_color": (0.74, 0.78, 0.84, 1.0), "metallic": 0.72, "roughness": 0.20},
    "Grip": {"base_color": (0.035, 0.038, 0.042, 1.0), "metallic": 0.0, "roughness": 0.75},
    "Mag": {"base_color": (0.06, 0.065, 0.075, 1.0), "metallic": 0.50, "roughness": 0.45},
    "Ammo": {"base_color": (0.88, 0.68, 0.24, 1.0), "metallic": 0.78, "roughness": 0.24},
}


def _make_pbr_material(
    name: str,
    base_color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission_color: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_color is not None and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = emission_color
    if emission_strength > 0.0 and "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat


def _read_glb_header(path: Path) -> dict:
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(clen))
    meshes = gltf.get("meshes", [])
    return {
        "glb_bytes": path.stat().st_size,
        "meshes": len(meshes),
        "primitives": len(meshes[0].get("primitives", [])) if meshes else 0,
        "materials": [m.get("name") for m in gltf.get("materials", [])],
        "nodes": [n.get("name") for n in gltf.get("nodes", [])],
    }


def build_pistol() -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory() as td:
        with zipfile.ZipFile(FBX_ZIP, "r") as zf:
            zf.extract("FBX/Rigged/Rigged_M1911.fbx", td)
        fbx_path = Path(td) / "FBX/Rigged/Rigged_M1911.fbx"
        bpy.ops.import_scene.fbx(filepath=str(fbx_path))

    pistol = bpy.data.objects.get("M1911")
    assert pistol is not None and pistol.type == "MESH", "M1911 mesh not found in Rigged_M1911.fbx"

    bpy.ops.object.select_all(action="DESELECT")
    pistol.select_set(True)
    bpy.context.view_layer.objects.active = pistol
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

    for obj in list(bpy.data.objects):
        if obj != pistol:
            bpy.data.objects.remove(obj, do_unlink=True)

    pistol.data = pistol.data.copy()
    for mod in list(pistol.modifiers):
        if mod.type == "ARMATURE":
            pistol.modifiers.remove(mod)

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Replace materials IN PLACE so polygon material_index slots (Grip/Slide/Frame/Barrel/Ammo/Mag) stay intact.
    for idx in range(len(pistol.data.materials)):
        slot_mat = pistol.data.materials[idx]
        raw_name = slot_mat.name.split(".")[0] if slot_mat else "Frame"
        spec = PISTOL_MATERIALS.get(raw_name, PISTOL_MATERIALS["Frame"])
        pistol.data.materials[idx] = _make_pbr_material(
            f"M1911_{raw_name}",
            spec["base_color"],
            spec["metallic"],
            spec["roughness"],
        )

    for img in list(bpy.data.images):
        bpy.data.images.remove(img)

    # Shift Grip center (0.036, 0, -0.025) to (0,0,0) and rotate -90 deg around +Z, transforming custom split normals cleanly.
    xform = Matrix.Rotation(-math.pi * 0.5, 4, "Z") @ Matrix.Translation(Vector((-0.036, 0.0, 0.025)))
    pistol.data.transform(xform)
    pistol.data.update()
    assert pistol.data.has_custom_normals, "M1911 lost custom split normals after transform"

    muzzle = bpy.data.objects.new("MuzzlePoint", None)
    muzzle.empty_display_type = "PLAIN_AXES"
    muzzle.empty_display_size = 0.03
    muzzle.parent = pistol
    muzzle.location = Vector((0.0, 0.192, 0.070))
    bpy.context.collection.objects.link(muzzle)

    os.makedirs(PISTOL_GLB_OUT.parent, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    pistol.select_set(True)
    muzzle.select_set(True)
    bpy.context.view_layer.objects.active = pistol
    bpy.ops.export_scene.gltf(
        filepath=str(PISTOL_GLB_OUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_yup=True,
        export_normals=True,
        export_materials="EXPORT",
        export_apply=True,
    )

    info = _read_glb_header(PISTOL_GLB_OUT)
    assert info["primitives"] == 6, f"Expected 6 material primitives on M1911, got {info['primitives']}"
    info["has_custom_normals"] = bool(pistol.data.has_custom_normals)
    info["tris"] = sum(max(1, len(p.vertices) - 2) for p in pistol.data.polygons)
    info["dimensions_m"] = [round(float(v), 4) for v in pistol.dimensions]
    return info


def build_bullet() -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory() as td:
        with zipfile.ZipFile(FBX_ZIP, "r") as zf:
            zf.extract("FBX/NonRigged/NonRigged_45ACP_Ammo.fbx", td)
        fbx_path = Path(td) / "FBX/NonRigged/NonRigged_45ACP_Ammo.fbx"
        bpy.ops.import_scene.fbx(filepath=str(fbx_path))

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    assert meshes, "No mesh found in NonRigged_45ACP_Ammo.fbx"
    bullet = meshes[0]
    bullet.name = "Bullet45ACP"

    bpy.ops.object.select_all(action="DESELECT")
    bullet.select_set(True)
    bpy.context.view_layer.objects.active = bullet
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

    for obj in list(bpy.data.objects):
        if obj != bullet:
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    bullet.location = Vector((0.0, 0.0, 0.0))

    # Determine which Z extreme is the rounded nose by comparing mean radial distance of top vs bottom 15%.
    zs = [v.co.z for v in bullet.data.vertices]
    z_min, z_max = min(zs), max(zs)
    z_span = max(1e-6, z_max - z_min)
    top_radii = [math.hypot(v.co.x, v.co.y) for v in bullet.data.vertices if v.co.z >= z_max - 0.15 * z_span]
    bot_radii = [math.hypot(v.co.x, v.co.y) for v in bullet.data.vertices if v.co.z <= z_min + 0.15 * z_span]
    mean_top_r = sum(top_radii) / max(1, len(top_radii))
    mean_bot_r = sum(bot_radii) / max(1, len(bot_radii))

    # Point the narrow nose along +X in both Blender and Godot.
    rot_y = math.pi * 0.5 if mean_top_r < mean_bot_r else -math.pi * 0.5
    bullet.rotation_euler = (0.0, rot_y, 0.0)
    bpy.ops.object.select_all(action="DESELECT")
    bullet.select_set(True)
    bpy.context.view_layer.objects.active = bullet
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    x_len = max(1e-5, bullet.dimensions.x)
    scale_factor = 0.16 / x_len
    bullet.scale = Vector((scale_factor, scale_factor, scale_factor))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    bullet.location = Vector((0.0, 0.0, 0.0))

    mat = _make_pbr_material(
        "Bullet45ACPMat",
        base_color=(0.95, 0.68, 0.22, 1.0),
        metallic=0.90,
        roughness=0.20,
        emission_color=(1.0, 0.72, 0.25, 1.0),
        emission_strength=0.35,
    )
    bullet.data.materials.clear()
    bullet.data.materials.append(mat)

    os.makedirs(BULLET_GLB_OUT.parent, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    bullet.select_set(True)
    bpy.context.view_layer.objects.active = bullet
    bpy.ops.export_scene.gltf(
        filepath=str(BULLET_GLB_OUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
    )

    info = _read_glb_header(BULLET_GLB_OUT)
    info["nose_was_top_z"] = mean_top_r < mean_bot_r
    info["mean_top_r"] = round(mean_top_r, 5)
    info["mean_bot_r"] = round(mean_bot_r, 5)
    info["tris"] = sum(max(1, len(p.vertices) - 2) for p in bullet.data.polygons)
    info["dimensions_m"] = [round(float(v), 4) for v in bullet.dimensions]
    return info


def main() -> None:
    report = {
        "pistol": build_pistol(),
        "bullet": build_bullet(),
    }
    os.makedirs(REPORT_OUT.parent, exist_ok=True)
    REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("PISTOL_PROPS_BUILT:", json.dumps(report))


if __name__ == "__main__":
    main()
