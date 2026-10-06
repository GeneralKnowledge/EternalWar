## Procedural ship mesh from ShipDesign grammar (role silhouette + style constraints).
## Tiered construction: hull → modules → wings → surface.
## Geometry ops live in GeometryKernel; ShapePrims remains the semantic facade.
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
	var key := "ship:%d:%d:%s:lod%d:v3" % [seed, ship_class, style, lod]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var desc: Dictionary = ShipDesign.build(design, {"lod": lod})
	var length: float = float(desc["length"])
	var width: float = float(desc["width"])
	var height: float = float(desc["height"])
	var color: Color = desc["color"]
	var accent: Color = desc["accent"]
	var nose: float = float(desc["nose_taper"])
	var hull: Dictionary = desc.get("hull", {})
	var exhaust: Color = desc.get("exhaust", Color(0.4, 0.7, 1.0))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# LOD maps to construction tiers
	var include_surface := lod <= VisualLOD.LOD_FULL
	var include_secondary := lod <= VisualLOD.LOD_SIMPLE
	var include_functional := lod <= VisualLOD.LOD_LOW
	var include_engines := true
	var bevel_segs := 2 if lod <= VisualLOD.LOD_FULL else (1 if lod <= VisualLOD.LOD_SIMPLE else 0)
	var bevel_amt := float(hull.get("bevel", 0.18))
	if lod >= VisualLOD.LOD_LOW:
		bevel_amt *= 0.45
	if lod >= VisualLOD.LOD_BATCH:
		bevel_amt = 0.0
		bevel_segs = 0

	# Tier 1 — silhouette hull
	_emit_hull(st, hull, length, width, height, color, nose, bevel_amt, bevel_segs)

	# Tier 2 — engines + functional modules
	if include_engines:
		for e in desc["engines"]:
			var ep: Vector3 = e["pos"]
			var ex: Color = e.get("exhaust", exhaust)
			var segs := int(e.get("segments", 6))
			if lod >= VisualLOD.LOD_BATCH:
				ShapePrims.box(st, ep, Vector3(float(e["radius"]) * 1.6, float(e["radius"]) * 1.6, float(e["length"])), accent.darkened(0.2))
			else:
				GeometryKernel.engine_block(
					st, ep, float(e["radius"]), float(e["length"]),
					accent.darkened(0.15), ex, bevel_amt * 0.8, segs
				)

	if include_functional:
		for m in desc["modules"]:
			_emit_module(st, m, accent, color, lod, exhaust)

	if include_functional:
		for hp in desc["hardpoints"]:
			_emit_hardpoint(st, hp, color, accent, lod)

	# Tier 3 — wings, struts, plates
	if include_secondary:
		for w in desc["wings"]:
			_emit_wing(st, w, accent, lod)
		for s in desc.get("struts", []):
			ShapePrims.strut(st, s["a"], s["b"], float(s.get("thickness", 0.06)), color.darkened(0.1))
		for p in desc.get("plates", []):
			if lod <= VisualLOD.LOD_FULL:
				ShapePrims.panel(st, p["pos"], p["size"], color.darkened(0.12))

	# Tier 4 — surface ridges / pirate salvage
	if include_surface and (style == STYLE_INDUSTRIAL or style == STYLE_MINING):
		for i in 3:
			var z := -length * 0.18 + float(i) * length * 0.16
			ShapePrims.box(st, Vector3(0, height * 0.42, z), Vector3(width * 0.75, height * 0.05, length * 0.05), color.darkened(0.2))

	if include_surface and style == STYLE_PIRATE and not bool(desc["symmetric"]):
		ShapePrims.box(
			st,
			Vector3(width * 0.48, height * 0.12, length * 0.1),
			Vector3(width * 0.28, height * 0.28, length * 0.16),
			Color(0.42, 0.22, 0.18)
		)

	if include_surface and style == STYLE_MILITARY and ship_class == SimEntities.ShipClass.PATROL:
		# Light armour plate along dorsal — secondary mass, not a second hull
		var plate_z0 := -length * 0.15
		var plate_z1 := length * 0.28
		var plate_stations: Array = [
			GeometryKernel.station(plate_z0, width * 0.42, height * 0.08, height * 0.38, 0.0, "box", 4),
			GeometryKernel.station(plate_z1, width * 0.38, height * 0.06, height * 0.36, 0.0, "box", 4),
		]
		GeometryKernel.loft_hull(st, plate_stations, color.darkened(0.12), 0.1, 1, true, true)
	elif include_surface and style == STYLE_MILITARY:
		ShapePrims.box(st, Vector3(0, height * 0.4, length * 0.05), Vector3(width * 0.55, height * 0.08, length * 0.45), color.darkened(0.15))

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
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
	}


static func _emit_hull(
	st: SurfaceTool, hull: Dictionary, length: float, width: float, height: float,
	color: Color, nose: float, bevel_amt: float, bevel_segs: int
) -> void:
	var lang := str(hull.get("language", "wedge"))
	var sides := int(hull.get("sides", 6))
	var aft := float(hull.get("aft_taper", 0.88))
	var stations: Array = hull.get("stations", [])
	match lang:
		"loft":
			if stations.is_empty():
				stations = [
					GeometryKernel.station(-length * 0.5, width * nose * 0.5, height * nose * 0.5),
					GeometryKernel.station(0.0, width, height),
					GeometryKernel.station(length * 0.5, width * aft, height * aft),
				]
			GeometryKernel.loft_hull(st, stations, color, bevel_amt, maxi(bevel_segs, 1), true, true)
		"block":
			ShapePrims.block_hull(st, Vector3.ZERO, length, width, height, color)
		"round":
			ShapePrims.rounded_hull(st, Vector3.ZERO, length, width, height, color, nose)
		"spine":
			ShapePrims.spine(st, Vector3.ZERO, length * 0.9, width * 0.42, height * 0.45, color)
			ShapePrims.prism_hull(st, Vector3(0, 0, -length * 0.15), length * 0.55, width * 0.85, height * 0.85, color, sides, nose, aft)
		_:
			ShapePrims.prism_hull(st, Vector3.ZERO, length, width, height, color, sides, nose, aft)


