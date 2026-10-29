"""Generates the player character with MPFB 2 (MakeHuman for Blender).

Run:  blender -b --python blender/make_player.py

Needs Blender 4.5 LTS with the MPFB 2 extension and the MakeHuman asset packs
(see the README section "Pedestrian characters"). Every asset used is CC0.

Writes, in assets/characters/player/:
  player.glb          the character: low-poly MPFB body proxy, Mixamo-compatible
                      skeleton (mixamorig_* bones), textures capped at 1024 px as
                      WebP. Faces +Z with its feet on y = 0, in metres.
  player.glb.import   Godot import settings: the BoneMap that renames the bones
                      to Godot's SkeletonProfileHumanoid (the team's standard
                      skeleton: Hips, Spine, Chest, ... LeftHand), and embedded
                      Basis Universal textures, the same as the pedestrians.
  player.json         what the game reads to find the player model (one entry,
                      so a different model can be swapped in by editing it or
                      by pointing model_path at any rigged humanoid .glb).

To change the character, edit only the PLAYER block below and run the script
again, then `godot --headless --path . --import`.
"""
import bpy
import json
import os

from bl_ext.user_default.mpfb.services.humanservice import HumanService

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "characters", "player")
MPFB_DATA = os.path.join(bpy.utils.extension_path_user("bl_ext.user_default.mpfb", create=False), "data")
MAX_TEXTURE = 1024
BLACK_HAIR = (0.3, 0.27, 0.25)
# The MPFB body proxy measured in Blender (body_height) is this many times
# smaller than the exported glTF is in metres inside Godot. Calibrated against
# the in-engine AABB rendered by tests/view_driver.gd -- player at the slider
# actually used below (slider 0.43: proxy 0.840 m, Godot height 1.81 m -> 2.155).
# Used to report the true export height and to pick the fixed height slider. The
# pedestrians set the slider the same way (a fixed value), so re-measure with
# view_driver if this ever drifts.
EXPORT_SCALE = 2.155

# ============================================================================
# PLAYER CONFIG: the main character. Change this block to change the player.
# ============================================================================
PLAYER = {
    "id": "PLAYER_PH_HUSTLER",
    "name": "Young PH hustler",
    # The owner's description, kept verbatim for reference
    "description": "Black African man, about 25 years old, about 1.80 m tall, athletic build, "
                   "dark skin, short fade/low cut hair (black), casual shirt and jeans, trainers.",
    # MakeHuman phenotype, 0..1. gender 1 = male. age 0.5 = 25 years.
    "gender": 1.0,
    "age": 0.5,
    "muscle": 0.72,   # athletic
    "weight": 0.45,   # lean
    # Target standing height in metres (for reference / the credits line).
    "target_height_m": 1.80,
    # MakeHuman height slider, 0..1, set directly like the pedestrians. 0.43
    # gives ~1.80 m in Godot (target_height_m / EXPORT_SCALE). To change the
    # player's height, change this and re-measure with view_driver -- player.
    "height": 0.43,
    "skin": "young_african_male",
    # Multiplies the skin texture (on-screen colour); below 1 darkens it
    "skin_tint": (0.78, 0.74, 0.72),
    # Short black hair: (asset, tint, alternative material, recolour)
    "hair": ("short01", BLACK_HAIR),
    "eyebrows": "eyebrow001",
    # Purple shirt with blue jeans (an outfit no pedestrian wears), white trainers
    "clothes": [("male_casualsuit01", None, "toigo_male_casual_suit_01_purple_shirt"),
                ("shoes05", None, None)],
}
# ============================================================================


def mhmat_path(subdir, asset, variant):
    if not variant:
        return None
    return os.path.join(MPFB_DATA, subdir, asset, variant, variant + ".mhmat")


def diffuse_of(mhmat):
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
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def restyle(obj, tint=None, texture_file=None):
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
        if tint and tex is not None:
            mix = mat.node_tree.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (*[to_linear(c) for c in tint], 1.0)
            mat.node_tree.links.new(tex.outputs["Color"], mix.inputs[6])
            mat.node_tree.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def cap_textures(tmp_dir):
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


