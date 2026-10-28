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

The engine module itself lives in
[uno1982/godot](https://github.com/uno1982/godot), `modules/godot_physx`, on
the `feature/physx5-module` branch.

The tests and the runtime demos (`demo/cpu/`, `demo/gpu/`) are grouped by what
they need:

- **`cpu/`** — rigid bodies, joints, characters, areas, queries. Works with any
  `godot_physx` build.
- **`gpu/`** — GPU particle fluids (`PhysXParticleFluid3D`). The PBD solver
  needs an engine built with `physx_gpu=yes` and a CUDA device; the MPM
  compute solver runs on any GPU (`solver = Auto` picks it without CUDA).
- **`flow/`** — NVIDIA Flow smoke, fire and dust (`PhysXFlow3D`). Needs an
  engine built with `flow_sdk=<path to the Flow SDK>` (the `flow` folder of the
  PhysX repo, built with its `build.bat`), `nvflow.dll` and `nvflowext.dll`
  next to the editor binary (the build copies them), and the Forward+ or
  Mobile renderer. Any GPU works -- Flow runs on Godot's own Vulkan or
  Direct3D 12 device, not CUDA. Without Flow in the build its scenes still
  open, with the Flow nodes as placeholders.

The editor demos (`demo/editor/`) are grouped by feature instead: nearly all of
them run on either path. `PhysXCloth3D` runs on the GPU (a PhysX deformable
surface) when CUDA is present and falls back to a built-in CPU solver
otherwise, like GPU rigid dynamics; `cloth/cloth_ball_cpu_solver.tscn` and
`cloth_ball_gpu_solver.tscn` force one solver each, to compare them. The
`destruction/` scene (and the destructible in the vehicle track) needs an
engine built with `blast_sdk=`, and `flow/` needs Flow as above.

## Demos

`demo/cpu/` and `demo/gpu/` are **runtime demos** — they build the whole scene
from GDScript and are meant to be played. `demo/editor/` holds **authoring
demos** — the PhysX object is a real scene node, so you select it to use its
viewport gizmo and inspector, then press Play.

### `demo/editor/` — author with the node, then play

**`bodies/`**

| Scene | What it shows |
| --- | --- |
| `body_features.tscn` | Rigid-body settings you set in the Inspector, one station each: a carousel and an elevator built from `MovingPlatform` (an `AnimatableBody3D` with spin / travel / period, `demo/common/moving_platform.gd`) that the character and loose crates ride; crates that float on a **constant force** equal to their weight and a pinwheel turned by **constant torque**; two flywheels, one with 5x **inertia** (`F` kicks both); and two roly-poly toys, the green one with a low **custom center of mass** that rights itself (`G` knocks them over). Walk with `WASD`. Runs on PhysX and Jolt alike. |
| `heightmap.tscn` | Stock `HeightMapShape3D` terrain — a `@tool` script generates the collision and the matching visible mesh from noise, so selecting `Terrain/CollisionShape3D` shows the real height-field gizmo in the editor; the exported noise params rebuild it live. Play to walk the terrain (`WASD`, `SPACE` jump) and `B` rolls a row of balls down a slope. |
| `shape_scale.tscn` | Walk a capsule character over collision shapes with non-uniform node scale baked into the geometry — stretched box platforms, a chamfered-box convex ramp, a trimesh hump, a scaled sphere dome and a scaled height-field mound. Select a piece and stretch its transform in the inspector, then press Play. |
| `back_faces.tscn` | `ConcavePolygonShape3D.backface_collision`: two identical floating trimesh platforms, one one-sided (off) and one solid (on). Step on a glowing pad to be launched up -- you pass through the one-way platform and land on top, and bump your head on the solid one; `F` fires balls up from underneath both. Select a platform's `CollisionShape3D` to see the setting. |
| `picking.tscn` | Mouse picking and area queries, set in the Inspector: hover lights objects up and clicks react (`input_event`), Area3D zones included. A glass pane with `input_ray_pickable` off lets you click the zone behind it; one with it on blocks. Click the crate to kick it. A `RayCast3D` laser sweeps the zones -- `T` toggles its `collide_with_areas`. |
| `area_zone_demo.tscn` | Area-to-area detection: fly a camera with an `Area3D` probe into the scene's zones and each one reacts through `area_entered` / `area_exited`. |
| `stairs.tscn` | `SeparationRayShape3D`: two bots walk up identical 0.3 m stairs -- the one standing on a ray climbs, the capsule-only one stops at the first step. Walk them yourself on the same setup. A hover sled (a `RigidBody3D` on four corner rays) floats over bumps when you walk into it. Select a ray's `CollisionShape3D` to see it. |
| `lips.tscn` | Plain capsules walking up a lip in a triangle mesh -- no `SeparationRayShape3D` (that's `stairs.tscn`). Six lanes, each one `ConcavePolygonShape3D` with a 2 to 30 cm lip, a bot walking into each: a default capsule (radius 0.5) gets up a lip its rounded bottom meets at a slope gentler than `floor_max_angle` -- 15 cm yes, 20 cm no, on PhysX and Jolt alike. Walk them yourself. |
| `snow.tscn` | A capsule wading through fresh snow on a `HeightMapShape3D`: real `PhysXChunkEmitter3D` clumps it kicks up and plows aside. |

**`joints/`**

| Scene | What it shows |
| --- | --- |
| `bridge.tscn` | A rope bridge built entirely from stock nodes — `RigidBody3D` planks joined by `Generic6DOFJoint3D` (linear axes locked, angular Z a spring). Select a `Deck/J*` joint to see the spring config and its limit gizmo. Play and it settles under the crates; `C` drops more. |
| `ragdoll.tscn` | Ragdolls with Godot's own workflow: the mannequin's physical skeleton from **Create Physical Skeleton** (`PhysicalBoneSimulator3D` + `PhysicalBone3D`), with cone joints at the spine, shoulders, hips and ankles and one-way hinges at the knees and elbows (`demo/common/mannequin/mannequin_ragdoll.tscn` — select a bone to see its joint and limits). The mannequins animate until left-click shoots one over; `SPACE` drops one down the steps. Runs on PhysX and Jolt alike. |

**`cloth/`**

| Scene | What it shows |
| --- | --- |
| `cloth.tscn` | `PhysXCloth3D` flags and a banner as scene nodes: select a cloth to drag its grid handles, move its pins and tune its inspector. A `WindArea` gusts them on Play. Runs anywhere. |
| `cloth_ball_gpu_solver.tscn` | A 48×48 `PhysXCloth3D` sheet draping over a sphere plus a wind-blown flag — the resolution and drape the GPU deformable surface allows. SPACE drops a ball. Falls back to the CPU solver without CUDA. |
| `cloth_ball_cpu_solver.tscn` | The same scene with both cloths forced onto the CPU solver (`simulation_mode`), to compare the two. |
| `character_cloth.tscn` | The mannequin in a long skirt and a cape, each a `PhysXSkinnedCloth3D` (compute shaders, any GPU), animating around a circle so the cloth reacts to real movement; `1`-`7` switch animations. |
| `soft_body.tscn` | Stock `SoftBody3D` blobs (sphere, subdivided box) on the PhysX backend — select one to paint pinned vertices with its gizmo and tune `pressure_coefficient` / `linear_stiffness` / `total_mass` in the inspector. Press Play, `SPACE` drops a heavy ball on them. |

**`fluid/`**

| Scene | What it shows |
| --- | --- |
| `fluid.tscn` | `PhysXParticleFluid3D` as a scene node: gizmo and inspector for the emitter, filling a tank. `SPACE` drops a ball, `M` cycles the render mode. Set to the MPM compute solver (any GPU). |
| `flamethrower_liquid.tscn` | A liquid flamethrower: hold left click to spray a `PhysXParticleFluid3D` from a camera-mounted muzzle. |
| `sand.tscn` | `PhysXGranular3D` sand in a pit: wade a character through it, drop a boulder (`F`). Flip `solver` between MPM and PBD (CUDA) to compare. |
| `debris.tscn` | `PhysXChunkEmitter3D` as a scene node: select it to tune chunk size, impulse, spread and budget in the inspector. A small shooting range — walk in, left-click a wall or the floor and real rigid-body chunks fly out, bounce and settle; with fluid emitters and a vortex to fire. |

**`water/`**

| Scene | What it shows |
| --- | --- |
| `lake.tscn`, `beach.tscn`, `round_pool.tscn` | `PhysXWaterSurface3D` with sample-point buoyant floaters (`demo/common/buoyant_body.gd`): `SPACE` drops more, left-click-drag shoves one to ripple the surface. |
| `ocean_storm.tscn` | A boat on open ocean whose sea state changes during play: `1`-`3` calm / breezy / storm, `4` an automatic storm cycle; `W`/`S` throttle, `A`/`D` steer. |

**`vehicles/`**

| Scene | What it shows |
| --- | --- |
| `vehicle_demo.tscn` | Seven vehicles on one track, `Tab` to switch: a stock `VehicleBody3D` car and motorcycle and their `PhysXVehicle3D` / `PhysXMotorcycle3D` counterparts, a `PhysXTank3D` (left click fires), and a stock `VehicleBody3D` arcade stunt plane on its own runway with eight rings to fly through (`demo/common/plane.tscn`: tricycle gear for the runway; in the air it flies where its nose points and turns toward the mouse aim, banking into turns -- `C` switches to manual stick controls; moving control surfaces and prop), and a stock `RigidBody3D` helicopter on a pad (`demo/common/heli.tscn`: hovers when you let go; it turns toward the mouse aim, W/S forward/back, Space/Ctrl climb/descend, A/D yaw, Q/E strafe; spinning main and tail rotors) that can fly the same rings. Red vehicles are stock nodes and run on any engine; blue ones are PhysX nodes. |

**`destruction/`**

| Scene | What it shows |
| --- | --- |
| `destructible_demo.tscn` | `PhysXDestructible3D` (Blast) walls and props: walk in first person, fire a ragdoll or the bomb and they break into real rigid-body pieces. Needs a `blast_sdk=` build. |

**`rendering/`**

| Scene | What it shows |
| --- | --- |
| `light_shafts.tscn` | `PhysXLightShafts3D`: screen-space sun shafts through a colonnade, a lattice window and a grove, next to Godot's own volumetric fog. `1` shafts on / off, `2` fog (Forward+ only), `M` mode, arrows move the sun. Works on Forward+ and Mobile. |
| `gi_courtyard.tscn` | Experimental: PXTGI, the module's global illumination (`PXTGI3D`), in a sunlit courtyard with a mirror sphere and a reflection probe. Bounce light and reflections are traced on screen, then against the scene's collision shapes. `G` PXTGI / Godot's SDFGI / none, `R` reflections traced / screen space / Godot's own, `F` Godot's SSR, `P` reflection probe (inside its box its cubemap replaces the traced reflections, as with SDFGI), `B` debug views, `L` lens effects, arrows move the sun. Forward+ only; runs in the editor viewport too. |
| `gi_courtyard_night.tscn` | Experimental: the courtyard by moonlight, lit mostly by a green emissive box that sweeps from wall to wall: bounce light from moving emissives. Same keys as `gi_courtyard.tscn`. |
| `gi_reflections.tscn` | Experimental: PXTGI's traced reflections without a reflection probe: a wall mirror showing coloured boxes behind the camera (off screen, so traced against their collision shapes), a mirror sphere, and a row of metal spheres from roughness 0.1 to 0.6 across `reflection_roughness_cutoff` (the traced reflection fades into Godot's from 0.375 to 0.5). The probe starts off; same keys as `gi_courtyard.tscn`. |
| `gi_cornell_box.tscn` | Experimental: PXTGI in the Cornell box (one light under the ceiling, no ambient light, so everything but the direct light is bounce light). `G` PXTGI / Godot's SDFGI / none, `B` debug views, `M` multi-bounce. Forward+ only. |

### `demo/editor/flow/` — NVIDIA Flow

Each flow is a `PhysXFlow3D` (the simulation, how it looks) fed by
`PhysXFlowEmitter3D` nodes (where gas comes from); an emitter's `flow` path
picks which flow it feeds, or with it empty, the scene's only one -- so an
emitter can live inside a vehicle scene. Physics bodies near the gas are solids
it flows around. `demo/flow/presets/` holds ready-made looks (fire, black smoke,
steam, dust, signal smoke) to instance or copy.

| Scene | What it shows |
| --- | --- |
| `smoke_plume.tscn` | A fire plume rolling over a tilted box: select the flow or the emitter to tune them while it runs in the editor. |
| `presets.tscn` | The five presets side by side -- five independent flows at once. |
| `dust_trail.tscn` | A cart circling on a `MovingPlatform` hub kicks dust up from its rear wheels; the emitters ride along inside the cart, the flow sits at the scene root. |
| `moving_collider.tscn` | A slab sweeping back and forth through a fire plume, pushing the smoke aside as it passes. |
| `flame_thrower.tscn` | A burning fuel jet fired at a wall, rolling into fire across it. Nozzle-like emitters need a high `couple_rate` (Flow's default 2 only nudges the gas) and low `buoyancy` so the burning jet holds its line. |
| `jet_flame.tscn` | A jet engine's exhaust at night: a sharp white-hot core cone (`demo/flow/jet_core_solid.gdshader`) with the Flow plume carrying on past it. The core is an opaque glowing mesh, so Flow -- drawn after transparent geometry as usual -- composites around it; `divergence` below zero on the nozzle keeps the plume a tight stream. |
| `torch.tscn` | A blowtorch drawn entirely by `demo/flow/jet_cone.gdshader`: a crisp, additive blue cone with a white-hot inner cone. A fluid grid can't resolve a flame front that thin, so the sharp part is a mesh. |
| `light_scattering.tscn` | `PhysXFlow3D.light_scattering`: a green light glowing through swirling ground fog, with pillars and a slab casting dark shafts through the glow (`L` scattering, `K` its shadows, `G` the light). |
| `light_shafts.tscn` | The `rendering/light_shafts.tscn` scene with a Flow fire burning in front of the sun: glowing gas doesn't stream like the sun, and its smoke blocks the shafts. |

### `demo/cpu/`

| Scene | What it shows |
| --- | --- |
| `physx_playground.tscn` | First-person character, a jointed ragdoll, a hinged door, a pendulum row, a 2000-box `MultiMesh` pile, and dangling chains. Left click launches a ragdoll, right click fires a ball with a radial blast. |
| `physx_playground_gi.tscn` | Experimental: the playground with PXTGI (`PXTGI3D`), the module's global illumination, lighting it from the 2000 boxes' collision shapes as they fall and settle. `G` GI on / off. Forward+ only. |
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
  `heightmap_edge_test` (bodies off the height-field rim — regression for the
  GPU boundary crash), `shape_scale_test` /
  `shape_scale_walk_test` (non-uniform scale baked into box / convex / trimesh /
  height-field shapes), `ballpit_test` (12k rigid spheres pile in a pit, a
  wrecking ball plows in), `soft_body_test`,
  `soft_body_spawn_test`, `soft_body_cascade_test`, `determinism_test`,
  `ragdoll_skeletal_test` (a rigged humanoid `Skeleton3D` +
  `PhysicalBoneSimulator3D` ragdoll: shove it, it must fall, keep its joints
  connected and never NaN), `body_parity_test` (constant force/torque,
  custom inertia and center of mass, direct-state torque/force/mass queries,
  axis velocity, a character riding a spinning platform -- the same numbers
  as on Jolt), `backface_collision_test` (a one-sided trimesh met from behind
  by rays, shape casts, bodies and a character, back faces off and on),
  `query_filter_test` (`collide_with_bodies` / `collide_with_areas` across
  rays, point/shape overlaps, casts, rest info and a `RayCast3D`),
  `separation_ray_test` (a character standing on a ray: rest height, up and
  down a step; a ray-only character; a rigid body on a ray).
  `physics_bench.gd` is a step-time benchmark across body counts (run once per
  engine, flipping `physics/3d/physics_engine`).
- **`test/gpu/`** — `particle_fluid_test`, `particle_emit_test`,
  `particle_foam_test`, `soft_body_gpu_test` (`PxDeformableVolume` — fall,
  collide, deform, impulse, pin). These `SKIP` (exit 0) without a CUDA device.
- **`test/flow/`** — `flow_smoke_test` (gas rises, `sample_smoke`),
  `flow_targets_test` (emitters feed the flow their `flow` path names),
  `flow_render_test` (the render effect draws), `flow_compositor_test` (user
  compositors are left as they were, no compositors left behind). Flow needs a
  RenderingDevice, so these run **windowed** (drop `--headless`); they `SKIP`
  in a build without Flow.

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
