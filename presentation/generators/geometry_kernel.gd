## Geometric construction kernel — lofted hulls, planform wings, structural engines.
## Semantic names stay in ShapePrims / ShipMeshGen; this file owns real mesh ops.
## Inspired by LT ShapeLib (prism → extrude → bevel → mirror) — no LT code copied.
class_name GeometryKernel
extends RefCounted


## Corner-chamfer a convex (or mild non-convex) XY profile. Amount is fraction of edge length.
## Returns PackedVector2Array of beveled outline (more verts than input).
static func bevel_profile(pts: PackedVector2Array, amount: float, segments: int = 1) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or amount <= 1e-5:
		return pts
	var seg := clampi(segments, 1, 4)
	var out := PackedVector2Array()
	for i in n:
		var prev: Vector2 = pts[(i - 1 + n) % n]
		var cur: Vector2 = pts[i]
		var nxt: Vector2 = pts[(i + 1) % n]
		var d0 := cur - prev
		var d1 := nxt - cur
		var l0 := d0.length()
		var l1 := d1.length()
		if l0 < 1e-8 or l1 < 1e-8:
			out.append(cur)
			continue
		var cut := minf(amount * minf(l0, l1), minf(l0, l1) * 0.45)
		var a := cur - d0.normalized() * cut
		var b := cur + d1.normalized() * cut
		out.append(a)
		for s in seg:
			if s == 0:
				continue
			var t := float(s) / float(seg)
			# Quadratic-ish corner: lerp through a shortened apex for soft bevel
			var mid := a.lerp(b, t).lerp(cur, 0.35 * (1.0 - absf(t - 0.5) * 2.0))
			if s < seg:
				out.append(mid)
		out.append(b)
	return out


## Regular N-gon (or flattened) profile in XY, optionally corner-beveled.
static func ngon_profile(sides: int, rx: float, ry: float, bevel: float = 0.0, bevel_segs: int = 1) -> PackedVector2Array:
	var seg := clampi(sides, 3, 24)
	var pts := PackedVector2Array()
	for i in seg:
		var a := float(i) / float(seg) * TAU + PI * 0.5
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	if bevel > 0.0:
		return bevel_profile(pts, clampf(bevel, 0.0, 0.45), bevel_segs)
	return pts


## Wedge / flattened hex fighter profile — wider on sides, flatter top/bottom.
static func fighter_profile(rx: float, ry: float, bevel: float = 0.18, bevel_segs: int = 1) -> PackedVector2Array:
	# Non-uniform hex: shoulders + flat deck (reads as LT prism, not ellipse).
	var raw := PackedVector2Array([
		Vector2(0.0, ry),
		Vector2(rx * 0.72, ry * 0.55),
		Vector2(rx, 0.0),
		Vector2(rx * 0.72, -ry * 0.65),
		Vector2(0.0, -ry),
		Vector2(-rx * 0.72, -ry * 0.65),
		Vector2(-rx, 0.0),
		Vector2(-rx * 0.72, ry * 0.55),
	])
	if bevel > 0.0:
		return bevel_profile(raw, clampf(bevel, 0.0, 0.4), bevel_segs)
	return raw


## Station descriptor helper.
static func station(z: float, width: float, height: float, y_off: float = 0.0, x_off: float = 0.0, profile: String = "fighter", sides: int = 6) -> Dictionary:
	return {
		"z": z,
		"width": width,
		"height": height,
		"y_offset": y_off,
		"x_offset": x_off,
		"profile": profile,
		"sides": sides,
	}


## Loft a hull through longitudinal stations. Each station has width/height/offsets.
## bevel_amount / bevel_segs control profile corner chamfer (LOD-cost knob).
static func loft_hull(
	st: SurfaceTool,
	stations: Array,
	color: Color,
	bevel_amount: float = 0.18,
	bevel_segs: int = 1,
	cap_nose: bool = true,
	cap_aft: bool = true
) -> void:
	if stations.size() < 2:
		return
	var rings: Array = []
	for s in stations:
		var sd: Dictionary = s
		var rx := float(sd["width"]) * 0.5
		var ry := float(sd["height"]) * 0.5
		var cx := float(sd.get("x_offset", 0.0))
		var cy := float(sd.get("y_offset", 0.0))
		var cz := float(sd["z"])
		var prof := str(sd.get("profile", "fighter"))
		var sides := int(sd.get("sides", 6))
		var local_bevel := float(sd.get("bevel", bevel_amount))
		var pts: PackedVector2Array
		match prof:
			"ngon", "prism":
				pts = ngon_profile(sides, rx, ry, local_bevel, bevel_segs)
			"box":
				pts = ngon_profile(4, rx, ry, local_bevel, bevel_segs)
			"round":
				pts = ngon_profile(maxi(sides, 10), rx, ry, local_bevel * 0.5, bevel_segs)
			_:
				pts = fighter_profile(rx, ry, local_bevel, bevel_segs)
		var ring: PackedVector3Array = PackedVector3Array()
		for p in pts:
			ring.append(Vector3(cx + p.x, cy + p.y, cz))
		rings.append(ring)

	# Caps
	if cap_nose:
		_cap_ring(st, rings[0], color.lightened(0.04), true)
	if cap_aft:
		_cap_ring(st, rings[rings.size() - 1], color.darkened(0.08), false)

	# Bridges — slight darkening aft for material boundary cue
	for i in rings.size() - 1:
		var t := float(i) / float(maxi(rings.size() - 2, 1))
		var c := color.lerp(color.darkened(0.06), t * 0.5)
		_bridge_rings(st, rings[i], rings[i + 1], c)


