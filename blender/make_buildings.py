"""Builds the street-life buildings and props (Task 5 Phase 2) as low-poly models.

Run:  blender -b --python blender/make_buildings.py

Writes one .glb per model to assets/models/buildings/ and manifest.json beside
them: each model's file, size, collision boxes and licence. All models are
made here from plain boxes and cylinders (CC0, made for this project). Signs
are blank boards; the game puts the made-up names on them with Label3D.

Conventions: metres, the model's front faces +Z (Blender -Y), origin at the
middle of the base on the ground.
"""
import bpy
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "models", "buildings")

COLORS = {
    "concrete": (0.55, 0.54, 0.5),
    "concrete_dark": (0.38, 0.37, 0.35),
    "cream": (0.9, 0.85, 0.72),
    "white": (0.92, 0.92, 0.9),
    "dark_glass": (0.08, 0.1, 0.12),
    "door": (0.12, 0.13, 0.15),
    "awning_red": (0.7, 0.12, 0.1),
    "sign_board": (0.95, 0.95, 0.93),
    "green_cross": (0.05, 0.55, 0.2),
    "trim_blue": (0.2, 0.32, 0.5),
    "wood": (0.45, 0.3, 0.18),
    "wood_dark": (0.3, 0.2, 0.12),
    "metal": (0.3, 0.3, 0.32),
    "rust": (0.45, 0.25, 0.15),
    "zinc": (0.62, 0.64, 0.66),
    "meat": (0.4, 0.15, 0.08),
    "coal": (0.08, 0.06, 0.05),
    "ember": (0.9, 0.35, 0.05),
    "yellow": (0.9, 0.75, 0.15),
    "umbrella_red": (0.8, 0.15, 0.12),
    "umbrella_blue": (0.15, 0.35, 0.75),
    "cloth_white": (0.9, 0.88, 0.82),
    "mat_reed": (0.65, 0.55, 0.32),
    "cardboard": (0.62, 0.48, 0.3),
    "sack": (0.55, 0.5, 0.38),
    "bag_blue": (0.2, 0.3, 0.6),
    "bag_black": (0.1, 0.1, 0.1),
    "bucket": (0.2, 0.45, 0.75),
    "stone": (0.42, 0.4, 0.38),
    "crate": (0.6, 0.45, 0.25),
}

# name: list of parts. Part: (shape, colour, size (x, y, z), centre (x, y, z), extra)
# shape "box" or "cyl" (size x = diameter at the bottom, extra = top diameter,
# None for a straight cylinder). Game axes: x right, y up, z towards the front.


def flyover():
    parts = []
    length, width, deck_bottom, deck = 34.0, 10.0, 6.0, 0.8
    parts.append(("box", "concrete", (length, deck, width), (0, deck_bottom + deck / 2, 0), None))
    for side in (-1, 1):
        # Parapets along both edges
        parts.append(("box", "concrete_dark", (length, 0.7, 0.3), (0, deck_bottom + deck + 0.35, side * (width / 2 - 0.15)), None))
        # Pillar rows 10 m either side of the middle: a cross beam on two columns
        x = side * 10.0
        parts.append(("box", "concrete_dark", (1.2, 0.7, width - 1.0), (x, deck_bottom - 0.35, 0), None))
        for z in (-3.0, 3.0):
            parts.append(("box", "concrete", (0.8, deck_bottom - 0.7, 0.8), (x, (deck_bottom - 0.7) / 2, z), None))
        # Solid end walls (abutments) carrying the deck down to the ground
        parts.append(("box", "concrete_dark", (1.5, deck_bottom, width), (side * (length / 2 - 0.75), deck_bottom / 2, 0), None))
    collision = [p for p in parts if p[1] in ("concrete", "concrete_dark")]
    return parts, collision


def supermarket():
    w, h, d = 14.0, 6.0, 12.0
    parts = [
        ("box", "cream", (w, h, d), (0, h / 2, 0), None),
        ("box", "dark_glass", (w - 2.0, 2.2, 0.08), (0, 1.5, d / 2 + 0.04), None),
        ("box", "door", (2.4, 2.6, 0.12), (0, 1.3, d / 2 + 0.06), None),
        ("box", "awning_red", (w, 0.15, 2.0), (0, 3.2, d / 2 + 1.0), None),
        ("box", "sign_board", (10.0, 1.3, 0.2), (0, 4.4, d / 2 + 0.1), None),
    ]
    return parts, [("box", "cream", (w, h, d), (0, h / 2, 0), None)]


