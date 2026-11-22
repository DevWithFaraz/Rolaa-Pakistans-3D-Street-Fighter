"""Extract curated VFX textures from Unity packages and build 3D lightning_bolts.glb and slash_arc.glb."""

import json
import math
import os
import struct
import tarfile
import tempfile
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
DL_DIR = Path(r"C:\Users\IT\Downloads")
PKG_MAGIC = DL_DIR / "game_vfx_magiccircle.unitypackage"
PKG_SLASH = DL_DIR / "free_slash_vfx_6_urp.unitypackage"
LIGHTNING_BLEND = DL_DIR / "New folder" / "source" / "p_150_lighting.blend"

VFX_DIR = ROOT / "game/assets/vfx"
LIGHTNING_GLB_OUT = VFX_DIR / "lightning_bolts.glb"
SLASH_GLB_OUT = VFX_DIR / "slash_arc.glb"
REPORT_OUT = ROOT / "outputs/p3-animations/super-vfx-assets-report.json"

MAGIC_TEX_MAP = {
    "Assets/Game VFX - MagicCircle/Textures/circle2.PNG": "magic_circle_outer.png",
    "Assets/Game VFX - MagicCircle/Textures/Rune_01.png": "magic_rune_inner.png",
    "Assets/Game VFX - MagicCircle/Textures/eye_lwy_t_sun_29_single.png": "sunburst_core.png",
    "Assets/Game VFX - MagicCircle/Textures/FX_smoke_02.png": "vfx_smoke.png",
}

SLASH_TEX_MAP = {
    "Assets/Free Slash VFX/Textures/Circle Fire_albedo.png": "fire_ring.png",
    "Assets/Free Slash VFX/Textures/Slash Noise_Slash Noise.png": "slash_noise.png",
    "Assets/Free Slash VFX/Textures/Voronoi Noise 1_albedo.png": "voronoi_noise.png",
    "Assets/Free Slash VFX/Textures/Noise_GrayScale/T_Lu_Noise_29.png": "fire_noise_flow.png",
    "Assets/Free Slash VFX/Textures/Ground Crack.png": "ground_crack.png",
    "Assets/Free Slash VFX/Textures/Crack Tex.png": "ground_crack_veins.png",
    "Assets/Free Slash VFX/Textures/Impact.png": "impact_ring.png",
    "Assets/Free Slash VFX/Textures/Flare(2).png": "star_flare.png",
    "Assets/Free Slash VFX/Textures/Looping Laser.png": "lightning_core.png",
    "Assets/Free Slash VFX/Textures/Cut.png": "impact_cut.png",
}


def _extract_unity_assets(pkg_path: Path, path_map: dict[str, Path]) -> dict[str, int]:
    extracted: dict[str, int] = {}
    with tarfile.open(pkg_path, "r:gz") as tf:
        guid_to_path: dict[str, str] = {}
        asset_members: dict[str, tarfile.TarInfo] = {}
        for m in tf.getmembers():
            parts = m.name.split("/")
            if len(parts) == 2 and parts[1] == "pathname":
                guid_to_path[parts[0]] = tf.extractfile(m).read().decode("utf-8", "ignore").splitlines()[0].strip()
            elif len(parts) == 2 and parts[1] == "asset":
                asset_members[parts[0]] = m
        for guid, asset_path in guid_to_path.items():
            if asset_path in path_map and guid in asset_members:
                dst = path_map[asset_path]
                os.makedirs(dst.parent, exist_ok=True)
                data = tf.extractfile(asset_members[guid]).read()
                dst.write_bytes(data)
                extracted[dst.name] = len(data)
    return extracted


def _read_glb_header(path: Path) -> dict:
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(clen))
    return {
        "glb_bytes": path.stat().st_size,
        "meshes": len(gltf.get("meshes", [])),
        "nodes": [n.get("name") for n in gltf.get("nodes", [])],
    }


