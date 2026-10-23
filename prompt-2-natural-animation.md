# Task 2: natural walking and running for the realistic characters

Task 1 (standard skeleton and realistic ragdoll) must be finished first. Check the README Progress log to confirm.

## The problem

The realistic pedestrians walk worse than the old stick figure did. `scripts/humanoid_walk.gd` only swings the thighs, knees, upper arms and forearms, so the hips, spine, shoulders, feet and head stay frozen and the walk looks robotic.

## The approach

Replace the procedural walk with real motion-capture animation clips, shared by every character through the standard skeleton from Task 1. Keep `humanoid_walk.gd` only as a fallback for any model whose skeleton can't use the clips.

## Steps

### 1. Get the animation clips

- Find humanoid animation clips licensed CC0 or CC BY. Check quaternius.com and other CC0 sources first. Mixamo is acceptable only if its current terms allow the clip files to be stored in a public GitHub repo; check, and write down what you found.
- Clips needed now:
  - 2–3 idles (standing still, shifting weight, looking around)
  - walks: normal, slow (for elders) and brisk
  - a jog and a run (for crossing roads)
  - waiting at the kerb, looking left and right
- Clips later tasks need, so get them now: sitting and driving with hands on the wheel, getting up from the ground, jump, fall and sprint.
- Retarget them all to the standard skeleton once and save one shared `AnimationLibrary`. Credit every source.

### 2. Movement animation on every pedestrian

- Give each pedestrian an `AnimationTree` that blends idle → walk → jog → run by movement speed.
- Match playback speed to actual ground speed so feet don't slide.
- Give each person a random starting point in the cycle and small differences in speed and stride, so crowds don't march in step.
- Turn smoothly toward the walking direction instead of snapping.
- Use the registry's tags: elders use the slow walk, younger people walk briskly.
- Add one clear function that movement code calls, for example `set_locomotion(speed, state)`, with states such as `idle`, `walk`, `run` and `wait_at_kerb`. Task 3 rewrites where pedestrians walk and will only call this function, so document it in README.
- After a ragdoll, the player should play the get-up animation instead of the blend from Task 1.

### 3. Performance

- Beyond about 40 m, update animations less often (for example every third frame). Beyond 120 m pedestrians are already hidden, so stop updating them.
- Compare the profile with 30 pedestrians before and after.

### 4. Testing and checking

- Extend `tests/pedestrian_models_test.gd`: every character plays idle, walk and run without errors, and its feet stay on the ground.
- Render side-view image sequences of three different characters walking and running, about 12 frames per cycle. Look at them: heels strike the ground, knees bend, hips and shoulders twist opposite to each other, arms swing opposite to the legs, and the head stays steady. Fix anything stiff or broken.
- Confirm the Task 1 ragdoll still takes over cleanly from these animations, with no jump in pose.

## Rules

- Read README.md first, especially the Progress log, then every script you'll change. README is the handoff note between sessions: update its Progress log after every step.
- Work in steps and commit after each one with a clear message.
- Godot 4.7.2, GDScript, Compatibility renderer, Jolt physics. Check the Godot 4.7 docs for any API you aren't sure of. Don't use Godot 3 or deprecated APIs.
- Don't change controls, touch controls, car handling values or the quality presets unless this task says to.
- Downloaded assets must be CC0 or CC BY, credited in the matching CREDITS file. No assets ripped from other games and nothing NonCommercial.
- Before every commit, run every test listed in README → Testing; all must pass. Add tests for what you build.
- Tests can't tell whether movement looks natural. Render image sequences of your work (the way `tests/view_driver.gd` renders images), look at every frame yourself, and fix what looks wrong before calling a step done.
- Run `tests/performance_profile.gd` before you start and at the end, and report both. The Low preset must still aim for 30 fps on a mid-range phone, so anything new needs distance shortcuts: update less often far away, stop beyond 120 m.
- When you finish, report what changed, the before and after profile numbers, anything you couldn't verify, and a short list of things for me to check by eye.