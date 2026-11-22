"""Build optimized 3D rock prop (cliff_rock.glb) and 6 fractured shards (cliff_rock_shards.glb)."""

import json
import os
import random
import struct
import zipfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
FBX_IN = Path(r"C:\Users\IT\Downloads\New Animations\Cliff_Rock_Two_FBX.fbx")
TEX_ZIP = Path(r"C:\Users\IT\Downloads\New Animations\Cliff_Rock_Two_Texture4K.zip")
WORK_DIR = ROOT / "outputs/khan-model2/rock_prop"
GLB_OUT = ROOT / "game/assets/props/cliff_rock.glb"
SHARDS_GLB_OUT = ROOT / "game/assets/props/cliff_rock_shards.glb"


def extract_and_resize_textures() -> dict[str, Path]:
    os.makedirs(WORK_DIR, exist_ok=True)
    needed = {
        "basecolor": "Cliff_Rock_Two_BaseColor.png",
        "normal": "Cliff_Rock_Two_Normal.png",
        "roughness": "Cliff_Rock_Two_Roughness.png",
    }
    out_paths: dict[str, Path] = {}
    with zipfile.ZipFile(TEX_ZIP, "r") as zf:
        entries = {Path(name).name: name for name in zf.namelist()}
        for key, fname in needed.items():
            entry = entries[fname]
            raw_path = WORK_DIR / fname
            with zf.open(entry) as src, open(raw_path, "wb") as dst:
                dst.write(src.read())

            img = bpy.data.images.load(str(raw_path), check_existing=False)
            img.scale(1024, 1024)
            jpg_path = WORK_DIR / f"cliff_rock_{key}_1k.jpg"
            bpy.context.scene.render.image_settings.file_format = "JPEG"
            bpy.context.scene.render.image_settings.quality = 88
            img.filepath_raw = str(jpg_path)
            img.file_format = "JPEG"
            img.save()
            bpy.data.images.remove(img)
            if raw_path.exists():
                raw_path.unlink()
            out_paths[key] = jpg_path
    return out_paths


