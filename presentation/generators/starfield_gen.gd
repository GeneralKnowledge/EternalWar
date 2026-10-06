## Procedural starfield — clustered billboard quads with temperature colours.
## Inspired by LT Starfield.lua.
class_name StarfieldGen
extends RefCounted


static func build_multimesh(system_seed: int, count: int = 2800) -> MultiMesh:
	var rng := SeedHash.make_rng(system_seed, "starfield")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mm.mesh = quad
	mm.instance_count = count

	# Cluster seed points (LT-style: grow from existing stars)
	var clusters: Array[Vector3] = []
	clusters.append(rng.dir3())
	for i in mini(64, count):
		var base: Vector3 = clusters[rng.randi_range(0, clusters.size() - 1)]
		var p: Vector3 = (base + rng.dir3() * rng.randf_range(0.04, 0.5)).normalized()
		clusters.append(p)

	for i in count:
		var dir: Vector3
		if rng.randf() < 0.78:
			dir = clusters[rng.randi_range(0, clusters.size() - 1)]
			dir = (dir + rng.dir3() * rng.randf_range(0.0, 0.1)).normalized()
		else:
			dir = rng.dir3()
		var dist := rng.randf_range(7000.0, 14000.0)
		# Magnitude: many faint, few bright
		var mag := pow(rng.randf(), 2.4)
		var size := lerpf(4.0, 36.0, mag)
		var temp_t := rng.randf()
		var col := _temp_color(temp_t)
		var bright := 0.4 + mag * 0.95
		col = Color(col.r * bright, col.g * bright, col.b * bright)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * dist))
		mm.set_instance_color(i, col)
	return mm


static func nebula_color(system_seed: int) -> Color:
	var rng := SeedHash.make_rng(system_seed, "nebula")
	var h := rng.randf()
	var s := rng.randf_range(0.3, 0.7)
	var l := rng.randf_range(0.12, 0.35)
	return Color.from_hsv(h, s, l)


static func _temp_color(t: float) -> Color:
	if t < 0.2:
		return Color(1.0, 0.5, 0.32)
	if t < 0.45:
		return Color(1.0, 0.82, 0.55)
	if t < 0.7:
		return Color(0.96, 0.96, 1.0)
	return Color(0.55, 0.72, 1.0)
