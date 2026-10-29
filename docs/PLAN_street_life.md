# Plan: street life (Task 5)

Spec: `prompt-lead.md`. One phase per session. After each phase: commit, add 3–4 lines to README's Progress log, update `progress.md`, stop. The next session starts with "continue with the next phase in docs/PLAN_street_life.md".

**Status:** Phases 0–2 done. Next: Phase 3 (danfos).

## What already exists (reuse, don't redo)

- Every character has the standard skeleton (`GeneralSkeleton`, `SkeletonProfileHumanoid` BoneMap) and a T-pose rest (`fix_silhouette`, threshold 1.0). The Mixamo rig rests in the same T-pose, so the clips transfer the way the Quaternius ones do.
- `scripts/locomotion.gd` already gives each pedestrian an AnimationTree: idle → walk → jog → run by speed, playback matched to ground speed, random start, `set_locomotion(speed, state, facing)`, `humanoid_walk.gd` fallback. It plays the CC0 Quaternius library `assets/animations/pedestrian_library.res`, built by `scripts/animation_library_build.gd`.
- Task 4 Phase 2 (drivers, passengers, realistic player) is half-built in the save point `ed55ee4`, and `smoke_test` fails there (`driving: false`). Every phase needs the whole suite green before committing, so **Phase 1 starts by getting the suite green again**.

## The Mixamo clips

All 59 files were imported and measured. Every one is "without skin" (no body mesh) on the standard Mixamo rig (`mixamorig_` bones, T-pose, hips 1.04 m). Walks and runs carry root motion (hip travel), which is stripped so the game moves the character. The four `… Pose` files are single frames with no hip height, so lying and sitting bodies get their height from their lowest bone.

Sex: **M** male only, **F** female only, **any** both. Loop: **L** looping, **1** one-shot, **P** held pose.

| File | Shows | Sex | Loop | Use |
|---|---|---|---|---|
| Standard Walk | normal walk (1.8 m per cycle) | any | L | Phase 1: walk for anyone without a sex-specific walk |
| Female Walk | female walk with hip sway | F | L | Phase 1: women's walk. The clip leans back and looks up, so the builder tips the spine forward and the head down a little |
| Male Locomotion Pack/walking | male walk | M | L | Phase 1: men's walk |
| Jogging | jog | any | L | Phase 1: jog (crossing roads, running to a crash) |
| Running | fast run | any | L | Phase 1: run for women and the player |
| Male Locomotion Pack/standard run | male run | M | L | Phase 1: men's run |
| Male Locomotion Pack/idle | relaxed standing idle, weight shifts | any | L | Phase 1: main idle for everyone (`Idle_Stand`). It's from the male pack but reads as neutral on women, and the CC0 idles look wrong on the Renderpeople women (head tipped back, wide stance) |
| Talking On Phone | standing on the phone, turns around (39 s) | any | L | Phase 1: occasional idle (1 in 3); Phase 2: shoppers, kiosk customers |
| Drunk Idle Variation | swaying idle | any | L | Phase 2: some under-bridge people |
| Sitting | perched high (hips at 0.8–1.0 m, a bar stool, not a chair) | any | L | skip for benches and seats; kept in the library for a stool or wall ledge if one is added |
| Sitting Talking | seated, talking (44 s) | any | L | Phase 2: clinic bench, under-bridge; Phase 3: passengers |
| Sitting Laughing | seated, laughing | any | L | Phase 3: passengers (variety) |
| Sitting Clap | seated, clapping | any | L | Phase 3: passengers (rare) |
| Sitting Angry | seated, angry gestures | any | L | Phase 3: passengers when the player takes the danfo |
| Female Sitting Pose | seated pose | F | P | Phase 1/2: women sitting |
| Male Laying Pose | lying down | M | P | Phase 1: lie test; Phase 2: men sleeping on mats |
| Female Laying Pose | lying down | F | P | Phase 2: women sleeping on mats |
| drug abuse Pose | standing, bent forward at the waist | any | P | skip: reads as doubled over. People under the bridge sit on upturned crates by the pillars instead (Sitting Talking), since no clip sits on the ground |
| Angry | standing, angry shouting (19 s) | any | L | Phase 3: driver and conductor shout at the player; Phase 4: angry crowd at the driver |
| Yelling While Standing | yelling, leaning forward | any | 1 | Phase 4: shouting after a crash, shouting after a driver who leaves |
| Block | arms raised, standing firm | any | 1 (hold last frame) | Phase 4: blocking the car |
| Kneeling Pointing | kneeling, pointing | any | L | Phase 4: people at the body; bystanders pointing |
| Praying | kneels and prays | any | 1 (hold last frame) | Phase 4: kneeling or grieving at the body |
| Dodging Right | quick sidestep flinch | any | 1 | Phase 4: flinch within 8 m |
| Standing Idle To Fight Idle | squares up | any | 1 | Phase 4: angry people stepping up to the car |
| Removing Driver | pulls a driver out of a vehicle | any | 1 | Phase 3: maybe for the player taking a danfo (decide after a look) |
| Standing Up | gets up from lying | any | 1 | Phase 1: player get-up after a ragdoll (replaces the Quaternius GetUp if it looks better) |
| Jump | standing jump | any | 1 | Phase 1: player jump |
| Male Locomotion Pack/jump | same as Jump | M | 1 | skip: duplicate |
| Falling | falling loop | any | L | Phase 1: player falling |
| Hard Landing | big landing | any | 1 | Phase 1: player landing from a high fall |
| Jumping Down (high/low ground) | step off a ledge | any | 1 | skip: no ledges in the city yet |
| Head Hit, Head Hit (1), Medium Hit To Head | hit reactions | any | 1 | skip: fights aren't in this task |
| Hook, Lead Jab, Kicking, Left Block | fighting | any | 1 | skip: fights aren't in this task |
| Cheering, Clapping | celebrating | any | L | skip: wrong mood for a crash; keep for later events |
| Kiss | needs a partner | any | 1 | skip: needs a second actor lined up |
| Dying, Fall Flat | collapse | any | 1 | skip: deaths and falls use the realistic ragdoll |
| Catwalk Walk Forward HighKnees, Catwalk Idle To Twist R | runway walk and pose | F | L / 1 | skip: exaggerated, looks out of place on a street |
| Crouched Sneaking Left, Run Forward Arc Left, Long Step Forward, Standing Cover Turn | sneaking, arcs, lunges, cover | any | — | skip: no gameplay uses them |
| Jog In Circle | jogs in a circle | any | L | skip: circles instead of going straight |
| Wheelbarrow Walk | pushing walk with nothing in the hands | any | L | skip until there is a cart prop (maybe Phase 2 market) |
| Male Locomotion Pack/left/right strafe (walking), left/right turn 90 | strafes and turns | M | L / 1 | skip: pedestrians and the player turn smoothly without them |

