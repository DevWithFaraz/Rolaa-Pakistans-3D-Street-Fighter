import bpy
import math
import os
from mathutils import Matrix, Vector

ROOT = r"C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1"
OPT_BLEND = os.path.join(ROOT, "blender", "asim-model1-optimization-trial.blend")


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def apply_forearm_pronation(obj, angle_deg=90.0):
    """Smoothly pronate forearms + hands from palms-forward to Mixamo palms-down/inward."""
    me = obj.data
    rad = math.radians(angle_deg)

    # Anatomically measured centerline anchors on normalized 1.80m Asim_Model1 mesh.
    left_elbow = Vector((0.355, 0.074, 1.165))
    left_wrist = Vector((0.505, 0.032, 0.960))
    right_elbow = Vector((-left_elbow.x, left_elbow.y, left_elbow.z))
    right_wrist = Vector((-left_wrist.x, left_wrist.y, left_wrist.z))

    def pronate_side(v_co, p0, p1, sign):
        axis = (p1 - p0)
        seg_len = axis.length
        axis_dir = axis.normalized()
        rel = v_co - p0
        along = rel.dot(axis_dir)
        # Keep only vertices along forearm/hand outside torso width.
        if along <= 0.0 or abs(v_co.x) < 0.34:
            return v_co
        closest_pt = p0 + axis_dir * along
        radial = (v_co - closest_pt).length
        if radial > 0.145:
            return v_co
        # Smooth ramp across lower forearm (~0.02..0.95 of [elbow..wrist_cuff]), rigid past wrist_cuff.
        t = along / seg_len
        blend = 1.0 if t >= 0.95 else smoothstep((t - 0.02) / 0.93)
        if blend <= 0.0:
            return v_co
        rot = Matrix.Rotation(sign * rad * blend, 3, axis_dir)
        return closest_pt + (rot @ (v_co - closest_pt))

    moved = 0
    for v in me.vertices:
        co = v.co.copy()
        if co.x > 0.34:
            new_co = pronate_side(co, left_elbow, left_wrist, +1.0)
        elif co.x < -0.34:
            new_co = pronate_side(co, right_elbow, right_wrist, -1.0)
        else:
            continue
        if (new_co - co).length > 1e-7:
            v.co = new_co
            moved += 1

    if me.has_custom_normals:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for p in me.polygons:
        p.use_smooth = True
    me.update()
    return moved


def run():
    if "Asim_Model1_Optimization_Trial" not in bpy.data.objects:
        bpy.ops.wm.open_mainfile(filepath=OPT_BLEND)

    trial = bpy.data.objects["Asim_Model1_Optimization_Trial"]
    if "Asim_Model1_Working" in bpy.data.objects:
        bpy.data.objects["Asim_Model1_Working"].hide_viewport = True

    moved = apply_forearm_pronation(trial, angle_deg=90.0)
    bpy.ops.wm.save_as_mainfile(filepath=OPT_BLEND)
    print(f"PRONATION_OK moved_vertices={moved}")


if __name__ == "__main__":
    run()
