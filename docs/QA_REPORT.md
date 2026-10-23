# QA report

Maintained by teammate `qa`. QA only tests and reports; it doesn't edit game code. Newest review first under "Reviews".

## How QA runs a review

1. Every test listed in README → Testing, run one at a time through `tools/locked.sh godot --headless --path . --script tests/<name>.gd`, plus any new tests the builders add (`skeleton_test`, `ragdoll_models_test`, ...).
2. `tests/performance_profile.gd` twice each with `-- --quality=high` and `-- --quality=low` (headless, CPU only).
3. `tests/qa_fps.gd`: windowed 1280x720, vsync off, 180 warm-up and 300 measured frames from the default spawn view (GPU and CPU). `-- --quality=high|low [--shot=/abs/path.png]`.
4. Every image the builder points to is opened and checked.
5. Licence and credits for every new asset: CC0 or CC BY only, credited in the matching CREDITS file, nothing NonCommercial and nothing ripped from games.

## Baseline (Q1), 2026-10-23 04:50 WAT

**Traceability:** HEAD `285d540` (Replace stick-figure pedestrians with 23 realistic rigged characters). `git status --short` at the start: `M .gitignore`, `M README.md`, untracked `docs/TEAM_TASKS.md`, `prompt-*.md`, `prompt-lead.md`, `tools/`. No game code (`scripts/`, `assets/`, `tests/`) was modified when the baseline ran.

### Test suite: 9/9 pass, no `ERROR`, `SCRIPT ERROR` or `WARNING` lines in any log

| Test | Result | Key output |
|---|---|---|
| smoke_test | PASS (37 s) | `cars: 13  car y: 0.6` (pre-settle height, known), `ragdoll pelvis y after 1.5s: 0.12  ragdolls: 1`, `player back up: true`, `driving: true`, `driver steering pose: true`, `car speed km/h: 63  upright: true  driven wheel contacts: 1.0`, `pedestrian ragdolled: true  ped freed: true`, `safe exit after braking: true  vehicle speed: 0.01`, `repeated stationary exit launch check: true` |
| touch_controls_test | PASS | joystick press/release of `move_forward`, jump button pressed and released |
| phone_menu_test | PASS | `pause, cancel, and resume passed` |
| vehicle_tires_test | PASS | `Vehicle tire audit passed for all 10 models in both asset sets.` |
| vehicle_rigs_test | PASS | `independent driver's door and automatic van up/down shifts` |
| vehicle_contact_test | PASS | `4 wheels grounded; passenger mass 75 kg added/restored smoothly; grip 0.28 airborne and contact recovered` |
| vehicle_persistence_test | PASS | `versioned save/load, restart restoration, and invalid transform fallback passed` |
| world_systems_test | PASS | `distant traffic advances on low-cost ticks; far blocks and parked cars deactivate; ground collision remains` |
| pedestrian_models_test | PASS | all 23 `ok`, head 1.33–1.86 m, feet -0.01..0.03 m; split 88.2% Black African (target 90%); `PEDESTRIAN MODELS: PASS` |

### Headless CPU profile (`performance_profile.gd`, 240 frames after 120 warm-up)

| Preset | Run | avg frame ms | max frame ms | physics ms | nodes | cars | pedestrians |
|---|---|---:|---:|---:|---:|---:|---:|
| High | 1 | 6.897 | 10.808 | 2.839 | 2,666 | 17 | 30 |
| High | 2 | 6.897 | 15.909 | 3.789 | 2,666 | 17 | 30 |
| Low | 1 | 6.905 | 9.984 | 2.186 | 1,969 | 7 | 12 |
| Low | 2 | 6.900 | 9.804 | 1.488 | 1,969 | 7 | 12 |

Headless CPU only, no GPU. The average sits at about 6.9 ms (~145 fps) on both presets, which looks like a frame-pacing floor in headless mode rather than real work, so it won't show changes below that. Compare **max frame ms** and **physics ms** instead. Physics ms is a single-frame monitor reading and varies by ±1 ms between runs. `cars` counts parked plus traffic cars (High 13+4, Low 6+1).

### Windowed FPS (`tests/qa_fps.gd`, 1280x720, vsync off, default spawn view)

| Preset | avg ms | fps | p95 ms | p99 ms | max ms | draw calls | primitives | nodes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| High | 39.64 | **25.2** | 47.99 | 64.26 | 137.94 | 1,979 | 1,124,267 | 2,666 |
| Low | 17.40 | **57.5** | 21.35 | 31.29 | 33.15 | 411 | 243,672 | 1,969 |

2013 Intel Iris, macOS 12, Compatibility renderer. High is GPU-bound (about 1.1 M primitives, about 2,000 draw calls). The spawn view has few pedestrians in frame, so builders should treat these as the "before" numbers for the same view. Screenshots look correct (flat ambient light is the known GPU limitation): `/private/tmp/claude-501/-Users-mac-Documents-gta-portharcourt/d31efed6-f247-437e-8b08-5a1cbd325dca/scratchpad/base/fps_high.png`, `.../fps_low.png`.

### Observations at baseline (not failures)

- In the spawn view, the parked white sedan sits on the asphalt about one lane-width from the kerb, inside the right-hand lane. This is relevant to Task 3 step 1 (parked cars must not block driving lanes). Recheck when T1 is reported.
- The player is still the stick figure, as expected until Task 4.

## Reviews

_None yet._

## Open bugs

_None._
