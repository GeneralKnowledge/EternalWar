## Shared ShapeLib-lite primitives for procedural ships/stations.
## Boxes, bevelled boxes, tapers, cylinders, mirrored pairs — intentional composition, not noise.
class_name ShapePrims
extends RefCounted


static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	_box_corners(st, _corners(center, size), color)


static func bevel_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, bevel: float = 0.08) -> void:
	# Approximate bevel by drawing a slightly inset main box + thin edge ridges.
	var inner := size - Vector3.ONE * minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.25)
	inner = Vector3(maxf(inner.x, size.x * 0.7), maxf(inner.y, size.y * 0.7), maxf(inner.z, size.z * 0.7))
	box(st, center, inner, color)
	var edge := color.lightened(0.08)
	box(st, center + Vector3(0, size.y * 0.48, 0), Vector3(size.x * 0.98, size.y * 0.06, size.z * 0.98), edge)
	box(st, center + Vector3(0, -size.y * 0.48, 0), Vector3(size.x * 0.98, size.y * 0.06, size.z * 0.98), edge.darkened(0.05))


static func taper(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, nose_scale: float = 0.45) -> void:
	# Two-segment tapered hull along -Z (nose) → +Z (aft).
	var mid := size
	box(st, center, Vector3(mid.x, mid.y, mid.z * 0.55), color)
	box(st, center + Vector3(0, 0, -size.z * 0.32), Vector3(size.x * nose_scale, size.y * nose_scale, size.z * 0.35), color.lightened(0.04))
	box(st, center + Vector3(0, 0, size.z * 0.32), Vector3(size.x * 0.88, size.y * 0.82, size.z * 0.28), color.darkened(0.05))


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
		# Caps
		_tri(st, base, p1, p0, color.darkened(0.05))
		_tri(st, top, p3, p2, color.lightened(0.05))


static func engine_bell(st: SurfaceTool, pos: Vector3, radius: float, length: float, color: Color) -> void:
	cylinder(st, pos - Vector3(0, 0, length * 0.15), radius * 0.7, length * 0.05, color.darkened(0.15), 8)
	# Orient bell along +Z by stacking scaled boxes (cheap nozzle flare).
	box(st, pos, Vector3(radius * 1.1, radius * 1.1, length * 0.55), color.darkened(0.2))
	box(st, pos + Vector3(0, 0, length * 0.35), Vector3(radius * 1.45, radius * 1.45, length * 0.25), color.darkened(0.1))
	box(st, pos + Vector3(0, 0, length * 0.55), Vector3(radius * 0.85, radius * 0.85, length * 0.18), Color(0.35, 0.7, 1.0))


static func mirrored_x(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	box(st, center, size, color)
	box(st, Vector3(-center.x, center.y, center.z), size, color)


static func wing(st: SurfaceTool, root: Vector3, span: float, chord: float, thickness: float, color: Color, sweep: float = 0.15) -> void:
	# Sweep tip aft (+Z).
	var tip := root + Vector3(span, 0, sweep * chord)
	box(st, root.lerp(tip, 0.35), Vector3(span * 0.7, thickness, chord), color)
	box(st, tip, Vector3(span * 0.35, thickness * 0.7, chord * 0.65), color.darkened(0.08))


static func ring(st: SurfaceTool, center: Vector3, radius: float, tube: float, color: Color, segments: int = 12) -> void:
	var seg := maxi(segments, 6)
	for i in seg:
		var a := float(i) / float(seg) * TAU
		var p := center + Vector3(cos(a) * radius, 0, sin(a) * radius)
		box(st, p, Vector3(tube, tube, tube * 1.4), color)


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
