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

Scenes and tests are split by what they need:

- **`cpu/`** — rigid bodies, joints, characters, areas, queries. Works with any
  `godot_physx` build.
- **`gpu/`** — GPU particle fluids (`PhysXParticleFluid3D`, `PhysXFluidRenderer`).
  Needs an engine built with `physx_gpu=yes` and a CUDA device; inert otherwise.

## Demos

### `demo/cpu/`

| Scene | What it shows |
| --- | --- |
| `physx_playground.tscn` | First-person character, a jointed ragdoll, a hinged door, a pendulum row, a 2000-box `MultiMesh` pile, and dangling chains. Left click launches a ragdoll, right click fires a ball with a radial blast. |
| `physx_showcase.tscn` | Box stress test with a switchable body count (1k–50k) and an orbiting camera. |
| `physx_wind.tscn` | A gusting `WindArea` driving cloth pennants, streamers, tumbling debris and a pendulum wind gauge; walk into the volume and it pushes the character too. |

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
