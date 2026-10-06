## Shared ShapeLib-lite primitives for procedural ships/stations.
## Inspired by LT Gen.ShapeLib principles (prism, extrude taper, bevel, mirror)
## — independently implemented; no LT code copied.
class_name ShapePrims
extends RefCounted


static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	_box_corners(st, _corners(center, size), color)


static func bevel_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, bevel: float = 0.08) -> void:
	var inner := size - Vector3.ONE * minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.25)
	inner = Vector3(maxf(inner.x, size.x * 0.7), maxf(inner.y, size.y * 0.7), maxf(inner.z, size.z * 0.7))
	box(st, center, inner, color)
	var edge := color.lightened(0.08)
	box(st, center + Vector3(0, size.y * 0.48, 0), Vector3(size.x * 0.98, size.y * 0.06, size.z * 0.98), edge)
	box(st, center + Vector3(0, -size.y * 0.48, 0), Vector3(size.x * 0.98, size.y * 0.06, size.z * 0.98), edge.darkened(0.05))


## LT-style prism hull: N-gon extruded along Z with nose taper (pointiness).
static func prism_hull(
	st: SurfaceTool,
	center: Vector3,
	length: float,
	width: float,
	height: float,
	color: Color,
	sides: int = 6,
	nose_taper: float = 0.45,
	aft_taper: float = 0.85
) -> void:
	var seg := clampi(sides, 3, 16)
	var hz := length * 0.5
	var nose_z := center.z - hz
	var aft_z := center.z + hz
	var mid_z := center.z + hz * 0.15
	var nose_rx := width * 0.5 * nose_taper
	var nose_ry := height * 0.5 * nose_taper
	var mid_rx := width * 0.5
	var mid_ry := height * 0.5
	var aft_rx := width * 0.5 * aft_taper
	var aft_ry := height * 0.5 * aft_taper
	_ring_cap(st, Vector3(center.x, center.y, nose_z), nose_rx, nose_ry, seg, color.lightened(0.05), true)
	_ring_bridge(st, Vector3(center.x, center.y, nose_z), nose_rx, nose_ry, Vector3(center.x, center.y, mid_z), mid_rx, mid_ry, seg, color)
	_ring_bridge(st, Vector3(center.x, center.y, mid_z), mid_rx, mid_ry, Vector3(center.x, center.y, aft_z), aft_rx, aft_ry, seg, color.darkened(0.04))
	_ring_cap(st, Vector3(center.x, center.y, aft_z), aft_rx, aft_ry, seg, color.darkened(0.08), false)


## Compact rounded hull (more sides, milder taper) — luxury / civilian.
static func rounded_hull(
	st: SurfaceTool, center: Vector3, length: float, width: float, height: float, color: Color, nose_taper: float = 0.55
) -> void:
	prism_hull(st, center, length, width, height, color, 10, nose_taper, 0.9)


## Blocky industrial hull — fewer sides, blunt nose.
static func block_hull(
	st: SurfaceTool, center: Vector3, length: float, width: float, height: float, color: Color
) -> void:
	prism_hull(st, center, length, width, height, color, 4, 0.72, 0.95)
	box(st, center + Vector3(0, height * 0.08, 0), Vector3(width * 0.92, height * 0.55, length * 0.7), color.darkened(0.06))


## Thin structural spine connecting separated modules (capital / hauler).
static func spine(st: SurfaceTool, center: Vector3, length: float, width: float, height: float, color: Color) -> void:
	box(st, center, Vector3(width, height, length), color)
	box(st, center + Vector3(0, height * 0.55, 0), Vector3(width * 1.15, height * 0.18, length * 0.92), color.lightened(0.04))


## Cargo / equipment pod with optional gap from hull (negative space).
static func pod(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, rounded: bool = false) -> void:
	if rounded:
		bevel_box(st, center, size, color, 0.1)
	else:
		box(st, center, size, color)