def build_rock() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tex_paths = extract_and_resize_textures()

    bpy.ops.import_scene.fbx(filepath=str(FBX_IN))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    assert meshes, "No mesh found in Cliff_Rock_Two_FBX.fbx"

    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    rock = bpy.context.view_layer.objects.active
    rock.name = "CliffRock"

    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    rock.location = Vector((0.0, 0.0, 0.0))

    max_dim = max(rock.dimensions.x, rock.dimensions.y, rock.dimensions.z, 1e-5)
    scale_factor = 0.34 / max_dim
    rock.scale = Vector((scale_factor, scale_factor, scale_factor))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    source_tris = len(rock.data.polygons)
    highres_bm = bmesh.new()
    highres_bm.from_mesh(rock.data)

    mod = rock.modifiers.new(name="RockDecimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = 0.18
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in rock.data.polygons:
        poly.use_smooth = True

    mat = bpy.data.materials.new(name="CliffRockMat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.0

    tex_bc = nt.nodes.new("ShaderNodeTexImage")
    tex_bc.image = bpy.data.images.load(str(tex_paths["basecolor"]))
    tex_bc.image.colorspace_settings.name = "sRGB"

    tex_rm = nt.nodes.new("ShaderNodeTexImage")
    tex_rm.image = bpy.data.images.load(str(tex_paths["roughness"]))
    tex_rm.image.colorspace_settings.name = "Non-Color"

    tex_n = nt.nodes.new("ShaderNodeTexImage")
    tex_n.image = bpy.data.images.load(str(tex_paths["normal"]))
    tex_n.image.colorspace_settings.name = "Non-Color"
    norm_node = nt.nodes.new("ShaderNodeNormalMap")

    nt.links.new(tex_bc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex_rm.outputs["Color"], bsdf.inputs["Roughness"])
    nt.links.new(tex_n.outputs["Color"], norm_node.inputs["Color"])
    nt.links.new(norm_node.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    rock.data.materials.clear()
    rock.data.materials.append(mat)

    os.makedirs(GLB_OUT.parent, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    rock.select_set(True)
    bpy.context.view_layer.objects.active = rock
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="JPEG",
        export_tangents=True,
    )

    with open(GLB_OUT, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(clen))

    shards_report = build_rock_shards(highres_bm, mat)
    highres_bm.free()

    report = {
        "source_tris": source_tris,
        "final_tris": len(rock.data.polygons),
        "dimensions_m": [round(float(v), 4) for v in rock.dimensions],
        "glb_bytes": GLB_OUT.stat().st_size,
        "meshes": len(gltf.get("meshes", [])),
        "images": len(gltf.get("images", [])),
        "shards": shards_report,
    }
    (WORK_DIR / "rock-build.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ROCK_BUILT:", json.dumps(report))


def _bisect_and_cap_chunk(bm_base: bmesh.types.BMesh, cuts: list[tuple[Vector, Vector, bool]], rng: random.Random) -> bmesh.types.BMesh:
    """Slice a copy of the rock mesh with angled planes, cap fracture faces with rock UVs, and triangulate."""
    bm = bm_base.copy()
    uv_layer = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")
    for co, no, keep_inner in cuts:
        no_n = no.normalized()
        old_faces = set(bm.faces)
        res = bmesh.ops.bisect_plane(
            bm,
            geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
            dist=1e-5,
            plane_co=co,
            plane_no=no_n,
            use_snap_center=False,
            clear_outer=keep_inner,
            clear_inner=not keep_inner,
        )
        cut_edges = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMEdge) and g.is_valid]
        if cut_edges:
            bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
        new_faces = [f for f in bm.faces if f not in old_faces and f.is_valid]
        if new_faces:
            ref = Vector((0.0, 0.0, 1.0)) if abs(no_n.z) < 0.9 else Vector((1.0, 0.0, 0.0))
            u_ax = no_n.cross(ref).normalized()
            v_ax = no_n.cross(u_ax).normalized()
            poked = bmesh.ops.poke(bm, faces=new_faces)
            for v in poked["verts"]:
                v.co += no_n * rng.uniform(-0.011, 0.011)
            cap_faces = set(poked["faces"]) | {f for f in new_faces if f.is_valid}
            u_off = rng.uniform(0.25, 0.75)
            v_off = rng.uniform(0.25, 0.75)
            for f in cap_faces:
                if not f.is_valid:
                    continue
                for loop in f.loops:
                    p = loop.vert.co
                    loop[uv_layer].uv = (
                        max(0.05, min(0.95, u_off + p.dot(u_ax) * 1.6)),
                        max(0.05, min(0.95, v_off + p.dot(v_ax) * 1.6)),
                    )
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def build_rock_shards(highres_bm: bmesh.types.BMesh, mat: bpy.types.Material) -> dict:
    """Slice the photogrammetry rock into 6 jagged asymmetric PBR chunks (<= 1200 tris total) and export GLB."""
    p1 = (Vector((0.0, 0.0, 0.0)), Vector((0.92, 0.25, 0.29)))
    p2 = (Vector((-0.03, 0.01, 0.01)), Vector((-0.24, 0.34, 0.91)))
    p3 = (Vector((-0.03, -0.01, -0.02)), Vector((0.28, 0.91, -0.30)))
    p4 = (Vector((0.03, -0.01, 0.0)), Vector((0.20, -0.36, 0.91)))
    p5 = (Vector((0.03, 0.01, 0.01)), Vector((-0.32, 0.89, 0.32)))

    chunk_cuts = [
        [(p1[0], p1[1], True), (p2[0], p2[1], False)],
        [(p1[0], p1[1], True), (p2[0], p2[1], True), (p3[0], p3[1], True)],
        [(p1[0], p1[1], True), (p2[0], p2[1], True), (p3[0], p3[1], False)],
        [(p1[0], p1[1], False), (p4[0], p4[1], False)],
        [(p1[0], p1[1], False), (p4[0], p4[1], True), (p5[0], p5[1], True)],
        [(p1[0], p1[1], False), (p4[0], p4[1], True), (p5[0], p5[1], False)],
    ]

    rng = random.Random(20261117)
    shard_objs: list[bpy.types.Object] = []
    shard_tris: dict[str, int] = {}
    for idx, cuts in enumerate(chunk_cuts):
        bm_chunk = _bisect_and_cap_chunk(highres_bm, cuts, rng)
        mesh = bpy.data.meshes.new(f"ShardMesh_{idx}")
        bm_chunk.to_mesh(mesh)
        bm_chunk.free()

        obj = bpy.data.objects.new(f"Shard_{idx}", mesh)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        obj.location = Vector((0.0, 0.0, 0.0))

        target_tris = 175
        if len(obj.data.polygons) > target_tris:
            mod = obj.modifiers.new(name="ShardDecimate", type="DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = float(target_tris) / float(len(obj.data.polygons))
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)

        for poly in obj.data.polygons:
            poly.use_smooth = False
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        obj.data.update()
        shard_objs.append(obj)
        shard_tris[obj.name] = len(obj.data.polygons)

    total_tris = sum(shard_tris.values())
    assert total_tris <= 1200, f"Total shard tris {total_tris} exceeds 1200"

    bpy.ops.object.select_all(action="DESELECT")
    for obj in shard_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = shard_objs[0]
    bpy.ops.export_scene.gltf(
        filepath=str(SHARDS_GLB_OUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="JPEG",
        export_tangents=True,
    )

    with open(SHARDS_GLB_OUT, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        gltf = json.loads(f.read(clen))
    node_names = [n.get("name") for n in gltf.get("nodes", [])]
    assert node_names == [f"Shard_{i}" for i in range(6)], f"Unexpected shard nodes: {node_names}"
    return {
        "total_tris": total_tris,
        "per_shard_tris": shard_tris,
        "nodes": node_names,
        "glb_bytes": SHARDS_GLB_OUT.stat().st_size,
    }


if __name__ == "__main__":
    build_rock()