def clinic():
    w, h, d = 10.0, 4.5, 9.0
    parts = [
        ("box", "white", (w, h, d), (0, h / 2, 0), None),
        ("box", "trim_blue", (w + 0.3, 0.3, d + 0.3), (0, h + 0.15, 0), None),
        ("box", "door", (2.0, 2.4, 0.12), (0, 1.2, d / 2 + 0.06), None),
        ("box", "dark_glass", (1.6, 1.2, 0.08), (-3.2, 1.6, d / 2 + 0.04), None),
        ("box", "dark_glass", (1.6, 1.2, 0.08), (3.2, 1.6, d / 2 + 0.04), None),
        ("box", "sign_board", (7.0, 1.0, 0.15), (0, 3.4, d / 2 + 0.08), None),
        # Green "+" on its own white panel at the left of the sign
        ("box", "white", (1.1, 1.1, 0.1), (-4.2, 3.4, d / 2 + 0.1), None),
        ("box", "green_cross", (0.9, 0.28, 0.06), (-4.2, 3.4, d / 2 + 0.16), None),
        ("box", "green_cross", (0.28, 0.9, 0.06), (-4.2, 3.4, d / 2 + 0.16), None),
    ]
    return parts, [("box", "white", (w, h, d), (0, h / 2, 0), None)]


def bench():
    parts = [("box", "wood", (2.4, 0.06, 0.45), (0, 0.45, 0), None),
             ("box", "wood", (2.4, 0.4, 0.05), (0, 0.72, -0.2), None)]
    for x in (-1.05, 1.05):
        parts.append(("box", "metal", (0.06, 0.45, 0.4), (x, 0.225, 0), None))
    return parts, [("box", "wood", (2.4, 0.9, 0.5), (0, 0.45, 0), None)]


def suya_kiosk():
    parts = [
        ("box", "wood", (2.6, 1.0, 1.0), (0, 0.5, -0.4), None),
        ("box", "zinc", (3.2, 0.08, 2.4), (0, 2.4, 0), None),
        # Grill in front: a rusty drum half on legs, glowing coals, skewers
        ("box", "rust", (1.3, 0.35, 0.55), (0, 0.85, 0.75), None),
        ("box", "coal", (1.2, 0.05, 0.45), (0, 1.03, 0.75), None),
        ("box", "ember", (0.9, 0.02, 0.3), (0, 1.06, 0.75), None),
    ]
    for x in (-1.5, 1.5):
        for z in (-1.1, 1.1):
            parts.append(("box", "wood_dark", (0.1, 2.4, 0.1), (x, 1.2, z), None))
    for x in (-0.5, 0.5):
        parts.append(("box", "metal", (0.05, 0.68, 0.05), (x, 0.34, 0.75), None))
    for i in range(6):
        parts.append(("box", "meat", (0.06, 0.05, 0.42), (-0.45 + i * 0.18, 1.1, 0.75), None))
    return parts, [("box", "wood", (2.6, 1.0, 1.0), (0, 0.5, -0.4), None),
                   ("box", "rust", (1.3, 1.1, 0.55), (0, 0.55, 0.75), None)]


def market_stall(colour):
    parts = [("box", "wood", (2.0, 0.08, 1.0), (0, 0.85, 0), None),
             ("box", "cloth_white", (2.0, 0.5, 0.02), (0, 0.6, 0.5), None),
             ("box", "metal", (0.05, 2.3, 0.05), (0, 1.15, 0), None),
             ("cyl", colour, (2.8, 0.5, 2.8), (0, 2.35, 0), 0.05)]
    for x in (-0.9, 0.9):
        for z in (-0.4, 0.4):
            parts.append(("box", "wood_dark", (0.06, 0.85, 0.06), (x, 0.42, z), None))
    # Goods on the table: a few small boxes
    for i, x in enumerate((-0.6, -0.1, 0.45)):
        parts.append(("box", ("bag_blue", "yellow", "crate")[i], (0.35, 0.22, 0.3), (x, 1.0, 0), None))
    return parts, [("box", "wood", (2.0, 0.9, 1.0), (0, 0.45, 0), None)]


def kiosk_booth():
    parts = [("box", "yellow", (1.8, 2.3, 1.6), (0, 1.15, 0), None),
             ("box", "dark_glass", (1.2, 0.7, 0.06), (0, 1.4, 0.8), None),
             ("box", "zinc", (2.3, 0.08, 2.1), (0, 2.4, 0.15), None)]
    return parts, [("box", "yellow", (1.8, 2.3, 1.6), (0, 1.15, 0), None)]


