## Procedural starfield + galactic structure — clustered billboards, density lanes.
class_name StarfieldGen
extends RefCounted


static func build_multimesh(system_seed: int, count: int = 6200) -> MultiMesh:
	## Dense star points: mostly small, a few brighter gems — not bokeh discs.
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
	for i in mini(120, count):
		var base: Vector3 = clusters[rng.randi_range(0, clusters.size() - 1)]
		clusters.append((base + rng.dir3() * rng.randf_range(0.04, 0.5)).normalized())

	var plane_n := Vector3(rng.randf_range(-0.22, 0.22), 1.0, rng.randf_range(-0.22, 0.22)).normalized()

	var positions := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var colors := PackedFloat32Array()
	positions.resize(count * 3)
	scales.resize(count)
	colors.resize(count * 4)

	for i in count:
		var dir: Vector3
		var on_plane := rng.randf() < 0.5
		if on_plane:
			dir = rng.dir3()
			dir = (dir - plane_n * dir.dot(plane_n) * rng.randf_range(0.5, 0.95)).normalized()
			if rng.randf() < 0.55:
				dir = (dir + clusters[rng.randi_range(0, clusters.size() - 1)] * 0.4).normalized()
		elif rng.randf() < 0.7:
			dir = (clusters[rng.randi_range(0, clusters.size() - 1)] + rng.dir3() * rng.randf_range(0.0, 0.14)).normalized()
		else:
			dir = rng.dir3()

		var dist := rng.randf_range(3200.0, 7800.0)
		var mag := pow(rng.randf(), 2.4)
		if on_plane:
			mag = minf(1.0, mag + 0.08)
		# Small sharp points; rare gems a bit larger.
		var size: float
		if mag > 0.82:
			size = lerpf(14.0, 28.0, (mag - 0.82) / 0.18)
		else:
			size = lerpf(3.5, 12.0, mag / 0.82)
		var temp_k := lerpf(2800.0, 14000.0, rng.randf())
		if rng.randf() < 0.7:
			temp_k = lerpf(3400.0, 7400.0, rng.randf())
		var col := StellarColour.from_temperature(temp_k)
		var bright := 0.9 + mag * 1.5
		col = Color(col.r * bright, col.g * bright, col.b * bright)
		var pos := dir * dist
		var i3 := i * 3
		positions[i3] = pos.x
		positions[i3 + 1] = pos.y
		positions[i3 + 2] = pos.z
		scales[i] = size
		var c4 := i * 4
		colors[c4] = col.r
		colors[c4 + 1] = col.g
		colors[c4 + 2] = col.b
		colors[c4 + 3] = col.a

	NativeBridge.fill_scaled_instances(mm, positions, scales)
	NativeBridge.fill_instance_colors(mm, colors)
	return mm


static func build_galactic_dust(system_seed: int, count: int = 480) -> MultiMesh:
	## Soft large-scale dust along the galactic plane (subtle, not giant bokeh).
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

	var positions := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var colors := PackedFloat32Array()
	positions.resize(count * 3)
	scales.resize(count)
	colors.resize(count * 4)

	for i in count:
		var dir := rng.dir3()
		dir = (dir - plane_n * dir.dot(plane_n) * rng.randf_range(0.65, 0.98)).normalized()
		var dist := rng.randf_range(4000.0, 9000.0)
		var size := rng.randf_range(40.0, 110.0)
		var a := rng.randf_range(0.08, 0.2)
		var c := Color(
			lerpf(tint.r, 0.45, 0.35),
			lerpf(tint.g, 0.5, 0.3),
			lerpf(tint.b, 0.95, 0.45),
			a
		)
		var pos := dir * dist
		var i3 := i * 3
		positions[i3] = pos.x
		positions[i3 + 1] = pos.y
		positions[i3 + 2] = pos.z
		scales[i] = size
		var c4 := i * 4
		colors[c4] = c.r
		colors[c4 + 1] = c.g
		colors[c4 + 2] = c.b
		colors[c4 + 3] = c.a

	NativeBridge.fill_scaled_instances(mm, positions, scales)
	NativeBridge.fill_instance_colors(mm, colors)
	return mm


static func nebula_color(system_seed: int) -> Color:
	var rng := SeedHash.make_rng(system_seed, "nebula")
	var hue_pick := rng.randf()
	var hue: float
	if hue_pick < 0.3:
		hue = rng.randf_range(0.52, 0.62)
	elif hue_pick < 0.6:
		hue = rng.randf_range(0.62, 0.78)
	elif hue_pick < 0.85:
		hue = rng.randf_range(0.78, 0.92)
	else:
		hue = rng.randf_range(0.92, 1.0)
		if rng.randf() < 0.45:
			hue = rng.randf_range(0.0, 0.06)
	return Color.from_hsv(hue, rng.randf_range(0.45, 0.78), rng.randf_range(0.22, 0.42))
