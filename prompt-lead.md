# Task 5: street life, crash drama, danfos and new places

Plan first, then build it phase by phase.

## What I want

The game should feel like a real Nigerian street: busy, packed together and dramatic. I've downloaded Mixamo animations into `assets/animations/mixamo/` (for example `Angry.fbx` and `Block.fbx`; list the folder for the full set). They include lying, sitting and walking clips, with male and female versions, plus reactions. Use them on the player and the pedestrians wherever they fit. You choose which clip goes where.

1. **People move like people:** real clips for idle, walk, run, sit and lie down instead of the procedural walk, matched to each character (female clips on women, elder clips on older people).
2. **The under-bridge:** a flyover with space beneath it where homeless people live. Some sleep lying on mats or cardboard, some sit against the pillars, a few walk around. Add belongings: bags, buckets, a small fire or lamp.
3. **Crash drama:** when a car crashes into another car or a building, or hits a person, nearby people react the way they would in Nigeria. They shout, put their hands on their heads, point, run to the scene and crowd around it. If someone is killed, people gather around the body, some kneel or cry, and some angrily walk up to the car, shout at the driver and block it. The crowd breaks up after a while.
4. **Danfos:**
   - The sliding door slides open, then stays open while driving, as in Nigeria.
   - A conductor always hangs in the doorway, holding the roof with one hand and leaning out.
   - Seats are packed tight: the driver plus 2 passengers in front, then 3 rows of 4 behind.
5. **New places:**
   - A **suya kiosk**: grill, smoke, a seller turning the meat, and customers waiting or eating standing up.
   - A **supermarket**: people going in and out, some carrying bags.
   - A **medical point**: a proper clinic building, with people waiting outside on a bench.
   - Around these, other buildings, stalls and kiosks can be packed close together and partly hidden behind each other, like a congested street. Not everything needs an interior or to be fully visible.

## How to work

- **Read first:** the Progress log in README.md, then the scripts each phase touches. Tasks 1–4 (realistic ragdoll, animations, traffic, player model and drivers) may be partly done. Check the log and reuse whatever exists; don't redo it.
- **Phase 0, plan:** write `docs/PLAN_street_life.md`, keeping it short. It should contain:
  - a table of every clip in the mixamo folder: file, what it shows, male/female/any, looping or one-shot, and where you'll use it (or "skip" and why)
  - where each new place goes in the city
  - the performance budget per phase
  - anything you can't do, and why

  Then go straight into Phase 1. Only stop to ask me about decisions that are mine (how something should look).
- **One phase per session:** after each phase, commit, add 3–4 lines to the Progress log saying what's done and what's next, then stop. I'll start a fresh session with "continue with the next phase in docs/PLAN_street_life.md".

## Phases

### Phase 1: animation clips on pedestrians and the player

- **Import:**
  - If the clips aren't imported yet, write one script that imports every FBX in `assets/animations/mixamo/` as an Animation Library.
  - Retarget them with a BoneMap on `SkeletonProfileHumanoid`. The MPFB characters already use `mixamorig:` bone names; the Renderpeople and other downloaded models need their own bone maps.
  - Set looping clips to loop.
  - Check each file: some may include a character body ("with skin"), and walks may move forward instead of staying in place. Strip the root motion from locomotion clips so the game moves the character, not the clip.
- **Who gets what:**
  - Write `assets/animations/animation_sets.json`, which says which clips each kind of character may use, based on the gender and age tags in `pedestrian_registry.gd`. Add any missing tags.
  - Each pedestrian picks its clips once, seeded by its stable ID.
  - Show the chosen clips in the F4 inspector.
- **Playback:**
  - Give each pedestrian an AnimationTree that blends idle → walk → run by speed, with playback speed matched to ground speed so feet don't slide.
  - Start each one at a random point in the cycle.
  - Add `set_locomotion(speed, state)` as the one function movement code calls.
  - Keep `humanoid_walk.gd` as the fallback, and print a warning when a model can't use the clips.
- **Player:**
  - If the player is still the stick figure, give him one of the existing MPFB characters for now. Set this in one place so I can swap the model later.
  - Use the same clips on him. Keep `player.gd` controls, speeds and collision capsule exactly as they are.

### Phase 2: the under-bridge and the new places

- **How to build them:**
  - Model them as low-poly Blender scripts in `blender/`, exported to `assets/models/buildings/`, and list each one in an asset manifest.
  - Place them in `city.gd`. The bridge is a flyover over one of the roads; traffic must still drive under it.
- **Under-bridge:**
  - Homeless people use fixed lying and sitting clips. They're cheap, with no navigation.
  - A few walk short loops around the pillars.
