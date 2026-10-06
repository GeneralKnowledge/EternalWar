## Procedural starfield populations — 4-tier hierarchy + galactic dust.
## Magnitude hierarchy mirrors LT Starfield.lua (most faint, few bright).
## Tiers: micro (bg) → field (visible) → notable → gems (exceptional).
class_name StarfieldGen
extends RefCounted


static func build_from_composition(comp: Dictionary) -> Dictionary:
	## Returns {micro, field, notable, gems, dust} MultiMeshes driven by SkyComposition.
	var seed: int = int(comp.get("seed", 42))
	var galaxy_n: Vector3 = comp.get("galaxy_normal", Vector3.UP)
	var voids: Array = comp.get("voids", [])
	var masses: Array = comp.get("masses", [])
	var gem_defs: Array = comp.get("gems", [])
	return {
		"micro": _build_population(seed, "starfield_micro", int(comp.get("star_micro_count", 11000)), galaxy_n, voids, masses, 1),
		"field": _build_population(seed, "starfield_field", int(comp.get("star_field_count", 5600)), galaxy_n, voids, masses, 0),
		"notable": _build_population(seed, "starfield_notable", int(comp.get("star_notable_count", 180)), galaxy_n, voids, masses, 2),
		"gems": _build_gems(seed, gem_defs),
		"dust": build_galactic_dust(seed, int(comp.get("dust_count", 480)), galaxy_n, comp.get("palette", {})),
	}


static func build_multimesh(system_seed: int, count: int = 5600) -> MultiMesh:
	## Back-compat for tests — field population without full composition.
	var comp := SkyComposition.build(system_seed)
	return _build_population(system_seed, "starfield", count, comp["galaxy_normal"], comp["voids"], comp["masses"], 0)


static func build_galactic_dust(system_seed: int, count: int = 480, galaxy_n: Vector3 = Vector3.UP, palette: Dictionary = {}) -> MultiMesh:
	var rng := SeedHash.make_rng(system_seed, "galactic_dust")
	var positions := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var colors := PackedFloat32Array()
	positions.resize(count * 3)
	scales.resize(count)
	colors.resize(count * 4)
	var tint: Color = palette.get("primary", nebula_color(system_seed))
	var secondary: Color = palette.get("secondary", tint.darkened(0.2))
	for i in count:
		var dir := rng.dir3()
		dir = (dir - galaxy_n * dir.dot(galaxy_n) * rng.randf_range(0.6, 0.97)).normalized()
		var dist := rng.randf_range(4200.0, 9500.0)
		var size := rng.randf_range(35.0, 100.0)
		var a := rng.randf_range(0.07, 0.18)
		var c := tint.lerp(secondary, rng.randf())
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
		colors[c4 + 3] = a
	return _mm_from_soa(count, positions, scales, colors)


static func nebula_color(system_seed: int) -> Color:
	var comp := SkyComposition.build(system_seed)
	return comp["palette"]["primary"]


static func _mm_from_soa(count: int, positions: PackedFloat32Array, scales: PackedFloat32Array, colors: PackedFloat32Array) -> MultiMesh:
	## Pack MultiMesh from SoA buffers in GDScript (keeps visuals independent of optional instance kernels).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mm.mesh = quad
	mm.instance_count = count
	for i in count:
		var i3 := i * 3
		var pos := Vector3(positions[i3], positions[i3 + 1], positions[i3 + 2])
		var s := scales[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), pos))
		var c4 := i * 4
		mm.set_instance_color(i, Color(colors[c4], colors[c4 + 1], colors[c4 + 2], colors[c4 + 3]))
	return mm


