## Procedural asteroid mesh families — variety in geometry, not only scale.
class_name AsteroidMeshGen
extends RefCounted

const FAMILY_CHUNK := 0
const FAMILY_SHARD := 1
const FAMILY_LOBED := 2
const FAMILY_CRAG := 3


static func build(seed: int, detail: int = 1, composition: String = "iron") -> ArrayMesh:
	var family := seed % 4
	# Composition biases family
	match composition:
		"ice":
			family = FAMILY_SHARD if (seed % 3) != 0 else FAMILY_CRAG
		"carbon":
			family = FAMILY_LOBED if (seed % 2) == 0 else FAMILY_CHUNK
		"silicate":
			family = FAMILY_CRAG if (seed % 2) == 0 else FAMILY_CHUNK
		_:
			family = seed % 4

	var key := "asteroid_sdf:%d:%d:%s" % [seed, detail, composition]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	# LT path: cell-noise SDF asteroid (Asteroid.lua / sdf/asteroid.glsl).
	# Family only tints composition colour; shape comes from SDF.
	var tint := Color(0.38, 0.35, 0.32)
	match composition:
		"ice":
			tint = Color(0.72, 0.78, 0.85)
		"carbon":
			tint = Color(0.22, 0.2, 0.19)
		"silicate":
			tint = Color(0.48, 0.42, 0.34)
		_:
			tint = Color(0.4, 0.36, 0.3)
	var mesh: ArrayMesh = ShapeLibAsteroid.generate_mesh(seed, detail, tint)
	return MeshCache.store(key, mesh) as ArrayMesh


static func family_name(seed: int, composition: String = "iron") -> String:
	var mesh_key_family := seed % 4
	match composition:
		"ice":
			mesh_key_family = FAMILY_SHARD if (seed % 3) != 0 else FAMILY_CRAG
		"carbon":
			mesh_key_family = FAMILY_LOBED if (seed % 2) == 0 else FAMILY_CHUNK
		"silicate":
			mesh_key_family = FAMILY_CRAG if (seed % 2) == 0 else FAMILY_CHUNK
	match mesh_key_family:
		FAMILY_SHARD:
			return "shard"
		FAMILY_LOBED:
			return "lobed"
		FAMILY_CRAG:
			return "crag"
		_:
			return "chunk"


static func _build_chunk(st: SurfaceTool, rng: SeededRNG, detail: int) -> void:
	var verts: Array[Vector3] = [
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var faces: Array = [
		[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2],
		[1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5],
	]
	if detail >= 1:
		faces = _subdivide(verts, faces)
	for f in faces:
		_tri(st, _displace(verts[f[0]], rng, 0.55, 1.15), _displace(verts[f[1]], rng, 0.55, 1.15), _displace(verts[f[2]], rng, 0.55, 1.15))


static func _build_shard(st: SurfaceTool, rng: SeededRNG, composition: String) -> void:
	# Elongated crystalline / icy shard
	var stretch := Vector3(0.55, 0.7, 1.45) if composition == "ice" else Vector3(0.6, 0.55, 1.35)
	var tip := Vector3(0, 0, -1.2) * stretch
	var aft := Vector3(0, 0, 1.0) * stretch
	var ring: Array[Vector3] = []
	for i in 5:
		var a := float(i) / 5.0 * TAU + rng.randf() * 0.2
		ring.append(Vector3(cos(a) * rng.randf_range(0.4, 0.7), sin(a) * rng.randf_range(0.35, 0.65), 0) * stretch)
	for i in ring.size():
		var n: Vector3 = ring[(i + 1) % ring.size()]
		_tri(st, tip, ring[i], n)
		_tri(st, aft, n, ring[i])


static func _build_lobed(st: SurfaceTool, rng: SeededRNG) -> void:
	# Two fused blobs
	_add_blob(st, Vector3.ZERO, 0.7, rng)
	_add_blob(st, Vector3(rng.randf_range(0.4, 0.7), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.3)), 0.5, rng)


static func _build_crag(st: SurfaceTool, rng: SeededRNG, detail: int) -> void:
	_build_chunk(st, rng, detail)
	# Extra peaks
	for _i in 3:
		var p := rng.dir3() * rng.randf_range(0.7, 1.1)
		var base := p * 0.4
		var s := rng.randf_range(0.15, 0.35)
		_tri(st, p, base + Vector3(s, 0, 0), base + Vector3(0, 0, s))
		_tri(st, p, base + Vector3(0, 0, s), base + Vector3(-s, 0, 0))
		_tri(st, p, base + Vector3(-s, 0, 0), base + Vector3(0, 0, -s))
		_tri(st, p, base + Vector3(0, 0, -s), base + Vector3(s, 0, 0))


static func _add_blob(st: SurfaceTool, center: Vector3, radius: float, rng: SeededRNG) -> void:
	var verts: Array[Vector3] = []
	var dirs := [
		Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0),
		Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	for d in dirs:
		verts.append(center + d.normalized() * radius * rng.randf_range(0.7, 1.2))
	var faces := [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]
	for f in faces:
		_tri(st, verts[f[0]], verts[f[1]], verts[f[2]])


static func _displace(v: Vector3, rng: SeededRNG, lo: float, hi: float) -> Vector3:
	return v.normalized() * rng.randf_range(lo, hi)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		n = Vector3.UP
	else:
		n = n.normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


static func _subdivide(verts: Array[Vector3], faces: Array) -> Array:
	var mid_cache: Dictionary = {}
	var out: Array = []
	for f in faces:
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		var ab := _mid(verts, mid_cache, a, b)
		var bc := _mid(verts, mid_cache, b, c)
		var ca := _mid(verts, mid_cache, c, a)
		out.append([a, ab, ca])
		out.append([b, bc, ab])
		out.append([c, ca, bc])
		out.append([ab, bc, ca])
	return out


static func _mid(verts: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	if cache.has(key):
		return int(cache[key])
	var m: Vector3 = (verts[a] + verts[b]).normalized()
	var idx := verts.size()
	verts.append(m)
	cache[key] = idx
	return idx