## Trapezoidal wing planform with thickness (not stacked boxes).
## root/tip are mid-chord centers; chords along +Z; span along sign of (tip.x - root.x).
static func wing_planform(
	st: SurfaceTool,
	root: Vector3,
	tip: Vector3,
	root_chord: float,
	tip_chord: float,
	thickness: float,
	color: Color,
	dihedral: float = 0.0,
	le_bias: float = 0.35
) -> void:
	var rc := maxf(root_chord, 0.02)
	var tc := maxf(tip_chord, 0.01)
	var th := maxf(thickness, 0.008)
	# Leading-edge bias: fraction of chord ahead of mid (0.5 = centered)
	var r_le := root + Vector3(0, 0, -rc * le_bias)
	var r_te := root + Vector3(0, 0, rc * (1.0 - le_bias))
	var tip_adj := tip + Vector3(0, sin(dihedral) * (tip - root).length(), 0)
	var t_le := tip_adj + Vector3(0, 0, -tc * le_bias)
	var t_te := tip_adj + Vector3(0, 0, tc * (1.0 - le_bias))
	var up := Vector3(0, th * 0.5, 0)
	# Upper / lower quads
	var ru0 := r_le + up
	var ru1 := r_te + up
	var tu0 := t_le + up
	var tu1 := t_te + up
	var rl0 := r_le - up
	var rl1 := r_te - up
	var tl0 := t_le - up
	var tl1 := t_te - up
	_quad(st, ru0, tu0, tu1, ru1, color) # upper
	_quad(st, rl0, rl1, tl1, tl0, color.darkened(0.06)) # lower
	_quad(st, ru0, ru1, rl1, rl0, color.darkened(0.04)) # root
	_quad(st, tu0, tl0, tl1, tu1, color.darkened(0.1)) # tip
	_quad(st, ru0, rl0, tl0, tu0, color.lightened(0.03)) # leading
	_quad(st, ru1, tu1, tl1, rl1, color.darkened(0.08)) # trailing


## Structural engine housing + recessed exhaust (geometry first, colour second).
static func engine_block(
	st: SurfaceTool,
	pos: Vector3,
	radius: float,
	length: float,
	body_color: Color,
	exhaust: Color,
	bevel: float = 0.15,
	segments: int = 6
) -> void:
	var r := maxf(radius, 0.02)
	var L := maxf(length, 0.05)
	# Housing loft: slightly flared aft intake → cylindrical mid → recessed nozzle
	var stations: Array = [
		station(pos.z - L * 0.45, r * 1.55, r * 1.55, pos.y, pos.x, "ngon", segments),
		station(pos.z - L * 0.05, r * 1.7, r * 1.7, pos.y, pos.x, "ngon", segments),
		station(pos.z + L * 0.25, r * 1.45, r * 1.45, pos.y, pos.x, "ngon", segments),
		station(pos.z + L * 0.42, r * 1.15, r * 1.15, pos.y, pos.x, "ngon", segments),
	]
	loft_hull(st, stations, body_color.darkened(0.12), bevel, 1, true, false)
	# Recessed exhaust well (negative space) + emissive core
	var well_z := pos.z + L * 0.38
	_ring_disk(st, Vector3(pos.x, pos.y, well_z), r * 0.95, body_color.darkened(0.35), segments, false)
	_ring_disk(st, Vector3(pos.x, pos.y, well_z + L * 0.08), r * 0.55, exhaust, segments, true)
	# Short nozzle sleeve
	var sleeve := [
		station(well_z, r * 1.05, r * 1.05, pos.y, pos.x, "ngon", segments),
		station(well_z + L * 0.12, r * 0.7, r * 0.7, pos.y, pos.x, "ngon", segments),
	]
	loft_hull(st, sleeve, body_color.darkened(0.2), bevel * 0.5, 1, false, true)


