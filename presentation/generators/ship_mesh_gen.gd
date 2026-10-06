## Procedural ship mesh from ShipDesign grammar (role silhouette + style constraints).
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
	var key := "ship:%d:%d:%s:lod%d" % [seed, ship_class, style, lod]
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

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# LOD: skip detail modules at lower tiers
	var include_detail := lod <= VisualLOD.LOD_SIMPLE
	var include_wings := lod <= VisualLOD.LOD_LOW
	var include_engines := true

	ShapePrims.taper(st, Vector3.ZERO, Vector3(width, height, length), color, nose)
	if include_detail:
		ShapePrims.bevel_box(st, Vector3(0, height * 0.05, -length * 0.05), Vector3(width * 0.92, height * 0.85, length * 0.4), color.lightened(0.03), 0.06)

	if include_engines:
		for e in desc["engines"]:
			var ep: Vector3 = e["pos"]
			ShapePrims.engine_bell(st, ep, float(e["radius"]), float(e["length"]), accent)

	if include_detail or lod <= VisualLOD.LOD_LOW:
		for m in desc["modules"]:
			_emit_module(st, m, accent, color, lod)

	for hp in desc["hardpoints"]:
		ShapePrims.box(st, hp["pos"], hp["size"], Color(0.85, 0.28, 0.22))

	if include_wings:
		for w in desc["wings"]:
			ShapePrims.wing(st, w["root"], float(w["span"]), float(w["chord"]), float(w["thickness"]), accent.darkened(0.1), float(w["sweep"]))

	# Style plating ridges for industrial/mining
	if include_detail and (style == STYLE_INDUSTRIAL or style == STYLE_MINING):
		for i in 3:
			var z := -length * 0.18 + float(i) * length * 0.16
			ShapePrims.box(st, Vector3(0, height * 0.5, z), Vector3(width * 0.95, height * 0.07, length * 0.07), color.darkened(0.18))

	if include_detail and style == STYLE_PIRATE and not bool(desc["symmetric"]):
		ShapePrims.box(st, Vector3(width * 0.55, height * 0.18, length * 0.08), Vector3(width * 0.35, height * 0.32, length * 0.18), Color(0.55, 0.25, 0.2))

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
	}


static func _emit_module(st: SurfaceTool, m: Dictionary, accent: Color, color: Color, lod: int) -> void:
	var t: String = str(m["type"])
	var pos: Vector3 = m["pos"]
	var size: Vector3 = m["size"]
	match t:
		"drill":
			ShapePrims.cylinder(st, pos - Vector3(0, size.y * 0.5, 0), size.x * 0.25, size.y, Color(0.35, 0.35, 0.3), 6)
			ShapePrims.box(st, pos, size, Color(0.45, 0.4, 0.32))
		"ore_bay", "cargo", "spine":
			if lod <= VisualLOD.LOD_SIMPLE:
				ShapePrims.bevel_box(st, pos, size, accent, 0.05)
			else:
				ShapePrims.box(st, pos, size, accent)
		"crane":
			ShapePrims.cylinder(st, pos, size.x * 0.4, size.y, Color(0.4, 0.38, 0.32), 5)
		"cockpit", "fin":
			ShapePrims.bevel_box(st, pos, size, color.lightened(0.15), 0.04)
		"sensor":
			ShapePrims.box(st, pos, size, Color(0.6, 0.75, 0.9))
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
