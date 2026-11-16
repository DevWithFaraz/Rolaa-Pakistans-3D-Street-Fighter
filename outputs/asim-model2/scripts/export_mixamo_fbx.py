import json
import os
import struct
import bpy

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model2"
OPT_BLEND = os.path.join(ROOT, "blender", "asim-model2-optimization-trial.blend")
FBX_OUT = os.path.join(ROOT, "mixamo", "Asim_Model2_Rigging_Trial.fbx")
EXPORT_JSON = os.path.join(ROOT, "inspection", "mixamo-export.json")
ROUNDTRIP_JSON = os.path.join(ROOT, "inspection", "fbx-roundtrip.json")


def read_fbx_axes(fbx_path: str) -> dict:
    with open(fbx_path, "rb") as f:
        data = f.read(65536)
    axes = {}
    for key in (b"UpAxis", b"UpAxisSign", b"FrontAxis", b"FrontAxisSign", b"CoordAxis", b"CoordAxisSign"):
        idx = data.find(key)
        pos = data.find(b"I", idx + len(key) + 20) if idx != -1 else -1
        axes[key.decode()] = struct.unpack("<i", data[pos + 1 : pos + 5])[0] if pos != -1 else None
    return axes


def export_fbx():
    os.makedirs(os.path.dirname(FBX_OUT), exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=OPT_BLEND)

    trial = bpy.data.objects["Asim_Model2_Optimization_Trial"]
    bpy.ops.object.select_all(action='DESELECT')
    trial.hide_viewport = False
    trial.select_set(True)
    bpy.context.view_layer.objects.active = trial

    # Standard Mixamo FBX coordinate convention (Y-up, +Z-forward, right-handed), matching Khan_Model2
    bpy.ops.export_scene.fbx(
        filepath=FBX_OUT,
        use_selection=True,
        object_types={'MESH'},
        use_mesh_modifiers=True,
        mesh_smooth_type='FACE',
        bake_anim=False,
        path_mode='COPY',
        embed_textures=True,
        axis_forward='-Z',
        axis_up='Y',
        apply_unit_scale=True,
        global_scale=1.0,
        apply_scale_options='FBX_SCALE_ALL',
        use_space_transform=True,
        bake_space_transform=False,
    )

    size_bytes = os.path.getsize(FBX_OUT)
    fbx_axes = read_fbx_axes(FBX_OUT)
    report = {
        "fbx_path": FBX_OUT,
        "size_bytes": size_bytes,
        "size_mb": round(size_bytes / (1024 * 1024), 2),
        "exported_object": trial.name,
        "triangles": sum(max(1, len(p.vertices) - 2) for p in trial.data.polygons),
        "vertices": len(trial.data.vertices),
        "dimensions_m": [round(float(d), 6) for d in trial.dimensions],
        "uv_layers": [uv.name for uv in trial.data.uv_layers],
        "materials": [m.name for m in trial.data.materials if m],
        "embed_textures": True,
        "bake_anim": False,
        "axis_forward": "-Z",
        "axis_up": "Y",
        "fbx_axes": fbx_axes,
        "object_types": ["MESH"],
    }
    with open(EXPORT_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"FBX_EXPORTED: {FBX_OUT} ({report['size_mb']} MB) axes={fbx_axes}")


def roundtrip_verify_cli():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX_OUT)

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    armatures = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    assert len(meshes) == 1, f"Expected 1 mesh in FBX roundtrip, got {len(meshes)}"
    assert len(armatures) == 0, f"Expected 0 armatures in mesh-only FBX, got {len(armatures)}"

    m = meshes[0]
    dims = [round(float(d), 6) for d in m.dimensions]
    rot = [round(float(r), 6) for r in m.rotation_euler]
    tris = sum(max(1, len(p.vertices) - 2) for p in m.data.polygons)
    verts = len(m.data.vertices)
    uvs = [uv.name for uv in m.data.uv_layers]
    mats = [mat.name for mat in m.data.materials if mat]
    imgs = [{"name": img.name, "size": list(img.size), "packed": img.packed_file is not None} for img in bpy.data.images]

    fbx_axes = read_fbx_axes(FBX_OUT)
    expected_axes = {"UpAxis": 1, "UpAxisSign": 1, "FrontAxis": 2, "FrontAxisSign": 1, "CoordAxis": 0, "CoordAxisSign": 1}

    ws_verts = [m.matrix_world @ v.co for v in m.data.vertices]
    head_vs = [v for v in ws_verts if 1.48 <= v.z <= 1.66]
    head_y_range = [round(min(v.y for v in head_vs), 4), round(max(v.y for v in head_vs), 4)] if head_vs else [0.0, 0.0]

    passed = (
        len(meshes) == 1
        and len(armatures) == 0
        and abs(dims[2] - 1.80) < 0.02
        and all(abs(r) < 1e-4 for r in rot)
        and fbx_axes == expected_axes
        and abs(head_y_range[0]) > abs(head_y_range[1])
        and len(uvs) >= 1
        and len(imgs) >= 1
        and tris > 50000
    )
    report = {
        "passed": passed,
        "fbx_path": FBX_OUT,
        "meshes": len(meshes),
        "armatures": len(armatures),
        "triangles": tris,
        "vertices": verts,
        "dimensions_m": dims,
        "rotation_euler": rot,
        "fbx_axes": fbx_axes,
        "head_y_range": head_y_range,
        "uv_layers": uvs,
        "materials": mats,
        "images": imgs,
    }
    with open(ROUNDTRIP_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"FBX_ROUNDTRIP_PASSED={passed} dims={dims} rot={rot} axes={fbx_axes} tris={tris} imgs={len(imgs)}")
    assert passed, f"FBX roundtrip check failed: {report}"


if __name__ == "__main__":
    if os.environ.get("ASIM2_FBX_ROUNDTRIP_ONLY") == "1":
        roundtrip_verify_cli()
    else:
        export_fbx()
