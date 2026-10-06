## Modular procedural station mesh — composition driven by role + faction style.
## Inspired by LT Station.lua: assemble primitives on joints rather than unique sculptures.
class_name StationMeshGen
extends RefCounted

const ROLE_MINING := "mining"
const ROLE_TRADE := "trade"
const ROLE_INDUSTRIAL := "industrial"
const ROLE_MILITARY := "military"
const ROLE_HABITAT := "habitat"


static func build(design: Dictionary) -> ArrayMesh:
	var seed: int = int(design.get("seed", 1))
	var role: String = str(design.get("role", ROLE_TRADE))
	var key := "station:%d:%s" % [seed, role]
	var cached: Mesh = MeshCache.get_mesh(key)
	if cached != null:
		return cached as ArrayMesh

	var rng := SeededRNG.new(seed)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var style: String = str(design.get("style", "industrial"))
	var accent: Color = design.get("color", Color(0.6, 0.65, 0.7))

	# Core
	_box(st, Vector3.ZERO, Vector3(1.2, 1.0, 1.2), accent)

	# Spire / command
	_box(st, Vector3(0, 1.4, 0), Vector3(0.35, 1.6, 0.35), accent.lightened(0.1))

	match role:
		ROLE_MINING:
			_box(st, Vector3(1.6, 0, 0), Vector3(1.4, 0.7, 0.9), accent.darkened(0.15))
			_box(st, Vector3(-1.6, 0, 0), Vector3(1.4, 0.7, 0.9), accent.darkened(0.15))
			_box(st, Vector3(0, -0.2, 1.8), Vector3(0.8, 0.5, 1.5), Color(0.45, 0.4, 0.3))
			for i in 3:
				var y := -0.8 - float(i) * 0.55
				_box(st, Vector3(0, y, 2.4), Vector3(0.35, 0.25, 0.35), Color(0.35, 0.32, 0.28))
		ROLE_TRADE:
			for i in 4:
				var a := float(i) * TAU * 0.25 + 0.2
				var p := Vector3(cos(a) * 2.0, 0.0, sin(a) * 2.0)
				_box(st, p, Vector3(0.9, 0.45, 0.9), accent.lightened(0.05))
			_box(st, Vector3(0, 0.1, 0), Vector3(2.4, 0.25, 2.4), accent.darkened(0.2))
		ROLE_INDUSTRIAL:
			_box(st, Vector3(1.8, 0.2, 0), Vector3(1.6, 1.4, 1.1), accent.darkened(0.1))
			_box(st, Vector3(-1.8, 0.2, 0), Vector3(1.6, 1.4, 1.1), accent.darkened(0.1))
			_box(st, Vector3(0, 0, 2.0), Vector3(1.0, 0.8, 1.3), Color(0.5, 0.45, 0.4))
			for i in 2:
				_cyl_approx(st, Vector3(1.2 + float(i) * 0.7, 1.6, 0.8), 0.2, 1.2, Color(0.4, 0.4, 0.42))
		ROLE_MILITARY:
			_box(st, Vector3(0, 0, 0), Vector3(1.6, 0.7, 2.2), accent.darkened(0.25))
			for i in 3:
				var z := -1.2 + float(i) * 1.1
				_box(st, Vector3(1.5, 0.3, z), Vector3(0.5, 0.35, 0.5), Color(0.7, 0.25, 0.25))
				_box(st, Vector3(-1.5, 0.3, z), Vector3(0.5, 0.35, 0.5), Color(0.7, 0.25, 0.25))
			_box(st, Vector3(0, 2.0, 0), Vector3(0.5, 0.9, 0.5), accent)
		_:
			_box(st, Vector3(1.4, 0.3, 0), Vector3(1.0, 1.1, 1.0), accent.lightened(0.15))
			_box(st, Vector3(-1.4, 0.3, 0), Vector3(1.0, 1.1, 1.0), accent.lightened(0.15))
			_box(st, Vector3(0, 0.5, 1.6), Vector3(1.2, 0.9, 0.8), accent)

	# Docking arm — all roles
	var dock_len := rng.randf_range(1.4, 2.2)
	_box(st, Vector3(0, -0.9, dock_len * 0.5), Vector3(0.35, 0.25, dock_len), accent.darkened(0.05))
	_box(st, Vector3(0, -0.9, dock_len), Vector3(0.9, 0.4, 0.5), Color(0.8, 0.75, 0.4))

	# Style tweak: exposed industrial scaffolding
	if style == "industrial" or style == "pirate":
		for i in 4:
			var a := float(i) * TAU * 0.25
			_box(st, Vector3(cos(a) * 1.1, rng.randf_range(-0.5, 1.0), sin(a) * 1.1), Vector3(0.12, 1.4, 0.12), accent.darkened(0.3))

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return MeshCache.store(key, mesh) as ArrayMesh


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var v := [
		center + Vector3(-hx, -hy, -hz),
		center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, hy, -hz),
		center + Vector3(-hx, hy, -hz),
		center + Vector3(-hx, -hy, hz),
		center + Vector3(hx, -hy, hz),
		center + Vector3(hx, hy, hz),
		center + Vector3(-hx, hy, hz),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(b)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(d)


static func _cyl_approx(st: SurfaceTool, base: Vector3, radius: float, height: float, color: Color) -> void:
	# Low-segment prism as chimney/tank.
	var seg := 6
	var top := base + Vector3(0, height, 0)
	for i in seg:
		var a0 := float(i) / float(seg) * TAU
		var a1 := float(i + 1) / float(seg) * TAU
		var p0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var p2 := top + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var p3 := top + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var n: Vector3 = (p1 - p0).cross(p3 - p0).normalized()
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p0)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p1)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p2)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p0)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p2)
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(p3)
