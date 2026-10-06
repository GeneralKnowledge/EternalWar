## Procedural ship mesh — ShapeLib-lite composition from class + style + design seed.
class_name ShipMeshGen
extends RefCounted

const STYLE_INDUSTRIAL := "industrial"
const STYLE_MILITARY := "military"
const STYLE_CIVILIAN := "civilian"
const STYLE_PIRATE := "pirate"
const STYLE_MINING := "mining"
const STYLE_LUXURY := "luxury"


static func build(design: Dictionary) -> ArrayMesh:
	var seed: int = int(design.get("seed", 1))
	var ship_class: int = int(design.get("ship_class", SimEntities.ShipClass.TRADER))
	var style: String = str(design.get("style", STYLE_CIVILIAN))
	var key := "ship:%d:%d:%s" % [seed, ship_class, style]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var dims: Dictionary = _class_dims(ship_class, rng, style)
	var length: float = float(dims["length"])
	var width: float = float(dims["width"])
	var height: float = float(dims["height"])
	var color: Color = design.get("color", Color(0.7, 0.75, 0.8))
	var accent: Color = design.get("accent", color.darkened(0.2))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var nose := 0.42 if style == STYLE_MILITARY or style == STYLE_PIRATE else 0.55
	if style == STYLE_INDUSTRIAL or style == STYLE_MINING:
		nose = 0.7
	ShapePrims.taper(st, Vector3.ZERO, Vector3(width, height, length), color, nose)
	ShapePrims.bevel_box(st, Vector3(0, height * 0.05, -length * 0.05), Vector3(width * 0.92, height * 0.85, length * 0.4), color.lightened(0.03), 0.06)

	# Engines aft
	var engine_count: int = int(dims["engines"])
	for i in engine_count:
		var t := 0.0
		if engine_count > 1:
			t = (float(i) / float(engine_count - 1) - 0.5) * width * 0.75
		var epos := Vector3(t, -height * 0.12, length * 0.48)
		ShapePrims.engine_bell(st, epos, width * 0.1, length * 0.2, accent)

	match ship_class:
		SimEntities.ShipClass.MINER:
			ShapePrims.box(st, Vector3(0, -height * 0.4, 0.05 * length), Vector3(width * 0.6, height * 0.3, length * 0.4), Color(0.45, 0.4, 0.32))
			ShapePrims.cylinder(st, Vector3(0, -height * 0.55, -length * 0.1), width * 0.12, height * 0.4, Color(0.35, 0.35, 0.3), 6)
			ShapePrims.mirrored_x(st, Vector3(width * 0.55, -height * 0.15, length * 0.05), Vector3(width * 0.25, height * 0.2, length * 0.2), accent.darkened(0.1))
		SimEntities.ShipClass.HAULER, SimEntities.ShipClass.TRADER:
			var cargo_n: int = int(dims["cargo"])
			for i in cargo_n:
				var side := 1.0 if i % 2 == 0 else -1.0
				var z := -length * 0.12 + float(i / 2) * length * 0.2
				ShapePrims.bevel_box(st, Vector3(side * width * 0.55, 0.0, z), Vector3(width * 0.38, height * 0.55, length * 0.16), accent, 0.05)
			if ship_class == SimEntities.ShipClass.HAULER:
				ShapePrims.box(st, Vector3(0, height * 0.35, length * 0.05), Vector3(width * 0.5, height * 0.2, length * 0.35), color.darkened(0.1))
		SimEntities.ShipClass.PATROL:
			ShapePrims.mirrored_x(st, Vector3(width * 0.4, height * 0.1, -length * 0.05), Vector3(width * 0.18, height * 0.12, length * 0.28), Color(0.85, 0.28, 0.22))
			ShapePrims.box(st, Vector3(0, height * 0.42, length * 0.05), Vector3(width * 0.22, height * 0.18, length * 0.18), color.lightened(0.12))
			ShapePrims.wing(st, Vector3(width * 0.45, 0, length * 0.05), width * 0.7, length * 0.35, height * 0.07, accent.darkened(0.1), 0.2)
			ShapePrims.wing(st, Vector3(-width * 0.45, 0, length * 0.05), -width * 0.7, length * 0.35, height * 0.07, accent.darkened(0.1), 0.2)

	if style == STYLE_MILITARY or style == STYLE_PIRATE:
		if ship_class != SimEntities.ShipClass.PATROL:
			var wing_w := width * rng.randf_range(0.7, 1.2)
			ShapePrims.wing(st, Vector3(wing_w * 0.4, 0, length * 0.02), wing_w * 0.55, length * 0.32, height * 0.08, accent.darkened(0.1), 0.18)
			ShapePrims.wing(st, Vector3(-wing_w * 0.4, 0, length * 0.02), -wing_w * 0.55, length * 0.32, height * 0.08, accent.darkened(0.1), 0.18)
	elif style == STYLE_LUXURY or style == STYLE_CIVILIAN:
		ShapePrims.bevel_box(st, Vector3(0, height * 0.42, -length * 0.02), Vector3(width * 0.42, height * 0.28, length * 0.28), color.lightened(0.18), 0.05)

	if style == STYLE_PIRATE:
		ShapePrims.box(st, Vector3(width * 0.55, height * 0.18, length * 0.08), Vector3(width * 0.35, height * 0.32, length * 0.18), Color(0.55, 0.25, 0.2))
	if style == STYLE_INDUSTRIAL or style == STYLE_MINING:
		for i in 3:
			var z := -length * 0.18 + float(i) * length * 0.16
			ShapePrims.box(st, Vector3(0, height * 0.5, z), Vector3(width * 0.95, height * 0.07, length * 0.07), color.darkened(0.18))

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh


