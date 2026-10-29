# Progress handoff

Last updated 2026-10-29. Read this first, then README.md (Progress log, "Interfaces between tasks", "Decisions and gotchas"), `docs/TEAM_TASKS.md` and `docs/QA_REPORT.md`.

## Current task: Task 5, street life (`prompt-lead.md`, which now holds the Task 5 spec)

Phases: 0 plan (`docs/PLAN_street_life.md`), 1 Mixamo clips on pedestrians and the player, 2 under-bridge and new places, 3 danfos, 4 crash drama, 5 final check. One phase per session: commit, add 3–4 lines to README's Progress log, stop. The next session starts with "continue with the next phase in docs/PLAN_street_life.md".

Task 5 log (newest last):
- 2026-10-29: started Phase 0. The owner's Mixamo clips are in `assets/animations/mixamo/` (49 `.fbx` plus 10 in `Male Locomotion Pack/`); the folder is git-ignored because the repo is public. Inspecting each clip (body included? length, root motion, loop) before writing the plan.
- Phase 0 done: `docs/PLAN_street_life.md` (clip table, places, budget, limits). All 59 clips are skinless, on the T-pose `mixamorig_` rig; walks/runs have root motion to strip; the 4 `Pose` files have no hip height. `.gitignore` also covers `assets/animations/mixamo_*.res/.tres`. Next: Phase 1, starting by getting the test suite green at the save point (smoke_test failed with `driving: false`).
- Phase 1 in progress (uncommitted). Written so far: `scripts/mixamo_library_build.gd` + `tools/build_mixamo_library.sh` (BoneMap imports, root-motion strip, pose hip height, output git-ignored `mixamo_library.res`); `assets/animations/animation_sets.json` + `scripts/animation_sets.gd` (clip per slot, seeded by ID, CC0 fallback); `locomotion.gd` (optional `mx/` library, `sit`/`lie` hold states, `summary()`); `pedestrian.gd` (uses the sets, warns on procedural fallback, `animation_summary()`); F4 inspector shows clips (`main.gd`); player uses the sets via new `gender`/`tags` in `player.json` (also written by `make_player.py`); `adult` age tag added where missing. Smoke test updated to check the realistic driver's wheel angle; `vehicle_persistence.gd` no longer prints an engine error on a damaged save. Library built (`tools/build_mixamo_library.sh`, 30 clips). Fixes found by rendering and testing: lying/sitting poses floated (hip height now computed from the pose's own rotations); ground speeds now from the mocap's recorded travel (foot method halved runs); `Female Walk` leans back and looks up, so the builder tips spine forward and head down; CC0 idles look wrong on Renderpeople women, so the male pack's neutral idle is now `Idle_Stand` for everyone; `mx/Sit` is a high perch (hips 0.8–1.0 m), dropped from sit sets. New `tests/animation_sets_test.gd` passes with and without the Mixamo library. Renders checked: PED_BA_F04, PED_BA_M07, PED_BA_SF01 (Carla) idle/walk/run/sit/lie, side and front. Full suite with Phase 1: 13/14 pass (including the save point's `steering_hands_test` and `steering_drivers_test`). `world_systems_test` fails deterministically: one crossing pedestrian stands still in the road (`57 too slow`, same every run); it passed at `29fc3c3`. Checking whether the save point (Phase 2 `car.gd`/`traffic.gd`) or Phase 1 causes it, using a worktree of HEAD in the scratchpad. Profile with Phase 1: High 6.891 ms avg / 9.609 max / 2.719 physics; Low 6.898 / 10.134 / 3.248 (no regression).
- Cause found: it passed at the save point, but `pedestrian_navigation.gd` seeds each walker's RNG from its instance ID, so new objects created at startup reshuffled who crosses when. That exposed a real gap: on a crossing, a runner directly behind a slower person was blocked (velocity 0, pushed along). Fixed by steering past on crossings (`_passing_side`, `CROSS_PASS`); world test 0 too slow, twice. Note: navigation picks "older" walkers by a 15% coin flip, not the registry's `elder` tag (worth fixing in Phase 4). README Progress log updated. Final full suite: 14/14 pass, 0 errors, 0 warnings; profile High 6.910 ms avg / 10.556 max, Low 6.904 / 9.348. Phase 1 committed; next session: Phase 2.
- Phase 2 (owner said keep going without stopping): `blender/make_buildings.py` makes 16 low-poly CC0 models + `assets/models/buildings/manifest.json` (collision boxes); `scripts/street_places.gd` builds the flyover over road 1 at row 3 with an under-bridge camp (mats, cardboard, fire with smoke, sitters on crates, pacers), the market on block (2,1) (GARDEN CITY MART supermarket with shoppers going in/out with bags, MALLAM SUYA SPOT kiosk with smoke, seller and customers, packed stalls) and HOPE MEDICAL POINT on block (3,1) (green +, bench sitters). `city.gd` reserves those lots (RNG draws kept so the rest of the city is unchanged); `pedestrian.gd` gains `anchor_state`, `clip_overrides`, `loop_path`, `set_carrying`, `from_entry`. Fixes from renders: colours were washed out (sRGB→linear in Blender), smoke too faint, Mixamo 'drug abuse Pose' is standing bent over (replaced by crate seats). `tests/street_places_test.gd` passes; `tests/view_places.gd` renders 7 views.

## Before Task 5 (Tasks 1–4)

## Where things stand

| Work | State |
|---|---|
| Install (Godot, Blender, MPFB + MakeHuman packs) | Done |
| Task 1: realistic ragdoll | Done, committed |
| Task 2: mocap animation | Done, committed |
| Task 3: traffic and pavements | Done, committed |
| Task 4 steps 1–2: steering-wheel/seat data, player model | Done, committed |
| Arm fix (forearms raised on every model except Nathan) | Done, committed (`29fc3c3`) |
| **Task 4 steps 3–5 (Phase 2)** | **In progress, not verified. Committed as-is in the save point tagged `save-point-for-codex`** |

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

Spec: `prompt-4-player-and-drivers.md`, steps 3–5. A previous agent was building it and stopped mid-work. Its unfinished changes are committed in the save point (tag `save-point-for-codex`) so nothing is lost; treat them as work in progress, not as passing code:

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

Then run the whole suite, commit the fixes with `git add <files>` (never `git add -A`), update README's Progress log and `docs/TEAM_TASKS.md` (V3–V5).

## Decide before committing

- **`assets/animations/mixamo/`** (7 `.fbx` clips on the owner's disk, nothing references them) is git-ignored: Mixamo's terms don't allow the clip files in a public repo, and Task 2 rejected Mixamo for that reason. Don't commit or depend on them.
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
- Phase 2 full suite 15/15 pass. Physics-time readings drift a lot on this PC; A/B on Low: places add ~0.9 ms (5.3 vs 4.4 ms, 20 vs 12 people). Committed Phase 2. Next: Phase 3 (danfos); `tests/view_danfo.gd` written to render the van.
