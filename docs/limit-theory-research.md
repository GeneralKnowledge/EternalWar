# Limit Theory Research Notes

Technical inspiration drawn from publicly available Limit Theory (LT) and Limit Theory Redux (LTR) source. This is **not** a port. Each section records the original idea, the problem it solves, and how we map it into Godot.

Reference repositories inspected:

- [JoshParnell/ltheory](https://github.com/JoshParnell/ltheory) — C + Lua generation (LibPHX era)
- [JoshParnell/ltheory-old](https://github.com/JoshParnell/ltheory-old) — earlier C++ / LTSL gameplay
- [JoshParnell/libphx](https://github.com/JoshParnell/libphx) — engine-as-library philosophy
- [Limit-Theory-Redux/ltheory](https://github.com/Limit-Theory-Redux/ltheory) — Rust + Lua community continuation

---

## 1. Script-driven gameplay over a thin native core

### Original concept
LibPHX exposes a C API to LuaJIT via FFI. Gameplay (economy, AI jobs, entities) lives mostly in script; the engine handles physics, rendering, and heavy math.

### Problem it solves
Iterate gameplay without recompiling the engine. Keep the majority of simulation logic readable and moddable while still calling into fast native code when needed.

### Relevant references
- `libphx` README (engine-as-library, Lua control flow)
- `ltheory/script/Game/*` (Entity, Jobs, Actions, Economy)

### Proposed Godot implementation
GDScript owns simulation data and AI. Godot Nodes handle rendering, camera, audio, and player input. Reserve Rust (via GDExtension) only after profiling proves a hot path.

### Why it differs
Godot already provides the “native core.” We do not rebuild an engine. The LT split maps to **simulation RefCounteds / dictionaries** vs **presentation Nodes**.

### Performance implications
GDScript is fine for hundreds of agents. Profile before adding native code. Keep the Godot↔Rust surface tiny if introduced later.

---

## 2. Lightweight entities with mixin-style components

### Original concept
`Entity` is a tiny ID + event handler table. Behaviours (`addEconomy`, `addTrader`, `addFactory`, `addFlows`) attach data and register for `Event.Update` / `Event.Debug` / `Event.Render`.

### Problem it solves
Compose stations, ships, and systems without deep inheritance trees. Systems can query “who has a trader?” without a heavy ECS framework in the original LT Lua code.

### Relevant references
- `ltheory/script/Game/Entity.lua`
- `ltheory/script/Game/Components/{Economy,Trader,Factory,Market,Flows,Yield}.lua`
- LTR modular ECS under `script/Modules/{Economy,CelestialObjects,...}`

### Proposed Godot implementation
Typed dictionaries / small Resource classes for `ShipState`, `StationState`, `PlanetState`, `YieldSite`. Optional components as nested dictionaries (`market`, `factory`, `yield`). No third-party ECS unless profiling demands it.

### Why it differs
Godot Nodes are expensive at scale. Simulated ships are **not** Node3Ds. Presentation spawns MultiMesh / pooled visuals only for nearby or player-relevant entities.

### Performance implications
Dictionary/array SoA-style updates beat thousands of scene-tree nodes. Event-bus style (`register`/`send`) is optional; explicit system ticks are clearer in GDScript.

---

## 3. Economy as cached job board + local markets

### Original concept
A system-level `Economy` periodically scans children for factories, markets, traders, and yields, then **caches jobs** (Mine, Transport). Idle assets sample jobs and pick by **payout** (or historically by “flow pressure”).

Stations expose ask/bid books (`Trader`). Factories run production recipes that consume inputs and produce outputs. `Flow` records item rate at a location so net supply/demand can be summed.

### Problem it solves
AI does not hard-code “go mine here.” Economic opportunity is data. Agents react when prices and stocks change.

### Relevant references
- `ltheory/script/Game/Components/Economy.lua`
- `ltheory/script/Game/Jobs/{Mine,Transport}.lua`
- `ltheory/script/Game/Actions/Think.lua`
- `ltheory/script/Game/Components/{Trader,Factory,Market,Flows}.lua`
- `ltheory/script/Game/Production.lua`, `Flow.lua`, `Job.lua`

### Proposed Godot implementation
`EconomySystem` rebuilds a job list on a slow tick (~1 Hz). Each job is a dictionary: `{type, src, dst, commodity, expected_payout}`. Ship AI samples N jobs and picks the best payout. Station markets use simple ask/bid or inventory+price curves for the prototype.

Production chains for prototype:

```
ore → metal → components
energy / food as station consumption sinks
```

### Why it differs
LT’s full order-book + escrow is powerful but unfinished (comments warn about order spam). Prototype uses inventory-backed prices first; upgrade toward order books once stable.

### Performance implications
Job cache is O(yields×markets + traders²×items). Acceptable at one-system scale. Must aggregate or spatialise before multi-system galaxies.

---

## 4. Goal-oriented AI via action stacks and jobs

### Original concept
`Think` manages idle assets: sample economy jobs, push a Job action. Jobs are state machines that push sub-actions (`MoveTo`, `MineAt`, `DockAt`, `Undock`) then pop when complete.

### Problem it solves
Composable behaviour without a giant behaviour tree. Jobs estimate travel time and payout so agents choose profitable work.

### Relevant references
- `ltheory/script/Game/Actions/Think.lua`
- `ltheory/script/Game/Actions/{MoveTo,MineAt,DockAt,Undock}.lua`
- `ltheory/script/Game/Job.lua`

### Proposed Godot implementation
Per-ship `action` enum / small stack: `IDLE → TRAVEL → MINE/DOCK → TRADE → IDLE`. Job selection mirrors LT payout sampling (`kJobIterations`-style). Keep decision logic in simulation, not in Node scripts.

### Why it differs
No LTSL/Lua action inheritance. Explicit enums and dictionaries are easier to unit-test in headless Godot.

### Performance implications
Only idle ships re-evaluate jobs. Active ships run cheap travel/mine steps. Stagger AI updates across frames if needed.

---

## 5. Deterministic seeded generation

### Original concept
`SystemGenerator(seed)` owns an RNG; asteroids, stations, and planets are placed from seeded distributions. Ship meshes are also seed-driven (`Gen.Ship`).

### Problem it solves
Reproducible universes for debugging and exploration. Hierarchical content without hand-authoring every object.

### Relevant references
- `ltheory/script/Gen/SystemGenerator.lua`
- `ltheory/script/Gen/System/SystemBasic.lua`
- `ltheory/script/Gen/Ship.lua`, ShapeLib
- LTR `UniverseManager` / `GenerationContext` / `UniverseGenerationSystem`

### Proposed Godot implementation
`SeededRNG` wraps `RandomNumberGenerator`. System seed = `hash(galaxy_seed, system_coords)`. Generate star, planets, yields, stations, initial inventories from that RNG. Same seed → identical system.

**GDScript footgun:** unqualified `randf()` / `randi()` / `randf_range()` inside a class resolve to **GlobalScope** (non-seeded), not instance methods. Always call `_rng.randf()` (or `self.randf()`) inside the wrapper. Also avoid chaining multiple RNG calls in one expression — evaluate them in separate statements.

### Why it differs
Godot’s `RandomNumberGenerator` is usable if seed and call order are controlled. We wrap it to forbid unseeded draws in generation paths.

### Performance implications
Generate on demand; do not materialise the whole galaxy. Cache generated system state when entered.

---

## 6. Simulation vs presentation separation

### Original concept
Entities register for `Event.Render` separately from `Event.Update`. LOD meshes draw based on eye distance / scale (`VisibleLodMesh`). System begins/ends render by pushing shader env maps.

### Problem it solves
Simulate more than you draw. Distant detail collapses visually without deleting economic identity.

### Relevant references
- `ltheory/script/Game/Components/VisibleLodMesh.lua`
- `ltheory/script/Game/Entities/System.lua` (`beginRender` / `render` / `update`)

### Proposed Godot implementation
`StarSystemSim.tick(dt)` is headless-safe. `SystemPresenter` reads state and drives MultiMeshInstance3D for ships, MeshInstance3D for planets/stations. Distance LOD later; prototype always draws simplified primitives.

### Why it differs
Godot MultiMesh / VisibilityNotifier replace custom mesh LOD for early milestones. Shader nebulae are out of scope.

### Performance implications
500 ships as MultiMesh instances is cheap. Avoid per-ship Node3D until player interaction requires it.

---

## 7. Flow pressure (historical) vs payout (practical)

### Original concept
`Job:getPressure` measured how a job would change squared flow imbalance — agents could reduce economic “pressure.” Later `Think` switched to **maximise payout** (`if true then -- Use payout, not flow`).

### Problem it solves
Pressure is elegant for systemic balance; payout is more intuitive and was what LT used in practice.

### Relevant references
- `ltheory/script/Game/Job.lua` (`getPressure`)
- `ltheory/script/Game/Actions/Think.lua` (payout branch)

### Proposed Godot implementation
Prototype uses payout. Keep flow accounting on stations for debug metrics and future pressure-based AI experiments.

### Why it differs
We document both; ship only payout until we need emergent shortage-chasing beyond price signals.

### Performance implications
Payout queries hit market books; cache mid prices on economy refresh.

---

## 8. Factories and production recipes

### Original concept
`Production` defines inputs, outputs, duration. Factories advance timers, consume inventory, emit outputs, and (optionally) post asks/bids.

### Problem it solves
Industry chains create demand for transport and mining without scripted quests.

### Relevant references
- `ltheory/script/Game/Production.lua`
- `ltheory/script/Game/Components/Factory.lua`

### Proposed Godot implementation
Static recipe table in `data/recipes.gd`. Stations tick production on the economy interval. Blocked factories raise input prices / post higher bids over time.

### Why it differs
Skip unbounded order posting (LT comment: tens of thousands of energy-cell orders stalled the game). Cap active orders / use inventory targets.

### Performance implications
Few dozen factories updating at ≤1 Hz is negligible.

---

## 9. Universe scale and hierarchical generation (LTR)

### Original concept
LTR organises celestial content into modules with a `UniverseManager`, `GenerationContext`, and scale config. Generation is contextual and rule-driven rather than one monolithic function.

### Problem it solves
Large universes need staged generation and clear data pipelines.

### Relevant references
- `ltheory-redux/script/Modules/CelestialObjects/Managers/UniverseManager/*`
- `UniverseGenerationSystem.lua`, `UniverseScaleConfig.lua`

### Proposed Godot implementation
Milestone 1–6: single system. Milestone 8: `GalaxyGenerator` with hierarchical seeds and lazy system materialisation. `GenerationContext`-like dictionary passed through generators.

### Why it differs
Start smaller. Do not invent galaxy plumbing before one living system works.

### Performance implications
Lazy generation + sim LOD (aggregates for distant systems) is mandatory before claiming large ship counts.

---

## 10. Profiling as a first-class citizen

### Original concept
LT wraps sections in `Profiler.Begin` / `Profiler.End` throughout economy, AI, and physics.

### Problem it solves
Know what is slow before rewriting in C/Rust.

### Relevant references
- Economy / System / Think profiler calls throughout `ltheory/script/Game`

### Proposed Godot implementation
`PerfStats` dictionary updated each tick; debug overlay shows ships, active jobs, economy ms, AI ms, render ms. Headless tests assert determinism and basic throughput.

### Why it differs
Godot Debugger + custom overlay. No LibPHX profiler.

### Performance implications
Instrumentation cost should stay tiny (timestamps around major phases only).

---

## Decisions for this prototype

| LT idea | Adopt now? | Form |
|--------|------------|------|
| Data entities vs scene nodes | Yes | Dictionaries + arrays |
| Economy job board | Yes | Mine + Transport jobs |
| Payout-based Think | Yes | Sample N jobs / pick best |
| Ask/bid traders | Simplified | Inventory + dynamic price |
| Production recipes | Yes | ore→metal→components |
| Seeded system gen | Yes | SeededRNG + SystemGenerator |
| Action stack AI | Yes | Compact action enums |
| Visual LOD meshes | Deferred | MultiMesh primitives |
| Full galaxy | Deferred | Single system first |
| Rust | No | Profile first |

---

## Open questions for later milestones

1. How to preserve economic state when demoting a system to aggregate LOD?
2. When do we need spatial partitioning for job search?
3. Should factions own station inventories or only ships?
4. How much of LT’s ShapeLib ship generation is worth porting vs faction-tinted primitives?
