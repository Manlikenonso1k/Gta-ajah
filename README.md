# GTA Port Harcourt

Open-world 3D game set in Port Harcourt, built with **Godot 4.7** (Jolt physics) and **Blender 4.5 LTS** for assets.

## Run

Open the folder in Godot (Import → select `project.godot`) and press F5, or from a terminal:

```
godot --path ~/Documents/gta-portharcourt
```

## Controls

| On foot | In a car |
|---|---|
| WASD move, Shift run, Space jump | WASD drive |
| E enter nearby car | E get out |
| R ragdoll | Space handbrake |
| Mouse look, Esc frees the mouse | Mouse look (camera swings back behind the car) |

## What's in it

- `scripts/city.gd`: procedural placeholder city (5×5 blocks, roads, buildings, palm trees)
- `scripts/player.gd`: third-person player, car entry, ragdoll and get-up
- `scripts/car.gd`: `VehicleBody3D` car; knocks characters into ragdolls above 4 m/s
- `scripts/pedestrian.gd`: wandering pedestrians
- `scripts/ragdoll.gd`: shared humanoid: walk animation plus an 11-part jointed ragdoll
- `scripts/camera_rig.gd`: orbit camera with a spring arm

Physics layers: 1 world, 2 vehicles, 3 characters, 4 ragdolls.

## Assets from Blender

Blender models go in `assets/models/` as `.glb` files; generator scripts go in `blender/`. Run a generator without opening Blender:

```
blender -b --python blender/<script>.py
```

Then swap the matching placeholder in the scripts above for the imported model.

## Test

```
godot --headless --path . --script tests/smoke_test.gd
```

The test spawns the world, ragdolls the player, drives a car into a pedestrian, and prints the results.