## Hardpoint as a structural shelf / pylons, not a floating coloured cube.
static func hardpoint_shelf(
	st: SurfaceTool,
	pos: Vector3,
	size: Vector3,
	orient: Vector3,
	body_color: Color,
	mount_color: Color,
	role: String = "gun"
) -> void:
	var sx := maxf(size.x, 0.04)
	var sy := maxf(size.y, 0.04)
	var sz := maxf(size.z, 0.06)
	# Shelf plate following hull side
	var plate_stations: Array = [
		station(pos.z - sz * 0.45, sx * 0.9, sy * 0.55, pos.y, pos.x, "box", 4),
		station(pos.z + sz * 0.45, sx * 0.75, sy * 0.45, pos.y, pos.x, "box", 4),
	]
	loft_hull(st, plate_stations, body_color.darkened(0.08), 0.12, 1, true, true)
	# Mount stub pointing roughly along orient (default forward -Z for guns)
	var dir := orient
	if dir.length_squared() < 1e-6:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var stub_len := sz * 0.55
	var stub_r := minf(sx, sy) * 0.28
	var stub_c := pos + dir * stub_len * 0.35 + Vector3(0, -sy * 0.15, 0)
	match role:
		"missile":
			ShapePrims.box(st, stub_c, Vector3(stub_r * 1.6, stub_r * 1.2, stub_len), mount_color.darkened(0.1))
		"sensor":
			ShapePrims.box(st, stub_c, Vector3(stub_r * 1.2, stub_r * 1.2, stub_len * 0.7), mount_color)
		_:
			# Gun barrel — thin prism extruded forward
			var gun_stations: Array = [
				station(stub_c.z + stub_len * 0.2, stub_r * 1.4, stub_r * 1.4, stub_c.y, stub_c.x, "ngon", 6),
				station(stub_c.z - stub_len * 0.55, stub_r * 0.7, stub_r * 0.7, stub_c.y, stub_c.x, "ngon", 6),
			]
			loft_hull(st, gun_stations, mount_color.darkened(0.15), 0.1, 1, true, true)


## Cockpit blister that follows hull deck (raised, tapered forward).
static func cockpit_blister(
	st: SurfaceTool,
	pos: Vector3,
	size: Vector3,
	hull_color: Color,
	glass_color: Color
) -> void:
	var stations: Array = [
		station(pos.z - size.z * 0.45, size.x * 0.55, size.y * 0.35, pos.y - size.y * 0.1, pos.x, "fighter", 6),
		station(pos.z - size.z * 0.05, size.x * 0.95, size.y * 0.95, pos.y, pos.x, "fighter", 6),
		station(pos.z + size.z * 0.4, size.x * 0.7, size.y * 0.55, pos.y - size.y * 0.05, pos.x, "round", 8),
	]
	loft_hull(st, stations, hull_color.lightened(0.06), 0.22, 1, true, true)
	# Glass inset
	ShapePrims.box(
		st,
		pos + Vector3(0, size.y * 0.12, -size.z * 0.08),
		Vector3(size.x * 0.55, size.y * 0.22, size.z * 0.4),
		glass_color
	)


# --- internal ring ops ---

static func _bridge_rings(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array, color: Color) -> void:
	var na := a.size()
	var nb := b.size()
	if na < 3 or nb < 3:
		return
	# Resample to common count if needed
	var n := na
	var aa := a
	var bb := b
	if na != nb:
		n = maxi(na, nb)
		aa = _resample_ring(a, n)
		bb = _resample_ring(b, n)
	for i in n:
		var i1 := (i + 1) % n
		_quad(st, aa[i], aa[i1], bb[i1], bb[i], color)


static func _cap_ring(st: SurfaceTool, ring: PackedVector3Array, color: Color, nose: bool) -> void:
	var n := ring.size()
	if n < 3:
		return
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(n)
	for i in n:
		var i1 := (i + 1) % n
		if nose:
			_tri(st, c, ring[i1], ring[i], color)
		else:
			_tri(st, c, ring[i], ring[i1], color)


static func _ring_disk(st: SurfaceTool, center: Vector3, radius: float, color: Color, segments: int, facing_aft: bool) -> void:
	var seg := maxi(segments, 3)
	for i in seg:
		var a0 := float(i) / float(seg) * TAU + PI * 0.5
		var a1 := float(i + 1) / float(seg) * TAU + PI * 0.5
		var p0 := center + Vector3(cos(a0) * radius, sin(a0) * radius, 0)
		var p1 := center + Vector3(cos(a1) * radius, sin(a1) * radius, 0)
		if facing_aft:
			_tri(st, center, p0, p1, color)
		else:
			_tri(st, center, p1, p0, color)


static func _resample_ring(ring: PackedVector3Array, count: int) -> PackedVector3Array:
	var n := ring.size()
	var out := PackedVector3Array()
	# Perimeter parameterisation
	var lens: Array = [0.0]
	var total := 0.0
	for i in n:
		var d := ring[(i + 1) % n].distance_to(ring[i])
		total += d
		lens.append(total)
	if total < 1e-8:
		for _i in count:
			out.append(ring[0])
		return out
	for i in count:
		var target := float(i) / float(count) * total
		var j := 0
		while j < n and float(lens[j + 1]) < target:
			j += 1
		var t0 := float(lens[j])
		var t1 := float(lens[j + 1])
		var u := 0.0 if t1 <= t0 else (target - t0) / (t1 - t0)
		out.append(ring[j % n].lerp(ring[(j + 1) % n], u))
	return out


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
