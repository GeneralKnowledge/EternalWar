## Formal visual LOD tiers for presentation.
## LOD0 full design · LOD1 simplified · LOD2 low-poly · LOD3 MultiMesh archetype · LOD4 sim-only
class_name VisualLOD
extends RefCounted

const LOD_FULL := 0
const LOD_SIMPLE := 1
const LOD_LOW := 2
const LOD_BATCH := 3
const LOD_SIM := 4

const DIST_FULL := 280.0
const DIST_SIMPLE := 550.0
const DIST_LOW := 1100.0
const DIST_BATCH := 4500.0


static func for_distance(dist: float) -> int:
	if dist < DIST_FULL:
		return LOD_FULL
	if dist < DIST_SIMPLE:
		return LOD_SIMPLE
	if dist < DIST_LOW:
		return LOD_LOW
	if dist < DIST_BATCH:
		return LOD_BATCH
	return LOD_SIM


static func label(lod: int) -> String:
	match lod:
		LOD_FULL:
			return "full"
		LOD_SIMPLE:
			return "simple"
		LOD_LOW:
			return "low"
		LOD_BATCH:
			return "batch"
		_:
			return "sim"
