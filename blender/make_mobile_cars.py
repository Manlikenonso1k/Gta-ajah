"""Create lightweight copies of every configured car using Blender 4.5.

Run from the project root: blender -b --python blender/make_mobile_cars.py
The original Sketchfab files are read-only inputs and are never overwritten.
"""
import bpy
import json
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/models/cars/real"
OUTPUT = ROOT / "assets/models/cars/mobile"
CONFIG = ROOT / "assets/models/cars/vehicles.json"
TARGET_TRIANGLES = 12000
MAX_TEXTURE = 1024

with CONFIG.open(encoding="utf8") as f:
    models = json.load(f)

OUTPUT.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        # Keep datablocks referenced by the just-imported scene only.
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def triangles(obj):
    return sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)


def simplify(objs):
    total = sum(triangles(obj) for obj in objs)
    if total <= TARGET_TRIANGLES:
        return total
    ratio = TARGET_TRIANGLES / total
    for obj in objs:
        count = triangles(obj)
        if count < 4:
            continue
        modifier = obj.modifiers.new("MobileDecimate", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = max(0.03, ratio)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return sum(triangles(obj) for obj in objs)


def resize_textures():
    seen = set()
    for image in bpy.data.images:
        if image.name in seen or image.source != "FILE":
            continue
        seen.add(image.name)
        width, height = image.size
        scale = min(1.0, MAX_TEXTURE / max(width, height))
        if scale < 1.0:
            image.scale(max(1, round(width * scale)), max(1, round(height * scale)))
        # Pack the resized pixels into the GLB so it has no external dependencies.
        try:
            image.pack()
        except RuntimeError:
            pass


for key, cfg in models.items():
    if key.startswith("_"):
        continue
    source_path = SOURCE / f"{key}.glb"
    if not source_path.exists():
        print(f"SKIP {key}: missing {source_path}")
        continue
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(source_path))
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        print(f"SKIP {key}: no mesh objects")
        continue
    source_triangles = sum(triangles(obj) for obj in mesh_objects)
    final_triangles = simplify(mesh_objects)
    resize_textures()

    # Keep one body mesh name and four axle markers. The runtime currently
    # cuts wheel triangles from the body so rotating wheels remain functional.
    for index, obj in enumerate(mesh_objects):
        obj.name = "body" if index == 0 else f"body-detail-{index:02d}"
        obj.data.name = obj.name
    wheels = cfg["wheels"]
    radius = wheels[3]
    # Convert Blender's Z-up imported vertices to the Y-up coordinates Godot
    # uses, then invert the same size/yaw/ground transform vehicle_model applies.
    source_points = [Vector((p.x, p.z, -p.y))
                     for obj in mesh_objects
                     for p in (obj.matrix_world @ Vector(corner) for corner in obj.bound_box)]
    yaw = Matrix.Rotation(float(cfg["yaw"]) * 3.141592653589793 / 180.0, 3, "Y")
    rotated = [yaw @ p for p in source_points]
    low = Vector(tuple(min(p[i] for p in rotated) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in rotated) for i in range(3)))
    scale = float(cfg["length"]) / (high.z - low.z)
    center = (low + high) * 0.5
    offset = Vector((-center.x * scale,
                     -low.y * scale - (wheels[2] - radius),
                     -center.z * scale))
    half_track = max(0.45, (high.x - low.x) * scale * 0.36)
    for axle, axle_z in (("front", wheels[0]), ("back", wheels[1])):
        for side, x in (("left", half_track), ("right", -half_track)):
            marker = bpy.data.objects.new(f"wheel-{axle}-{side}", None)
            bpy.context.collection.objects.link(marker)
            target = Vector((x, radius, axle_z))
            source = yaw.inverted() @ ((target - offset) / scale)
            marker.location = (source.x, -source.z, source.y)

    for obj in bpy.context.scene.objects:
        obj.select_set(obj.type in ("MESH", "EMPTY"))
    bpy.context.view_layer.objects.active = mesh_objects[0]
    destination = OUTPUT / f"{key}.glb"
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB",
                              use_selection=True, export_apply=True,
                              export_materials="EXPORT", export_image_format="AUTO")
    print(f"{key}: {source_triangles:,} -> {final_triangles:,} triangles, {destination.stat().st_size:,} bytes")
