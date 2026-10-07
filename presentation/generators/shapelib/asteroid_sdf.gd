## Limit Theory asteroid SDF — cell-noise sphere displacement.
## Source: res/shader/fragment/sdf/asteroid.glsl + script/Gen/Asteroid.lua
## d = length(p) - mix(0.05, 1.0, fCellNoise(2p, seed, octaves, smoothness))
## LOD bands approximate LT LodMesh 8-band distance ranges (sphere densify, not Tex3D bake).
class_name ShapeLibAsteroid
extends RefCounted

## LT Asteroid.lua: 8 bands with res lac=1.5. We map VisualLOD/detail → band.
const BAND_COUNT := 8


static func generate_mesh(seed: int, detail: int = 1, color: Color = Color(0.35, 0.32, 0.28)) -> ArrayMesh:
	var band := clampi(detail, 0, BAND_COUNT - 1)
	# Map EW detail 0/1/2 → denser bands (higher = nearer)
	if detail <= 0:
		band = 0
	elif detail == 1:
		band = 3
	else:
		band = 6
	var key := "shapelib_asteroid:%d:b%d" % [seed, band]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var noise_seed := rng.randf_range(0.0, 1000.0)
	# Near bands: more octaves + subdiv; far bands: cheap hull.
	var octaves := clampi(4 + band, 4, 10)
	var smoothness := 2.5
	var subdiv := clampi(1 + band / 2, 1, 5)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mesh_base := SphereMesh.new()
	mesh_base.radial_segments = 8 * (subdiv + 1)
	mesh_base.rings = 4 * (subdiv + 1)
	mesh_base.radius = 1.0
	mesh_base.height = 2.0
	var arr := mesh_base.surface_get_arrays(0)
	var src_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var src_idx_v: Variant = arr[Mesh.ARRAY_INDEX]
	var out_verts: PackedVector3Array = PackedVector3Array()
	out_verts.resize(src_verts.size())
	var search_iters := 8 if band <= 2 else (10 if band <= 5 else 12)
	for i in src_verts.size():
		var p: Vector3 = src_verts[i].normalized()
		var r := _surface_radius(p, noise_seed, octaves, smoothness, search_iters)
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


static func _surface_radius(dir: Vector3, seed: float, octaves: int, smoothness: float, iters: int = 10) -> float:
	var lo := 0.05
	var hi := 1.35
	for _k in iters:
		var mid := (lo + hi) * 0.5
		var p := dir * mid
		var n := _f_cell_noise(p * 2.0, seed, octaves, smoothness)
		var d := mid - lerpf(0.05, 1.0, n)
		if d > 0.0:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


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
