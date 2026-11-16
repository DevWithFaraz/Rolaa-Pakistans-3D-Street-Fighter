import bpy
import hashlib
import json
import os
import struct

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1"
OPT_BLEND = os.path.join(ROOT, "blender", "asim-model1-optimization-trial.blend")
TEX_DIR = os.path.join(ROOT, "textures")
FBX_OUT = os.path.join(ROOT, "mixamo", "Asim_Model1_Rigging_Trial.fbx")
DOWNLOADS_DIR = os.path.join(ROOT, "mixamo", "downloads")
EXPORT_REPORT = os.path.join(ROOT, "inspection", "mixamo-export.json")
ROUNDTRIP_REPORT = os.path.join(ROOT, "inspection", "fbx-roundtrip.json")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def run():
    os.makedirs(os.path.dirname(FBX_OUT), exist_ok=True)
    os.makedirs(DOWNLOADS_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(EXPORT_REPORT), exist_ok=True)

    if "Asim_Model1_Optimization_Trial" not in bpy.data.objects:
        bpy.ops.wm.open_mainfile(filepath=OPT_BLEND)

    trial = bpy.data.objects["Asim_Model1_Optimization_Trial"]
    if "Asim_Model1_Working" in bpy.data.objects:
        w = bpy.data.objects["Asim_Model1_Working"]
        w.select_set(False)
        w.hide_viewport = True

    bpy.ops.object.select_all(action='DESELECT')
    trial.hide_viewport = False
    trial.select_set(True)
    bpy.context.view_layer.objects.active = trial

    # Ensure external filepaths on packed images point to our 2048px files so COPY+embed packs cleanly.
    for img in bpy.data.images:
        if img.name.startswith("Asim_Working_"):
            ext_path = os.path.join(TEX_DIR, img.name + ".jpg")
            if os.path.exists(ext_path):
                img.filepath = ext_path

    res = bpy.ops.export_scene.fbx(
        filepath=FBX_OUT,
        use_selection=True,
        object_types={'MESH'},
        bake_anim=False,
        path_mode='COPY',
        embed_textures=True,
        mesh_smooth_type='FACE',
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        apply_unit_scale=True,
        apply_scale_options='FBX_SCALE_ALL',
        global_scale=1.0,
        use_space_transform=True,
        bake_space_transform=False,
        axis_forward='-Z',
        axis_up='Y',
    )

    tex_entries = []
    for fname in ["Asim_Working_basecolor.jpg", "Asim_Working_rm.jpg", "Asim_Working_normal.jpg"]:
        p = os.path.join(TEX_DIR, fname)
        if os.path.exists(p):
            tex_entries.append({
                "path": p,
                "sha256": sha256_file(p),
                "bytes": os.path.getsize(p),
            })

    export_data = {
        "export": FBX_OUT,
        "bytes": os.path.getsize(FBX_OUT),
        "result": list(res),
        "textures": tex_entries,
        "animation_included": False,
        "rig_included": False,
        "object_names": [trial.name],
        "triangles": len(trial.data.polygons),
        "vertices": len(trial.data.vertices),
    }
    with open(EXPORT_REPORT, "w", encoding="utf-8") as f:
        json.dump(export_data, f, indent=2)

    print("FBX_EXPORTED:", json.dumps(export_data, indent=2))


def read_fbx_axes(fbx_path):
    with open(fbx_path, "rb") as f:
        data = f.read(65536)
    axes = {}
    for key in (b"UpAxis", b"UpAxisSign", b"FrontAxis", b"FrontAxisSign", b"CoordAxis", b"CoordAxisSign"):
        idx = data.find(key)
        pos = data.find(b"I", idx + len(key) + 20) if idx != -1 else -1
        axes[key.decode()] = struct.unpack("<i", data[pos + 1 : pos + 5])[0] if pos != -1 else None
    return axes


def roundtrip_verify_cli():
    """Run in a clean factory-empty Blender CLI process to verify FBX roundtrip."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX_OUT)
    objs = []
    armatures = 0
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            armatures += 1
        elif obj.type == 'MESH':
            tris = sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
            rot = [round(v, 6) for v in obj.rotation_euler]
            ws = [obj.matrix_world @ v.co for v in obj.data.vertices]
            head_vs = [v for v in ws if 1.48 <= v.z <= 1.66]
            head_y_range = [round(min(v.y for v in head_vs), 4), round(max(v.y for v in head_vs), 4)] if head_vs else [0.0, 0.0]
            imgs = []
            for mat in obj.data.materials:
                if mat and mat.use_nodes and mat.node_tree:
                    for n in mat.node_tree.nodes:
                        if n.type == 'TEX_IMAGE' and n.image:
                            imgs.append({
                                "name": n.image.name,
                                "size": list(n.image.size),
                                "source_path": bpy.path.abspath(n.image.filepath),
                            })
            objs.append({
                "name": obj.name,
                "type": obj.type,
                "dimensions_m": [round(v, 6) for v in obj.dimensions],
                "rotation_euler": rot,
                "head_y_range": head_y_range,
                "location": [round(v, 6) for v in obj.location],
                "scale": [round(v, 6) for v in obj.scale],
                "vertices": len(obj.data.vertices),
                "triangles": tris,
                "uv_layers": [u.name for u in obj.data.uv_layers],
                "texture_images": imgs,
            })
    fbx_axes = read_fbx_axes(FBX_OUT)
    expected_axes = {"UpAxis": 1, "UpAxisSign": 1, "FrontAxis": 2, "FrontAxisSign": 1, "CoordAxis": 0, "CoordAxisSign": 1}
    passed = (
        armatures == 0
        and len(objs) == 1
        and abs(objs[0]["dimensions_m"][2] - 1.80) < 0.02
        and all(abs(r) < 1e-4 for r in objs[0]["rotation_euler"])
        and fbx_axes == expected_axes
        and abs(objs[0]["head_y_range"][0]) > abs(objs[0]["head_y_range"][1])
        and len(objs[0]["uv_layers"]) >= 1
    )
    rt = {"objects": objs, "armatures": armatures, "fbx_axes": fbx_axes, "passed": passed}
    with open(ROUNDTRIP_REPORT, "w", encoding="utf-8") as f:
        json.dump(rt, f, indent=2)
    print("FBX_ROUNDTRIP:", json.dumps(rt, indent=2))
    assert passed, f"Asim Model 1 FBX roundtrip check failed: {rt}"


if __name__ == "__main__":
    if os.environ.get("ASIM_FBX_ROUNDTRIP_ONLY") == "1":
        roundtrip_verify_cli()
    else:
        run()
