## Procedural starfield + galactic structure — clustered billboards, density lanes.
class_name StarfieldGen
extends RefCounted


static func build_multimesh(system_seed: int, count: int = 3200) -> MultiMesh:
	var rng := SeedHash.make_rng(system_seed, "starfield")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mm.mesh = quad
	mm.instance_count = count

	# Cluster seeds + galactic plane bias
	var clusters: Array[Vector3] = []
	clusters.append(rng.dir3())
	for i in mini(72, count):
		var base: Vector3 = clusters[rng.randi_range(0, clusters.size() - 1)]
		var p: Vector3 = (base + rng.dir3() * rng.randf_range(0.04, 0.48)).normalized()
		clusters.append(p)

	# Galactic plane normal (deterministic tilt)
	var plane_n := Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()

	for i in count:
		var dir: Vector3
		var on_plane := rng.randf() < 0.42
		if on_plane:
			# Sample near galactic plane: project random dir onto plane band
			dir = rng.dir3()
			dir = (dir - plane_n * dir.dot(plane_n) * rng.randf_range(0.55, 0.95)).normalized()
			if rng.randf() < 0.5:
				dir = (dir + clusters[rng.randi_range(0, clusters.size() - 1)] * 0.35).normalized()
		elif rng.randf() < 0.75:
			dir = clusters[rng.randi_range(0, clusters.size() - 1)]
			dir = (dir + rng.dir3() * rng.randf_range(0.0, 0.1)).normalized()
		else:
			dir = rng.dir3()

		var dist := rng.randf_range(7500.0, 15000.0)
		var mag := pow(rng.randf(), 2.5)
		if on_plane:
			mag = minf(1.0, mag + 0.08)
		var size := lerpf(2.8, 20.0, mag)
		var temp_k := lerpf(2800.0, 14000.0, rng.randf())
		# Hotter stars rarer
		if rng.randf() < 0.7:
			temp_k = lerpf(3000.0, 7000.0, rng.randf())
		var col := StellarColour.from_temperature(temp_k)
		var bright := 0.35 + mag * 1.0
		col = Color(col.r * bright, col.g * bright, col.b * bright)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * dist))
		mm.set_instance_color(i, col)
	return mm


static func build_galactic_dust(system_seed: int, count: int = 400) -> MultiMesh:
	## Faint large-scale dust along the galactic plane.
	var rng := SeedHash.make_rng(system_seed, "galactic_dust")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mm.mesh = quad
	mm.instance_count = count
	var plane_n := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized()
	var tint := nebula_color(system_seed)
	for i in count:
		var dir := rng.dir3()
		dir = (dir - plane_n * dir.dot(plane_n) * rng.randf_range(0.7, 0.98)).normalized()
		var dist := rng.randf_range(5000.0, 11000.0)
		var size := rng.randf_range(40.0, 120.0)
		var a := rng.randf_range(0.04, 0.14)
		var c := Color(tint.r, tint.g, tint.b, a)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * dist))
		mm.set_instance_color(i, c)
	return mm


static func nebula_color(system_seed: int) -> Color:
	var rng := SeedHash.make_rng(system_seed, "nebula")
	var h := rng.randf()
	var s := rng.randf_range(0.3, 0.7)
	var l := rng.randf_range(0.12, 0.35)
	return Color.from_hsv(h, s, l)
