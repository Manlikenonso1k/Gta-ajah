# GTA Port Harcourt

An open-world 3D game set in Port Harcourt, Nigeria, inspired by GTA Vice City. It's built with **Godot 4.7** (using its built-in Jolt physics engine), and its 3D assets are made in **Blender 4.5 LTS**.

> **Status:** early prototype. The city, buildings and characters are simple placeholder shapes generated from code; the vehicles are realistic test models downloaded from Sketchfab.

---

## Progress log (read this first)

This section is the handoff note between work sessions. It's kept current so a new session can pick up the work without reading the whole codebase. **Update it at the end of every step.**

### Current task: Android support (from `prompt.md`)

Goal: playable on Android phones in landscape at a steady 30 fps on a mid-range phone (about 4 GB RAM, Mali or Adreno GPU), without changing desktop keyboard and mouse play. Commit after each step.

| # | Step | Status |
|---|---|---|
| 1 | Audit car models and asset sizes | ✅ Done, see [Asset audit](#asset-audit) |
| 2 | Touch controls (`scenes/touch_controls.tscn`, `scripts/touch_controls.gd`) | ✅ Done. Shown on touchscreens, or on desktop with `godot --path . -- --touch` |
| 3 | Quality presets Low / Medium / High | ⏳ Next |
| 4 | Mobile car models (Blender script → `assets/models/cars/mobile/`) | ⬜ |
| 5 | Project settings: ETC2/ASTC, landscape | ⬜ |
| 6 | Android export preset and README "Android build" section | ⬜ |
| 7 | Tests: touch test, phone checklist | ⬜ |

### Where things are (quick map)

- `scripts/main.gd`: entry point. Registers input actions in code (`_setup_input`), builds the sky/sun/fog, spawns the city, cars, pedestrians and player, and draws the on-screen text.
- `scripts/car.gd`: drivable `VehicleBody3D`. Gets its meshes from `scripts/vehicle_model.gd`, which loads a `.glb` from `assets/models/cars/real/`, scales it from a per-model config, and cuts the wheels out of the mesh at load time. **Don't change the handling values in `car.gd`.**
- `scripts/player.gd`, `pedestrian.gd`, `ragdoll.gd` (shared body and ragdoll), `camera_rig.gd` (mouse orbit camera), `city.gd` (generated city and spawn points).
- Tests: `tests/smoke_test.gd` (headless gameplay check), `tests/view_vehicle.gd` (renders vehicle views for measuring).

### Decisions and gotchas so far

- **Renderer:** Compatibility (OpenGL). Vulkan crashes on the dev Mac (2013 Intel Iris), and Compatibility is also the safe choice for Android.
- **Lighting on the dev Mac:** the Intel Iris OpenGL driver ignores Godot's lights, so the game uses warm ambient light that looks right with or without the sun.
- **Vehicle textures:** must be imported as VRAM Compressed; lossless textures made loading take 20 s instead of 0.7 s.
- **Blender on the dev Mac (macOS 12):** glTF import and export fail because Blender 4.5's bundled numpy needs macOS 13.3. See [Troubleshooting](#troubleshooting).
- **Touch input:** `touch_controls.gd` reads `InputEventScreenTouch`/`Drag` in `_input()` and presses the normal input actions (`Input.action_press` with analog strength). Godot also turns touches into fake mouse events; `camera_rig.gd` ignores those (`event.device == InputEvent.DEVICE_ID_EMULATION`) and skips mouse capture and Esc on mobile. Touch look goes through `camera_rig.look()`, the same function the mouse uses. Run is a toggle on touch, so the right thumb stays free for looking.
- **The prompt says "9 cars" and "preload() in car.gd":** both are out of date. There are now 13 parked vehicles (10 models), and models are loaded by `vehicle_model.gd`.

---

## Contents

1. [Features](#features)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Running the game](#running-the-game)
5. [Controls](#controls)
6. [Project structure](#project-structure)
7. [How it works](#how-it-works)
8. [Blender asset pipeline](#blender-asset-pipeline)
9. [Testing](#testing)
10. [Pushing to GitHub](#pushing-to-github)
11. [Android and mobile](#android-and-mobile)
12. [Troubleshooting](#troubleshooting)
13. [Roadmap](#roadmap)
14. [Credits](#credits)
15. [A note on the name](#a-note-on-the-name)

---

## Features

- **City:** a generated 5×5 grid of city blocks with roads and yellow centre lines. Buildings come in cream, terracotta, pale blue and ochre, with dark window bands on each floor. There are palm trees, red laterite earth beyond the city, and a hazy tropical sky.
- **Third-person player:** walks, runs and jumps relative to the camera, with simple arm and leg swing animation.
- **Vehicles:** 13 drivable vehicles across 10 realistic models from Sketchfab: Toyota Corolla, Camry and Hiace, Mercedes G-Class and Sprinter, BMW E30, Honda Accord, a VW T3 danfo, a town bus and a coach. Each has suspension, spinning and steering wheels, handling scaled to its weight, steering that gets less sharp at speed, brakes and a handbrake. Press E to get in or out.
- **Pedestrians:** 30 people wander the sidewalks.
- **Ragdoll physics:** any character hit by a car faster than about 15 km/h becomes an 11-part jointed ragdoll with realistic joint limits. The player can also ragdoll on demand and gets back up after 4 seconds.
- **Camera:** an orbit camera that pulls in instead of clipping through walls. When you're driving and leave the mouse alone, it swings back behind the car.
- **Display:** an on-screen line showing the controls, plus your speed in km/h while driving.

---

## Requirements

### Tested setup

| Item | Version |
|---|---|
| Computer | MacBook Pro 2013 (MacBookPro11,1), Intel (x86_64), Intel Iris graphics |
| Operating system | macOS 12.7.6 Monterey |
| Game engine | Godot **4.7.2** stable (standard build, not .NET) |
| 3D software | Blender **4.5.15 LTS** |
| Version control | git |

### Minimum hardware

- A 64-bit CPU and 8 GB of RAM (16 GB recommended if Blender and Godot are open together)
- A GPU that supports Vulkan or Metal. Integrated Intel graphics will run the current placeholder graphics.
- About 2 GB of free disk space for Godot, Blender and the project

### Why these versions

- **Renderer:** the project uses Godot's **Compatibility** (OpenGL) renderer. The Vulkan-based Forward+ renderer crashes on older Intel Macs, because MoltenVK fails to allocate GPU memory on the Intel Iris/HD driver (`MTLIGAccelDevice newHeapWithDescriptor` → `SIGABRT`).
- **Godot 4.7** includes **Jolt Physics**, which this project uses for the car, the ragdolls and collisions. The project needs Godot **4.4 or newer**; older 4.x versions don't have the Jolt setting.
- **Blender 4.5 LTS** is the last Blender release that supports **Intel Macs**; Blender 5.x only runs on Apple Silicon. Everyone working on the project should use **Blender 4.5 LTS**, because `.blend` files saved in Blender 5.x may not open in 4.5.

---

## Installation

### macOS (Intel or Apple Silicon)

#### 1. Godot 4.7.2

**Option A: download it from the website (easiest)**

1. Go to <https://godotengine.org/download/macos/> and download **Godot 4.7.2** (the standard version, not .NET).
2. Unzip it and drag **Godot.app** into **Applications**.

**Option B: install it from the terminal, with a checksum check** (this is how it was set up on the development machine)

```bash
cd ~/Downloads
B=https://github.com/godotengine/godot/releases/download/4.7.2-stable
F=Godot_v4.7.2-stable_macos.universal.zip
curl -fsSLO $B/$F
curl -fsSL $B/SHA512-SUMS.txt | grep " $F" > godot.sha512
shasum -a 512 -c godot.sha512          # must print: OK
ditto -x -k $F /Applications/
```

**Add a `godot` terminal command:**

```bash
mkdir -p ~/.local/bin
printf '#!/bin/sh\nexec /Applications/Godot.app/Contents/MacOS/Godot "$@"\n' > ~/.local/bin/godot
chmod +x ~/.local/bin/godot
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
godot --version                        # 4.7.2.stable.official...
```

#### 2. Blender 4.5 LTS

**Option A: download it from the website**

1. Go to <https://www.blender.org/download/lts/4-5/>.
2. Pick **macOS Intel** or **macOS Apple Silicon** to match your Mac.
3. Open the `.dmg` and drag **Blender** into **Applications**.

**Option B: install it from the terminal (Intel Mac)**

```bash
cd ~/Downloads
F=blender-4.5.15-macos-x64.dmg          # Apple Silicon: blender-4.5.15-macos-arm64.dmg
curl -fsSLO https://download.blender.org/release/Blender4.5/$F
curl -fsSL https://download.blender.org/release/Blender4.5/blender-4.5.15.sha256 | grep "$F"
shasum -a 256 $F                        # the two hashes must match
hdiutil attach -nobrowse $F
cp -R /Volumes/Blender/Blender.app /Applications/
hdiutil detach /Volumes/Blender
```

**Add a `blender` terminal command.** Use a small launcher script like the one below. A plain symlink doesn't work, because Blender's built-in Python can't find its own files when started through one.

```bash
printf '#!/bin/sh\nexec /Applications/Blender.app/Contents/MacOS/Blender "$@"\n' > ~/.local/bin/blender
chmod +x ~/.local/bin/blender
blender --version                      # Blender 4.5.15 LTS
```

#### 3. Get the project

```bash
cd ~/Documents
git clone https://github.com/Manlikenonso1k/Gta-ajah.git gta-portharcourt
cd gta-portharcourt
```

#### 4. First import

Godot builds its cache folder (`.godot/`) on first open. You can do this from the terminal:

```bash
godot --headless --path . --import
```

You can also open Godot, click **Import**, choose `project.godot`, and click **Import & Edit**.

### Windows

#### 1. Git

Install **Git for Windows** from <https://git-scm.com/download/win>. The default options are fine. It also installs **Git Bash**, a terminal that accepts the same commands as macOS.

#### 2. Godot 4.7.2

1. Download **Godot 4.7.2** (standard, not .NET) from <https://godotengine.org/download/windows/>.
2. Unzip it to a permanent folder, for example `C:\Godot\`. You get `Godot_v4.7.2-stable_win64.exe` (the editor) and `Godot_v4.7.2-stable_win64_console.exe` (the same program, but it also shows a console window with log output).
3. **Optional: add a `godot` command.** Rename `Godot_v4.7.2-stable_win64_console.exe` to `godot.exe`. Then add `C:\Godot` to your PATH: open **Start → "Edit environment variables for your account" → Path → Edit → New**, enter `C:\Godot`, and click OK. Open a new terminal and run `godot --version`.

#### 3. Blender 4.5 LTS

Download **Blender 4.5 LTS** for Windows from <https://www.blender.org/download/lts/4-5/> and run the installer. Use 4.5 LTS rather than 5.x so `.blend` files stay compatible with the Mac.

#### 4. Get the project

In **Git Bash**, **PowerShell** or **Command Prompt**:

```bash
cd %USERPROFILE%\Documents          # PowerShell / Git Bash: cd ~/Documents
git clone https://github.com/Manlikenonso1k/Gta-ajah.git gta-portharcourt
cd gta-portharcourt
godot --headless --path . --import  # first import (or use the Godot UI below)
```

If you didn't set up the `godot` command, open Godot, click **Import**, choose `gta-portharcourt\project.godot`, and click **Import & Edit**.

> **Line endings:** `.gitattributes` makes git keep files with LF line endings on every system, so files edited on Windows and macOS don't show as entirely changed. Don't turn this off.

### Linux

1. Download **Godot 4.7.2** (standard) from <https://godotengine.org/download/linux/>, extract it, and make the file executable (`chmod +x`).
2. Install **Blender 4.5 LTS** from <https://www.blender.org/download/lts/4-5/>. Your distribution's package may be a different version, so check it.
3. Clone the repo and import `project.godot`.

---

## Running the game

First go to the project folder (`cd ~/Documents/gta-portharcourt`, or on Windows `cd %USERPROFILE%\Documents\gta-portharcourt`). Then:

| What | Command or step |
|---|---|
| Play the game | `godot --path .` |
| Open the editor | `godot --path . -e` |
| Play from inside the editor | Press **F5** (or the ▶ button at the top right) |
| No `godot` command? | Open Godot, pick **GTA Port Harcourt** in the Project Manager, and click **Edit** (or **Run**) |

The first launch can take longer while Godot compiles its shaders.

**Renderer:** the project uses Godot's **Compatibility** (OpenGL) renderer so it runs on older Intel Macs. It works on Windows and Linux too. If Godot itself crashes before the Project Manager appears (common on older Intel Macs), start it with `godot --rendering-driver opengl3`.

---

## Controls

| Action | On foot | In a car |
|---|---|---|
| Move or drive | W A S D / arrow keys | W accelerate, S brake/reverse, A D steer |
| Run | Shift | — |
| Jump / handbrake | Space | Space |
| Enter or exit a car | E (or F) near a car | E (or F) |
| Ragdoll yourself | R | — |
| Look around | Mouse | Mouse |
| Release the mouse | Esc (click to capture it again) | Esc |

Input actions are registered in code (`scripts/main.gd` → `_setup_input`), so they don't appear in the editor's Input Map.

---

## Project structure

```
gta-portharcourt/
├── project.godot          # Engine config: Jolt physics, 1280×720, physics layer names
├── scenes/
│   └── main.tscn          # Entry scene: a single node running scripts/main.gd
├── scripts/
│   ├── main.gd            # Input, sky/sun/fog, spawns city, player, cars, pedestrians, display text
│   ├── city.gd            # Generated placeholder city (blocks, roads, buildings, palms)
│   ├── player.gd          # Player movement, entering cars, ragdoll and getting back up
│   ├── car.gd             # VehicleBody3D car, controls, hitting pedestrians
│   ├── vehicle_model.gd   # Vehicle model list; scales models and cuts out their wheels
│   ├── pedestrian.gd      # Wandering pedestrian
│   ├── ragdoll.gd         # Shared humanoid body: visual, walk animation, physics ragdoll
│   └── camera_rig.gd      # Third-person orbit camera with spring arm
├── assets/
│   └── models/            # Blender exports (.glb) go here
│       └── cars/real/     # Sketchfab vehicles (CC BY), see CREDITS.md there
├── blender/               # Blender Python scripts that generate assets
├── tests/
│   ├── smoke_test.gd      # Automated gameplay test that runs without a window
│   └── view_vehicle.gd    # Renders vehicle side/top views for measuring new models
└── README.md
```

---

## How it works

### Physics layers

| Layer | Name | Used by |
|---|---|---|
| 1 | world | Ground, buildings, palm trees |
| 2 | vehicles | Cars |
| 3 | characters | Player and pedestrians (capsule colliders) |
| 4 | ragdolls | Ragdoll body parts |

The camera's spring arm only collides with layer 1, so it never snaps in front of characters or cars.

### Directions and units

- Characters face **−Z**; their position is at the **feet**.
- Cars face **+Z**. This is a convention of Godot's `VehicleBody3D`.
- 1 unit = 1 metre. Vehicles weigh from 1200 kg (BMW E30) to 13,000 kg (coach), set per model in `scripts/vehicle_model.gd`. The ragdoll parts add up to about 68 kg.

### Parking

`scripts/city.gd` parks 3 vehicles on each of the 4 inner north–south roads, one per block, so even a 12 m coach fits and nothing spawns on top of anything else. The middle block is kept clear for the car you start next to.

### Ragdolls

`scripts/ragdoll.gd` defines one humanoid body as a table of 11 parts: pelvis, chest, head, upper and lower arms, and upper and lower legs. That table is used two ways:

- **Alive:** meshes on pivot nodes at the shoulders and hips, swung back and forth to animate walking.
- **Knocked down:** a `RigidBody3D` for each part, joined with joints that limit how far each one can bend. Shoulders, hips, neck and spine use `ConeTwistJoint3D`; elbows and knees use `HingeJoint3D`.

At most 25 ragdolls exist at once; the oldest is removed when a new one spawns.

### Car tuning (in `scripts/car.gd`)

Values are for a 1200 kg car (`BASE_MASS`). Engine force, brakes and suspension strength are multiplied by `mass / 1200`, so a 13 t coach accelerates about like a car instead of crawling.

| Setting | Value | Effect |
|---|---|---|
| `ENGINE` | 2500 | Engine force per rear wheel (rear-wheel drive) |
| `BRAKE` / `HANDBRAKE` | 25 / 40 | Braking strength |
| `suspension_max_force` | 12000 | Strongest push one wheel's spring can give |
| `MAX_STEER` | 0.55 rad | Steering angle at low speed (drops to 0.2 at high speed) |
| `TOP_SPEED` | 45 m/s | About 160 km/h |
| `HIT_SPEED` | 4 m/s | Speed needed to knock a character into a ragdoll |
| `wheel_friction_slip` | 3.0 | Lower = more sliding and drifting |
| `suspension_stiffness` | 40 | Higher = firmer, more race-like |

---

## Blender asset pipeline

Blender makes the models; Godot runs the game.

1. **Model** in Blender 4.5 LTS. Use **metres** and face the model's front toward **−Z** for characters or **+Z** for cars, matching the game.
2. **Export** as **glTF Binary (`.glb`)** into `assets/models/`, with *Apply Modifiers* checked.
3. **Swap it in:** load the `.glb` in the matching script instead of the placeholder shapes.

### Adding a car

Downloaded car models come in every scale, facing any direction, and usually have their wheels merged into the body. `scripts/vehicle_model.gd` copes with all of that. You give it a few numbers per model; at load time it scales and turns the model, then cuts the wheel triangles out of the mesh so they can spin and steer. (The two passes take under a second for all ten vehicles.)

To add a vehicle:

1. **Download** it as `.glb` into `assets/models/cars/real/`, named like `lexus_es.glb`. On Sketchfab, filter by *Downloadable* and prefer models under about 100k triangles. Check that it actually has four wheels; some don't. Run `godot --headless --path . --import` once afterwards.
2. **Render a measuring view**, giving the real length in metres and a guess at the yaw (0 or 90):
   ```bash
   godot --path . --script tests/view_vehicle.gd -- raw lexus_es 4.9 0
   ```
   This saves a side view on a 0.5 m grid to `~/Library/Application Support/Godot/app_userdata/GTA Port Harcourt/vehicle_views/` (on Windows: `%APPDATA%\Godot\app_userdata\GTA Port Harcourt\vehicle_views\`). The car should lie lengthwise with its **front on the left**. If it's sideways, add 90 to the yaw; if it's backwards, add 180.
3. **Read off the wheels**: front and rear axle z (the red vertical line is z = 0, left is +), the wheel-centre height and the tyre radius, all in metres.
4. **Add an entry** to `MODELS` in `scripts/vehicle_model.gd`, for example
   `"lexus_es": {"length": 4.9, "yaw": 0, "wheels": [1.45, -1.40, 0.34, 0.34], "mass": 1600},`
   then add `"lexus_es"` to `CAR_MODELS` in `scripts/main.gd`.
5. **Check the cut**: `godot --path . --script tests/view_vehicle.gd -- car lexus_es` draws the separated wheels in magenta. If bits of tyre stay black, raise the radius a little; for twin rear tyres (trucks, buses) raise `"width"`.
6. **Credit the author** in `assets/models/cars/real/CREDITS.md` if the license is CC BY.

**Texture import:** set each model's textures to *VRAM Compressed* (select the extracted `.png` files in Godot's FileSystem dock → Import tab → Compress Mode → VRAM Compressed → Reimport). The default (lossless) made the cars take 20 seconds to load instead of under one.

**Where to get models:** Sketchfab has many free, realistic, downloadable cars (free account needed). Check each one's license: CC BY needs a credit, and NonCommercial ones can't go in a game you sell. Models from GTA mod sites are usually ripped from other games: fine for private testing, but don't publish them.

Assets can also be generated by Python scripts, without opening Blender:

```bash
blender -b --python blender/<script>.py
```

Scripts in `blender/` should save their output to `assets/models/`. Keep Blender's backup files (`*.blend1`) out of git; `.gitignore` already does this.

**Keeping it fast on modest hardware:** an integrated Intel GPU can't handle GTA V-level detail. Aim for:
- A few thousand triangles per car or character
- Textures no larger than 2K
- Lower-detail versions of models for objects far from the camera

---

## Testing

An automated test spawns the world without opening a window, ragdolls the player, gets them up again, enters a car, drives into a pedestrian, and prints the results:

```bash
godot --headless --path . --script tests/smoke_test.gd
```

Expected output:

```
cars: 13  car y: 0.0
ragdoll pelvis y after 1.5s: 0.14  ragdolls: 1
player back up: true  ragdolls: 0
driving: true
car speed km/h: 49  upright: true
pedestrian ragdolled: true  ped freed: true
```

Any line containing `ERROR` or `SCRIPT ERROR` means something is broken.

---

## Pushing to GitHub

The project is already a git repository on the `main` branch. To publish it:

1. Create an **empty** repository on GitHub, with no README, licence or `.gitignore`.
2. Run:

```bash
cd ~/Documents/gta-portharcourt
git add -A
git commit -m "Add full README"
git remote add origin https://github.com/Manlikenonso1k/Gta-ajah.git
git push -u origin main
```

If a push is rejected with **"fetch first"**, someone changed the repo on GitHub. Run `git pull --rebase`, then push again.

If a big push (for example new models) fails with **"the remote end hung up unexpectedly"**, raise git's upload buffer for this repo and push again:

```bash
git config http.postBuffer 524288000
```

The vehicle models make the repo about 60 MB. GitHub refuses single files over 100 MB, so keep each model below that (or use Git LFS).

`.gitignore` excludes `.godot/` (Godot's cache, which is rebuilt on import), `*.blend1`, `/build/` and `.DS_Store`.

---

## Android and mobile

### Asset audit

Measured 2026-10-22, before any mobile work. Triangle and texture counts were read by loading each model in Godot; the textures are what the materials actually use.

| Model | Triangles | Textures (count × resolution) | `.glb` size |
|---|---:|---|---:|
| `corolla` | 84,398 | 27: 25 × 1024², 1 × 1024×512, 1 × 256² | 17.6 MB |
| `town_bus` | 55,527 | 2: 1 × 1024², 1 × 1024×128 | 3.8 MB |
| `sprinter` | 37,564 | 26: 26 × 1024² | 6.3 MB |
| `camry` | 18,410 | 0 (plain colours) | 1.9 MB |
| `bmw_e30` | 13,076 | 7: 7 × 1024² | 3.4 MB |
| `benz_g` | 12,516 | 1: 128² | 0.6 MB |
| `coach` | 11,210 | 5: 4 × 1024², 1 × 512×1024 | 1.3 MB |
| `hiace` | 8,348 | 8: 2 × 512², 5 × 256², 1 × 128² | 0.6 MB |
| `accord` | 6,222 | 18: up to 1024×128, mostly 256² or smaller | 0.6 MB |
| `vw_t3` | 5,671 | 0 (plain colours) | 0.5 MB |

**Total `assets/`: 60 MB.** The 10 biggest files:

| Size | File |
|---:|---|
| 17.6 MB | `assets/models/cars/real/corolla.glb` |
| 6.3 MB | `assets/models/cars/real/sprinter.glb` |
| 3.8 MB | `assets/models/cars/real/town_bus.glb` |
| 3.4 MB | `assets/models/cars/real/bmw_e30.glb` |
| 1.9 MB | `assets/models/cars/real/camry.glb` |
| 1.7 MB | `assets/models/cars/real/corolla_7.png` |
| 1.3 MB | `assets/models/cars/real/coach.glb` |
| 1.2 MB | `assets/models/cars/real/corolla_4.png` |
| 1.1 MB | `assets/models/cars/real/sprinter_18.png` |
| 1.0 MB | `assets/models/cars/real/corolla_18.png` |

**What this means for phones:**
- The Corolla, town bus and Sprinter need cutting down to the 8–15k triangle budget. The other seven are already near it.
- Each texture is stored twice: embedded in its `.glb` and also unpacked as a `.png` by Godot's importer. The exported game only ships the imported copies.
- With 13 parked vehicles, the scene holds roughly 330k vehicle triangles, which is too much for a mid-range phone.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `godot: command not found` | Open a new terminal, or run `source ~/.zshrc`. Check that `~/.local/bin/godot` exists. |
| Blender can't import or export glTF on macOS 12: `numpy` error mentioning `_cblas_caxpy$NEWLAPACK` | Blender 4.5's bundled numpy needs macOS 13.3 or newer. This should fix it (not yet tried on the development Mac): install a numpy that works on macOS 12 into Blender's Python: `/Applications/Blender.app/Contents/Resources/4.5/python/bin/python3.11 -m pip install --upgrade --force-reinstall "numpy==1.26.4" --only-binary=:all: --target /Applications/Blender.app/Contents/Resources/4.5/python/lib/python3.11/site-packages`. Windows and newer Macs aren't affected. |
| Blender prints Python errors about `sys.prefix` | You're starting it through a symlink. Use the launcher script from [Installation](#installation). |
| Blender 5.x won't open on an Intel Mac | Expected: use Blender 4.5 LTS. |
| The project opens but physics settings look wrong | You're on Godot older than 4.4. Install 4.7.2. |
| Flat lighting with no sun shading or shadows (older Intel Mac) | A driver bug: the Intel Iris/HD OpenGL driver on macOS ignores Godot's lights (seen with Godot 4.4 and 4.7). The game uses warm ambient light so colours still look right. Lighting works normally on Windows, Linux and newer Macs. |
| Low frame rate | In `scripts/main.gd`, lower `directional_shadow_max_distance` or set `sun.shadow_enabled = false`. A smaller window size in `project.godot` also helps. |
| Godot crashes on launch (`SIGABRT` in `Metal` / `MTLIGAccelDevice` / `vkAllocateMemory`) | Your GPU can't run Vulkan through MoltenVK. The project already uses the OpenGL Compatibility renderer, so open it directly with `godot --path . -e`. To open the Project Manager, run `godot --rendering-driver opengl3`. |
| The mouse is stuck | Press **Esc** to release it. |
| Homebrew says "No developer tools installed" | Not needed for this project. If you want Homebrew anyway, run `xcode-select --install`. |

---

## Roadmap

- [x] Realistic test vehicles: Corolla, Camry, G-Class, E30, Accord, Hiace, Sprinter, VW T3, town bus, coach (downloaded from Sketchfab)
- [ ] Our own Blender models to replace them, plus a keke, a proper danfo and an okada
- [ ] Lexus RX and Toyota Sienna (the downloaded models were broken: missing wheels)
- [ ] A rigged and animated character model, with a ragdoll built on its skeleton
- [ ] Port Harcourt landmarks: Garrison roundabout, the waterfront and creeks, Mile 1 market
- [ ] AI traffic and smarter pedestrians
- [ ] Day/night cycle and street lights
- [ ] Weapons, wanted level, police
- [ ] Missions and a minimap
- [ ] Sound: engines, horns, city ambience, radio

---

## Credits

- Vehicle models: 10 models from Sketchfab by their authors, CC BY 4.0. See [assets/models/cars/real/CREDITS.md](assets/models/cars/real/CREDITS.md) for each author and source link.

---

## A note on the name

"GTA" and "Grand Theft Auto" are trademarks of Rockstar Games. The name is fine for a personal or learning project. Rename the game before publishing or selling it (for example "Port Harcourt Hustle" or "Garden City Stories"). To rename it, change `config/name` in `project.godot` and the title at the top of this file.
