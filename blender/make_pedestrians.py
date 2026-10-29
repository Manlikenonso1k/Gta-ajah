"""Generates the Black African pedestrian characters with MPFB2 (MakeHuman for Blender).

Run:  blender -b --python blender/make_pedestrians.py            (all characters)
      blender -b --python blender/make_pedestrians.py -- PED_BA_M01   (one character)

Needs Blender 4.5 LTS with the MPFB 2 extension and the MakeHuman asset packs
installed (see the README section "Pedestrian characters"). All MakeHuman assets
used here are CC0 except where ROSTER notes otherwise.

Each character is built from MPFB's low-poly body proxy, rigged with MPFB's
Mixamo-compatible skeleton (bones named mixamorig:Hips etc.), and exported to
assets/characters/pedestrians/black_african/<id>.glb with textures capped at
1024 px and stored as WebP (Godot keeps them GPU-compressed; see the README). It faces +Z with its feet on y = 0, in metres. A summary of the roster
is written to assets/characters/pedestrians/generated_roster.json, which
scripts/pedestrian_registry.gd reads.
"""
import bpy
import json
import os
import sys

from bl_ext.user_default.mpfb.services.humanservice import HumanService

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "characters", "pedestrians", "black_african")
ROSTER_JSON = os.path.join(ROOT, "assets", "characters", "pedestrians", "generated_roster.json")
MPFB_DATA = os.path.join(bpy.utils.extension_path_user("bl_ext.user_default.mpfb", create=False), "data")
MAX_TEXTURE = 1024

# A tint multiplies an asset's texture colour (exported as the glTF base colour
# factor), so one outfit can appear in several colours. Tints are written as
# on-screen (sRGB) colours. Hair textures in the packs are mostly brown, so a
# dark tint gives natural black hair.
# Clothes entries: (asset, tint, alternative material, recolour). With recolour
# the texture is first turned to greyscale, so the tint sets the actual colour;
# use it only for single-garment textures (dresses, suits), because tee-and-jeans
# textures would get one colour all over.
BLACK_HAIR = (0.3, 0.27, 0.25)
GREY_HAIR = (0.78, 0.78, 0.78)

