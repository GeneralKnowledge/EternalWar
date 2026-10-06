## Procedural starfield + galactic structure — clustered billboards, density lanes.
class_name StarfieldGen
extends RefCounted


static func build_multimesh(system_seed: int, count: int = 4800) -> MultiMesh:
	## Dense far-field stars. Counts should stay high so empty sky never reads as flat black.
	var rng := SeedHash.make_rng(system_seed, "starfield")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mm.mesh = quad
	mm.instance_count = count

	var clusters: Array[Vector3] = []
	clusters.append(rng.dir3())
	for i in mini(96, count):
		var base: Vector3 = clusters[rng.randi_range(0, clusters.size() - 1)]
		clusters.append((base + rng.dir3() * rng.randf_range(0.04, 0.48)).normalized())

	# Galactic plane normal (deterministic tilt)
	var plane_n := Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()

	for i in count:
		var dir: Vector3
		var on_plane := rng.randf() < 0.45
		if on_plane:
			dir = rng.dir3()
			dir = (dir - plane_n * dir.dot(plane_n) * rng.randf_range(0.55, 0.95)).normalized()
			if rng.randf() < 0.5:
				dir = (dir + clusters[rng.randi_range(0, clusters.size() - 1)] * 0.35).normalized()
		elif rng.randf() < 0.72:
			dir = (clusters[rng.randi_range(0, clusters.size() - 1)] + rng.dir3() * rng.randf_range(0.0, 0.12)).normalized()
		else:
			dir = rng.dir3()

		var dist := rng.randf_range(7200.0, 14800.0)
		var mag := pow(rng.randf(), 2.2)
		if on_plane:
			mag = minf(1.0, mag + 0.1)
		# Keep points small so they read as stars, not glowing discs under bloom.
		var size := lerpf(3.2, 14.0, mag)
		var temp_k := lerpf(2800.0, 14000.0, rng.randf())
		if rng.randf() < 0.7:
			temp_k = lerpf(3200.0, 7200.0, rng.randf())
		var col := StellarColour.from_temperature(temp_k)
		# Bright enough to survive ACES + dark sky without forcing bloom blowout.
		var bright := 0.55 + mag * 1.15
		col = Color(col.r * bright, col.g * bright, col.b * bright)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * dist))
		mm.set_instance_color(i, col)
	return mm


static func build_galactic_dust(system_seed: int, count: int = 520) -> MultiMesh:
	## Soft large-scale dust along the galactic plane — structure without washing the sky.
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
		var dist := rng.randf_range(5200.0, 12000.0)
		var size := rng.randf_range(55.0, 160.0)
		var a := rng.randf_range(0.06, 0.18)
		var c := Color(
			lerpf(tint.r, 0.55, 0.25),
			lerpf(tint.g, 0.5, 0.2),
			lerpf(tint.b, 0.75, 0.35),
			a
		)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * dist))
		mm.set_instance_color(i, c)
	return mm


static func nebula_color(system_seed: int) -> Color:
	var rng := SeedHash.make_rng(system_seed, "nebula")
	var h := rng.randf()
	var s := rng.randf_range(0.35, 0.72)
	var l := rng.randf_range(0.16, 0.38)
	return Color.from_hsv(h, s, l)
