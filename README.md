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
| `cpu/debris.tscn` | `PhysXChunkEmitter3D` as a scene node: select it to tune chunk size, impulse, spread and budget in the inspector. A small shooting range — walk in, left-click a wall or the floor and real rigid-body chunks fly out, bounce and settle. |
| `cpu/soft_body.tscn` | Stock `SoftBody3D` blobs (sphere, subdivided box) on the PhysX backend — select one to paint pinned vertices with its gizmo and tune `pressure_coefficient` / `linear_stiffness` / `total_mass` in the inspector. Press Play, `SPACE` drops a heavy ball on them. |
| `cpu/heightmap.tscn` | Stock `HeightMapShape3D` terrain — a `@tool` script generates the collision and the matching visible mesh from noise, so selecting `Terrain/CollisionShape3D` shows the real height-field gizmo in the editor; the exported noise params rebuild it live. Play to walk the terrain (`WASD`, `SPACE` jump) and `B` rolls a row of balls down a slope. |
| `cpu/shape_scale.tscn` | Walk a capsule character over collision shapes with non-uniform node scale baked into the geometry — stretched box platforms, a chamfered-box convex ramp, a trimesh hump, a scaled sphere dome and a scaled height-field mound. Select a piece and stretch its transform in the inspector, then press Play. |

### `demo/cpu/`

| Scene | What it shows |
| --- | --- |
| `physx_playground.tscn` | First-person character, a jointed ragdoll, a hinged door, a pendulum row, a 2000-box `MultiMesh` pile, and dangling chains. Left click launches a ragdoll, right click fires a ball with a radial blast. |
| `physx_showcase.tscn` | Box stress test with a switchable body count (1k–50k) and an orbiting camera. Each box is a `RigidBody3D` node. |
| `physx_rid_showcase.tscn` | The same stress test, but every box is a bare `PhysicsServer3D` RID body (one shared shape, no nodes) — much lighter at high counts. Use it against `physx_showcase` to see the per-node cost. |
| `physx_wind.tscn` | A gusting `WindArea` driving jointed rigid-body pennants and streamers, tumbling debris and a pendulum wind gauge; walk into the volume and it pushes the character too. |
| `cloth_wind.tscn` | The same gusting `WindArea`, now driving real `PhysXCloth3D` flags and banners (CPU XPBD), with tumbling crates and drifting leaves. Walkable. |
| `physx_bridge.tscn` | A walkable rope bridge: a chain of plank `RigidBody3D` bodies pin-jointed end to end and anchored to a stone abutment at each side, sagging into a catenary. Walk across, drop a crate pile mid-span (`C`) and it dips and holds. |
| `physx_soft_body.tscn` | A soft-body marble run — batches of stock `SoftBody3D` blobs pour down a chute, bounce and squash down a stair section and out into a catch basin. Free-fly camera (`WASD` + mouse), `F` drops more onto the running pile so the count/FPS climb, `C` clears, `B` rolls a heavy ball in. Headless `bench` mode. |
| `physx_ballpit.tscn` | A FleX-style ball pit — 5k–20k small rigid spheres (bare `PhysicsServer3D` RID bodies, one shared shape, `MultiMesh`-drawn) piling in a dark pit on the GPU solver. Wade a capsule character through them (`WASD`, `SHIFT` sprint, `SPACE` hop) and they scatter; `F` flings a wrecking ball, `G` pours a fresh wave, `1`–`4` set the count. |

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
  `heightmap_test`, `heightmap_character_test` (walk terrain, no facet snag),
  `heightmap_edge_test` / `heightmap_crash_repro` (bodies off the height-field
  rim — regressions for the GPU boundary crash), `shape_scale_test` /
  `shape_scale_walk_test` (non-uniform scale baked into box / convex / trimesh /
  height-field shapes), `ballpit_test` (12k rigid spheres pile in a pit, a
  wrecking ball plows in), `soft_body_test`,
  `soft_body_spawn_test`, `soft_body_cascade_test`, `determinism_test`,
  `ragdoll_skeletal_test` (a rigged humanoid `Skeleton3D` +
  `PhysicalBoneSimulator3D` ragdoll: shove it, it must fall, keep its joints
  connected and never NaN).
  `physics_bench.gd` is a step-time benchmark across body counts (run once per
  engine, flipping `physics/3d/physics_engine`). `heightmap_runtime_probe.tscn`
  is a **windowed** run (not `--script`) — the GPU boundary crash only faults
  reliably with a renderer sharing the GPU.
- **`test/gpu/`** — `particle_fluid_test`, `particle_emit_test`,
  `particle_foam_test`, `soft_body_gpu_test` (`PxDeformableVolume` — fall,
  collide, deform, impulse, pin). These `SKIP` (exit 0) without a CUDA device.

Both `physx_showcase` and `physx_rid_showcase` also take a headless benchmark
mode — no window, no rendering — that prints physics step time and rate:

```
godot --headless --path . demo/cpu/physx_rid_showcase.tscn --fixed-fps 60 -- bench count=25000 frames=600
```

## License

This project (scenes, scripts, tests) is under the MIT License — see
[LICENSE](LICENSE). Copyright (c) 2026 Wild Ox Studios.

It targets the `godot_physx` engine module, which links NVIDIA PhysX 5
(BSD-3-Clause); that licensing lives with the engine build, not here.
