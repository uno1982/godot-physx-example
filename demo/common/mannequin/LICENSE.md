# Mannequin, animations and garments

CC0 1.0 Universal (public domain): https://creativecommons.org/publicdomain/zero/1.0/

- `ual_animations.glb` -- *Universal Animation Library* (standard version) by
  Quaternius (quaternius.com), CC0: the mannequin and its 43 animations,
  retargeted to Godot's humanoid profile on import (`ual_bonemap.tres`).
- `skirt.tres`, `cape.tres` -- garments generated to fit the mannequin's rest
  pose: single layer with open hems, skinned rigidly to the hips and the upper
  chest (the cloth simulation does the rest). `mannequin_skin.tres` is the
  mannequin's own Skin, so the garments bind to its skeleton.
- `mannequin_ragdoll.tscn` -- the mannequin with its physical skeleton (made
  with Godot's Create Physical Skeleton, as in the character cloth demo) as a
  ragdoll; `mannequin_ragdoll.gd` starts it simulating.