static func describe(design: Dictionary) -> Dictionary:
	var rng := SeededRNG.new(int(design.get("seed", 1)))
	var ship_class: int = int(design.get("ship_class", 0))
	var style: String = str(design.get("style", ""))
	var dims := _class_dims(ship_class, rng, style)
	return {
		"seed": int(design.get("seed", 1)),
		"ship_class": ship_class,
		"style": style,
		"length": dims["length"],
		"width": dims["width"],
		"height": dims["height"],
		"engines": dims["engines"],
		"cargo_modules": dims["cargo"],
	}


static func _class_dims(ship_class: int, rng: SeededRNG, style: String = STYLE_CIVILIAN) -> Dictionary:
	var stretch := 1.0
	if style == STYLE_MILITARY:
		stretch = 1.08
	elif style == STYLE_LUXURY:
		stretch = 0.95
	elif style == STYLE_INDUSTRIAL or style == STYLE_MINING:
		stretch = 1.05
	match ship_class:
		SimEntities.ShipClass.MINER:
			return {
				"length": rng.randf_range(2.4, 3.2) * stretch,
				"width": rng.randf_range(1.25, 1.85),
				"height": rng.randf_range(0.95, 1.35),
				"engines": 2,
				"cargo": 2,
			}
		SimEntities.ShipClass.HAULER:
			return {
				"length": rng.randf_range(3.3, 4.4) * stretch,
				"width": rng.randf_range(1.65, 2.25),
				"height": rng.randf_range(1.25, 1.75),
				"engines": 3,
				"cargo": 6,
			}
		SimEntities.ShipClass.PATROL:
			return {
				"length": rng.randf_range(1.85, 2.5) * stretch,
				"width": rng.randf_range(1.0, 1.45),
				"height": rng.randf_range(0.48, 0.78),
				"engines": 2,
				"cargo": 0,
			}
		_:
			return {
				"length": rng.randf_range(2.2, 3.05) * stretch,
				"width": rng.randf_range(1.1, 1.65),
				"height": rng.randf_range(0.7, 1.1),
				"engines": 2,
				"cargo": 4,
			}