def make_human(entry, height):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = HumanService._create_default_human_info_dict()
    info["phenotype"].update({k: entry[k] for k in ("gender", "age", "muscle", "weight")})
    info["phenotype"]["height"] = height
    info["phenotype"]["race"] = {"african": 1.0, "asian": 0.0, "caucasian": 0.0}
    info["rig"] = "mixamo"
    info["proxy"] = "male1591/male1591.proxy"
    info["skin_mhmat"] = f"{entry['skin']}/{entry['skin']}.mhmat"
    info["skin_material_type"] = "GAMEENGINE"
    info["eyes"] = "low-poly/low-poly.mhclo"
    info["eyes_material_type"] = "GAMEENGINE"
    info["eyebrows"] = f"{entry['eyebrows']}/{entry['eyebrows']}.mhclo"
    info["hair"] = f"{entry['hair'][0]}/{entry['hair'][0]}.mhclo"
    info["clothes"] = [f"{c[0]}/{c[0]}.mhclo" for c in entry["clothes"]]
    info["clothes_material_type"] = "GAMEENGINE"
    info["alternative_materials"] = {}
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    basemesh = HumanService.deserialize_from_dict(info, settings)
    return basemesh, basemesh.parent


def part(rig, asset):
    for child in rig.children:
        if child.name.endswith("." + asset) or asset in str(child.get("asset_source", "")):
            return child
    for child in rig.children:
        if any(asset in str(v) for v in child.keys()):
            return child
    print(f"WARNING player: no object for {asset}; children: {[c.name for c in rig.children]}")
    return None


def body_height(rig, basemesh):
    """Height of the body proxy (no hair, no shoes) in metres."""
    proxy = None
    for child in rig.children:
        if child is not basemesh and "male1591" in (child.name + str(dict(child.items()))).lower():
            proxy = child
    target = proxy or basemesh
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = target.evaluated_get(deps).to_mesh()
    zs = [(target.matrix_world @ v.co).z for v in mesh.vertices]
    target.evaluated_get(deps).to_mesh_clear()
    return max(zs) - min(zs)


