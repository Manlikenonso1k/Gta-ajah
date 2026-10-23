# Team lead: run Tasks 1–4 as an agent team

You are the team lead. Your teammates build; you plan, coordinate, commit and keep README current. Don't implement features yourself. Wait for teammates to finish their tasks.

The four task specs are in root:

- `prompt-1-realistic-ragdoll.md`
- `prompt-2-natural-animation.md`
- `prompt-3-traffic-and-pavements.md`
- `prompt-4-player-and-drivers.md`

Before spawning anyone, read README.md (especially the Progress log), all four specs, and the scripts they mention.

## Teammates

Spawn five teammates with these exact names:

| Name | Job |
|---|---|
| `ragdoll` | Task 1: standard skeleton first, then the realistic ragdoll |
| `animator` | Task 2: animation clips and natural movement |
| `traffic` | Task 3: road traffic, pavements and crossings |
| `vehicles` | Task 4 steps 1–2 now (player model, steering wheels and seat measurements); steps 3–5 in Phase 2 |
| `qa` | Tests and checks everyone's work. Never edits game code |

Give each builder a spawn prompt that says: read README.md and your task spec in `prompts/`, follow its Rules section with the changes listed under "Rules for every teammate" below, and only edit the files you own.

## Phases

### Phase 1: everyone starts now

- **ragdoll:** Task 1 step 1 (one standard skeleton) first. It should be small, and other work depends on it. As soon as it's done, message everyone the standard bone names, then continue with the rest of Task 1.
- **animator:** Task 2 step 1 research right away: find, licence-check and download the clips. Retargeting waits until `ragdoll` sends the bone names (make it a dependent task). Then continue with Task 2.
- **traffic:** all of Task 3. It doesn't depend on the skeleton.
- **vehicles:** Task 4 step 1 (generate the player model with MPFB; don't wire it into `player.gd` yet) and step 2 (seat and steering-wheel measurements, cutting the steering wheels into separate meshes).
- **qa:** before anyone changes code, run the full test suite and the performance profile on High and Low, and record the baseline in `docs/QA_REPORT.md`. Then review each task as it's reported done.

### Phase 2: after `ragdoll`, `animator` and `vehicles` are approved by `qa`

- **vehicles:** Task 4 steps 3–5: hands on the wheel, the realistic player wired into `player.gd` with the new ragdoll and animations, and drivers and passengers in moving traffic cars. If `traffic` is still working, agree with it how traffic cars are spawned before adding drivers.
- Transfer ownership of files from teammates who have finished to whoever needs them, and record the change in README.

## Interfaces teammates must agree early

Teammates message each other to settle these in their first few minutes, even before they're built. Record each agreed interface in a README section called "Interfaces between tasks".

- **ragdoll → everyone:** the standard bone names, and the function that starts a ragdoll (for example `start_ragdoll(impact_velocity, impact_point, vehicle_mass)`).
- **animator → traffic:** the locomotion function (for example `set_locomotion(speed, state)`) and its states, so `traffic` can call it before it exists.
- **vehicles → Phase 2:** the format of seat and steering-wheel data in `assets/models/cars/vehicles.json`.
- **traffic → Phase 2:** how traffic cars are spawned and driven, so drivers can be added.

## File ownership

Teammates share one working folder, and two teammates editing the same file overwrite each other. Start from this table, adjust it after reading the code, and write the final version in README before spawning anyone.

| Owner | Files |
|---|---|
| `ragdoll` | `scripts/ragdoll.gd`, new skeleton/ragdoll scripts, the characters' `.glb.import` files, `tests/ragdoll_models_test.gd`, `tests/view_ragdoll.gd` |
| `animator` | `scripts/pedestrian.gd`, `scripts/humanoid_walk.gd`, `scripts/pedestrian_registry.gd`, new animation scripts, `assets/animations/`, `tests/pedestrian_models_test.gd` |
| `traffic` | `scripts/city.gd`, `scripts/traffic.gd`, `scripts/car.gd`, new road, pavement and pedestrian-navigation scripts, `tests/world_systems_test.gd` |
| `vehicles` | `scripts/vehicle_model.gd`, `assets/models/cars/vehicles.json`, the player's Blender script and `assets/characters/player/`, `tests/view_vehicle.gd`, `tests/view_driver.gd` |
| `qa` | new `tests/qa_*.gd` files and `docs/QA_REPORT.md` only |
| lead | `scripts/main.gd`, `scripts/player.gd`, `README.md`, `.gitignore`, `project.godot`, and any file not listed |

Examples of cross-file work: `ragdoll` needs the car-hit code in `car.gd` to call its ragdoll function, so it messages `traffic` with the exact change. `traffic` puts pedestrian navigation in a new script and asks `animator` to call it from `pedestrian.gd`.

## Rules for every teammate

Add these to every spawn prompt. They replace the matching parts of each task spec's Rules section.

- **Don't commit.** The lead commits. **Don't edit README.** Send your Progress-log update to the lead instead.
- **Only edit files you own.** To change another file, message its owner with exactly what you need.
- **Never run `git checkout`, `git reset`, `git stash`, `git clean` or `git rebase`, and never delete files you didn't create.** Other teammates' unfinished work is in the same folder.
- **Run Godot and Blender only through `tools/locked.sh`**, for example `tools/locked.sh godot --headless --path . --script tests/x.gd`. They share Godot's import cache, and this computer can't run several at once. Keep each run short: run only your own tests while iterating and leave the full suite to `qa`.
- **When you finish a task,** mark it done and message `qa` with what changed, which files, which tests to run and which images to look at.

## QA's job

- Whenever a teammate reports a task done, run the **whole** test suite (not only theirs), the performance profile on High and Low, and look at the rendered images. Check the licence and credits of any newly downloaded asset.
- **Pass:** message the lead `approved: <task>` with the test results and profile numbers.
- **Fail:** message the owner with the failing test, or what looks wrong and in which image, and create a fix task for them.
- Keep `docs/QA_REPORT.md` current: what was tested, results, open bugs.

## Your loop as lead

1. **Set up:** create `tools/locked.sh` (below) and make it executable, add `.tool_lock` to `.gitignore`, write the ownership table and the empty "Interfaces between tasks" section in README, create the shared task list with dependencies, then spawn the teammates.
2. **While they work:** answer questions, settle interface disagreements, and stop anyone editing files they don't own.
3. **When `qa` approves a task:** commit only that task's files (`git add` the specific files, never `git add -A`) with a clear message, and update the README Progress log from the teammate's report.
4. **Start Phase 2** once `ragdoll`, `animator` and `vehicles` are approved.
5. **Stop and ask me** when a decision is mine to make (how something should look or feel), when something would delete or overwrite my work, when two teammates can't agree, or when the same QA failure happens three times.
6. **At the end:** a final full QA pass with everything together, then report what's done, what isn't, before and after performance, and the checklist of things I need to check by eye and on my phone.

## `tools/locked.sh`

```sh
#!/bin/sh
# Runs one Godot or Blender command at a time across all agents.
# Usage: tools/locked.sh godot --headless --path . --script tests/smoke_test.gd
# If a crash leaves a stale .tool_lock folder behind, delete it.
until mkdir .tool_lock 2>/dev/null; do sleep 3; done
trap 'rmdir .tool_lock' EXIT INT TERM
"$@"
```