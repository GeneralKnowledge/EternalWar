## Procedural ship mesh from class + visual style + design seed.
## Inspired by LT ShipFighter / ShapeLib: hull + attached modules + symmetry,
## not unconstrained random boxes.
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
	var dims: Dictionary = _class_dims(ship_class, rng)
	var length: float = float(dims["length"])
	var width: float = float(dims["width"])
	var height: float = float(dims["height"])
	var color: Color = design.get("color", Color(0.7, 0.75, 0.8))
	var accent: Color = design.get("accent", color.darkened(0.2))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Main hull — tapered forward for silhouette.
	_hull(st, length, width, height, color, style, rng)

	# Engines aft
	var engine_count: int = int(dims["engines"])
	for i in engine_count:
		var t := 0.0
		if engine_count > 1:
			t = (float(i) / float(engine_count - 1) - 0.5) * width * 0.7
		var epos := Vector3(t, -height * 0.15, length * 0.48)
		_engine(st, epos, width * 0.12, height * 0.18, length * 0.18, accent)

	# Class-specific modules
	match ship_class:
		SimEntities.ShipClass.MINER:
			_box(st, Vector3(0, -height * 0.35, 0.05 * length), Vector3(width * 0.55, height * 0.25, length * 0.35), Color(0.45, 0.4, 0.32))
			_box(st, Vector3(0, -height * 0.5, -length * 0.15), Vector3(width * 0.2, height * 0.35, width * 0.2), Color(0.35, 0.35, 0.3))
		SimEntities.ShipClass.HAULER, SimEntities.ShipClass.TRADER:
			var cargo_n: int = int(dims["cargo"])
			for i in cargo_n:
				var side := 1.0 if i % 2 == 0 else -1.0
				var z := -length * 0.15 + float(i / 2) * length * 0.22
				_box(st, Vector3(side * width * 0.55, 0.0, z), Vector3(width * 0.35, height * 0.55, length * 0.18), accent)
		SimEntities.ShipClass.PATROL:
			_box(st, Vector3(width * 0.35, height * 0.15, -length * 0.1), Vector3(width * 0.15, height * 0.15, length * 0.25), Color(0.85, 0.3, 0.25))
			_box(st, Vector3(-width * 0.35, height * 0.15, -length * 0.1), Vector3(width * 0.15, height * 0.15, length * 0.25), Color(0.85, 0.3, 0.25))
			_box(st, Vector3(0, height * 0.45, length * 0.1), Vector3(width * 0.2, height * 0.2, length * 0.15), color.lightened(0.1))

	# Style wings / fins
	if style == STYLE_MILITARY or style == STYLE_PIRATE:
		var wing_w := width * rng.randf_range(0.8, 1.4)
		_box(st, Vector3(wing_w * 0.55, 0, length * 0.05), Vector3(wing_w, height * 0.08, length * 0.35), accent.darkened(0.1))
		_box(st, Vector3(-wing_w * 0.55, 0, length * 0.05), Vector3(wing_w, height * 0.08, length * 0.35), accent.darkened(0.1))
	elif style == STYLE_LUXURY or style == STYLE_CIVILIAN:
		_box(st, Vector3(0, height * 0.4, -length * 0.05), Vector3(width * 0.4, height * 0.25, length * 0.3), color.lightened(0.15))

	if style == STYLE_PIRATE:
		# Asymmetric scavenged pod
		_box(st, Vector3(width * 0.6, height * 0.2, length * 0.1), Vector3(width * 0.4, height * 0.35, length * 0.2), Color(0.55, 0.25, 0.2))

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh


static func describe(design: Dictionary) -> Dictionary:
	var rng := SeededRNG.new(int(design.get("seed", 1)))
	var ship_class: int = int(design.get("ship_class", 0))
	var dims := _class_dims(ship_class, rng)
	return {
		"seed": int(design.get("seed", 1)),
		"ship_class": ship_class,
		"style": str(design.get("style", "")),
		"length": dims["length"],
		"width": dims["width"],
		"height": dims["height"],
		"engines": dims["engines"],
		"cargo_modules": dims["cargo"],
	}


static func _class_dims(ship_class: int, rng: SeededRNG) -> Dictionary:
	match ship_class:
		SimEntities.ShipClass.MINER:
			return {
				"length": rng.randf_range(2.4, 3.2),
				"width": rng.randf_range(1.2, 1.8),
				"height": rng.randf_range(0.9, 1.3),
				"engines": 2,
				"cargo": 2,
			}
		SimEntities.ShipClass.HAULER:
			return {
				"length": rng.randf_range(3.2, 4.2),
				"width": rng.randf_range(1.6, 2.2),
				"height": rng.randf_range(1.2, 1.7),
				"engines": 3,
				"cargo": 6,
			}
		SimEntities.ShipClass.PATROL:
			return {
				"length": rng.randf_range(1.8, 2.4),
				"width": rng.randf_range(1.0, 1.4),
				"height": rng.randf_range(0.5, 0.8),
				"engines": 2,
				"cargo": 0,
			}
		_:
			return {
				"length": rng.randf_range(2.2, 3.0),
				"width": rng.randf_range(1.1, 1.6),
				"height": rng.randf_range(0.7, 1.1),
				"engines": 2,
				"cargo": 4,
			}


static func _hull(st: SurfaceTool, length: float, width: float, height: float, color: Color, style: String, rng: SeededRNG) -> void:
	var taper := 0.55 if style != STYLE_INDUSTRIAL else 0.75
	# Mid body
	_box(st, Vector3(0, 0, 0), Vector3(width, height, length * 0.55), color)
	# Nose
	_box(st, Vector3(0, 0, -length * 0.35), Vector3(width * taper, height * taper, length * 0.35), color.lightened(0.05))
	# Aft
	_box(st, Vector3(0, 0, length * 0.35), Vector3(width * 0.9, height * 0.85, length * 0.25), color.darkened(0.05))
	if style == STYLE_INDUSTRIAL or style == STYLE_MINING:
		# Extra plating ridges
		for i in 3:
			var z := -length * 0.2 + float(i) * length * 0.18
			_box(st, Vector3(0, height * 0.52, z), Vector3(width * 0.95, height * 0.08, length * 0.08), color.darkened(0.15))


static func _engine(st: SurfaceTool, pos: Vector3, w: float, h: float, depth: float, color: Color) -> void:
	_box(st, pos, Vector3(w, h, depth), color.darkened(0.2))
	_box(st, pos + Vector3(0, 0, depth * 0.45), Vector3(w * 0.7, h * 0.7, depth * 0.2), Color(0.4, 0.75, 1.0))


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var v := [
		center + Vector3(-hx, -hy, -hz),
		center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, hy, -hz),
		center + Vector3(-hx, hy, -hz),
		center + Vector3(-hx, -hy, hz),
		center + Vector3(hx, -hy, hz),
		center + Vector3(hx, hy, hz),
		center + Vector3(-hx, hy, hz),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(b)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(d)
