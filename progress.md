# Progress handoff

Last updated 2026-10-29. Last commit: `29fc3c3`. Read this first, then README.md (Progress log, "Interfaces between tasks", "Decisions and gotchas"), `docs/TEAM_TASKS.md` and `docs/QA_REPORT.md`. The task specs are `prompt-lead.md` and `prompt-1…4-*.md` in the repo root.

## Where things stand

| Work | State |
|---|---|
| Install (Godot, Blender, MPFB + MakeHuman packs) | Done |
| Task 1: realistic ragdoll | Done, committed |
| Task 2: mocap animation | Done, committed |
| Task 3: traffic and pavements | Done, committed |
| Task 4 steps 1–2: steering-wheel/seat data, player model | Done, committed |
| Arm fix (forearms raised on every model except Nathan) | Done, committed (`29fc3c3`) |
| **Task 4 steps 3–5 (Phase 2)** | **In progress, uncommitted, not verified** |

Commits since the team started:

```
29fc3c3 Fix pedestrians' raised forearms by matching every rest pose to the clips
eda3615 Record Phase 1 results, interfaces and QA pass
c9284d4 Generate the player model with MPFB (Task 4 steps 1-2)
f1f029d Keep pedestrians on the pavement and finish the traffic tests (Task 3)
3808578 Animate pedestrians with shared mocap clips (Task 2)
6494d7d Make the realistic pedestrians ragdoll on their own models (Task 1)
```

At `29fc3c3` the full suite passed: 11/11 tests, 0 errors, 0 warnings (headless profile ~6.9 ms/frame on High and Low). Nothing has been pushed to GitHub.

## Next: finish Phase 2 (Task 4 steps 3–5)

Spec: `prompt-4-player-and-drivers.md`, steps 3–5. A previous agent was building it and stopped mid-work. Its changes are uncommitted in the working tree:

| File | What it is |
|---|---|
| `scripts/vehicle_occupants.gd` (new) | Driver and passengers inside one vehicle; added to every car by `car.gd` (parked cars stay empty) |
| `scripts/seated_pose.gd` (new) | Poses a seated character: Driving / Sit_Idle clip via `locomotion.gd`, hands on the wheel |
| `scripts/player.gd` | Realistic player (from `assets/characters/player/player.json`), sit-down/get-out animations. Large change (+387 lines) |
| `scripts/car.gd`, `scripts/traffic.gd` | Hooks that attach occupants (must not change handling or AI driving) |
| `scripts/vehicle_model.gd`, `assets/models/cars/vehicles.json` | Small cabin/steering adjustments |
| `assets/characters/player/player.glb.import`, `blender/make_player.py` | Arm rest-pose fix applied to the player (see below) |
| `tests/view_driver.gd` | Driver renders |
| `tests/steering_hands_test.gd`, `tests/steering_drivers_test.gd` (new) | Phase 2 acceptance tests |
| `tests/steering_probe.gd`, `steering_profile.gd`, `steering_smoke_check.gd` (new) | Throwaway probes; delete before committing unless useful |

**Known problem at last check:** `tests/smoke_test.gd` fails with `driving: false`: the player no longer gets into the car. It passes at `29fc3c3`, so it comes from the Phase 2 entry/exit changes in `player.gd`/`car.gd`. Fix this first. High-preset physics time also looked higher with the occupants in (2.7–4.5 ms vs 1.9–3.4 ms; noisy), so check that seated people have no colliders.

What Phase 2 must still deliver and prove (from the spec):
- Steering wheel rotates with the car's steering value, up to `wheel_turn_deg` each way (cabin data in `vehicles.json`, documented in README).
- Driver seated at the measured seat with hands on the rim around 10 and 2, following it as it turns; head turns slightly into corners; bus/coach drivers sit more upright.
- Player: realistic model in `player.gd` with the shared animations, the realistic ragdoll for R and car hits, the GetUp clip afterwards. Don't change controls, speeds or the collision capsule. Keep the Sprinter's door animation.
- Every moving AI car has a driver from the pedestrian registry (90/10 mix); danfos and buses carry a few passengers; hand IK and wheel rotation only within ~40 m, fixed pose beyond, hidden beyond 120 m.
- Tests: driver visible in every moving AI car; hands within 3 cm of the rim from full left to full right in all 10 models; wheel rotates; player ragdoll uses the realistic model.
- Renders with `tests/view_driver.gd` for a sedan, the danfo, the Sprinter and the coach at full left, centre and full right, outside and from the driving camera. **Inspect from front, side and 3/4**: the arm problem below was missed because only side views were checked.
- Profile High and Low before and after, with all traffic drivers visible.

