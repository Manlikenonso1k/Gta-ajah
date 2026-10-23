# Task 4: realistic player, people inside moving cars, hands and steering wheel that turn

Tasks 1, 2 and 3 must be finished first (standard skeleton and ragdoll, shared animations, road traffic). Check the README Progress log to confirm.

## The problems

- The player is still the stick figure.
- Moving AI cars have nobody inside them.
- When driving, I want to see the hands and the steering wheel turn left and right, like in GTA San Andreas.

## Steps

### 1. Player model

- Generate a realistic player character with MPFB 2 (`blender/make_pedestrians.py` shows how), matching this description:
  **[DESCRIBE YOUR MAIN CHARACTER: age, height, build, skin tone, hair, clothes]**
- Make it easy to swap for another model later (one setting or registry entry).
- Use the standard skeleton, the shared animations (idle, walk, run, sprint, jump, fall, get up) and the realistic ragdoll for the R key and car hits. After a ragdoll, play the get-up animation.
- Don't change `player.gd` controls, speeds or collision capsule; change only the visuals and animation.

### 2. Steering wheel

- For each of the 10 vehicle models, measure the steering wheel's position, size and tilt, plus the driver's seat position, using `tests/view_vehicle.gd`. Store them per model in `assets/models/cars/vehicles.json`.
- If a model's steering wheel is part of the body mesh, cut its triangles out into a separate mesh so it can rotate, the same way `vehicle_model.gd` separates the road wheels. Only if that fails, add a simple low-poly wheel in its place.
- Rotate the steering wheel with the same steering value the car uses: up to about 180–270° each way for cars, more for the buses and coach.

### 3. Hands on the wheel

- Seat the driver with the sitting/driving animation, positioned from the measured seat.
- Keep the hands on the wheel rim (around 10 and 2 o'clock) and have them follow it as it turns, using the inverse kinematics nodes Godot 4.7 provides (check the docs for the current ones). If IK isn't reliable, blend three poses (full left, centre, full right) by the steering value.
- The head turns slightly into corners. Bus and coach drivers sit more upright with a bigger, flatter wheel.
- This replaces the procedural driver currently used for the player.
- Entering and exiting: keep the current collision-aware walk to the door. The realistic character walks up, sits down and gets out with animations instead of the timed slide. Keep the Sprinter's door animation.

### 4. People in moving cars

- Every moving AI car gets a driver picked from the pedestrian registry (same 90/10 mix), using the same seated pose, steering wheel and hand system.
- Danfos and buses get a few seated passengers. Parked cars stay empty.
- Performance: hand IK and steering-wheel rotation only within about 40 m; beyond that, a fixed seated pose; beyond 120 m, hide the people.

### 5. Testing and checking

- Tests:
  - every moving AI car has a visible driver
  - in all 10 models, the hands stay within 3 cm of the wheel rim while steering from full left to full right
  - the steering wheel rotates with steering input
  - the player's ragdoll uses the realistic model, with no stick figure
- Render images with `tests/view_driver.gd` for at least four models (a sedan, the danfo, the Sprinter and the coach) at full left, centre and full right steering, from outside and from the usual driving camera angle. Look at them and fix hands floating off the wheel, arms going through the body or seat, or the driver sitting in the wrong place.
- Compare the profile before and after, with all traffic drivers visible.

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