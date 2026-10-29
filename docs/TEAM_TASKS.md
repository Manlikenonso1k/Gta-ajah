# Team task list

Maintained by the lead. Teammates report status changes to the lead (and finished work to `qa`); the lead updates this file. "Needs" lists the tasks that must be done first.

| ID | Owner | Task | Needs | Status |
|---|---|---|---|---|
| R1 | ragdoll | Standard skeleton: same bone names on every character; documented; `tests/skeleton_test.gd` | — | ✅ |
| R2 | ragdoll | Message everyone the standard bone names and the ragdoll start function signature | R1 | ✅ |
| R3 | ragdoll | 16-part ragdoll sized per character, joint limits, no self-collision | R1 | ✅ |
| R4 | ragdoll | Walk → ragdoll switch at current pose; car impact by direction/speed/mass; SkeletonModifier3D; no stick figure | R3 | ✅ pose written from the ragdoll's physics step (modifier callback doesn't run without a mixer) |
| R5 | ragdoll | After the fall: stay down, sleep, remove after 20 s off-screen; player blend-back hook | R4 | ✅ |
| R6 | ragdoll | `tests/ragdoll_models_test.gd`, `tests/view_ragdoll.gd`, 8-ragdoll FPS on Low | R4 | ✅ 0 failures with the Jolt solver settings; 9 render sequences inspected; 8 ragdolls ≈ 3.3 ms physics |
| A1 | animator | Find, licence-check (CC0/CC BY; Mixamo terms checked) and download clips incl. sit/drive, get up, jump, fall, sprint | — | ✅ Quaternius UAL 1&2 (CC0); Mixamo rejected (no redistribution) |
| A2 | animator | Retarget clips to the standard skeleton; one shared `AnimationLibrary` in `assets/animations/`; credits | A1, R2 | ✅ `assets/animations/pedestrian_library.res` (22 clips) |
| A3 | animator | `AnimationTree` locomotion on every pedestrian, `set_locomotion(speed, state, facing)`, tags, desync, foot-speed matching | A2 | ✅ states idle/walk/jog/run/wait_at_kerb |
| A4 | animator | Distance LOD for animation; get-up animation hook for the player | A3 | ✅ LOD >40 m every 3rd frame; `Locomotion.play_action("GetUp")` for Phase 2 |
| A5 | animator | Tests and side-view image sequences | A3 | ✅ pedestrian_models_test PASS; 3 render sheets inspected |

**Task 2 done and approved.** The arm-clipping found by the owner was fixed in `locomotion.gd` (per-character upper-arm clearance). Pavement navigation is now on in the game (`USE_PAVEMENT_NAVIGATION = true`).
| T1 | traffic | Road/pavement layout check; parked cars off lanes; road graph; pavement graph; F6 debug view | — | ✅ |
| T2 | traffic | AI driving on the right: lanes, junction give-way, gaps, 90/10 driver types, stuck recovery | T1 | ✅ 10% reckless; 99.6% within 1 m of lane |
| T3 | traffic | Pedestrian navigation on pavements and crossings (calls animator's `set_locomotion`) | T1 (A3 interface) | ✅ 100% pavement; crossings at run speed; `_toward_pavement` containment |
| T4 | traffic | 60 s world test, F6 top-down image, profile High/Low | T2, T3 | ✅ world_systems_test PASS (fixed latent crash); F6 images inspected; CPU unchanged |

**Task 3 done and approved.** README interfaces updated (3-arg `set_locomotion`; how traffic cars are spawned and driven). Open, optional: move the starter car in `main.gd` from road_line(3)+3 to +4.8 so it sits fully out of the east lane.
| V1 | vehicles | Seat and steering-wheel measurements for all 10 models in `vehicles.json`; steering wheels cut out as separate meshes | — | ✅ verified (no new changes; already committed). `cabin` block + `build()` `driver_seat`/`steering_wheel` dict documented in README interfaces |
| V2 | vehicles | Player model with MPFB ("Young PH hustler": Black African man, ~25, ~1.80 m, athletic, dark skin, short black fade, casual shirt, jeans, trainers), not wired into `player.gd` yet | — | ✅ `assets/characters/player/` (player.glb 1.6 MB, CC0); verified 1.81 m in-engine. Fixed a height bug (secant search measured Blender proxy → 2.56 m giant; now fixed slider) |
| V3 | vehicles | Phase 2: hands on the wheel, seated driving pose, steering-wheel rotation | R2, A2, V1, QA approval of R/A/V | ⬜ |
| V4 | vehicles | Phase 2: realistic player in `player.gd` with ragdoll and animations | V2, R5, A4 | ⬜ |
| V5 | vehicles | Phase 2: drivers and passengers in moving traffic; tests and renders | V3, T2 | ⬜ |
| Q1 | qa | Baseline: full test suite, profile High and Low, `docs/QA_REPORT.md` | — | ✅ |
| Q2 | qa | Review each task when reported done; approve or file fixes | each task | ✅ Phase 1 combined pass by the lead, see `docs/QA_REPORT.md` |
| Q3 | qa | Final full pass with everything together | all | ⬜ |
