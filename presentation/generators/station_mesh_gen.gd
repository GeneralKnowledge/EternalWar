## Modular procedural station — architectural kits by role + faction style.
class_name StationMeshGen
extends RefCounted

const ROLE_MINING := "mining"
const ROLE_TRADE := "trade"
const ROLE_INDUSTRIAL := "industrial"
const ROLE_MILITARY := "military"
const ROLE_HABITAT := "habitat"


static func build(design: Dictionary) -> ArrayMesh:
	var seed: int = int(design.get("seed", 1))
	var role: String = str(design.get("role", ROLE_TRADE))
	var style: String = str(design.get("style", "industrial"))
	var key := "station:%d:%s:%s" % [seed, role, style]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var accent: Color = design.get("color", Color(0.6, 0.65, 0.7))
	var spine_h := rng.randf_range(1.8, 2.6)
	if style == "military":
		spine_h *= 1.15
	elif style == "civilian" or style == "luxury":
		spine_h *= 0.9

	# Central spine / habitat core
	ShapePrims.bevel_box(st, Vector3.ZERO, Vector3(1.15, 1.1, 1.15), accent, 0.08)
	ShapePrims.cylinder(st, Vector3(0, 0.55, 0), 0.28, spine_h, accent.lightened(0.08), 8)
	ShapePrims.box(st, Vector3(0, 0.55 + spine_h, 0), Vector3(0.55, 0.35, 0.55), accent.lightened(0.12))

	match role:
		ROLE_MINING:
			ShapePrims.mirrored_x(st, Vector3(1.7, 0, 0), Vector3(1.5, 0.75, 1.0), accent.darkened(0.15))
			ShapePrims.box(st, Vector3(0, -0.25, 2.0), Vector3(0.9, 0.55, 1.7), Color(0.45, 0.4, 0.3))
			for i in 4:
				var y := -0.7 - float(i) * 0.5
				ShapePrims.cylinder(st, Vector3(0, y, 2.55), 0.18, 0.35, Color(0.35, 0.32, 0.28), 6)
			ShapePrims.ring(st, Vector3(0, -0.2, 0), 2.4, 0.18, accent.darkened(0.25), 10)
		ROLE_TRADE:
			ShapePrims.ring(st, Vector3.ZERO, 2.15, 0.28, accent.darkened(0.15), 12)
			for i in 4:
				var a := float(i) * TAU * 0.25 + 0.15
				var p := Vector3(cos(a) * 2.05, 0.15, sin(a) * 2.05)
				ShapePrims.bevel_box(st, p, Vector3(0.95, 0.5, 0.95), accent.lightened(0.05), 0.05)
			ShapePrims.box(st, Vector3(0, 0.05, 0), Vector3(2.5, 0.22, 2.5), accent.darkened(0.2))
		ROLE_INDUSTRIAL:
			ShapePrims.mirrored_x(st, Vector3(1.9, 0.25, 0), Vector3(1.7, 1.5, 1.15), accent.darkened(0.1))
			ShapePrims.box(st, Vector3(0, 0, 2.1), Vector3(1.1, 0.85, 1.4), Color(0.5, 0.45, 0.4))
			for i in 3:
				ShapePrims.cylinder(st, Vector3(1.0 + float(i) * 0.55, 1.4, 0.7), 0.18, 1.35, Color(0.4, 0.4, 0.42), 6)
			ShapePrims.ring(st, Vector3(0, 0.8, 0), 1.6, 0.12, accent.darkened(0.3), 8)
		ROLE_MILITARY:
			ShapePrims.bevel_box(st, Vector3(0, 0, 0), Vector3(1.7, 0.75, 2.4), accent.darkened(0.25), 0.06)
			for i in 3:
				var z := -1.25 + float(i) * 1.15
				ShapePrims.mirrored_x(st, Vector3(1.55, 0.35, z), Vector3(0.55, 0.4, 0.55), Color(0.72, 0.22, 0.22))
			ShapePrims.box(st, Vector3(0, 2.15, 0), Vector3(0.55, 1.0, 0.55), accent)
			ShapePrims.wing(st, Vector3(1.2, 0, 0.2), 1.1, 1.4, 0.12, accent.darkened(0.2), 0.1)
			ShapePrims.wing(st, Vector3(-1.2, 0, 0.2), -1.1, 1.4, 0.12, accent.darkened(0.2), 0.1)
		_:
			ShapePrims.ring(st, Vector3(0, 0.4, 0), 1.9, 0.35, accent.lightened(0.1), 14)
			ShapePrims.mirrored_x(st, Vector3(1.5, 0.35, 0), Vector3(1.05, 1.15, 1.05), accent.lightened(0.12))
			ShapePrims.box(st, Vector3(0, 0.55, 1.7), Vector3(1.25, 0.95, 0.85), accent)

	# Docking arm
	var dock_len := rng.randf_range(1.5, 2.4)
	ShapePrims.box(st, Vector3(0, -1.0, dock_len * 0.5), Vector3(0.32, 0.22, dock_len), accent.darkened(0.05))
	ShapePrims.bevel_box(st, Vector3(0, -1.0, dock_len), Vector3(1.0, 0.45, 0.55), Color(0.82, 0.75, 0.4), 0.04)

	if style == "industrial" or style == "pirate" or style == "mining":
		for i in 4:
			var a := float(i) * TAU * 0.25
			ShapePrims.box(st, Vector3(cos(a) * 1.15, rng.randf_range(-0.4, 1.1), sin(a) * 1.15), Vector3(0.1, 1.5, 0.1), accent.darkened(0.35))
	elif style == "luxury" or style == "civilian":
		ShapePrims.ring(st, Vector3(0, 1.2, 0), 1.2, 0.1, accent.lightened(0.2), 10)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh
