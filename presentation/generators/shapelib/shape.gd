## Limit Theory ShapeLib.Shape — verts + polys with extrusion / topology ops.
## Ported from JoshParnell/ltheory script/Gen/ShapeLib/Shape.lua + Warp.lua.
## Indices are 0-based (LT polys store 0-based; Lua arrays are 1-based).
class_name ShapeLibShape
extends RefCounted

var verts: Array[Vector3] = []
var polys: Array = [] # Array of PackedInt32Array / Array[int]


func add_vertex(x: float, y: float, z: float) -> ShapeLibShape:
	verts.append(Vector3(x, y, z))
	return self


func add_tri(i0: int, i1: int, i2: int) -> ShapeLibShape:
	polys.append([i0, i1, i2])
	return self


func add_quad(i0: int, i1: int, i2: int, i3: int) -> ShapeLibShape:
	polys.append([i0, i1, i2, i3])
	return self


func add_poly(poly: Array) -> ShapeLibShape:
	assert(poly.size() >= 3)
	polys.append(poly.duplicate())
	return self


func add_shape(other: ShapeLibShape) -> ShapeLibShape:
	var offset := verts.size()
	for v in other.verts:
		verts.append(v)
	for poly in other.polys:
		var copy: Array = []
		for idx in poly:
			copy.append(int(idx) + offset)
		polys.append(copy)
	return self


func clone() -> ShapeLibShape:
	var c := ShapeLibShape.new()
	for v in verts:
		c.verts.append(v)
	for poly in polys:
		c.polys.append(poly.duplicate())
	return c


func get_vertex(index: int) -> Vector3:
	return verts[index]


func get_vertex_count() -> int:
	return verts.size()


func poly_valid(poly: Array) -> bool:
	if poly == null or poly.size() < 3:
		return false
	for idx in poly:
		var i := int(idx)
		if i < 0 or i >= verts.size():
			return false
	return true


func get_face_centroid(poly: Array) -> Vector3:
	var c := Vector3.ZERO
	for idx in poly:
		c += verts[int(idx)]
	return c / float(poly.size())


func get_face_center(poly: Array) -> Vector3:
	return get_face_centroid(poly)