# gender: 0 female .. 1 male. age: 0.1875 = 11, 0.5 = 25, 1 = 90 (MakeHuman scale).
ROSTER = [
    {"id": "PED_BA_M01", "name": "Student, yellow shirt", "tags": ["student", "young"], "gender": 1.0, "age": 0.4, "muscle": 0.5, "weight": 0.45, "height": 0.55,
     "skin": "young_african_male", "hair": ("short01", BLACK_HAIR), "eyebrows": "eyebrow001",
     "clothes": [("male_casualsuit01", None, "toigo_male_casual_suit_01_yellow_shirt"), ("shoes02", None, None)]},
    {"id": "PED_BA_M02", "name": "Commuter, afro", "tags": ["commuter", "young"], "gender": 1.0, "age": 0.45, "muscle": 0.55, "weight": 0.5, "height": 0.6,
     "skin": "young_african_male", "hair": ("afro01", BLACK_HAIR), "eyebrows": "eyebrow002",
     "clothes": [("male_casualsuit02", None, None), ("shoes01", None, None)]},
    {"id": "PED_BA_M03", "name": "Office worker, suit", "tags": ["office", "business_casual", "adult"], "gender": 1.0, "age": 0.55, "muscle": 0.5, "weight": 0.55, "height": 0.6,
     "skin": "middleage_african_male", "hair": ("short02", BLACK_HAIR), "eyebrows": "eyebrow003",
     "clothes": [("male_elegantsuit01", None, None), ("shoes03", None, None)]},
    {"id": "PED_BA_M04", "name": "Trader, work clothes", "tags": ["market", "worker", "adult"], "gender": 1.0, "age": 0.6, "muscle": 0.6, "weight": 0.7, "height": 0.5,
     "skin": "mindfront_skin_male_african_middleage", "hair": ("short04", BLACK_HAIR), "eyebrows": "eyebrow004",
     "clothes": [("male_worksuit01", None, None), ("shoes04", None, None)]},
    {"id": "PED_BA_M05", "name": "Young man, striped shirt", "tags": ["casual", "young"], "gender": 1.0, "age": 0.42, "muscle": 0.6, "weight": 0.5, "height": 0.7,
     "skin": "young_african_male", "hair": ("short03", BLACK_HAIR), "eyebrows": "eyebrow005",
     "clothes": [("male_casualsuit03", None, None), ("shoes05", None, None)]},
    {"id": "PED_BA_M06", "name": "Older man", "tags": ["elder"], "gender": 1.0, "age": 0.85, "muscle": 0.4, "weight": 0.6, "height": 0.45,
     "skin": "old_african_male", "hair": ("short02", GREY_HAIR, None, True), "eyebrows": "eyebrow006",
     "clothes": [("male_casualsuit06", None, None), ("shoes06", None, None)]},
    {"id": "PED_BA_M07", "name": "Tall man, white shirt", "tags": ["casual", "business_casual", "adult"], "gender": 1.0, "age": 0.5, "muscle": 0.65, "weight": 0.5, "height": 0.7,
     "skin": "middleage_african_male", "hair": ("short01", BLACK_HAIR), "eyebrows": "eyebrow007",
     "clothes": [("male_casualsuit01", None, "toigo_male_casual_suit_01_white_shirt"), ("shoes03", None, None)]},
    {"id": "PED_BA_M08", "name": "Young man, teal shirt", "tags": ["casual", "young"], "gender": 1.0, "age": 0.38, "muscle": 0.45, "weight": 0.4, "height": 0.5,
     "skin": "young_african_male", "hair": ("afro01", BLACK_HAIR), "eyebrows": "eyebrow008",
     "clothes": [("male_casualsuit01", None, "toigo_male_casual_suit_01_teal_shirt_with_black_jeans"), ("shoes02", None, None)]},
    {"id": "PED_BA_M09", "name": "Heavy-set man, casual", "tags": ["casual", "market", "adult"], "gender": 1.0, "age": 0.65, "muscle": 0.45, "weight": 0.85, "height": 0.5,
     "skin": "middleage_african_male", "hair": ("short03", BLACK_HAIR), "eyebrows": "eyebrow009",
     "clothes": [("male_casualsuit01", None, "toigo_male_casual_suit_01_red_shirt_with_black_jeans"), ("shoes01", None, None)]},
    {"id": "PED_BA_F01", "name": "Student, braids", "tags": ["student", "young"], "gender": 0.0, "age": 0.4, "muscle": 0.45, "weight": 0.45, "height": 0.5,
     "skin": "young_african_female", "hair": ("braid01", None, "toigo_braid01_black"), "eyebrows": "eyebrow010", "eyelashes": "eyelashes01",
     "clothes": [("female_casualsuit01", None, None), ("shoes05", None, None)]},
    {"id": "PED_BA_F02", "name": "Office worker, ponytail", "tags": ["office", "business_casual", "adult"], "gender": 0.0, "age": 0.52, "muscle": 0.5, "weight": 0.5, "height": 0.55,
     "skin": "middleage_african_female", "hair": ("ponytail01", None, "dariush086_ponytail01_black"), "eyebrows": "eyebrow011", "eyelashes": "eyelashes02",
     "clothes": [("female_elegantsuit01", None, None), ("shoes03", None, None)]},
    {"id": "PED_BA_F03", "name": "Market woman", "tags": ["market", "adult"], "gender": 0.0, "age": 0.62, "muscle": 0.45, "weight": 0.8, "height": 0.45,
     "skin": "middleage_african_female", "hair": ("bob01", BLACK_HAIR), "eyebrows": "eyebrow012", "eyelashes": "eyelashes01",
     "clothes": [("elvs_sporty_tracksuit_hoodie_dress1", (0.95, 0.55, 0.2), None, True), ("shoes04", None, None)]},
    {"id": "PED_BA_F04", "name": "Young woman, sportswear", "tags": ["casual", "young"], "gender": 0.0, "age": 0.38, "muscle": 0.6, "weight": 0.4, "height": 0.6,
     "skin": "young_african_female", "hair": ("afro01", BLACK_HAIR), "eyebrows": "eyebrow010", "eyelashes": "eyelashes03",
     "clothes": [("female_sportsuit01", None, None), ("shoes02", None, None)]},
    {"id": "PED_BA_F05", "name": "Older woman", "tags": ["elder"], "gender": 0.0, "age": 0.85, "muscle": 0.4, "weight": 0.65, "height": 0.4,
     "skin": "old_african_female", "hair": ("bob02", GREY_HAIR, None, True), "eyebrows": "eyebrow011", "eyelashes": "eyelashes01",
     "clothes": [("female_elegantsuit01", (0.3, 0.35, 0.6), None, True), ("shoes06", None, None)]},
    {"id": "PED_BA_F06", "name": "Woman, pantsuit", "tags": ["business_casual", "adult"], "gender": 0.0, "age": 0.48, "muscle": 0.5, "weight": 0.5, "height": 0.65,
     "skin": "middleage_african_female", "hair": ("long01", None, "toigo_long_01_black"), "eyebrows": "eyebrow012", "eyelashes": "eyelashes04",
     "clothes": [("elvs_halter_style_pantsuit1", None, None), ("shoes03", None, None)]},
    {"id": "PED_BA_F07", "name": "Young woman, hoodie dress", "tags": ["casual", "young"], "gender": 0.0, "age": 0.36, "muscle": 0.45, "weight": 0.45, "height": 0.5,
     "skin": "young_african_female", "hair": ("ponytail01", None, "dariush086_ponytail01_black"), "eyebrows": "eyebrow010", "eyelashes": "eyelashes02",
     "clothes": [("elvs_sporty_tracksuit_hoodie_dress1", None, None), ("shoes01", None, None)]},
]


