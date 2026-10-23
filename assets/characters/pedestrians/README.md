# Pedestrian character assets

- `black_african/`: 16 MPFB-generated characters (`PED_BA_*.glb`, CC0) and two downloaded models (`carla.glb`, `african_male.glb`, CC BY 4.0).
- `white/`: five Renderpeople models from Sketchfab (CC BY 4.0).
- `generated_roster.json`: written by `blender/make_pedestrians.py`; read by `scripts/pedestrian_registry.gd`.
- `CREDITS_SKETCHFAB.md`: author, licence and source link for every downloaded model (required by CC BY).

Downloaded models are stored slimmed (no animations or morph targets, 1024 px WebP textures); the originals can be re-downloaded from the links in the credits file. Textures are embedded in each imported scene as Basis Universal (`gltf/embedded_image_handling=2`), so no extracted `.png` files are needed.

See [docs/PEDESTRIAN_CATALOG.md](../../../docs/PEDESTRIAN_CATALOG.md) for the full list and how to add a character. `animations/`, `materials/` and `shared/` are reserved for future game-specific overrides.