func get_face_normal(poly: Array) -> Variant:
	if not poly_valid(poly):
		return null
	var n := Vector3.ZERO
	var p0: Vector3 = verts[int(poly[0])]
	for i in range(1, poly.size() - 1):
		var p1: Vector3 = verts[int(poly[i])]
		var p2: Vector3 = verts[int(poly[i + 1])]
		n += (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-12:
		return null
	return n.normalized()


func get_poly_with_normal(n: Vector3) -> int:
	var best := -1
	var closest := 1e10
	for i in polys.size():
		var poly: Array = polys[i]
		if not poly_valid(poly):
			continue
		var norm: Variant = get_face_normal(poly)
		if norm == null:
			continue
		var diff: float = ((norm as Vector3) - n).length()
		if diff < closest:
			closest = diff
			best = i
	return best


func get_center() -> Vector3:
	if verts.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for v in verts:
		c += v
	return c / float(verts.size())


func get_aabb() -> Dictionary:
	var lower := verts[0]
	var upper := verts[0]
	for i in range(1, verts.size()):
		var v: Vector3 = verts[i]
		lower = Vector3(minf(lower.x, v.x), minf(lower.y, v.y), minf(lower.z, v.z))
		upper = Vector3(maxf(upper.x, v.x), maxf(upper.y, v.y), maxf(upper.z, v.z))
	return {"lower": lower, "upper": upper}


func get_radius() -> float:
	var b := get_aabb()
	return 0.5 * ((b["upper"] as Vector3) - (b["lower"] as Vector3)).length()


func invert_poly(pi: int) -> void:
	var poly: Array = polys[pi]
	poly.reverse()
	polys[pi] = poly


func warp(fn: Callable) -> ShapeLibShape:
	# fn(Vector3) -> Vector3
	for i in verts.size():
		verts[i] = fn.call(verts[i])
	return self


## Project verts onto unit sphere (LT Warp.sphereize). p≈2 → Euclidean normalize.
func sphereize(p: float = 2.0) -> ShapeLibShape:
	for i in verts.size():
		var v: Vector3 = verts[i]
		if p >= 1.9 and p <= 2.1:
			if v.length_squared() > 1e-12:
				verts[i] = v.normalized()
		else:
			# Approximate p-norm normalize
			var ax := absf(v.x)
			var ay := absf(v.y)
			var az := absf(v.z)
			var pn := pow(ax, p) + pow(ay, p) + pow(az, p)
			if pn > 1e-12:
				var inv := 1.0 / pow(pn, 1.0 / p)
				verts[i] = v * inv
	return self


func scale_xyz(sx: float, sy: float = -1.0, sz: float = -1.0) -> ShapeLibShape:
	if sy < 0.0:
		sy = sx
	if sz < 0.0:
		sz = sx
	if sx < 1e-6 or sy < 1e-6 or sz < 1e-6:
		return self
	for i in verts.size():
		var v: Vector3 = verts[i]
		verts[i] = Vector3(v.x * sx, v.y * sy, v.z * sz)
	return self


func translate_xyz(dx: float = 0.0, dy: float = 0.0, dz: float = 0.0) -> ShapeLibShape:
	if is_zero_approx(dx) and is_zero_approx(dy) and is_zero_approx(dz):
		return self
	for i in verts.size():
		verts[i] += Vector3(dx, dy, dz)
	return self


func center_at(x: float = 0.0, y: float = 0.0, z: float = 0.0) -> ShapeLibShape:
	var c := get_center()
	return translate_xyz(x - c.x, y - c.y, z - c.z)


func mirror_axes(mx: bool, my: bool, mz: bool) -> ShapeLibShape:
	for i in verts.size():
		var v: Vector3 = verts[i]
		if mx:
			v.x = -v.x
		if my:
			v.y = -v.y
		if mz:
			v.z = -v.z
		verts[i] = v
	# Invert winding unless exactly two axes mirrored (LT Warp.lua)
	var two := (mx and my and not mz) or (mx and mz and not my) or (my and mz and not mx)
	if not two:
		for i in polys.size():
			invert_poly(i)
	return self


## Yaw / pitch / roll in radians (LT: Matrix.YawPitchRoll(dx,dy,dz)).
func rotate_ypr(yaw: float, pitch: float, roll: float) -> ShapeLibShape:
	if is_zero_approx(yaw) and is_zero_approx(pitch) and is_zero_approx(roll):
		return self
	var basis := Basis.from_euler(Vector3(pitch, yaw, roll))
	for i in verts.size():
		verts[i] = basis * verts[i]
	return self


func extrude_poly(
	pi: int,
	length: float = 0.5,
	scale: Vector3 = Vector3.ONE,
	dir: Variant = null,
	preserve_original: bool = false
) -> ShapeLibShape:
	if pi < 0 or pi >= polys.size():
		return self
	var poly: Array = polys[pi]
	if not poly_valid(poly):
		return self
	if scale.length() < 1e-6:
		return self
	var d: Vector3
	if dir == null:
		var n: Variant = get_face_normal(poly)
		if n == null:
			return self
		d = n as Vector3
	else:
		d = dir as Vector3
	if d.length() < 1e-6:
		return self
	d = d.normalized()
	var c := get_face_centroid(poly)
	var new_poly: Array = []
	for idx in poly:
		var p: Vector3 = verts[int(idx)]
		new_poly.append(verts.size())
		add_vertex(
			lerpf(c.x, p.x, scale.x) + d.x * length,
			lerpf(c.y, p.y, scale.y) + d.y * length,
			lerpf(c.z, p.z, scale.z) + d.z * length
		)
	for j0 in poly.size():
		var j1 := (j0 + 1) % poly.size()
		add_quad(int(poly[j0]), int(poly[j1]), int(new_poly[j1]), int(new_poly[j0]))
	if not preserve_original:
		polys[pi] = new_poly
	else:
		polys.append(new_poly)
		invert_poly(pi)
	return self


func extrude_all(length: float = 0.5, scale: Vector3 = Vector3.ONE) -> ShapeLibShape:
	var ps := polys.size()
	for i in ps:
		extrude_poly(i, length, scale)
	return self


func stellate(length: float = 1.0) -> ShapeLibShape:
	var count := polys.size()
	for i in count:
		_triangulate_poly_centroid(i, length)
	return self


func tessellate(n: int = 1) -> ShapeLibShape:
	if n <= 0:
		return self
	for _j in n:
		var ps := polys.size()
		for i in ps:
			if polys[i].size() > 4:
				_triangulate_poly_centroid(i, 0.0)
		var edge_map := {}
		var vc := get_vertex_count()
		ps = polys.size()
		for i in ps:
			var deg: int = polys[i].size()
			if deg == 3:
				_triangulate_tri_even(i, edge_map, vc)
			elif deg == 4:
				_tessellate_quad(i, edge_map, vc)
	return self


func greeble(
	rng: SeededRNG,
	n: int = -1,
	low: float = 0.05,
	high: float = 0.2,
	greeble_chance: float = 0.33,
	scale_chance: float = 0.0
) -> ShapeLibShape:
	if n < 0:
		n = rng.randi_range(1, 4)
	if low > high:
		return self
	tessellate(n)
	var ps := polys.size()
	for i in ps:
		if greeble_chance >= 1.0 or rng.randf() < greeble_chance:
			var length := rng.randf_range(low, high)
			if scale_chance >= 1.0 or (scale_chance > 0.0 and rng.randf() < scale_chance):
				var sc := Vector3(
					rng.randf_range(0.2, 1.0),
					rng.randf_range(0.2, 1.0),
					rng.randf_range(0.2, 1.0)
				)
				extrude_poly(i, length, sc)
			else:
				extrude_poly(i, length)
	return self


## Topology-aware bevel (LT Warp.lua). Returns new shape; self unchanged on failure.
func bevel(t: float = 0.2) -> ShapeLibShape:
	t = clampf(t, 0.0, 1.0)
	var top: Variant = _get_topology()
	if top == null:
		return self
	var v2f: Dictionary = top["v2f"]
	var v2v: Dictionary = top["v2v"]
	var result := ShapeLibShape.new()
	var e2v := {} # key: vc*v_from + v_to → [face_array, subindex]
	var vc := get_vertex_count()

	for i in verts.size():
		var v: Vector3 = verts[i]
		var faces: Array = v2f.get(i, [])
		var new_face: Array = []
		for j in faces.size():
			var face: Dictionary = faces[j]
			new_face.append(result.get_vertex_count())
			var face_ref: Array = face["ref"]
			var face_index: int = int(face["index"])
			var next_vert: int = int(face_ref[_wrap(face_index + 1, 0, face_ref.size() - 1)])
			e2v[vc * i + next_vert] = [new_face, j]
			var p: Vector3 = v.lerp(get_face_center(face_ref), t)
			result.add_vertex(p.x, p.y, p.z)
		if new_face.size() >= 3:
			result.add_poly(new_face)

	for i in verts.size():
		var faces2: Array = v2f.get(i, [])
		var verts_n: Array = v2v.get(i, [])
		for j in verts_n.size():
			var nj: int = int(verts_n[j])
			if i < nj:
				var corner1: Array = e2v.get(vc * i + nj, [])
				var corner2: Array = e2v.get(vc * nj + i, [])
				if corner1.is_empty() or corner2.is_empty():
					continue
				var f1: Array = corner1[0]
				var i1: int = int(corner1[1])
				var f2: Array = corner2[0]
				var i2: int = int(corner2[1])
				result.add_quad(
					int(f1[i1]),
					int(f1[_wrap(i1 - 1, 0, f1.size() - 1)]),
					int(f2[i2]),
					int(f2[_wrap(i2 - 1, 0, f2.size() - 1)])
				)

	for i in polys.size():
		var face: Array = polys[i]
		var new_face2: Array = []
		for j in face.size():
			var v1: int = int(face[j])
			var v2: int = int(face[_wrap(j + 1, 0, face.size() - 1)])
			var corner: Array = e2v.get(vc * v1 + v2, [])
			if corner.is_empty():
				continue
			var cf: Array = corner[0]
			var ci: int = int(corner[1])
			new_face2.append(int(cf[ci]))
		if new_face2.size() >= 3:
			result.add_poly(new_face2)
	return result


func triangulate_fan() -> void:
	var i := 0
	while i < polys.size():
		var poly: Array = polys[i]
		if poly_valid(poly) and poly.size() > 3:
			for j in range(1, poly.size() - 2):
				polys.append([int(poly[0]), int(poly[j + 1]), int(poly[j + 2])])
			polys[i] = [int(poly[0]), int(poly[1]), int(poly[2])]
		i += 1


## LT Shape:addAtIntersection — place `other` at first ray hit on this mesh.
func add_at_intersection(ray_origin: Vector3, ray_dir: Vector3, other: ShapeLibShape) -> bool:
	var hit: Variant = intersect_ray(ray_origin, ray_dir)
	if hit == null:
		return false
	var p: Vector3 = hit
	other.translate_xyz(p.x, p.y, p.z)
	add_shape(other)
	return true


## Raycast against triangulated polys. Returns hit point or null.
## WARNING: fan-triangulates this shape (same as LT).
func intersect_ray(ray_origin: Vector3, ray_dir: Vector3) -> Variant:
	triangulate_fan()
	var t_min := 1e30
	var hit: Variant = null
	var dir := ray_dir
	if dir.length_squared() < 1e-12:
		return null
	for poly in polys:
		if not poly_valid(poly) or poly.size() < 3:
			continue
		var t: Variant = _check_ray_intersect_tri(ray_origin, dir, poly)
		if t != null and float(t) < t_min and float(t) > 1e-6:
			t_min = float(t)
			hit = ray_origin + dir * t_min
	return hit


## Finalize → ArrayMesh. Soft AO + spherical UV panel tint (DiffuseMap spirit).
func finalize_mesh(hull_color: Color = Color(0.45, 0.45, 0.48), with_ao: bool = true) -> ArrayMesh:
	var work := clone()
	work.triangulate_fan()
	var ao: PackedFloat32Array = PackedFloat32Array()
	if with_ao and work.verts.size() > 0:
		ao = work._soft_ao(0.55 * work.get_radius())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly in work.polys:
		if not work.poly_valid(poly) or poly.size() < 3:
			continue
		for k in 3:
			var vi := int(poly[k])
			var p: Vector3 = work.verts[vi]
			var c := hull_color
			# Spherical UV → mild panel / triplanar-ish variation (no full UVMap packer).
			var nrm := p.normalized() if p.length_squared() > 1e-8 else Vector3.UP
			var u := 0.5 + atan2(nrm.z, nrm.x) / TAU
			var v := acos(clampf(nrm.y, -1.0, 1.0)) / PI
			var panel := 0.92 + 0.12 * sin(u * 28.0) * sin(v * 18.0)
			var seam := 1.0 - 0.08 * absf(sin(u * PI * 6.0))
			c = Color(c.r * panel * seam, c.g * panel * seam, c.b * panel * seam, c.a)
			if with_ao and ao.size() > vi:
				var a := ao[vi]
				c = Color(c.r * a, c.g * a, c.b * a, c.a)
			st.set_color(c)
			st.set_uv(Vector2(u, v))
			st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## Cheap AO: verts in dense neighbourhoods darken (stand-in for mesh:computeAO).
func _soft_ao(radius: float) -> PackedFloat32Array:
	var n := verts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var r2 := maxf(radius * radius * 0.04, 1e-4)
	for i in n:
		var p: Vector3 = verts[i]
		var occ := 0.0
		var samples := 0
		# Sparse neighbourhood sample — O(n) with stride for large meshes.
		var stride := maxi(1, n / 64)
		var j := 0
		while j < n:
			if j != i:
				var d2 := p.distance_squared_to(verts[j])
				if d2 < r2:
					occ += 1.0 - d2 / r2
					samples += 1
			j += stride
		var a := 1.0 - clampf(occ / maxf(float(samples), 1.0), 0.0, 1.0) * 0.45
		out[i] = clampf(a, 0.55, 1.0)
	return out


func _check_ray_intersect_tri(ray_origin: Vector3, ray_dir: Vector3, tri: Array) -> Variant:
	var p0: Vector3 = verts[int(tri[0])]
	var p1: Vector3 = verts[int(tri[1])]
	var p2: Vector3 = verts[int(tri[2])]
	var n: Variant = get_face_normal(tri)
	if n == null:
		return null
	var nn: Vector3 = n
	var denom := nn.dot(ray_dir)
	if denom >= -1e-8:
		return null # backface / parallel
	var t := nn.dot(p0 - ray_origin) / denom
	if t < 0.0:
		return null
	var p := ray_origin + ray_dir * t
	# Barycentric in dominant plane (LT checkRayIntersectTri)
	var u0: float
	var u1: float
	var u2: float
	var v0: float
	var v1: float
	var v2: float
	if absf(nn.x) > absf(nn.y):
		if absf(nn.x) > absf(nn.z):
			u0 = p.y - p0.y
			u1 = p1.y - p0.y
			u2 = p2.y - p0.y
			v0 = p.z - p0.z
			v1 = p1.z - p0.z
			v2 = p2.z - p0.z
		else:
			u0 = p.x - p0.x
			u1 = p1.x - p0.x
			u2 = p2.x - p0.x
			v0 = p.y - p0.y
			v1 = p1.y - p0.y
			v2 = p2.y - p0.y
	else:
		if absf(nn.y) > absf(nn.z):
			u0 = p.x - p0.x
			u1 = p1.x - p0.x
			u2 = p2.x - p0.x
			v0 = p.z - p0.z
			v1 = p1.z - p0.z
			v2 = p2.z - p0.z
		else:
			u0 = p.x - p0.x
			u1 = p1.x - p0.x
			u2 = p2.x - p0.x
			v0 = p.y - p0.y
			v1 = p1.y - p0.y
			v2 = p2.y - p0.y
	var temp := u1 * v2 - v1 * u2
	if absf(temp) < 1e-12:
		return null
	temp = 1.0 / temp
	var alpha := (u0 * v2 - v0 * u2) * temp
	if alpha < 0.0:
		return null
	var beta := (u1 * v0 - v1 * u0) * temp
	if beta < 0.0:
		return null
	if 1.0 - alpha - beta < 0.0:
		return null
	return t


# --- internals ---

static func _wrap(i: int, lo: int, hi: int) -> int:
	var n := hi - lo + 1
	if n <= 0:
		return lo
	var r := (i - lo) % n
	if r < 0:
		r += n
	return lo + r


func _triangulate_poly_centroid(pi: int, length: float = 0.0) -> void:
	var poly: Array = polys[pi]
	if not poly_valid(poly):
		return
	var c := get_face_centroid(poly)
	var n: Variant = get_face_normal(poly)
	var dir := Vector3.UP if n == null else (n as Vector3)
	var ci := verts.size()
	add_vertex(c.x + dir.x * length, c.y + dir.y * length, c.z + dir.z * length)
	var new_tris: Array = []
	for j in poly.size():
		var j1 := (j + 1) % poly.size()
		new_tris.append([ci, int(poly[j]), int(poly[j1])])
	polys[pi] = new_tris[0]
	for k in range(1, new_tris.size()):
		polys.append(new_tris[k])


func _midpoint_key(a: int, b: int, vc: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return vc * lo + hi


func _get_or_create_mid(a: int, b: int, edge_map: Dictionary, vc: int) -> int:
	var key := _midpoint_key(a, b, vc)
	if edge_map.has(key):
		return int(edge_map[key])
	var mid: Vector3 = (verts[a] + verts[b]) * 0.5
	var idx := verts.size()
	add_vertex(mid.x, mid.y, mid.z)
	edge_map[key] = idx
	return idx


func _triangulate_tri_even(pi: int, edge_map: Dictionary, vc: int) -> void:
	var poly: Array = polys[pi]
	if poly.size() != 3:
		return
	var a := int(poly[0])
	var b := int(poly[1])
	var c := int(poly[2])
	var ab := _get_or_create_mid(a, b, edge_map, vc)
	var bc := _get_or_create_mid(b, c, edge_map, vc)
	var ca := _get_or_create_mid(c, a, edge_map, vc)
	polys[pi] = [a, ab, ca]
	polys.append([ab, b, bc])
	polys.append([ca, bc, c])
	polys.append([ab, bc, ca])


func _tessellate_quad(pi: int, edge_map: Dictionary, vc: int) -> void:
	var poly: Array = polys[pi]
	if poly.size() != 4:
		return
	var a := int(poly[0])
	var b := int(poly[1])
	var c := int(poly[2])
	var d := int(poly[3])
	var ab := _get_or_create_mid(a, b, edge_map, vc)
	var bc := _get_or_create_mid(b, c, edge_map, vc)
	var cd := _get_or_create_mid(c, d, edge_map, vc)
	var da := _get_or_create_mid(d, a, edge_map, vc)
	var center := (verts[a] + verts[b] + verts[c] + verts[d]) * 0.25
	var mid := verts.size()
	add_vertex(center.x, center.y, center.z)
	polys[pi] = [a, ab, mid, da]
	polys.append([ab, b, bc, mid])
	polys.append([mid, bc, c, cd])
	polys.append([da, mid, cd, d])


func _get_topology() -> Variant:
	# v2f / v2v keyed by vertex index
	var v2f := {}
	var v2v := {}
	for i in verts.size():
		v2f[i] = []
		v2v[i] = []
	for fi in polys.size():
		var poly: Array = polys[fi]
		if not poly_valid(poly):
			continue
		for j in poly.size():
			var v: int = int(poly[j])
			var next_v: int = int(poly[(j + 1) % poly.size()])
			(v2f[v] as Array).append({"ref": poly, "face": fi, "index": j})
			(v2v[v] as Array).append(next_v)
	# Sort adjacency (CCW) — LT algorithm
	for i in verts.size():
		var faces: Array = v2f[i]
		var neigh: Array = v2v[i]
		if faces.size() != neigh.size() or faces.is_empty():
			continue
		var fi: Dictionary = faces[0]
		for j in range(1, faces.size()):
			var face_ref: Array = fi["ref"]
			var face_index: int = int(fi["index"])
			var next_vert: int = int(face_ref[_wrap(face_index - 1, 0, face_ref.size() - 1)])
			var found := false
			for k in range(j, faces.size()):
				fi = faces[k]
				var fr: Array = fi["ref"]
				var fidx: int = int(fi["index"])
				if int(fr[_wrap(fidx + 1, 0, fr.size() - 1)]) == next_vert:
					var tmpf = faces[j]
					faces[j] = faces[k]
					faces[k] = tmpf
					var tmpv = neigh[j]
					neigh[j] = neigh[k]
					neigh[k] = tmpv
					found = true
					break
			if not found:
				return null
			fi = faces[j]
		v2f[i] = faces
		v2v[i] = neigh
	return {"v2f": v2f, "v2v": v2v}
