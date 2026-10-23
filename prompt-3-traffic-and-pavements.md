# Task 3: traffic that follows the roads, pedestrians on the pavement

This task touches city, traffic and pedestrian movement code only. Don't change animation or ragdoll code (Tasks 1 and 2 own those).

## The problems

- AI cars don't follow the roads properly.
- Pedestrians wander inside a leash instead of walking along the pavements.
- It should feel like Nigeria: people walk on the pavement beside the road and run when they cross.

## What I want

- **Traffic drives on the right**, as in Nigeria.
- **90% of AI drivers drive normally:** they stay in their lane, keep a safe distance, and slow down for turns and people.
- **10% are reckless, danfo-style drivers:** faster, closer behind other cars, overtaking when the other lane is clear, braking late. They still stay on the road and never drive through buildings.
- **Pedestrians** walk along the pavements, wait at the kerb, look both ways, and run across the road.

## Steps

### 1. Road and pavement layout

- Read `scripts/city.gd` and measure the roads. Check there's room for two lanes plus a pavement on each side. If not, change the city layout as little as possible.
- Check the parked cars: they must not block driving lanes. If they do, move them against the kerb or into parking spots.
- Build a road graph from the city grid: junctions as nodes, one lane in each direction per road, lane centre lines, and turning connections at each junction.
- Build a pavement graph along both sides of every road, with crossing points at junctions and a few in the middle of blocks.
- Add a debug view, toggled with F6, that draws lanes, pavements, crossing points and each AI car's planned path, with reckless drivers in a different colour.

### 2. AI driving

- Steer to follow the lane centre line, looking a short distance ahead, using the existing vehicle physics for nearby cars. Keep the existing lightweight update for distant traffic, but move it along the road graph.
- Pick a random turn at each junction. Use a simple give-way rule so cars don't crash into each other at junctions. (No traffic lights yet.)
- Keep a gap to the car in front, and slow down or stop for pedestrians crossing ahead.
- Set the driver type when a car spawns: 90% normal, 10% reckless. Reckless drivers have their own speed, gap and braking settings, overtake when the other lane is clear, and slow down less for people.
- If a car gets stuck, it backs up and tries again. If it's off-screen, it may reset to the nearest lane.

### 3. Pedestrian movement

- Pedestrians walk along the pavement graph to random destinations. They stay on the pavement except when crossing, pass each other without walking through each other, and sometimes stop for a while, for example at a shop front or a corner.
- Crossing:
  - walk to a crossing point, wait at the kerb, and look both ways
  - check for a gap in traffic using the AI cars' positions and speeds, then run across
  - some start walking and break into a run when a car approaches
  - older people hurry but don't sprint
  - if a car gets close while they're halfway across, they run faster
- Keep the existing reactions: people step away from traffic, and run away if the player drives onto the pavement.
- Set speed and state through the function documented in README by Task 2 (`set_locomotion` or whatever it was named). If Task 2 isn't done yet, set the movement speed directly and leave a clear note in README for Task 2 to connect.

### 4. Testing and checking

- Extend `tests/world_systems_test.gd` with a 60-second simulated run that checks:
  - the 90/10 split of driver types
  - normal drivers stay within 1 m of their lane centre at least 95% of the time
  - no AI car, reckless or not, drives into a building or onto the pavement
  - no collisions between AI cars
  - pedestrians stay on the pavement except while crossing, and crossing pedestrians move at running speed
- Render a top-down image with the F6 debug view on and look at it.
- Compare the profile before and after, on both High and Low.

## Rules

- Read README.md first, especially the Progress log, then every script you'll change. README is the handoff note between sessions: update its Progress log after every step.
- Work in steps and commit after each one with a clear message.
- Godot 4.7.2, GDScript, Compatibility renderer, Jolt physics. Check the Godot 4.7 docs for any API you aren't sure of. Don't use Godot 3 or deprecated APIs.
- Don't change controls, touch controls, car handling values or the quality presets unless this task says to.
- Downloaded assets must be CC0 or CC BY, credited in the matching CREDITS file. No assets ripped from other games and nothing NonCommercial.
- Before every commit, run every test listed in README → Testing; all must pass. Add tests for what you build.
- Tests can't tell whether movement looks natural. Render images of your work (the way `tests/view_driver.gd` renders images), look at them yourself, and fix what looks wrong before calling a step done.
- Run `tests/performance_profile.gd` before you start and at the end, and report both. The Low preset must still aim for 30 fps on a mid-range phone, so anything new needs distance shortcuts: update less often far away, stop beyond 120 m.
- When you finish, report what changed, the before and after profile numbers, anything you couldn't verify, and a short list of things for me to check by eye.