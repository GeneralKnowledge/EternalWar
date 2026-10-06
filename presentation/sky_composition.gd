## Seeded sky composition — WHERE structure lives; shaders decide WHAT it looks like.
## Inspired by Limit Theory's Nebula env-map + Starfield split (not a clone).
class_name SkyComposition
extends RefCounted

const MOODS := ["indigo_violet", "amber_gold", "cyan_teal", "magenta_rose", "crimson", "cold_white"]


## Build a full sky composition from the system seed (+ optional nebula hue hint).
static func build(system_seed: int, nebula_hint: Color = Color(0.3, 0.25, 0.55)) -> Dictionary:
	var rng := SeedHash.make_rng(system_seed, "sky_composition")
	var mood_i := rng.randi_range(0, MOODS.size() - 1)
	# Bias mood toward nebula hint when saturated.
	if nebula_hint.s > 0.35:
		var h := nebula_hint.h
		if h > 0.5 and h < 0.7:
			mood_i = 0 if rng.randf() < 0.55 else 2
		elif h >= 0.7 and h < 0.95:
			mood_i = 3 if rng.randf() < 0.6 else 0
		elif h < 0.08 or h > 0.95:
			mood_i = 4 if rng.randf() < 0.5 else 3
		elif h > 0.08 and h < 0.2:
			mood_i = 1
	var mood: String = MOODS[mood_i]
	var palette := _palette_for(mood, rng, nebula_hint)

	# Galactic plane: tilted, not axis-aligned — large compositional anchor.
	var galaxy_normal := Vector3(
		rng.randf_range(-0.35, 0.35),
		1.0,
		rng.randf_range(-0.35, 0.35)
	).normalized()
	var band_width := rng.randf_range(2.8, 4.6) # higher = thinner band
	var band_strength := rng.randf_range(0.55, 0.95)

	# Nebula masses along / near the galactic plane + one off-axis accent.
	var masses: Array = []
	var mass_n := rng.randi_range(2, 4)
	for i in mass_n:
		var dir := _sample_near_plane(rng, galaxy_normal, 0.15 if i < mass_n - 1 else 0.75)
		# Push some masses into a preferred "bright hemisphere" for cinema framing.
		if i == 0:
			dir = (dir + Vector3(0.4, 0.1, 0.35)).normalized()
		masses.append({
			"dir": dir,
			"scale": rng.randf_range(0.55, 1.35),
			"core": rng.randf_range(0.35, 0.85),
			"dark": rng.randf_range(0.25, 0.65),
			"color_t": rng.randf(), # blend primary↔secondary
			"depth": rng.randf_range(0.35, 1.0),
			"shell": rng.randf_range(3500.0, 9000.0),
		})

	# Explicit negative-space cones — large dark resting areas.
	var voids: Array = []
	for i in rng.randi_range(2, 3):
		var vdir := rng.dir3()
		# Prefer voids away from primary mass.
		if not masses.is_empty():
			var primary: Vector3 = masses[0]["dir"]
			if vdir.dot(primary) > 0.2:
				vdir = (-primary + rng.dir3() * 0.4).normalized()
		voids.append({
			"dir": vdir,
			"radius": rng.randf_range(0.35, 0.7),
		})

	# Memorable gem stars (composition anchors).
	var gems: Array = []
	for i in rng.randi_range(4, 8):
		var gdir: Vector3
		if rng.randf() < 0.65 and not masses.is_empty():
			var m: Dictionary = masses[rng.randi_range(0, masses.size() - 1)]
			gdir = (m["dir"] + rng.dir3() * rng.randf_range(0.05, 0.35)).normalized()
		else:
			gdir = _sample_near_plane(rng, galaxy_normal, 0.45)
		gems.append({
			"dir": gdir,
			"temp": lerpf(3200.0, 12000.0, rng.randf()),
			"mag": rng.randf_range(0.65, 1.0),
		})

	return {
		"seed": system_seed,
		"mood": mood,
		"palette": palette,
		"galaxy_normal": galaxy_normal,
		"band_width": band_width,
		"band_strength": band_strength,
		"masses": masses,
		"voids": voids,
		"gems": gems,
		"star_field_count": rng.randi_range(4800, 7200),
		"star_micro_count": rng.randi_range(9000, 14000),
		"dust_count": rng.randi_range(380, 620),
	}