def mhmat_path(subdir, asset, variant):
    """Absolute path of an alternative material, or None for the asset's default."""
    if not variant:
        return None
    return os.path.join(MPFB_DATA, subdir, asset, variant, variant + ".mhmat")


def diffuse_of(mhmat):
    """The diffuse texture file named in a MakeHuman .mhmat file."""
    with open(mhmat) as f:
        for line in f:
            parts = line.split(None, 1)
            if len(parts) == 2 and parts[0] == "diffuseTexture":
                return os.path.join(os.path.dirname(mhmat), parts[1].strip())
    return None


def base_color_texture(material):
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            link = node.inputs["Base Color"].links
            if link and link[0].from_node.type == "TEX_IMAGE":
                return node, link[0].from_node
            return node, None
    return None, None


def to_linear(c):
    """sRGB on-screen colour channel -> the linear value Blender's colour inputs use."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def greyscale_copy(image):
    """A greyscale copy of `image`, brightened so its average is light grey. A
    tint on top then decides the colour while keeping the fabric detail."""
    import numpy as np
    w, h = image.size
    px = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    lum = px[:, 0] * 0.2126 + px[:, 1] * 0.7152 + px[:, 2] * 0.0722
    lum = np.clip(lum * (0.75 / max(float(lum.mean()), 0.05)), 0.0, 1.0)
    px[:, 0] = px[:, 1] = px[:, 2] = lum
    copy = bpy.data.images.new(image.name + "_grey", w, h, alpha=True)
    copy.pixels.foreach_set(px.ravel())
    copy.pack()
    return copy


def restyle(obj, tint=None, texture_file=None, recolour=False):
    """Swaps an object's colour texture and/or multiplies it by `tint`."""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or not mat.use_nodes:
            continue
        bsdf, tex = base_color_texture(mat)
        if bsdf is None:
            continue
        if texture_file and tex is not None:
            tex.image = bpy.data.images.load(texture_file, check_existing=True)
        if recolour and tex is not None:
            tex.image = greyscale_copy(tex.image)
        if tint and tex is not None:
            # Texture × colour through a Multiply mix: the glTF exporter writes
            # this as baseColorTexture plus baseColorFactor
            mix = mat.node_tree.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (*[to_linear(c) for c in tint], 1.0)
            mat.node_tree.links.new(tex.outputs["Color"], mix.inputs[6])
            mat.node_tree.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def cap_textures(tmp_dir):
    """Scales every image down to MAX_TEXTURE and re-saves it so the exporter uses the small copy."""
    os.makedirs(tmp_dir, exist_ok=True)
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        w, h = img.size
        if max(w, h) > MAX_TEXTURE:
            s = MAX_TEXTURE / max(w, h)
            img.scale(max(1, int(w * s)), max(1, int(h * s)))
            img.filepath_raw = os.path.join(tmp_dir, bpy.path.clean_name(img.name) + ".png")
            img.file_format = "PNG"
            img.save()