**Elders:** there are no elder clips. Older people keep the CC0 Quaternius `Walk_Slow`; women and men get the Mixamo clips above.

## Where the new places go

Blocks are 40 m squares on a 5×5 grid with 12 m roads; block (2,2) is the starting block and stays clear. Exact positions get confirmed with a top-down render in Phase 2.

- **Market street (suya kiosk, supermarket, stalls):** the block next to the start, so the player sees it straight away. The supermarket has a made-up name; the stalls, umbrellas and kiosks are packed along its pavement edge with walkable gaps.
- **Medical point:** on the block across the road from the market, with a bench outside. Green "+" sign, not a red cross.
- **Under-bridge:** a flyover across a north–south road on the far side of the city from the market, high enough for buses and the coach to pass under. Mats, cardboard, bags, buckets and a small fire under it.

## Performance budget

Baseline (headless, the last fully passing commit): about 6.9 ms per frame on High and Low. Windowed on the 2013 dev Mac: High 25 fps, Low 57.5 fps. Low must still aim for 30 fps on a mid-range phone.

| Phase | Adds | Budget on Low |
|---|---|---|
| 1 | swaps clips, no new characters | no measurable change |
| 2 | about 6 buildings, about 40 props, about 12 extra people on fixed loops | +100 draw calls at most; people beyond 40 m in a fixed pose, hidden beyond 120 m |
| 3 | up to 15 passengers + conductor per moving danfo | full animation only within 40 m; fixed pose beyond, hidden beyond 120 m |
| 4 | crowd reactions | at most 6 reacting on Low (12 on High), none beyond 30 m |

`tests/performance_profile.gd` runs on High and Low before Phase 1 and after every phase. The numbers go in the README Progress log.

## What I can't do, and why

- **The Mixamo clips can't ship in the repo.** The repo is public and Mixamo's terms forbid sharing the files, so `assets/animations/mixamo/` and the library built from it are git-ignored. Anyone who clones the repo without that folder gets the CC0 Quaternius clips instead, automatically.
- **No "hands on head" or crying clip** exists in the set. Hands-on-head will be a hand-made arm pose layered on the idle; crying will use the kneeling clips (Praying, Kneeling Pointing).
- **No conductor-hanging clip.** The conductor's pose (foot on the step, hand on the roof, leaning out) will be posed by hand with the hand pinned to the roof.
- **No elder clips** in the set; see above.
- **Phone FPS** can't be measured here; only headless CPU time and windowed FPS on this PC.
