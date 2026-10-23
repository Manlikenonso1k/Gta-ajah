"""Slims downloaded character models for use as pedestrians.

Run:  blender -b --python blender/slim_characters.py -- <file.glb> [<file.glb> ...]

Each file is rewritten in place without animations or shape keys (pedestrians
are animated by scripts/humanoid_walk.gd), with textures capped at 1024 px and
stored as WebP. The skeleton, skin weights and materials are kept. Originals
can be downloaded again from the links in
assets/characters/pedestrians/CREDITS_SKETCHFAB.md.
"""
import bpy
import os
import sys

MAX_TEXTURE = 1024


def slim(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    for obj in bpy.data.objects:
        obj.animation_data_clear()
        if obj.type == "MESH" and obj.data.shape_keys:
            obj.shape_key_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for img in list(bpy.data.images):
        w, h = img.size
        if w == 0:
            continue
        if img.depth < 24:
            # Blender's WebP writer fails on greyscale images; copy to RGBA
            rgba = bpy.data.images.new(img.name + "_rgba", w, h, alpha=True)
            pixels = [0.0] * (w * h * 4)
            img.pixels.foreach_get(pixels)
            rgba.pixels.foreach_set(pixels)
            rgba.colorspace_settings.name = img.colorspace_settings.name
            rgba.pack()
            img.user_remap(rgba)
            img = rgba
        if max(w, h) > MAX_TEXTURE:
            s = MAX_TEXTURE / max(w, h)
            img.scale(max(1, int(w * s)), max(1, int(h * s)))
    before = os.path.getsize(path)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=False,
                              export_morph=False, export_image_format="WEBP", export_image_quality=85)
    print(f"SLIM {os.path.basename(path)}: {before / 1e6:.1f} MB -> {os.path.getsize(path) / 1e6:.1f} MB")


for arg in sys.argv[sys.argv.index("--") + 1:]:
    slim(os.path.abspath(arg))
