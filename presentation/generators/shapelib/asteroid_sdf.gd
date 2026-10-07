## Limit Theory asteroid SDF — cell-noise sphere displacement.
## Source: res/shader/fragment/sdf/asteroid.glsl + script/Gen/Asteroid.lua
## d = length(p) - mix(0.05, 1.0, fCellNoise(2p, seed, octaves, smoothness))
class_name ShapeLibAsteroid
extends RefCounted


static func generate_mesh(seed: int, detail: int = 1, color: Color = Color(0.35, 0.32, 0.28)) -> ArrayMesh:
	var key := "shapelib_asteroid:%d:%d" % [seed, detail]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var noise_seed := rng.randf_range(0.0, 1000.0)
	var octaves := 6 if detail <= 0 else (8 if detail >= 2 else 7)
	var smoothness := 2.5

	# Sphere base, then displace along radial by SDF residual
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mesh_base := SphereMesh.new()
	var subdiv := 1 if detail <= 0 else (3 if detail >= 2 else 2)
	mesh_base.radial_segments = 8 * (subdiv + 1)
	mesh_base.rings = 4 * (subdiv + 1)
	mesh_base.radius = 1.0
	mesh_base.height = 2.0
	var arr := mesh_base.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var src_idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out_verts: PackedVector3Array = PackedVector3Array()
	out_verts.resize(src_verts.size())
	for i in src_verts.size():
		var p: Vector3 = src_verts[i].normalized()
		# Sample density along ray — find approximate surface where d≈0
		var r := _surface_radius(p, noise_seed, octaves, smoothness)
		out_verts[i] = p * r
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