## Connecting strut between two points (approximate with thin box).
static func strut(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var mid := a.lerp(b, 0.5)
	var delta := b - a
	var len := maxf(delta.length(), 0.01)
	var size := Vector3(thickness, thickness, len)
	# Align local Z to delta via approximate axis boxes (good enough at ship scale).
	if absf(delta.x) > absf(delta.y) and absf(delta.x) > absf(delta.z):
		size = Vector3(len, thickness, thickness)
	elif absf(delta.y) > absf(delta.z):
		size = Vector3(thickness, len, thickness)
	box(st, mid, size, color)


## Flat wing plate extruded from root (LT WingsStandard principle).
static func wing_plate(
	st: SurfaceTool,
	root: Vector3,
	span: float,
	chord: float,
	thickness: float,
	color: Color,
	sweep: float = 0.2,
	tip_scale: float = 0.35
) -> void:
	var tip := root + Vector3(span, 0, sweep * chord)
	box(st, root.lerp(tip, 0.3), Vector3(absf(span) * 0.55, thickness, chord), color)
	box(st, tip, Vector3(absf(span) * tip_scale, thickness * 0.65, chord * 0.7), color.darkened(0.08))
	# Pointy tip extrusion
	box(st, tip + Vector3(signf(span) * absf(span) * 0.12, 0, sweep * chord * 0.15), Vector3(absf(span) * 0.12, thickness * 0.35, chord * 0.35), color.darkened(0.12))


## Engine nacelle body + flared bell. Exhaust colour is a parameter (not hard-coded blue).
static func nacelle(
	st: SurfaceTool,
	pos: Vector3,
	radius: float,
	length: float,
	body_color: Color,
	exhaust: Color
) -> void:
	box(st, pos - Vector3(0, 0, length * 0.1), Vector3(radius * 1.5, radius * 1.5, length * 0.45), body_color.darkened(0.15))
	cylinder_z(st, pos, radius * 0.85, length * 0.35, body_color.darkened(0.2), 8)
	# Flare
	box(st, pos + Vector3(0, 0, length * 0.28), Vector3(radius * 1.55, radius * 1.55, length * 0.18), body_color.darkened(0.05))
	# Exhaust core (emissive cue via bright vertex colour)
	box(st, pos + Vector3(0, 0, length * 0.42), Vector3(radius * 0.9, radius * 0.9, length * 0.14), exhaust)


static func engine_bell(st: SurfaceTool, pos: Vector3, radius: float, length: float, color: Color, exhaust: Color = Color(-1, -1, -1)) -> void:
	var ex := exhaust if exhaust.r >= 0.0 else color.lightened(0.35)
	nacelle(st, pos, radius, length, color, ex)


static func cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, segments: int = 8) -> void:
	var top := base + Vector3(0, height, 0)
	var seg := maxi(segments, 4)
	for i in seg:
		var a0 := float(i) / float(seg) * TAU
		var a1 := float(i + 1) / float(seg) * TAU
		var p0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var p2 := top + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var p3 := top + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		_tri(st, p0, p1, p2, color)
		_tri(st, p0, p2, p3, color)
		_tri(st, base, p1, p0, color.darkened(0.05))
		_tri(st, top, p3, p2, color.lightened(0.05))


## Cylinder along +Z (engine / boom axis).
static func cylinder_z(st: SurfaceTool, center: Vector3, radius: float, length: float, color: Color, segments: int = 8) -> void:
	var seg := maxi(segments, 4)
	var z0 := center.z - length * 0.5
	var z1 := center.z + length * 0.5
	for i in seg:
		var a0 := float(i) / float(seg) * TAU
		var a1 := float(i + 1) / float(seg) * TAU
		var p0 := Vector3(center.x + cos(a0) * radius, center.y + sin(a0) * radius, z0)
		var p1 := Vector3(center.x + cos(a1) * radius, center.y + sin(a1) * radius, z0)
		var p2 := Vector3(center.x + cos(a1) * radius, center.y + sin(a1) * radius, z1)
		var p3 := Vector3(center.x + cos(a0) * radius, center.y + sin(a0) * radius, z1)
		_tri(st, p0, p1, p2, color)
		_tri(st, p0, p2, p3, color)