def _make_emissive_mat(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out_n = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.2
    if "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = color
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 2.0
    nt.links.new(bsdf.outputs["BSDF"], out_n.inputs["Surface"])
    return mat


def _ensure_cylindrical_uvs(obj: bpy.types.Object, vertical: bool = True) -> None:
    mesh = obj.data
    uv_layer = mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    span_x = max(1e-5, max(xs) - min(xs))
    span_z = max(1e-5, max(zs) - min(zs))
    min_x, min_z = min(xs), min(zs)
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            if vertical:
                u = (math.atan2(v.y, v.x) / (2.0 * math.pi)) + 0.5
                w = (v.z - min_z) / span_z
            else:
                u = (v.x - min_x) / span_x
                w = (math.atan2(v.z, v.y) / (2.0 * math.pi)) + 0.5
            uv_layer.data[li].uv = (u, w)


def build_lightning_bolts() -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(LIGHTNING_BLEND))
    keep_spec = [
        ("Lighting.001", "BoltSky_0", True, 2200, 11.5),
        ("Lighting.002", "BoltSky_1", True, 2000, 11.5),
        ("Lighting.003", "BoltSky_2", True, 2200, 11.5),
        ("Lighting.004", "BoltArc_0", False, 1800, 3.8),
    ]
    keep_names = {src for src, *_ in keep_spec}
    for obj in list(bpy.data.objects):
        if obj.name not in keep_names:
            bpy.data.objects.remove(obj, do_unlink=True)

    bolt_mat = _make_emissive_mat("LightningBoltMat", (0.78, 0.94, 1.0, 1.0))
    built_objs: list[bpy.types.Object] = []
    bolt_stats: dict[str, dict] = {}

    for src_name, dst_name, is_vertical, target_tris, target_len in keep_spec:
        obj = bpy.data.objects.get(src_name)
        assert obj is not None and obj.type == "MESH", f"Missing {src_name} in p_150_lighting.blend"
        obj.name = dst_name
        obj.data = obj.data.copy()

        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

        # Compute exact bounding box and center/orient cleanly.
        pts = [v.co for v in obj.data.vertices]
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        span = mx - mn
        center = (mn + mx) * 0.5

        if is_vertical:
            # Put bottom tip at z=0 and XY centered at (0,0), scale uniformly to target height (11.5 m).
            shift = Vector((-center.x, -center.y, -mn.z))
            scale_f = target_len / max(1e-4, span.z)
            xform = Matrix.Diagonal((scale_f, scale_f, scale_f, 1.0)) @ Matrix.Translation(shift)
            obj.data.transform(xform)
        else:
            # Horizontal discharge arc: orient longest horizontal axis along +X, center at (0,0,0), span target_len.
            shift = -center
            rot = Matrix.Identity(4)
            if span.y > span.x:
                rot = Matrix.Rotation(-math.pi * 0.5, 4, "Z")
                long_span = span.y
            else:
                long_span = span.x
            scale_f = target_len / max(1e-4, long_span)
            xform = Matrix.Diagonal((scale_f, scale_f, scale_f, 1.0)) @ rot @ Matrix.Translation(shift)
            obj.data.transform(xform)
        obj.data.update()

        cur_tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
        if cur_tris > target_tris:
            mod = obj.modifiers.new(name="BoltDecimate", type="DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = float(target_tris) / float(cur_tris)
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)

        for poly in obj.data.polygons:
            poly.use_smooth = True
        _ensure_cylindrical_uvs(obj, vertical=is_vertical)

        obj.data.materials.clear()
        obj.data.materials.append(bolt_mat)
        obj.location = Vector((0.0, 0.0, 0.0))
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = Vector((1.0, 1.0, 1.0))
        obj.data.update()

        final_tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
        bolt_stats[dst_name] = {
            "source_tris": cur_tris,
            "final_tris": final_tris,
            "dimensions_m": [round(float(v), 3) for v in obj.dimensions],
        }
        built_objs.append(obj)

    os.makedirs(LIGHTNING_GLB_OUT.parent, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in built_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = built_objs[0]
    bpy.ops.export_scene.gltf(
        filepath=str(LIGHTNING_GLB_OUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
    )
    info = _read_glb_header(LIGHTNING_GLB_OUT)
    info["bolts"] = bolt_stats
    return info


def build_slash_arcs() -> dict:
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        fbx_targets = {
            "Assets/Free Slash VFX/Model/Slash/Slash .fbx": td_path / "slash_wave.fbx",
            "Assets/Free Slash VFX/Model/Slash/Slash Projectile.fbx": td_path / "slash_crescent.fbx",
        }
        _extract_unity_assets(PKG_SLASH, fbx_targets)

        bpy.ops.wm.read_factory_settings(use_empty=True)
        slash_mat = _make_emissive_mat("SlashArcMat", (1.0, 0.85, 0.42, 1.0))
        exported: list[bpy.types.Object] = []
        stats: dict[str, dict] = {}

        # 1. SlashWave from Slash .fbx (keep 2 cleanest concentric ribbons)
        bpy.ops.import_scene.fbx(filepath=str(fbx_targets["Assets/Free Slash VFX/Model/Slash/Slash .fbx"]))
        wave_meshes = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: o.name)
        chosen = wave_meshes[:2]
        for o in list(bpy.data.objects):
            if o not in chosen:
                bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in chosen:
            o.select_set(True)
        bpy.context.view_layer.objects.active = chosen[0]
        if len(chosen) > 1:
            bpy.ops.object.join()
        wave = bpy.context.view_layer.objects.active
        wave.name = "SlashWave"
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        wave.location = Vector((0.0, 0.0, 0.0))
        max_d = max(wave.dimensions.x, wave.dimensions.y, 1e-4)
        s = 3.6 / max_d
        wave.scale = Vector((s, s, s))
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        wave.data.materials.clear()
        wave.data.materials.append(slash_mat)
        for poly in wave.data.polygons:
            poly.use_smooth = True
        exported.append(wave)
        stats["SlashWave"] = {
            "tris": sum(max(1, len(p.vertices) - 2) for p in wave.data.polygons),
            "dimensions_m": [round(float(v), 3) for v in wave.dimensions],
        }

        # 2. SlashCrescent from Slash Projectile.fbx
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=str(fbx_targets["Assets/Free Slash VFX/Model/Slash/Slash Projectile.fbx"]))
        new_objs = [o for o in bpy.data.objects if o not in before]
        cresc_meshes = [o for o in new_objs if o.type == "MESH"]
        for o in new_objs:
            if o not in cresc_meshes:
                bpy.data.objects.remove(o, do_unlink=True)
        cresc = cresc_meshes[0]
        cresc.name = "SlashCrescent"
        bpy.ops.object.select_all(action="DESELECT")
        cresc.select_set(True)
        bpy.context.view_layer.objects.active = cresc
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        cresc.location = Vector((0.0, 0.0, 0.0))
        max_c = max(cresc.dimensions.x, cresc.dimensions.y, 1e-4)
        sc = 2.8 / max_c
        cresc.scale = Vector((sc, sc, sc))
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        cresc.data.materials.clear()
        cresc.data.materials.append(slash_mat)
        for poly in cresc.data.polygons:
            poly.use_smooth = True
        exported.append(cresc)
        stats["SlashCrescent"] = {
            "tris": sum(max(1, len(p.vertices) - 2) for p in cresc.data.polygons),
            "dimensions_m": [round(float(v), 3) for v in cresc.dimensions],
        }

        bpy.ops.object.select_all(action="DESELECT")
        for o in exported:
            o.select_set(True)
        bpy.context.view_layer.objects.active = exported[0]
        bpy.ops.export_scene.gltf(
            filepath=str(SLASH_GLB_OUT),
            export_format="GLB",
            use_selection=True,
            use_active_scene=True,
            export_yup=True,
            export_materials="EXPORT",
            export_apply=True,
        )
        info = _read_glb_header(SLASH_GLB_OUT)
        info["arcs"] = stats
        return info


def main() -> None:
    os.makedirs(VFX_DIR, exist_ok=True)
    magic_out = _extract_unity_assets(PKG_MAGIC, {k: VFX_DIR / v for k, v in MAGIC_TEX_MAP.items()})
    slash_out = _extract_unity_assets(PKG_SLASH, {k: VFX_DIR / v for k, v in SLASH_TEX_MAP.items()})
    assert len(magic_out) == len(MAGIC_TEX_MAP), f"Missing magic textures: {magic_out}"
    assert len(slash_out) == len(SLASH_TEX_MAP), f"Missing slash textures: {slash_out}"

    report = {
        "textures": {**magic_out, **slash_out},
        "lightning_bolts": build_lightning_bolts(),
        "slash_arcs": build_slash_arcs(),
    }
    os.makedirs(REPORT_OUT.parent, exist_ok=True)
    REPORT_OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("SUPER_VFX_ASSETS_BUILT:", json.dumps(report))


if __name__ == "__main__":
    main()
