## Procedural low-poly asteroid mesh builder.
class_name AsteroidMeshGen
extends RefCounted


static func build(seed: int, detail: int = 1) -> ArrayMesh:
	var key := "asteroid:%d:%d" % [seed, detail]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Icosahedron-like irregular blob via octahedron subdivided once with noise.
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
		var a: Vector3 = _displace(verts[f[0]], rng)
		var b: Vector3 = _displace(verts[f[1]], rng)
		var c: Vector3 = _displace(verts[f[2]], rng)
		var n: Vector3 = (b - a).cross(c - a).normalized()
		st.set_normal(n)
		st.add_vertex(a)
		st.set_normal(n)
		st.add_vertex(b)
		st.set_normal(n)
		st.add_vertex(c)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh


static func _displace(v: Vector3, rng: SeededRNG) -> Vector3:
	var n := v.normalized()
	var r := rng.randf_range(0.55, 1.15)
	return n * r


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
