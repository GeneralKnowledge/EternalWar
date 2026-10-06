## Modular procedural station from StationDesign graph (role → modules → geometry).
class_name StationMeshGen
extends RefCounted

const ROLE_MINING := "mining"
const ROLE_TRADE := "trade"
const ROLE_INDUSTRIAL := "industrial"
const ROLE_MILITARY := "military"
const ROLE_HABITAT := "habitat"


static func build(design: Dictionary, lod: int = VisualLOD.LOD_FULL) -> ArrayMesh:
	var seed: int = int(design.get("seed", 1))
	var role: String = str(design.get("role", ROLE_TRADE))
	var style: String = str(design.get("style", "industrial"))
	var key := "station:%d:%s:%s:lod%d" % [seed, role, style, lod]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var desc: Dictionary = StationDesign.build(design)
	var accent: Color = desc["color"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var include_connectors := lod <= VisualLOD.LOD_SIMPLE
	var include_extras := lod <= VisualLOD.LOD_LOW

	# Core + modules from graph
	for node in desc["nodes"]:
		var ntype: String = str(node["type"])
		var pos: Vector3 = node["pos"]
		var size: Vector3 = node["size"]
		match ntype:
			"core":
				ShapePrims.bevel_box(st, pos, size, accent, 0.08)
			"power", "command", "communications":
				ShapePrims.cylinder(st, pos - Vector3(0, size.y * 0.5, 0), size.x * 0.45, size.y, accent.lightened(0.08), 8)
			"docking":
				ShapePrims.bevel_box(st, pos, size, Color(0.82, 0.75, 0.4), 0.04)
				ShapePrims.box(st, pos + Vector3(0, 0, -size.z * 0.6), Vector3(0.28, 0.2, size.z), accent.darkened(0.05))
			"weapons", "armour":
				ShapePrims.box(st, pos, size, Color(0.72, 0.22, 0.22))
			"habitation":
				ShapePrims.bevel_box(st, pos, size, accent.lightened(0.12), 0.05)
			"factories", "manufacturing", "processing", "refinery":
				ShapePrims.bevel_box(st, pos, size, accent.darkened(0.1), 0.06)
				if include_extras:
					ShapePrims.cylinder(st, pos + Vector3(size.x * 0.3, size.y * 0.4, 0), 0.18, size.y * 0.8, Color(0.4, 0.4, 0.42), 6)
			_:
				ShapePrims.box(st, pos, size, accent.darkened(0.05))

	# Structural connectors (edges → thin beams)
	if include_connectors:
		for e in desc["edges"]:
			var a: Dictionary = (desc["nodes"] as Array)[int(e["from"])]
			var b: Dictionary = (desc["nodes"] as Array)[int(e["to"])]
			var mid: Vector3 = (a["pos"] + b["pos"]) * 0.5
			var delta: Vector3 = b["pos"] - a["pos"]
			var beam := Vector3(0.12, 0.12, maxf(delta.length(), 0.2))
			# Orient roughly along Z by placing box along average; good enough for silhouette
			ShapePrims.box(st, mid, Vector3(maxf(absf(delta.x), 0.12), maxf(absf(delta.y), 0.12), maxf(absf(delta.z), 0.12)), accent.darkened(0.35))

	if include_extras:
		for x in desc["extras"]:
			match str(x["type"]):
				"ring":
					ShapePrims.ring(st, Vector3(0, float(x.get("y", 0)), 0), float(x["radius"]), float(x["tube"]), accent.darkened(0.15), 12)
				"spine":
					ShapePrims.cylinder(st, Vector3(0, 0.5, 0), 0.22, float(x["height"]), accent.lightened(0.05), 8)

	# Style scaffolding
	if include_detail_style(style) and include_extras:
		var det := SeededRNG.new(int(desc["detail_seed"]))
		for i in 4:
			var a := float(i) * TAU * 0.25
			ShapePrims.box(st, Vector3(cos(a) * 1.15, det.randf_range(-0.4, 1.1), sin(a) * 1.15), Vector3(0.1, 1.5, 0.1), accent.darkened(0.35))

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh


static func include_detail_style(style: String) -> bool:
	return style == "industrial" or style == "pirate" or style == "mining"


static func describe(design: Dictionary) -> Dictionary:
	var desc := StationDesign.build(design)
	var types: Array = []
	for n in desc["nodes"]:
		types.append(str(n["type"]))
	return {
		"seed": int(desc["seed"]),
		"layout_seed": int(desc["layout_seed"]),
		"role": str(desc["role"]),
		"style": str(desc["style"]),
		"module_count": (desc["nodes"] as Array).size(),
		"modules": types,
		"edge_count": (desc["edges"] as Array).size(),
	}