- **Suya kiosk:** smoke from `CPUParticles3D` (safe on the Compatibility renderer), a seller with a working loop, and 2–4 customers standing around.
- **Supermarket:**
  - Use a made-up name and sign; no real brands.
  - Pedestrians sometimes walk in through the door, and others walk out carrying a bag.
- **Medical point:**
  - Use a green cross or a "+" sign, not a red cross. The red cross emblem is legally protected.
  - People sit waiting on a bench outside.
- **Congestion:** pack stalls, umbrellas, kiosks and buildings close together around the market and clinic area. Pedestrians must still be able to walk through.

### Phase 3: danfos

The danfo is `vw_t3`. Do it first; if that works, do the same for the `hiace`, which also has a sliding door.

- **Sliding door:**
  - The sliding door is on the right-hand side, the kerb side when driving on the right. Cut its triangles out of the body mesh, the same way `vehicle_model.gd` separates the wheels.
  - Animate it sliding back along the body. It's open by default and stays open while driving.
  - If the door can't be cut out cleanly, show me images and ask before building a replacement panel.
- **Seats:**
  - Add simple bench seats: driver plus 2 front passengers, then 3 rows of 4.
  - Store the seat positions per model in `assets/models/cars/vehicles.json`.
  - Seats are meant to be tight; shoulders can touch, but no limbs through bodies or through the van walls. Keep the doorway clear for the conductor.
- **Passengers:**
  - Moving traffic danfos are 60–100% full, using sitting clips that match each person.
  - Parked danfos keep their door open and have no passengers.
- **Conductor:**
  - He hangs in the doorway on moving danfos, one foot on the step and one hand on the roof, leaning out and swaying with braking and turns.
  - When the danfo stops, he steps down beside the door, then climbs back on before it moves off.
- **Player takes a danfo:** if anyone is in it, they climb out, and the driver and conductor shout at the player (use `Angry`) before walking away.

### Phase 4: crash drama

- **Detecting crashes:**
  - Add one crash event that fires when any car (player or traffic) hits another car, a building or a person above a speed threshold.
  - Pass in where it happened, how bad it was, and whether someone died.
- **Reactions:**
  - **Within about 8 m:** people flinch and back away, and put their hands on their heads.
  - **8–30 m:** some run to the scene and stand in a loose crowd around it. Others just look and point.
  - **A death:** people gather close around the body; some kneel or cry. A few angry people walk to the car, shout at the driver and stand in front of it (use `Angry` and `Block`). If the driver drives off, they shout after the car, and one or two chase it a short way.
  - **Traffic:** traffic near a crowd slows and stops.
- **Ending:** after 30–60 s, the crowd slowly drifts back to normal walking.
- **Limits:**
  - Cap how many people react at once: 12 on High, 6 on Low.
  - People beyond 30 m don't react.

### Phase 5: final check

- Run the full test suite and the performance profile on High and Low.
- List the images I should look at.

## Rules

- **Proof before "done":**
  - Don't tell me something works unless you render images and show them to me.
  - Render with the windowed tools, like `tests/view_driver.gd`; headless runs can't capture images. If you can't render, say so plainly.
  - Each phase needs image sequences of what it added:
    - Phase 1: walks, sits and lies on three different characters.
    - Phase 2: each place.
    - Phase 3: the door opening and the full danfo from outside and inside.
    - Phase 4: a crash scene.
  - Look at every frame and fix limbs through bodies, sliding feet, people floating or sinking, and wrong-way joints.
- **Tests:** before every commit, run every test listed in README → Testing; all must pass. Add tests for what you build. For example:
  - every clip loads
  - female-only clips are never given to men
  - a traffic danfo seats at most 15 plus the conductor
  - a crash event makes nearby people react, and the crowd clears afterwards
- **Performance:** run `tests/performance_profile.gd` before Phase 1 and after each phase, and report the numbers. The Low preset must still aim for 30 fps on a mid-range phone, so:
  - passengers, the conductor and crowd animations update fully only within about 40 m
  - use fixed poses further out, and hide people beyond 120 m
  - homeless people and kiosk customers use cheap looping clips with no navigation
- **Licence:**
  - Mixamo files can't be shared publicly, and my repo is public. Add `assets/animations/mixamo/` and any saved copies of the clips (`.res`/`.tres`) to `.gitignore`, and tell me about anything else that would put Mixamo data in the repo.
  - Downloaded models must be CC0 or CC BY, with credits. No real brand names or logos.
- **Engine:** Godot 4.7.2, GDScript, Compatibility renderer, Jolt physics. Check the Godot 4.7 docs when unsure; no Godot 3 or deprecated APIs.
- **Don't change:** controls, touch controls, car handling values or the quality presets, unless this task says to.
- **Keep it lean:** keep changes small and readable, and don't re-read files you've already read this session.
- **Stop and ask me:**
  - when a decision is about how something should look
  - when something would delete or overwrite my work
  - when the same problem fails three times