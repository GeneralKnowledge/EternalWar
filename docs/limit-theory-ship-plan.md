# Limit Theory Ship Plan (EternalWar)

Derived from `docs/limit-theory-ship-forensics.md`.

---

## Architecture (preserve)

```
Ship role → ShipDesign → StyleProfile → semantic modules → ShipMeshGen → ShapePrims → Mesh
```

Semantic design stays in GDScript. Mesh assembly may move to Rust later if profiling justifies it (not this pass — generation is cheap vs travel kernels).

---

## Construction tiers

| Tier | Content | LOD |
| --- | --- | --- |
| 1 Silhouette | Hull volume, proportions, major asymmetry | Always |
| 2 Functional | Engines, cargo/mining, weapons, cockpit | ≤ LOW |
| 3 Secondary | Wings, struts, fins, armour plates | ≤ SIMPLE |
| 4 Surface | Ridges, small panels, lights | FULL only |

---

## Role grammars

| Role | Silhouette intent |
| --- | --- |
| Patrol | Flat tapered prism + swept wings + side mounts (fighter) |
| Trader | Compact hull + paired cargo pods with gaps |
| Hauler | Long spine + spaced cargo modules (capital sausage light) |
| Miner | Forward boom/drill + asymmetric machinery + ore pods |
| Military style | Disciplined symmetry, armour plates, hardpoints |
| Pirate style | Broken symmetry, salvaged pods, mixed exhaust |

---

## Style → shape (not just colour)

`StyleProfile` gains:

- `hull_language`: wedge / round / block / spine
- `negative_space`: 0–1 gap scale between modules
- `exhaust_family`: cyan / amber / white
- `panel_bias`, `strut_bias`

---

## Materials

- Default hull: **matte dark / industrial** (silhouette-first)
- Accents: painted panels, not full-hull neon
- Engines: emissive from `exhaust_family`, not hard-coded blue
- `vertex_color_use_as_albedo` retained for panel variation

---

## Iteration order

1. Silhouette / proportions / negative space  
2. Role identity  
3. Style → geometry  
4. Engine / material response  
5. Colour palette (de-blue)  
6. Fine bevel / panel detail  
7. Native mesh kernel only if gen cost shows up in profiles  

## Definition of progress

Gallery + silhouette compare scores climb; roles are readable at a glance; blue is no longer the universal ship/engine colour.