static func _build_population(
	system_seed: int,
	tag: String,
	count: int,
	galaxy_n: Vector3,
	voids: Array,
	masses: Array,
	mode: int
) -> MultiMesh:
	## mode 0=field, 1=micro, 2=notable
	var rng := SeedHash.make_rng(system_seed, tag)
	var positions := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var colors := PackedFloat32Array()
	positions.resize(count * 3)
	scales.resize(count)
	colors.resize(count * 4)

	var clusters: Array[Vector3] = []
	clusters.append(rng.dir3())
	for i in mini(140, count):
		var base: Vector3 = clusters[rng.randi_range(0, clusters.size() - 1)]
		clusters.append((base + rng.dir3() * rng.randf_range(0.03, 0.45)).normalized())

	for i in count:
		var dir: Vector3
		var on_plane := rng.randf() < (0.55 if mode != 1 else 0.4)
		if on_plane:
			dir = rng.dir3()
			dir = (dir - galaxy_n * dir.dot(galaxy_n) * rng.randf_range(0.45, 0.95)).normalized()
			if rng.randf() < 0.5 and not clusters.is_empty():
				dir = (dir + clusters[rng.randi_range(0, clusters.size() - 1)] * 0.4).normalized()
		elif rng.randf() < 0.7:
			dir = (clusters[rng.randi_range(0, clusters.size() - 1)] + rng.dir3() * rng.randf_range(0.0, 0.12)).normalized()
		else:
			dir = rng.dir3()

		if not masses.is_empty() and rng.randf() < (0.45 if mode == 2 else 0.35):
			var m: Dictionary = masses[rng.randi_range(0, masses.size() - 1)]
			dir = (dir * 0.55 + m["dir"] * 0.45).normalized()
		dir = _avoid_voids(dir, voids, rng)

		var dist: float
		var mag: float
		var size: float
		# Interleave distances with nebula depth ranges so stars sit behind / inside / in front of gas.
		var near_d := 2800.0
		var far_d := 7200.0
		if not masses.is_empty():
			var rm: Dictionary = masses[rng.randi_range(0, masses.size() - 1)]
			near_d = float(rm.get("depth_near", near_d))
			far_d = float(rm.get("depth_far", far_d))
		match mode:
			1: # micro — always behind volumes
				dist = rng.randf_range(maxf(far_d + 800.0, 10000.0), 17000.0)
				mag = pow(rng.randf(), 3.4)
				size = lerpf(1.6, 4.8, mag)
			2: # notable — front half of volumes + near space
				var slot := rng.randf()
				if slot < 0.45:
					dist = rng.randf_range(maxf(1200.0, near_d * 0.55), near_d * 0.95)
				elif slot < 0.8:
					dist = lerpf(near_d, far_d, rng.randf_range(0.2, 0.7))
				else:
					dist = rng.randf_range(far_d * 0.9, far_d * 1.15)
				mag = lerpf(0.55, 0.92, pow(rng.randf(), 1.2))
				size = lerpf(9.0, 18.0, mag)
			_: # field — mostly behind / through volumes (occludable)
				var fslot := rng.randf()
				if fslot < 0.55:
					dist = rng.randf_range(far_d * 0.95, far_d * 1.45)
				elif fslot < 0.85:
					dist = lerpf(near_d, far_d, rng.randf())
				else:
					dist = rng.randf_range(near_d * 0.7, near_d)
				mag = pow(rng.randf(), 2.6)
				if on_plane:
					mag = minf(1.0, mag + 0.06)
				if mag > 0.88:
					size = lerpf(9.0, 16.0, (mag - 0.88) / 0.12)
				else:
					size = lerpf(2.6, 8.5, mag / 0.88)

		var temp_k := lerpf(2800.0, 14000.0, rng.randf())
		if rng.randf() < 0.72:
			temp_k = lerpf(3400.0, 7200.0, rng.randf())
		var col := StellarColour.from_temperature(temp_k)
		var bright: float
		match mode:
			1:
				bright = 0.12 + mag * 0.55
			2:
				bright = 0.7 + mag * 1.1
			_:
				bright = 0.22 + mag * mag * 1.35
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
	return _mm_from_soa(count, positions, scales, colors)


static func _build_gems(system_seed: int, gem_defs: Array) -> MultiMesh:
	var rng := SeedHash.make_rng(system_seed, "starfield_gems")
	var count := maxi(gem_defs.size(), 1)
	var positions := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var colors := PackedFloat32Array()
	positions.resize(count * 3)
	scales.resize(count)
	colors.resize(count * 4)
	for i in count:
		var g: Dictionary = gem_defs[i] if i < gem_defs.size() else {"dir": rng.dir3(), "temp": 6000.0, "mag": 0.8}
		var dir: Vector3 = g.get("dir", rng.dir3())
		var dist := float(g.get("dist", rng.randf_range(2400.0, 5600.0)))
		var mag := float(g.get("mag", 0.8))
		var size := lerpf(18.0, 34.0, mag)
		var col := StellarColour.from_temperature(float(g.get("temp", 6000.0)))
		var bright := 1.35 + mag * 1.7
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
	return _mm_from_soa(count, positions, scales, colors)


static func _avoid_voids(dir: Vector3, voids: Array, rng: SeededRNG) -> Vector3:
	if voids.is_empty():
		return dir
	for _attempt in 3:
		var hit := false
		for v in voids:
			var vd: Vector3 = v["dir"]
			var r: float = float(v.get("radius", 0.5))
			if dir.dot(vd) > (1.0 - r * 0.85):
				hit = true
				break
		if not hit:
			return dir
		dir = (dir + rng.dir3() * 0.6).normalized()
	return dir
