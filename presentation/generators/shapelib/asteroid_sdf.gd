## Limit Theory asteroid SDF — cell-noise sphere displacement.
## Source: res/shader/fragment/sdf/asteroid.glsl + script/Gen/Asteroid.lua
## d = length(p) - mix(0.05, 1.0, fCellNoise(2p, seed, octaves, smoothness))
##
## LodMesh approximation: LT bakes 8 Tex3D bands (res 96, lac 1.5). We expose
## detail 0..3 as decreasing sphere resolution / octaves for distance LOD.
class_name ShapeLibAsteroid
extends RefCounted

## LT-style band count (Asteroid.lua loop 1..8). Callers pick a band by distance.
const LOD_BANDS := 4


static func lod_detail_for_distance(dist: float, field_scale: float = 750.0) -> int:
	# Map eye distance → detail 3 (near) .. 0 (far), lacunae-ish thresholds.
	var t := dist / maxf(field_scale, 1.0)
	if t < 0.35:
		return 3
	if t < 0.9:
		return 2
	if t < 2.2:
		return 1
	return 0


static func generate_mesh(seed: int, detail: int = 1, color: Color = Color(0.35, 0.32, 0.28)) -> ArrayMesh:
	var d := clampi(detail, 0, 3)
	var key := "shapelib_asteroid:v2:%d:%d" % [seed, d]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var noise_seed := rng.randf_range(0.0, 1000.0)
	# LT uses octaves=8 on the SDF shader; drop for far LODs.
	var octaves := 5 + d  # 5..8
	var smoothness := 2.5

	# Sphere base, then displace along radial by SDF residual
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mesh_base := SphereMesh.new()
	# Band 0≈far (low res) … band 3≈near (closer to LT res≈96 ish on Compatibility).
	var radial_opts: Array[int] = [8, 12, 16, 24]
	var ring_opts: Array[int] = [4, 6, 8, 12]
	mesh_base.radial_segments = radial_opts[d]
	mesh_base.rings = ring_opts[d]
	mesh_base.radius = 1.0
	mesh_base.height = 2.0
	var arr := mesh_base.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var src_idx_v: Variant = arr[Mesh.ARRAY_INDEX]
	var out_verts: PackedVector3Array = PackedVector3Array()
	out_verts.resize(src_verts.size())
	for i in src_verts.size():
		var p: Vector3 = src_verts[i].normalized()
		# Sample density along ray — find approximate surface where d≈0
		var r := _surface_radius(p, noise_seed, octaves, smoothness)
		out_verts[i] = p * r
	if src_idx_v == null:
		for i in range(0, out_verts.size(), 3):
			st.set_color(color)
			st.add_vertex(out_verts[i])
			st.set_color(color)
			st.add_vertex(out_verts[i + 1])
			st.set_color(color)
			st.add_vertex(out_verts[i + 2])
	else:
		var src_idx: PackedInt32Array = src_idx_v
		for i in range(0, src_idx.size(), 3):
			var i0 := src_idx[i]
			var i1 := src_idx[i + 1]
			var i2 := src_idx[i + 2]
			st.set_color(color)
			st.add_vertex(out_verts[i0])
			st.set_color(color)
			st.add_vertex(out_verts[i1])
			st.set_color(color)
			st.add_vertex(out_verts[i2])
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh


static func _surface_radius(dir: Vector3, seed: float, octaves: int, smoothness: float) -> float:
	# Binary search radius where length(p)-mix(0.05,1,n) ≈ 0 with p = dir*r
	var lo := 0.05
	var hi := 1.35
	for _k in 10:
		var mid := (lo + hi) * 0.5
		var p := dir * mid
		var n := _f_cell_noise(p * 2.0, seed, octaves, smoothness)
		var d := mid - lerpf(0.05, 1.0, n)
		if d > 0.0:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


## Worley / cell-noise approximation matching LT fCellNoise spirit (not bit-identical).
static func _f_cell_noise(p: Vector3, seed: float, octaves: int, smoothness: float) -> float:
	var amp := 1.0
	var freq := 1.0
	var sum := 0.0
	var norm := 0.0
	for o in octaves:
		sum += amp * _cell1(p * freq, seed + float(o) * 17.3)
		norm += amp
		amp *= 0.5
		freq *= smoothness * 0.55 + 0.85
	return sum / maxf(norm, 1e-4)


static func _cell1(p: Vector3, seed: float) -> float:
	var i := Vector3(floorf(p.x), floorf(p.y), floorf(p.z))
	var f := p - i
	var dmin := 8.0
	for xo in range(-1, 2):
		for yo in range(-1, 2):
			for zo in range(-1, 2):
				var g := i + Vector3(xo, yo, zo)
				var h := _hash33(g + Vector3(seed, seed * 1.7, seed * 2.3))
				var r := Vector3(xo, yo, zo) + h - f
				dmin = minf(dmin, r.length_squared())
	return clampf(1.0 - sqrt(dmin), 0.0, 1.0)


static func _frac(x: float) -> float:
	return x - floorf(x)


static func _hash33(p: Vector3) -> Vector3:
	var px := _frac(p.x * 0.1031)
	var py := _frac(p.y * 0.1031)
	var pz := _frac(p.z * 0.1031)
	var d := px * (py + 33.33) + py * (pz + 33.33) + pz * (px + 33.33)
	return Vector3(
		_frac((px + py) * pz + d),
		_frac((py + pz) * px + d),
		_frac((pz + px) * py + d)
	)