static func primary_mass_dir(comp: Dictionary) -> Vector3:
	var masses: Array = comp.get("masses", [])
	if masses.is_empty():
		return Vector3(0.4, 0.1, 0.35).normalized()
	return masses[0]["dir"]


static func _palette_for(mood: String, rng: SeededRNG, hint: Color) -> Dictionary:
	var primary: Color
	var secondary: Color
	var band: Color
	var bg: Color
	var accent: Color
	match mood:
		"amber_gold":
			primary = Color.from_hsv(0.1, 0.7, 0.55)
			secondary = Color.from_hsv(0.08, 0.55, 0.35)
			band = Color.from_hsv(0.12, 0.35, 0.7)
			bg = Color(0.04, 0.03, 0.05)
			accent = Color.from_hsv(0.08, 0.4, 0.9)
		"cyan_teal":
			primary = Color.from_hsv(0.52, 0.65, 0.5)
			secondary = Color.from_hsv(0.58, 0.45, 0.35)
			band = Color.from_hsv(0.55, 0.3, 0.65)
			bg = Color(0.03, 0.045, 0.07)
			accent = Color.from_hsv(0.5, 0.35, 0.85)
		"magenta_rose":
			primary = Color.from_hsv(0.9, 0.7, 0.55)
			secondary = Color.from_hsv(0.85, 0.5, 0.32)
			band = Color.from_hsv(0.92, 0.35, 0.7)
			bg = Color(0.05, 0.03, 0.055)
			accent = Color.from_hsv(0.95, 0.4, 0.9)
		"crimson":
			primary = Color.from_hsv(0.0, 0.72, 0.48)
			secondary = Color.from_hsv(0.97, 0.55, 0.28)
			band = Color.from_hsv(0.02, 0.4, 0.6)
			bg = Color(0.05, 0.025, 0.04)
			accent = Color.from_hsv(0.05, 0.45, 0.85)
		"cold_white":
			primary = Color.from_hsv(0.6, 0.25, 0.55)
			secondary = Color.from_hsv(0.65, 0.2, 0.35)
			band = Color.from_hsv(0.58, 0.12, 0.75)
			bg = Color(0.035, 0.04, 0.06)
			accent = Color(0.85, 0.9, 1.0)
		_: # indigo_violet
			primary = Color.from_hsv(0.72, 0.6, 0.5)
			secondary = Color.from_hsv(0.62, 0.45, 0.35)
			band = Color.from_hsv(0.68, 0.3, 0.65)
			bg = Color(0.03, 0.035, 0.08)
			accent = Color.from_hsv(0.58, 0.35, 0.9)
	# Nudge toward nebula hint without breaking mood.
	primary = primary.lerp(hint, 0.22)
	secondary = secondary.lerp(hint, 0.12)
	# Tiny seeded jitter
	primary = Color.from_hsv(
		fmod(primary.h + rng.randf_range(-0.03, 0.03) + 1.0, 1.0),
		clampf(primary.s + rng.randf_range(-0.05, 0.05), 0.25, 0.85),
		clampf(primary.v + rng.randf_range(-0.04, 0.04), 0.25, 0.65)
	)
	return {
		"bg": bg,
		"band": band,
		"primary": primary,
		"secondary": secondary,
		"accent": accent,
		"fog": primary.lerp(bg, 0.55),
		"ambient": bg.lerp(primary, 0.35),
	}


static func _sample_near_plane(rng: SeededRNG, plane_n: Vector3, off_plane: float) -> Vector3:
	var dir := rng.dir3()
	dir = (dir - plane_n * dir.dot(plane_n) * (1.0 - off_plane)).normalized()
	return dir