def build(entry):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    female = entry["gender"] < 0.5
    info = HumanService._create_default_human_info_dict()
    info["phenotype"].update({k: entry[k] for k in ("gender", "age", "muscle", "weight", "height")})
    info["phenotype"]["race"] = {"african": 1.0, "asian": 0.0, "caucasian": 0.0}
    info["rig"] = "mixamo"
    info["proxy"] = "female1605/female1605.proxy" if female else "male1591/male1591.proxy"
    info["skin_mhmat"] = f"{entry['skin']}/{entry['skin']}.mhmat"
    info["skin_material_type"] = "GAMEENGINE"
    info["eyes"] = "low-poly/low-poly.mhclo"
    info["eyes_material_type"] = "GAMEENGINE"
    info["eyebrows"] = f"{entry['eyebrows']}/{entry['eyebrows']}.mhclo"
    if entry.get("eyelashes"):
        info["eyelashes"] = f"{entry['eyelashes']}/{entry['eyelashes']}.mhclo"
    hair = entry["hair"]
    info["hair"] = f"{hair[0]}/{hair[0]}.mhclo"
    info["clothes"] = [f"{c[0]}/{c[0]}.mhclo" for c in entry["clothes"]]
    info["clothes_material_type"] = "GAMEENGINE"
    info["alternative_materials"] = {}
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    basemesh = HumanService.deserialize_from_dict(info, settings)
    rig = basemesh.parent

    def part(asset):
        # MPFB names each object "<human>.<asset>"; a few assets use their own
        # internal name, so fall back to the object whose source path matches
        for child in rig.children:
            if child.name.endswith("." + asset) or asset in str(child.get("asset_source", "")):
                return child
        for child in rig.children:
            if any(asset in str(v) for v in child.keys()):
                return child
        print(f"WARNING {entry['id']}: no object for {asset}; children: {[c.name for c in rig.children]}")
        return None

    def apply_style(subdir, asset, tint=None, var=None, recolour=False):
        obj = part(asset)
        if obj is None:
            return
        variant = mhmat_path(subdir, asset, var)
        restyle(obj, tint=tint, texture_file=diffuse_of(variant) if variant else None, recolour=recolour)

    # Brown eyes instead of the default
    eyes = part("low-poly")
    if eyes:
        restyle(eyes, texture_file=os.path.join(MPFB_DATA, "eyes", "materials", "brown_eye.png"))
    apply_style("hair", *hair)
    for clothes in entry["clothes"]:
        apply_style("clothes", *clothes)

    cap_textures(os.path.join(bpy.app.tempdir, "ped_textures"))

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for child in rig.children:
        # The full-detail base body stays hidden under the low-poly proxy
        child.select_set(child is not basemesh)
    rig.name = entry["id"] + "_rig"
    out = os.path.join(OUT_DIR, entry["id"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=False, export_image_format="WEBP", export_image_quality=85)
    print(f"PED {entry['id']}: {os.path.getsize(out) / 1e6:.1f} MB -> {out}")


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    for entry in ROSTER:
        if only and entry["id"] not in only:
            continue
        build(entry)
    roster = [{
        "id": e["id"],
        "display_name": e["name"],
        "model_path": "res://assets/characters/pedestrians/black_african/%s.glb" % e["id"],
        "appearance_category": "black_african",
        "gender": "female" if e["gender"] < 0.5 else "male",
        "outfit_id": "+".join(c[0] for c in e["clothes"]),
        "tags": e["tags"],
        "source": "Generated with MPFB 2 from MakeHuman system assets and asset packs (CC0)",
        "license": "CC0",
    } for e in ROSTER]
    with open(ROSTER_JSON, "w") as f:
        json.dump(roster, f, indent=1)
    print("ROSTER", len(roster), "->", ROSTER_JSON)


main()