def build():
    entry = PLAYER
    # MakeHuman's height slider is set directly (the pedestrians do the same).
    # body_height measures the Blender proxy; EXPORT_SCALE converts it to the
    # true exported height in metres (verified in Godot with view_driver).
    height = entry["height"]
    basemesh, rig = make_human(entry, height)
    proxy_m = body_height(rig, basemesh)
    measured = proxy_m * EXPORT_SCALE
    print(f"PLAYER height slider {height:.3f} -> proxy {proxy_m:.3f} m -> ~{measured:.3f} m exported")

    eyes = part(rig, "low-poly")
    if eyes:
        restyle(eyes, texture_file=os.path.join(MPFB_DATA, "eyes", "materials", "brown_eye.png"))
    if entry.get("skin_tint"):
        restyle(basemesh, tint=entry["skin_tint"])
        for child in rig.children:
            if child is not basemesh and "male1591" in (child.name + str(dict(child.items()))).lower():
                restyle(child, tint=entry["skin_tint"])
    hair = entry["hair"]
    hair_obj = part(rig, hair[0])
    if hair_obj:
        variant = mhmat_path("hair", hair[0], hair[2] if len(hair) > 2 else None)
        restyle(hair_obj, tint=hair[1], texture_file=diffuse_of(variant) if variant else None)
    for clothes in entry["clothes"]:
        obj = part(rig, clothes[0])
        if obj:
            variant = mhmat_path("clothes", clothes[0], clothes[2])
            restyle(obj, tint=clothes[1], texture_file=diffuse_of(variant) if variant else None)

    cap_textures(os.path.join(bpy.app.tempdir, "player_textures"))

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for child in rig.children:
        child.select_set(child is not basemesh)
    rig.name = "PLAYER_rig"
    out = os.path.join(OUT_DIR, "player.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=False, export_image_format="WEBP", export_image_quality=85)
    print(f"PLAYER {entry['id']}: body {measured:.3f} m, slider {height:.3f}, {os.path.getsize(out) / 1e6:.1f} MB -> {out}")
    write_import(out)
    with open(os.path.join(OUT_DIR, "player.json"), "w") as f:
        json.dump({
            "id": entry["id"],
            "display_name": entry["name"],
            "description": entry["description"],
            "model_path": "res://assets/characters/player/player.glb",
            "body_height_m": round(measured, 3),
            "skeleton": "SkeletonProfileHumanoid via BoneMap in player.glb.import (source bones mixamorig_*)",
            "source": "Generated with MPFB 2 from MakeHuman system assets and asset packs (CC0) by blender/make_player.py",
            "license": "CC0",
        }, f, indent=1)


BONES = {
    "Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head",
    "LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
    "RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot", "RightToes": "RightToeBase",
}
for side in ("Left", "Right"):
    BONES.update({f"{side}Shoulder": f"{side}Shoulder", f"{side}UpperArm": f"{side}Arm",
                  f"{side}LowerArm": f"{side}ForeArm", f"{side}Hand": f"{side}Hand",
                  f"{side}ThumbMetacarpal": f"{side}HandThumb1", f"{side}ThumbProximal": f"{side}HandThumb2",
                  f"{side}ThumbDistal": f"{side}HandThumb3"})
    for godot_name, mixamo in (("Index", "Index"), ("Middle", "Middle"), ("Ring", "Ring"), ("Little", "Pinky")):
        for i, joint in enumerate(("Proximal", "Intermediate", "Distal")):
            BONES[f"{side}{godot_name}{joint}"] = f"{side}Hand{mixamo}{i + 1}"
PROFILE_ORDER = ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftEye", "RightEye", "Jaw"]
for side in ("Left", "Right"):
    PROFILE_ORDER += [f"{side}Shoulder", f"{side}UpperArm", f"{side}LowerArm", f"{side}Hand",
                      f"{side}ThumbMetacarpal", f"{side}ThumbProximal", f"{side}ThumbDistal"]
    for finger in ("Index", "Middle", "Ring", "Little"):
        PROFILE_ORDER += [f"{side}{finger}{j}" for j in ("Proximal", "Intermediate", "Distal")]
for side in ("Left", "Right"):
    PROFILE_ORDER += [f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot", f"{side}Toes"]


def write_import(glb_path):
    """Godot import settings: standard-skeleton BoneMap and embedded textures,
    matching the pedestrians' .glb.import files."""
    if os.path.exists(glb_path + ".import"):
        # Keep Godot's uid and any hand edits; delete the file to regenerate it
        return
    entries = ",".join(f'"bone_map/{b}":&"{("mixamorig_" + BONES[b]) if b in BONES else ""}"' for b in PROFILE_ORDER)
    bone_map = ('Object(BoneMap,"resource_local_to_scene":false,"resource_name":"","profile":'
                'Object(SkeletonProfileHumanoid,"resource_local_to_scene":false,"resource_name":"","root_bone":&"Root",'
                '"scale_base_bone":&"Hips","group_size":4,"bone_size":56,"script":null)\n,"bonemap":null,'
                + entries + ',"script":null)')
    text = f"""[remap]

importer="scene"
importer_version=1

[deps]

source_file="res://assets/characters/player/{os.path.basename(glb_path)}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{
"nodes": {{
"PATH:PLAYER_rig/Skeleton3D": {{
"retarget/bone_map": {bone_map}
,
"retarget/rest_fixer/fix_silhouette/enable": true,
"retarget/rest_fixer/fix_silhouette/threshold": 1.0
}}
}}
}}
gltf/naming_version=2
gltf/embedded_image_handling=2
gltf/texture_map_mode=1
"""
    with open(glb_path + ".import", "w") as f:
        f.write(text)


build()
