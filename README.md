# godot_physx test project

A Godot 4.x project for exercising the **godot_physx** engine module (a PhysX 5
`PhysicsServer3D` backend). It has no value without a custom engine build that
includes that module.

## Running

Build Godot with the `godot_physx` module, then open this project with that
editor binary. `project.godot` already selects the PhysX backend:

```
[physics]
3d/physics_engine="PhysX"
```

Scenes and tests are grouped by what they need:

- **`cpu/`** — rigid bodies, joints, characters, areas, queries. Works with any
  `godot_physx` build.
- **`gpu/`** — GPU particle fluids (`PhysXParticleFluid3D`). Needs an engine
  built with `physx_gpu=yes` and a CUDA device; inert otherwise.

`PhysXCloth3D` runs on the GPU (a PhysX deformable surface) when CUDA is present
and falls back to a built-in CPU solver otherwise, like GPU rigid dynamics — so
its scenes appear under both.

## Demos

`demo/cpu/` and `demo/gpu/` are **runtime demos** — they build the whole scene
from GDScript and are meant to be played. `demo/editor/` holds **authoring
demos** — the PhysX object is a real scene node, so you select it to use its
viewport gizmo and inspector, then press Play.

### `demo/editor/` — author with the node, then play

| Scene | What it shows |
| --- | --- |
| `cpu/cloth.tscn` | `PhysXCloth3D` flags and a banner as scene nodes: select a cloth to drag its grid handles, move its pins and tune its inspector. A `WindArea` gusts them on Play. Runs anywhere. |
| `gpu/cloth.tscn` | A 48×48 `PhysXCloth3D` sheet draping over a sphere plus a wind-blown flag — the resolution and drape the GPU deformable surface allows. SPACE drops a ball. Falls back to the CPU solver without CUDA. |
| `gpu/fluid.tscn` | `PhysXParticleFluid3D` as a scene node: gizmo and inspector for the emitter, plus the GPU isosurface + foam surface. Needs a `physx_gpu=yes` build. |
| `cpu/bridge.tscn` | A rope bridge built entirely from stock nodes — `RigidBody3D` planks joined by `Generic6DOFJoint3D` (linear axes locked, angular Z a spring). Select a `Deck/J*` joint to see the spring config and its limit gizmo. Play and it settles under the crates; `C` drops more. |

### `demo/cpu/`

| Scene | What it shows |
| --- | --- |
| `physx_playground.tscn` | First-person character, a jointed ragdoll, a hinged door, a pendulum row, a 2000-box `MultiMesh` pile, and dangling chains. Left click launches a ragdoll, right click fires a ball with a radial blast. |
| `physx_showcase.tscn` | Box stress test with a switchable body count (1k–50k) and an orbiting camera. |
| `physx_wind.tscn` | A gusting `WindArea` driving jointed rigid-body pennants and streamers, tumbling debris and a pendulum wind gauge; walk into the volume and it pushes the character too. |
| `cloth_wind.tscn` | The same gusting `WindArea`, now driving real `PhysXCloth3D` flags and banners (CPU XPBD), with tumbling crates and drifting leaves. Walkable. |
| `physx_bridge.tscn` | A walkable rope bridge: a chain of plank `RigidBody3D` bodies pin-jointed end to end and anchored to a stone abutment at each side, sagging into a catenary. Walk across, drop a crate pile mid-span (`C`) and it dips and holds. |

### `demo/gpu/`

| Scene | What it shows |
| --- | --- |
| `physx_fluid.tscn` | A faucet streaming GPU fluid into a glass tank, with foam/spray and script-side buoyancy on dropped balls. |

## Tests

Headless pass/fail scripts, one behaviour each:

```
godot --headless --path . --script res://test/cpu/physics_smoke.gd
```

- **`test/cpu/`** — `physics_smoke`, `sleep_test`, `query_test`, `contact_test`,
  `property_test`, `area_test`, `area_override_test`, `mesh_shape_test`,
  `joint_test`, `character_test`, `pendulum_gravity_test`, `chain_force_test`,
  `determinism_test`. `physics_bench.gd` is a step-time benchmark across body
  counts (run once per engine, flipping `physics/3d/physics_engine`).
- **`test/gpu/`** — `particle_fluid_test`, `particle_emit_test`,
  `particle_foam_test`. These `SKIP` (exit 0) on a build without GPU particles.