static func _emit_wing(st: SurfaceTool, w: Dictionary, accent: Color, lod: int) -> void:
	if bool(w.get("tie", false)):
		ShapePrims.box(st, w["root"], Vector3(absf(float(w["span"])) * 2.0, float(w["thickness"]), float(w["chord"])), accent.darkened(0.12))
		return
	var root: Vector3 = w["root"]
	var span := float(w["span"])
	var chord := float(w["chord"])
	var tip_chord := float(w.get("tip_chord", chord * 0.35))
	var thick := float(w["thickness"])
	var sweep := float(w.get("sweep", 0.2))
	var dihedral := float(w.get("dihedral", 0.0))
	var le_bias := float(w.get("le_bias", 0.4))
	var tip := root + Vector3(span, 0, sweep * chord)
	if lod >= VisualLOD.LOD_BATCH:
		ShapePrims.box(st, root.lerp(tip, 0.45), Vector3(absf(span) * 0.9, thick, chord * 0.7), accent.darkened(0.1))
		return
	GeometryKernel.wing_planform(
		st, root, tip, chord, tip_chord, thick, accent.darkened(0.08), dihedral, le_bias
	)


static func _emit_hardpoint(st: SurfaceTool, hp: Dictionary, color: Color, accent: Color, lod: int) -> void:
	var pos: Vector3 = hp["pos"]
	var size: Vector3 = hp["size"]
	if lod >= VisualLOD.LOD_LOW:
		ShapePrims.box(st, pos, size * 0.7, accent.darkened(0.2))
		return
	var orient: Vector3 = hp.get("orient", Vector3(0, 0, -1))
	var role := str(hp.get("role", "gun"))
	GeometryKernel.hardpoint_shelf(st, pos, size, orient, color.darkened(0.05), accent.darkened(0.1), role)


static func _emit_module(
	st: SurfaceTool, m: Dictionary, accent: Color, color: Color, lod: int, exhaust: Color
) -> void:
	var t: String = str(m["type"])
	var pos: Vector3 = m["pos"]
	var size: Vector3 = m["size"]
	match t:
		"drill":
			ShapePrims.cylinder_z(st, pos + Vector3(0, 0, -size.z * 0.15), size.x * 0.22, size.z * 0.7, Color(0.35, 0.33, 0.28), 7)
			ShapePrims.box(st, pos, size * Vector3(0.85, 0.7, 0.55), Color(0.42, 0.38, 0.3))
			ShapePrims.box(st, pos + Vector3(0, -size.y * 0.2, -size.z * 0.4), Vector3(size.x * 0.55, size.y * 0.35, size.z * 0.25), Color(0.5, 0.45, 0.35))
		"boom":
			ShapePrims.cylinder_z(st, pos, size.x * 0.45, size.z, color.darkened(0.1), 6)
		"ore_bay", "cargo":
			if lod <= VisualLOD.LOD_SIMPLE:
				ShapePrims.pod(st, pos, size, accent, true)
			else:
				ShapePrims.pod(st, pos, size, accent, false)
		"spine":
			ShapePrims.spine(st, pos, size.z, size.x, size.y, color.darkened(0.05))
		"crane":
			ShapePrims.cylinder(st, pos - Vector3(0, size.y * 0.5, 0), size.x * 0.35, size.y, Color(0.4, 0.36, 0.3), 5)
			ShapePrims.box(st, pos + Vector3(size.x * 0.4, size.y * 0.2, 0), Vector3(size.x * 0.9, size.x * 0.25, size.x * 0.25), Color(0.38, 0.34, 0.28))
		"cockpit":
			if lod <= VisualLOD.LOD_FULL:
				GeometryKernel.cockpit_blister(st, pos, size, color.lightened(0.08), Color(0.4, 0.52, 0.62))
			else:
				ShapePrims.bevel_box(st, pos, size, color.lightened(0.12), 0.06)
		"fin":
			ShapePrims.fin(st, pos, size, accent.darkened(0.05))
		"sensor":
			var sensor_stations: Array = [
				GeometryKernel.station(pos.z - size.z * 0.4, size.x * 0.7, size.y * 0.7, pos.y, pos.x, "ngon", 6),
				GeometryKernel.station(pos.z + size.z * 0.4, size.x, size.y, pos.y, pos.x, "ngon", 6),
			]
			GeometryKernel.loft_hull(st, sensor_stations, Color(0.48, 0.52, 0.55), 0.12, 1, true, true)
			ShapePrims.box(st, pos + Vector3(0, size.y * 0.25, 0), Vector3(size.x * 0.35, size.y * 0.15, size.z * 0.35), exhaust.darkened(0.25))
		"mount":
			# Wing mount prism — structural mass with gap from core hull
			var mount_stations: Array = [
				GeometryKernel.station(pos.z - size.z * 0.45, size.x * 0.7, size.y * 0.75, pos.y, pos.x, "ngon", 6),
				GeometryKernel.station(pos.z + size.z * 0.1, size.x, size.y, pos.y, pos.x, "ngon", 6),
				GeometryKernel.station(pos.z + size.z * 0.45, size.x * 0.85, size.y * 0.7, pos.y, pos.x, "ngon", 6),
			]
			GeometryKernel.loft_hull(st, mount_stations, accent.darkened(0.12), 0.14, 1, true, true)
		_:
			ShapePrims.box(st, pos, size, accent)


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
