## Procedural ship mesh from ShipDesign grammar (role silhouette + style constraints).
## Silhouette hulls come from Limit Theory ShapeLib at every VisualLOD.
## GeometryKernel loft helpers remain for thruster / optional accents only.
class_name ShipMeshGen
extends RefCounted

const STYLE_INDUSTRIAL := "industrial"
const STYLE_MILITARY := "military"
const STYLE_CIVILIAN := "civilian"
const STYLE_PIRATE := "pirate"
const STYLE_MINING := "mining"
const STYLE_LUXURY := "luxury"


static func build(design: Dictionary, lod: int = VisualLOD.LOD_FULL) -> ArrayMesh:
	var seed: int = int(design.get("seed", 1))
	var ship_class: int = int(design.get("ship_class", SimEntities.ShipClass.TRADER))
	var style: String = str(design.get("style", STYLE_CIVILIAN))
	var key := "ship:%d:%d:%s:lod%d:v8shapelib" % [seed, ship_class, style, lod]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var desc: Dictionary = ShipDesign.build(design, {"lod": lod})
	var length: float = float(desc["length"])
	var color: Color = desc["color"]
	var accent: Color = desc["accent"]
	var exhaust: Color = desc.get("exhaust", Color(0.4, 0.7, 1.0))
	var detail := _lod_to_detail(lod)

	# All LODs: ShapeLib silhouette (fighter or sausage) + uniform role framing.
	var shape: ShapeLibShape
	if _uses_fighter_shapelib(ship_class):
		shape = ShapeLibShipFighter.standard(seed, detail, style)
	else:
		shape = ShapeLibShipCapital.sausage(seed, detail, style)

	var mesh := _shapelib_to_role(shape, length, color, accent, exhaust, desc, lod)
	return MeshCache.store(key, mesh) as ArrayMesh


static func describe(design: Dictionary) -> Dictionary:
	var desc := ShipDesign.build(design)
	return {
		"seed": int(desc["seed"]),
		"hull_seed": int(desc["hull_seed"]),
		"engine_seed": int(desc["engine_seed"]),
		"module_seed": int(desc["module_seed"]),
		"detail_seed": int(desc["detail_seed"]),
		"ship_class": int(desc["ship_class"]),
		"style": str(desc["style"]),
		"length": float(desc["length"]),
		"width": float(desc["width"]),
		"height": float(desc["height"]),
		"engines": (desc["engines"] as Array).size(),
		"cargo_modules": _count_type(desc["modules"], "cargo") + _count_type(desc["modules"], "ore_bay"),
		"symmetric": bool(desc["symmetric"]),
		"module_types": _module_types(desc["modules"]),
		"role_name": str(desc["role_name"]),
		"hull_language": str(desc.get("hull", {}).get("language", "")),
		"stations": (desc.get("hull", {}).get("stations", []) as Array).size(),
		"negative_space": float(desc.get("negative_space", 0.0)),
		"shapelib": "fighter" if _uses_fighter_shapelib(int(desc["ship_class"])) else "capital",
	}


static func _uses_fighter_shapelib(ship_class: int) -> bool:
	# Patrol + miner → LT ShipFighter; hauler/trader → ShipCapital.Sausage.
	return (
		ship_class == SimEntities.ShipClass.PATROL
		or ship_class == SimEntities.ShipClass.MINER
	)


static func _lod_to_detail(lod: int) -> int:
	if lod <= VisualLOD.LOD_FULL:
		return 2
	if lod <= VisualLOD.LOD_SIMPLE:
		return 1
	return 0


## Uniform scale to role length (preserve ShapeLib proportions — no AABB squash).
## Append engine ports at FULL/SIMPLE/LOW; skip at BATCH (far MultiMesh).
static func _shapelib_to_role(
	shape: ShapeLibShape,
	length: float,
	color: Color,
	accent: Color,
	exhaust: Color,
	desc: Dictionary,
	lod: int
) -> ArrayMesh:
	shape.center_at(0.0, 0.0, 0.0)
	var aabb: Dictionary = shape.get_aabb()
	var lo: Vector3 = aabb["lower"]
	var hi: Vector3 = aabb["upper"]
	var size := hi - lo
	# Role framing: match Z extent to design length; keep XY proportions.
	var mesh_len := maxf(size.z, 1e-4)
	var u := length / mesh_len
	shape.scale_xyz(u, u, u)
	var mesh := shape.finalize_mesh(color)
	# Batch far ships: hull only (no bolted engine blocks).
	if lod >= VisualLOD.LOD_BATCH:
		return mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in desc.get("engines", []):
		var ep: Vector3 = e["pos"]
		var ex: Color = e.get("exhaust", exhaust)
		var er := float(e["radius"])
		var el := float(e["length"])
		if lod >= VisualLOD.LOD_LOW:
			ShapePrims.box(st, ep, Vector3(er * 1.6, er * 1.6, el), accent.darkened(0.2))
		else:
			GeometryKernel.engine_block(
				st, ep, er, el, accent.darkened(0.15), ex, 0.12, 6
			)
	st.generate_normals()
	var eng: ArrayMesh = st.commit()
	if eng.get_surface_count() > 0 and mesh.get_surface_count() > 0:
		var merged := ArrayMesh.new()
		for s in mesh.get_surface_count():
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		for s in eng.get_surface_count():
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, eng.surface_get_arrays(s))
		return merged
	return mesh


static func _count_type(modules: Array, type_name: String) -> int:
	var n := 0
	for m in modules:
		if str(m.get("type", "")) == type_name:
			n += 1
	return n


static func _module_types(modules: Array) -> Array:
	var out: Array = []
	for m in modules:
		var t: String = str(m.get("type", ""))
		if not out.has(t):
			out.append(t)
	return out