Then run the whole suite, commit only Phase 2 files with `git add <files>` (never `git add -A`), update README's Progress log and `docs/TEAM_TASKS.md` (V3–V5).

## Decide before committing

- **`assets/animations/mixamo/`** (7 `.fbx` clips, untracked, nothing references them). Mixamo's terms don't allow the clip files in a public repo, and Task 2 rejected Mixamo for that reason. Don't commit them. Ask the owner whether they put them there; if they're kept locally, add `assets/animations/mixamo/` to `.gitignore`.
- Optional: the starter car in `scripts/main.gd` sits ~0.3 m into a driving lane (`road_line(3)+3`; `+4.8` clears it).

## Machine setup (Windows 10)

- Godot 4.7.2: `C:\Godot\godot.exe`. Blender 4.5.15 LTS: `C:\Blender\blender.exe`. Neither is on PATH.
- MPFB 2.0.18 and all 8 MakeHuman packs are installed in `%APPDATA%\Blender Foundation\Blender\4.5\extensions\.user\user_default\mpfb\data\`.
- In Git Bash use forward slashes: `/c/Godot/godot.exe`. Backslash paths break there.
- Run Godot/Blender through the lock: `sh tools/locked.sh "/c/Godot/godot.exe" --headless --path . --script tests/<name>.gd > out.log 2>&1`, then read the log (the standard Godot exe doesn't print reliably to the terminal). If a crash leaves `.tool_lock` behind and no Godot process is running, `rmdir .tool_lock`.
- Root-level `*.log` files are git-ignored scratch output.
- Godot re-saves `.import` files and `project.godot` on import (drops default values, reorders keys). That's harmless churn.
- To test a change without unrelated work in the tree, use a git worktree at HEAD, copy in only the changed files and run there. The worktree's `.godot` folder exceeds Windows path limits, so delete it with PowerShell `Remove-Item -LiteralPath "\\?\<path>" -Recurse -Force`, then `git worktree prune`.

## Full test suite

```
smoke_test touch_controls_test phone_menu_test vehicle_tires_test vehicle_rigs_test
vehicle_contact_test vehicle_persistence_test world_systems_test pedestrian_models_test
skeleton_test ragdoll_models_test
```
plus `tests/performance_profile.gd -- --quality=high` and `-- --quality=low`. All must pass with no `ERROR`/`SCRIPT ERROR` lines. Add `steering_hands_test` and `steering_drivers_test` once Phase 2 is done.

## Lessons that cost time (details in README "Decisions and gotchas")

- **Character arms:** the shared clips only look right on a model whose rest pose matches the clip rig's T-pose. Every character `.glb.import` needs `"retarget/rest_fixer/fix_silhouette/enable": true` and `"retarget/rest_fixer/fix_silhouette/threshold": 1.0` in its skeleton block (the default 15° threshold isn't enough). New characters must get both.
- **Ragdoll posing:** `SkeletonModifier3D` callbacks don't run on a skeleton whose AnimationMixer is off, so `realistic_ragdoll.gd` writes bone poses from its own `_physics_process`.
- **Jolt:** `project.godot` raises position/velocity steps to 24 and the Baumgarte factor to 0.4; without them the ragdoll joints drift past the 2 cm limit.
- **Blend points:** in Godot 4.7, `add_blend_point()` needs a name (4th argument) or it warns.
- **Player height:** `make_player.py` uses a fixed MakeHuman slider (0.43 → 1.81 m); measuring the Blender proxy gave a 2.56 m model.
- **`locomotion.gd`** must not use world transforms during setup: seated people are built before they enter the scene.
- The ragdoll test's 5 s settle limit is tight; ragdolls now get extra damping once nearly still, settling by ~4.2 s.

## Things only a human can check

Fullscreen/windowed FPS on this PC and FPS on a phone (tests measure CPU only); ragdoll falls in-game (the coach hides the final pose in renders); pedestrian arms and road crossings from several angles; how the reckless danfo drivers feel. Android export also needs JDK 17, the Android SDK/NDK and Godot export templates, none of which are installed.
