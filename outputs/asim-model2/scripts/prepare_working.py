import bpy
import bmesh
import json
import math
import os
from mathutils import Matrix

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model2"
UNPACKED_GLB = os.path.join(ROOT, "source", "asim-model2-uncompressed.glb")
TEX_DIR = os.path.join(ROOT, "textures")
BLEND_OUT = os.path.join(ROOT, "blender", "asim-model2-working.blend")
REPORT_OUT = os.path.join(ROOT, "inspection", "working-preparation.json")


def run():
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(REPORT_OUT), exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=UNPACKED_GLB)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    obj = meshes[0]
    obj.name = "Asim_Model2_Working"
    obj.data.name = "Asim_Model2_Working_Mesh"

    # Measure raw topology and bake world transform cleanly.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    source_verts = len(bm.verts)
    source_tris = sum(max(0, len(f.verts) - 2) for f in bm.faces)

    # Transform to Blender character convention: +Z up, -Y front (raw faces +X).
    rot_m = Matrix.Rotation(-math.pi * 0.5, 4, 'Z')
    bmesh.ops.transform(bm, matrix=rot_m, verts=bm.verts)

    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    height = max(zs) - min(zs)
    scale_factor = 1.80 / height
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    min_z = min(zs)

    norm_m = Matrix.Diagonal((scale_factor, scale_factor, scale_factor, 1.0)) @ Matrix.Translation((-cx, -cy, -min_z))
    bmesh.ops.transform(bm, matrix=norm_m, verts=bm.verts)

    # Exact-position vertex weld only, preserving UV loop attributes.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    working_verts = len(bm.verts)
    working_tris = sum(max(0, len(f.verts) - 2) for f in bm.faces)
    boundary_edges = sum(1 for e in bm.edges if e.is_boundary)
    nonmanifold_edges = sum(1 for e in bm.edges if not e.is_manifold)

    bm.to_mesh(obj.data)
    bm.free()

    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj.data.update()

    # Rebuild clean PBR material with 2048x2048 extracted textures packed.
    mat = bpy.data.materials.new(name="Asim2_Working_Material")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    out_node.location = (400, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    def load_packed(filename, colorspace):
        path = os.path.join(TEX_DIR, filename)
        img = bpy.data.images.load(path, check_existing=True)
        img.name = os.path.splitext(filename)[0]
        img.colorspace_settings.name = colorspace
        img.pack()
        return img

    img_col = load_packed("Asim2_Working_basecolor.jpg", "sRGB")
    img_rm = load_packed("Asim2_Working_rm.jpg", "Non-Color")
    img_nrm = load_packed("Asim2_Working_normal.jpg", "Non-Color")

    tex_col = nt.nodes.new("ShaderNodeTexImage")
    tex_col.image = img_col
    tex_col.location = (-350, 250)
    nt.links.new(tex_col.outputs["Color"], bsdf.inputs["Base Color"])

    tex_rm = nt.nodes.new("ShaderNodeTexImage")
    tex_rm.image = img_rm
    tex_rm.location = (-550, -50)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-250, -50)
    nt.links.new(tex_rm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.image = img_nrm
    tex_nrm.location = (-550, -350)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-250, -350)
    nt.links.new(tex_nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.clear()
    obj.data.materials.append(mat)

    for m in list(bpy.data.materials):
        if m != mat and m.users == 0:
            bpy.data.materials.remove(m)
    keep_imgs = {img_col, img_rm, img_nrm}
    for im in list(bpy.data.images):
        if im not in keep_imgs and im.name not in ("Render Result", "Viewer Node"):
            bpy.data.images.remove(im)

    bpy.context.scene.name = "Asim_Model2_Working_Scene"
    bpy.context.scene.render.fps = 30
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)

    dims = [round(v, 6) for v in obj.dimensions]
    mw = obj.matrix_world
    wmin = [min((mw @ v.co)[i] for v in obj.data.vertices) for i in range(3)]
    wmax = [max((mw @ v.co)[i] for v in obj.data.vertices) for i in range(3)]

    report = {
        "operation": "Rotated -90 deg Z to face -Y, grounded on Z=0, uniformly scaled to 1.80m, exact-position weld only preserving UVMap",
        "source_vertices": source_verts,
        "source_triangles": source_tris,
        "working_vertices": working_verts,
        "working_triangles": working_tris,
        "uv_layers": [u.name for u in obj.data.uv_layers],
        "working_dimensions": dims,
        "world_bbox_min": [round(v, 6) for v in wmin],
        "world_bbox_max": [round(v, 6) for v in wmax],
        "scale": [round(v, 6) for v in obj.scale],
        "boundary_edges": boundary_edges,
        "nonmanifold_edges": nonmanifold_edges,
        "material_images": [img_col.name, img_rm.name, img_nrm.name],
        "source_unchanged": True,
        "blend_saved": BLEND_OUT,
    }
    with open(REPORT_OUT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    run()