static func wing(st: SurfaceTool, root: Vector3, span: float, chord: float, thickness: float, color: Color, sweep: float = 0.15) -> void:
	wing_plate(st, root, span, chord, thickness, color, sweep, 0.35)


static func fin(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	box(st, center, size, color)
	box(st, center + Vector3(0, size.y * 0.35, -size.z * 0.1), Vector3(size.x * 0.6, size.y * 0.35, size.z * 0.55), color.darkened(0.08))


static func panel(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	box(st, center, size, color)


static func ring(st: SurfaceTool, center: Vector3, radius: float, tube: float, color: Color, segments: int = 12) -> void:
	var seg := maxi(segments, 6)
	for i in seg:
		var a := float(i) / float(seg) * TAU
		var p := center + Vector3(cos(a) * radius, 0, sin(a) * radius)
		box(st, p, Vector3(tube, tube, tube * 1.4), color)


static func mirrored_x(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	box(st, center, size, color)
	box(st, Vector3(-center.x, center.y, center.z), size, color)


static func taper(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, nose_scale: float = 0.45) -> void:
	# Legacy entry — route to prism hull for LT-like silhouette.
	prism_hull(st, center, size.z, size.x, size.y, color, 6, nose_scale, 0.88)


static func _ring_points(center: Vector3, rx: float, ry: float, sides: int) -> Array:
	var pts: Array = []
	for i in sides:
		var a := float(i) / float(sides) * TAU + PI * 0.5
		pts.append(center + Vector3(cos(a) * rx, sin(a) * ry, 0))
	return pts


static func _ring_bridge(
	st: SurfaceTool,
	c0: Vector3, rx0: float, ry0: float,
	c1: Vector3, rx1: float, ry1: float,
	sides: int, color: Color
) -> void:
	for i in sides:
		var a0 := float(i) / float(sides) * TAU + PI * 0.5
		var a1 := float(i + 1) / float(sides) * TAU + PI * 0.5
		var p0 := c0 + Vector3(cos(a0) * rx0, sin(a0) * ry0, 0)
		var p1 := c0 + Vector3(cos(a1) * rx0, sin(a1) * ry0, 0)
		var p2 := c1 + Vector3(cos(a1) * rx1, sin(a1) * ry1, 0)
		var p3 := c1 + Vector3(cos(a0) * rx1, sin(a0) * ry1, 0)
		_quad(st, p0, p1, p2, p3, color)


static func _ring_cap(st: SurfaceTool, center: Vector3, rx: float, ry: float, sides: int, color: Color, nose: bool) -> void:
	for i in sides:
		var a0 := float(i) / float(sides) * TAU + PI * 0.5
		var a1 := float(i + 1) / float(sides) * TAU + PI * 0.5
		var p0 := center + Vector3(cos(a0) * rx, sin(a0) * ry, 0)
		var p1 := center + Vector3(cos(a1) * rx, sin(a1) * ry, 0)
		if nose:
			_tri(st, center, p1, p0, color)
		else:
			_tri(st, center, p0, p1, color)


static func _corners(center: Vector3, size: Vector3) -> Array:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	return [
		center + Vector3(-hx, -hy, -hz),
		center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, hy, -hz),
		center + Vector3(-hx, hy, -hz),
		center + Vector3(-hx, -hy, hz),
		center + Vector3(hx, -hy, hz),
		center + Vector3(hx, hy, hz),
		center + Vector3(-hx, hy, hz),
	]


static func _box_corners(st: SurfaceTool, v: Array, color: Color) -> void:
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], color)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		n = Vector3.UP
	else:
		n = n.normalized()
	st.set_normal(n)
	st.set_color(color)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(color)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(color)
	st.add_vertex(c)