def crate_stack():
    parts = []
    for i, (x, y) in enumerate(((-0.35, 0.25), (0.35, 0.25), (0.0, 0.75))):
        parts.append(("box", "crate", (0.6, 0.5, 0.5), (x, y, 0), None))
    return parts, [("box", "crate", (1.3, 1.0, 0.5), (0, 0.5, 0), None)]


def seat_crate():
    # An upturned crate used as a stool; seat height suits the chair-sit clips
    return [("box", "crate", (0.5, 0.44, 0.4), (0, 0.22, 0), None)], [("box", "crate", (0.5, 0.44, 0.4), (0, 0.22, 0), None)]


def mat():
    return [("box", "mat_reed", (2.0, 0.03, 0.9), (0, 0.015, 0), None)], []


def cardboard():
    return [("box", "cardboard", (1.8, 0.03, 1.0), (0, 0.015, 0), None)], []


def sack():
    return [("box", "sack", (0.55, 0.4, 0.35), (0, 0.2, 0), None)], []


def bucket():
    return [("cyl", "bucket", (0.28, 0.3, 0.28), (0, 0.15, 0), 0.34)], []


def fire_pit():
    parts = []
    for i in range(7):
        a = i * math.tau / 7
        parts.append(("box", "stone", (0.18, 0.14, 0.18), (math.cos(a) * 0.32, 0.07, math.sin(a) * 0.32), None))
    parts.append(("box", "wood_dark", (0.5, 0.06, 0.07), (0, 0.06, 0), None))
    parts.append(("box", "wood_dark", (0.07, 0.06, 0.5), (0, 0.1, 0), None))
    parts.append(("box", "ember", (0.25, 0.03, 0.25), (0, 0.04, 0), None))
    return parts, []


def carry_bag():
    # Held in the hand: origin at the handles' top
    return [("box", "bag_black", (0.3, 0.35, 0.12), (0, -0.25, 0), None)], []


MODELS = {
    "flyover": flyover,
    "supermarket": supermarket,
    "clinic": clinic,
    "bench": bench,
    "suya_kiosk": suya_kiosk,
    "market_stall_red": lambda: market_stall("umbrella_red"),
    "market_stall_blue": lambda: market_stall("umbrella_blue"),
    "kiosk_booth": kiosk_booth,
    "crate_stack": crate_stack,
    "seat_crate": seat_crate,
    "mat": mat,
    "cardboard": cardboard,
    "sack": sack,
    "bucket": bucket,
    "fire_pit": fire_pit,
    "carry_bag": carry_bag,
}


def material(name):
    mat_ = bpy.data.materials.get(name)
    if mat_ is None:
        mat_ = bpy.data.materials.new(name)
        mat_.use_nodes = True
        bsdf = mat_.node_tree.nodes["Principled BSDF"]
        # COLORS are sRGB (as seen); Blender's base colour is linear
        bsdf.inputs["Base Color"].default_value = (*[to_linear(c) for c in COLORS[name]], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    return mat_


def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_blender(v):
    # Game (x, y up, z front) -> Blender (x, -z front, z up)
    return (v[0], -v[2], v[1])


def add_part(shape, colour, size, centre, extra):
    if shape == "box":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=to_blender(centre))
        obj = bpy.context.active_object
        obj.scale = (size[0], size[2], size[1])
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=size[0] / 2, radius2=(extra or size[0]) / 2,
                                        depth=size[1], location=to_blender(centre))
        obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material(colour))
    return obj


def build(name, func):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts, collision = func()
    objects = [add_part(*p) for p in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    # Origin stays at the world origin (middle of the base)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=False)
    xs = [c[3][0] + s * c[2][0] / 2 for c in parts for s in (-1, 1)]
    ys = [c[3][1] + s * c[2][1] / 2 for c in parts for s in (-1, 1)]
    zs = [c[3][2] + s * c[2][2] / 2 for c in parts for s in (-1, 1)]
    return {
        "file": "res://assets/models/buildings/%s.glb" % name,
        "size": [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
        "collision": [{"center": list(c[3]), "size": list(c[2])} for c in collision],
        "source": "Made for this project by blender/make_buildings.py",
        "license": "CC0",
        "triangles": sum(len(o.data.polygons) for o in [joined]) * 2,
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = {}
    for name, func in MODELS.items():
        manifest[name] = build(name, func)
        print("BUILDING %-18s %s" % (name, manifest[name]["size"]))
    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("BUILDINGS DONE: %d models" % len(manifest))


main()
