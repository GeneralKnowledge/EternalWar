## Procedural starfield + optional nebula tint for the system environment.
## Inspired by LT Starfield.lua: clustered points with temperature colours.
class_name StarfieldGen
extends RefCounted


static func build_multimesh(system_seed: int, count: int = 2500) -> MultiMesh:
	var rng := SeedHash.make_rng(system_seed, "starfield")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 4
	sphere.rings = 2
	mm.mesh = sphere
	mm.instance_count = count

	# Cluster seed points (LT-style: grow from existing stars)
	var clusters: Array[Vector3] = []
	clusters.append(rng.dir3())
	for i in mini(48, count):
		var base: Vector3 = clusters[rng.randi_range(0, clusters.size() - 1)]
		var p: Vector3 = (base + rng.dir3() * rng.randf_range(0.05, 0.55)).normalized()
		clusters.append(p)

	for i in count:
		var dir: Vector3
		if rng.randf() < 0.7:
			dir = clusters[rng.randi_range(0, clusters.size() - 1)]
			dir = (dir + rng.dir3() * rng.randf_range(0.0, 0.12)).normalized()
		else:
			dir = rng.dir3()
		var dist := rng.randf_range(9000.0, 16000.0)
		var size := rng.randf_range(2.5, 14.0) * (0.4 + rng.randf() * rng.randf())
		var temp_t := rng.randf()
		var col := _temp_color(temp_t)
		var bright := pow(rng.randf(), 2.2)
		col = col.lightened(bright * 0.35)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * dist))
		mm.set_instance_color(i, col)
	return mm


static func nebula_color(system_seed: int) -> Color:
	var rng := SeedHash.make_rng(system_seed, "nebula")
	var h := rng.randf()
	var s := rng.randf_range(0.25, 0.65)
	var l := rng.randf_range(0.08, 0.22)
	return Color.from_hsv(h, s, l)


static func _temp_color(t: float) -> Color:
	# Rough blackbody-ish: cool red → hot blue-white
	if t < 0.25:
		return Color(1.0, 0.55, 0.35)
	if t < 0.5:
		return Color(1.0, 0.85, 0.6)
	if t < 0.75:
		return Color(0.95, 0.95, 1.0)
	return Color(0.65, 0.78, 1.0)
