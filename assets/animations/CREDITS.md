# Animation credits

Every humanoid animation clip in the game comes from the sources below. All are
CC0 (public domain); credit is given anyway.

| Folder | Source | Author | Licence | Downloaded |
|---|---|---|---|---|
| `quaternius_ual1/` | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (Standard, `Unreal-Godot/UAL1_Standard.glb`, no root motion), via [itch.io](https://quaternius.itch.io/universal-animation-library) | Quaternius | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (`License.txt` in the folder) | 2026-10-23 |
| `quaternius_ual2/` | [Universal Animation Library 2](https://quaternius.itch.io/universal-animation-library-2) (Standard, `Unreal-Godot/UAL2_Standard.glb`, no root motion) | Quaternius | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (`License.txt` in the folder) | 2026-10-23 |

Both packs use the same Unreal-mannequin-style skeleton (`root`, `pelvis`,
`spine_01..03`, `neck_01`, `Head`, `clavicle_l`, `upperarm_l`, `lowerarm_l`,
`hand_l`, `thigh_l`, `calf_l`, `foot_l`, `ball_l`, ... and `_r`).

## Sources checked and not used

- **Mixamo (Adobe):** free to use inside finished games, but the Mixamo FAQ
  and Adobe's staff replies say raw character and animation files may not be
  redistributed (given away or sold as files). Storing the clip files in a
  public GitHub repo is redistribution, so Mixamo clips are not used.
  Sources: [Mixamo FAQ: licensing, royalties, ownership](https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/m-p/13234775),
  [Use and distribution of animations based on Mixamo animations](https://community.adobe.com/questions-696/use-and-distribution-of-created-animations-based-on-mixamo-animations-589442).
- **KayKit Character Animations** (Kay Lousberg, CC0): licence is fine, but the
  rig is a stylised chibi rig (one spine bone, big head) and the motion is
  cartoony, so it was not used for the realistic pedestrians.
- **CMU motion capture database:** "free for all uses" but not CC0/CC BY, so
  skipped under the project's licence rule.
- **Bandai Namco Research motion dataset:** CC BY-NC (NonCommercial), not allowed.
