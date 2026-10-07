## Limit Theory ShipCapital.Sausage — ShapeLib port.
## Sources: ShipCapital.lua, ShipLib/ShipCapitalHull.lua, ShipDetail.lua, ShipCapitalCockpit.lua
## Cockpit/detail attachment uses AABB placement (LT uses ray addAtIntersection).
class_name ShapeLibShipCapital
extends RefCounted


static func sausage(seed: int) -> ShapeLibShape:
	var rng := SeededRNG.new(seed)
	var shape := ShapeLibShape.new()
	var segments := rng.randi_range(1, 3)
	shape.add_shape(hull(rng))
	for _i in range(1, segments):
		var seg := hull(rng)
		if rng.randf() < 0.5:
			shape.add_shape(seg)
		else:
			var aabb: Dictionary = shape.get_aabb()
			var upper: Vector3 = aabb["upper"]
			seg.translate_xyz(0.0, 0.0, upper.z)
			shape.add_shape(seg)
	if rng.randf() < 0.5:
		var aabb2: Dictionary = shape.get_aabb()
		var lo: Vector3 = aabb2["lower"]
		var hi: Vector3 = aabb2["upper"]
		var cp := cockpit_large(rng)
		var cz := absf(hi.z - lo.z) * 0.2 + lo.z
		var mid_y := (hi.y + lo.y) * 0.5
		cp.translate_xyz(0.0, hi.y - mid_y * 0.15, cz)
		shape.add_shape(cp)
	if rng.randf() < 0.5:
		var plate := detail_plate(rng)
		var aabb3: Dictionary = shape.get_aabb()
		var lo3: Vector3 = aabb3["lower"]
		var hi3: Vector3 = aabb3["upper"]
		plate.scale_xyz(0.5 * absf(hi3.x - lo3.x), 1.0, 0.3 * absf(hi3.z - lo3.z))
		plate.center_at(0.0, hi3.y * 0.55, 0.0)
		shape.center_at()
		shape.add_shape(plate)
	shape.scale_xyz(rng.randf_range(0.5, 1.5), rng.randf_range(0.5, 1.5), 1.0)
	var r := shape.get_radius()
	if r > 1e-4:
		var s := 4.5 / r
		shape.scale_xyz(s, s, s)
	return shape


static func sausage_mesh(seed: int, hull_color: Color = Color(0.4, 0.38, 0.36)) -> ArrayMesh:
	return sausage(seed).finalize_mesh(hull_color)


static func hull(rng: SeededRNG) -> ShapeLibShape:
	var shape: ShapeLibShape
	if rng.randf() < 0.5:
		shape = ShapeLibBasic.box(0)
	else:
		var sides: int = int(rng.choose([3, 5, 6, 8, 20, 30]))
		shape = ShapeLibBasic.prism(2, sides)
		shape.scale_xyz(2, 2, 2)
		shape.rotate_ypr(0.0, PI * 0.5, 0.0)
		if sides % 2 != 0:
			shape.rotate_ypr(0.0, 0.0, PI * 0.5)
	var segments := rng.randi_range(1, 3)
	for _i in range(segments + 1):
		var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
		var pi := shape.get_poly_with_normal(Vector3(0, 0, dir))
		if pi < 0:
			continue
		var extrusion_length := rng.randf_range(0.2, 3.0)
		var extrusion_size := Vector3(rng.randf_range(0.2, 1.5), rng.randf_range(1.0, 1.5), 1.0)
		var extrusion_angle := rng.randf_range(PI - 0.2, PI + 0.2)
		var ed := Vector3(0.0, sin(extrusion_angle), -dir * cos(extrusion_angle))
		shape.extrude_poly(pi, extrusion_length, extrusion_size, ed)
	# Side detail extrudes (non-prism bases)
	if shape.polys.size() > 2 and rng.randf() < 0.55:
		var np := rng.randi_range(0, 4)
		for _j in np:
			var up := shape.get_poly_with_normal(Vector3(0, 1, 0))
			var dn := shape.get_poly_with_normal(Vector3(0, -1, 0))
			var pick := up if rng.randf() < 0.5 else dn
			if pick >= 0:
				shape.extrude_poly(pick, rng.randf_range(0.2, 1.0))
	return shape


static func detail_plate(rng: SeededRNG) -> ShapeLibShape:
	var shape := ShapeLibBasic.box(0)
	shape.scale_xyz(1.0, 0.2, 1.0)
	var n := rng.randi_range(1, 4)
	for _i in n:
		var zdir: float = 1.0 if rng.randf() < 0.5 else -1.0
		var pi := shape.get_poly_with_normal(Vector3(0, 0, zdir))
		if pi < 0:
			continue
		var scale := Vector3(rng.randf_range(0.2, 1.4), 1.0, 1.0)
		shape.extrude_poly(pi, rng.randf_range(0.2, 2.0), scale)
	return shape


static func cockpit_large(rng: SeededRNG) -> ShapeLibShape:
	var shape := hull(rng)
	var aabb: Dictionary = shape.get_aabb()
	var lo: Vector3 = aabb["lower"]
	var hi: Vector3 = aabb["upper"]
	var box := ShapeLibBasic.box(0)
	box.scale_xyz(absf(hi.x - lo.x) * 0.25, 2.0, 0.25 * absf(hi.z - lo.z))
	box.center_at(0.0, -1.8, 0.0)
	shape.add_shape(box)
	shape.scale_xyz(rng.randf_range(0.2, 0.5))
	aabb = shape.get_aabb()
	lo = aabb["lower"]
	hi = aabb["upper"]
	shape.center_at(0.0, 0.4 * absf(hi.y - lo.y), 0.0)
	return shape
