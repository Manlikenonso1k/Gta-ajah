# Task 1: ragdoll physics on the realistic characters

## The problem

When a car hits one of the 23 realistic pedestrians, the game swaps the model for the old stick figure, and the stick figure ragdolls. I never want to see the stick figure in play again. The realistic model itself must go limp and tumble, with its arms, hands, legs, knees, feet, neck and head all reacting.

The player is still the stick figure for now (Task 4 gives him a realistic model), so keep his current ragdoll working, but build the new system so the player can use it later.

## The approach

Start from the existing ragdoll in `scripts/ragdoll.gd`: its rigid bodies and joint limits already work with Jolt. Instead of drawing stick-figure meshes on those bodies, make the bodies invisible and use them to move the realistic character's skeleton, so the skinned mesh follows the physics.

You may evaluate Godot's built-in `PhysicalBone3D` / `PhysicalBoneSimulator3D` instead, but only use it if it's stable with Jolt in Godot 4.7.2: no jitter, joint limits respected, no exploding limbs. Write down in README which approach you chose and why.

## Steps

### 1. One standard skeleton for every character

- List the skeleton of every pedestrian model. They use three naming styles: MPFB/Mixamo (`mixamorig:LeftUpLeg`), Renderpeople (`upperleg_l`) and Unreal-style (`thigh_l`).
- Give them all the same bone names. Use Godot's import retargeting (a `BoneMap` with `SkeletonProfileHumanoid`, set in each `.glb.import` file) if it works cleanly with these models. If a model can't be retargeted cleanly, use a name-mapping table in code instead; `scripts/humanoid_walk.gd` already recognises all three styles.
- Later tasks depend on this (shared animation clips, seated drivers, the player model), so document the standard bone names in README.
- Add a test that checks every character has all the required bones.

### 2. Ragdoll bodies sized to each character

- Use 16 body parts: pelvis, lower spine, chest, head, both upper arms, forearms, hands, thighs, shins and feet.
- The neck bone takes part of the head's rotation, so the neck bends naturally instead of the head snapping.
- Size each part from that character's real bone lengths and approximate limb thickness, not fixed stick-figure sizes. Total mass should be about 55–95 kg, depending on height and build.
- Set joint limits like a real body: knees and elbows bend one way only, wrists and ankles have small ranges, the neck and spine twist only a little.
- Adjacent parts must not collide with each other.

### 3. Switching from walking to ragdoll

- On impact, create the bodies at the character's current animated pose so nothing jumps, and give them the character's current velocity.
- Then add the impact from the car, using its direction, speed and mass (vehicles range from 1,200 kg to 13,000 kg). A car bumper hits the legs first, so the upper body folds toward the bonnet. A bus or truck knocks the person flat and further.
- Cap the impulse so people are knocked down and thrown a believable distance, not launched across the city.
- The realistic mesh stays visible the whole time, and no stick-figure meshes are created. Keep the stick figure only as a fallback for when a model fails to load, and print a warning when that happens.
- Write the body transforms onto the skeleton every physics frame. In Godot 4.3 and newer, the supported way to override bone poses is a `SkeletonModifier3D`; check the 4.7 docs.
- Only the pelvis moves in position; every other bone only rotates, so the skin never stretches.

### 4. After the fall

- Pedestrians stay down. After about 20 s, remove them once they're off-screen. Keep the quality preset's ragdoll limit, removing the oldest first, as now.
- Ragdolls go to sleep once they settle, to save CPU.
- Leave a clear way for the player to use this later: after 4 s, blend from the ragdoll pose back to standing over about half a second. Task 2 adds a get-up animation that can replace the blend.

### 5. Testing and checking

- Add `tests/ragdoll_models_test.gd`. For every character, trigger a ragdoll, simulate 5 s, and check:
  - the realistic mesh is still visible and no stick figure was created
  - no body ends up below the ground or has NaN values
  - joints haven't stretched (each joint's two ends stay within 2 cm of their rest distance)
  - the ragdoll settles within 5 s
- Add `tests/view_ragdoll.gd`, which renders image sequences of a sedan, the danfo and the coach hitting three different characters (one MPFB, one Renderpeople, one other), about 10 frames each over 2 s. Look at every frame and fix limbs bending the wrong way, twisted hands or feet, the mesh tearing, or bodies sinking into the ground.
- Measure the frame rate with 8 ragdolls on the Low preset.

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