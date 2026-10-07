## Seeded sky composition — WHERE structure lives; shaders decide WHAT it looks like.
## Nebula masses describe volumetric ranges (center, radius, depth_near/far), not just billboard shells.
class_name SkyComposition
extends RefCounted

const MOODS := ["indigo_violet", "amber_gold", "cyan_teal", "magenta_rose", "crimson", "cold_white"]


## Build a full sky composition from the system seed (+ optional nebula hue hint).
## Pass mood_override (e.g. "amber_gold") to force a palette family for galleries/sheets.
static func build(
	system_seed: int,
	nebula_hint: Color = Color(0.3, 0.25, 0.55),
	mood_override: String = ""
) -> Dictionary:
	var rng := SeedHash.make_rng(system_seed, "sky_composition")
	var mood_i := rng.randi_range(0, MOODS.size() - 1)
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
	if mood_override != "" and mood_override in MOODS:
		mood = mood_override
	var palette := _palette_for(mood, rng, nebula_hint)

	var galaxy_normal := Vector3(
		rng.randf_range(-0.35, 0.35),
		1.0,
		rng.randf_range(-0.35, 0.35)
	).normalized()
	var band_width := rng.randf_range(2.8, 4.6)
	var band_strength := rng.randf_range(0.55, 0.95)

	var masses: Array = []
	var mass_n := rng.randi_range(2, 4)
	for i in mass_n:
		var dir := _sample_near_plane(rng, galaxy_normal, 0.15 if i < mass_n - 1 else 0.75)
		if i == 0:
			dir = (dir + Vector3(0.4, 0.1, 0.35)).normalized()
		var center_dist := rng.randf_range(3200.0, 7800.0)
		var radius := rng.randf_range(2200.0, 4600.0) * lerpf(0.9, 1.35, float(i == 0))
		var half_thick := radius * rng.randf_range(0.6, 1.05)
		var depth_near := maxf(900.0, center_dist - half_thick)
		var depth_far := center_dist + half_thick
		var scale := rng.randf_range(0.55, 1.35)
		masses.append({
			"dir": dir,
			"center": dir * center_dist,
			"center_dist": center_dist,
			"radius": radius,
			"depth_near": depth_near,
			"depth_far": depth_far,
			"scale": scale,
			"core": rng.randf_range(0.4, 0.9),
			"dark": rng.randf_range(0.35, 0.7), # cavity strength
			"filament": rng.randf_range(0.45, 0.95),
			"density": rng.randf_range(0.9, 1.55),
			"emission": rng.randf_range(1.0, 1.6),
			"color_t": rng.randf(),
			"depth": clampf((center_dist - 3200.0) / 4600.0, 0.0, 1.0), # legacy sky hint
			"shell": center_dist,
			"seed": rng.randi(),
			"elongation": Vector3(
				rng.randf_range(0.75, 1.35),
				rng.randf_range(0.45, 0.9),
				rng.randf_range(0.8, 1.4)
			),
			"volumetric": i < 3, # major masses raymarched; last may be wisp-only accent
		})

	var voids: Array = []
	for i in rng.randi_range(2, 3):
		var vdir := rng.dir3()
		if not masses.is_empty():
			var primary: Vector3 = masses[0]["dir"]
			if vdir.dot(primary) > 0.15:
				vdir = (-primary + rng.dir3() * 0.55).normalized()
		voids.append({
			"dir": vdir,
			# Wider voids → more near-black coverage (LT dark_frac ~28–40%).
			"radius": rng.randf_range(0.48, 0.85),
		})

	var gems: Array = []
	for i in rng.randi_range(4, 8):
		var gdir: Vector3
		var gdist := rng.randf_range(2400.0, 5600.0)
		if rng.randf() < 0.65 and not masses.is_empty():
			var m: Dictionary = masses[rng.randi_range(0, masses.size() - 1)]
			gdir = (m["dir"] + rng.dir3() * rng.randf_range(0.05, 0.35)).normalized()
			# Place gems near the front / mid of a volume so they can sit in gas
			gdist = lerpf(float(m["depth_near"]), float(m["depth_far"]), rng.randf_range(0.15, 0.7))
		else:
			gdir = _sample_near_plane(rng, galaxy_normal, 0.45)
		gems.append({
			"dir": gdir,
			"dist": gdist,
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
		"star_field_count": rng.randi_range(4200, 6400),
		"star_micro_count": rng.randi_range(10000, 15000),
		"star_notable_count": rng.randi_range(120, 220),
		"dust_count": rng.randi_range(380, 620),
		"volume_quality": 0, # world volumes demoted — IFS sky is the nebula
		"debug_nebula": 0,
		"roughness": rng.randf_range(0.62, 0.78), # LT nebula IFS roughness
	}


static func primary_mass_dir(comp: Dictionary) -> Vector3:
	var masses: Array = comp.get("masses", [])
	if masses.is_empty():
		return Vector3(0.4, 0.1, 0.35).normalized()
	return masses[0]["dir"]


static func primary_mass(comp: Dictionary) -> Dictionary:
	var masses: Array = comp.get("masses", [])
	if masses.is_empty():
		return {}
	return masses[0]


static func _palette_for(mood: String, rng: SeededRNG, hint: Color) -> Dictionary:
	var primary: Color
	var secondary: Color
	var band: Color
	var bg: Color
	var accent: Color
	match mood:
		"amber_gold":
			# LT cockpit warmth — ochre / ember, not desaturated sand
			primary = Color.from_hsv(0.09, 0.72, 0.55)
			secondary = Color.from_hsv(0.06, 0.55, 0.32)
			band = Color.from_hsv(0.11, 0.35, 0.58)
			bg = Color(0.018, 0.014, 0.022)
			accent = Color.from_hsv(0.08, 0.42, 0.88)
		"cyan_teal":
			primary = Color.from_hsv(0.52, 0.55, 0.42)
			secondary = Color.from_hsv(0.58, 0.38, 0.28)
			band = Color.from_hsv(0.55, 0.22, 0.5)
			bg = Color(0.012, 0.02, 0.032)
			accent = Color.from_hsv(0.5, 0.3, 0.8)
		"magenta_rose":
			# LT ship-gas magenta / rose
			primary = Color.from_hsv(0.91, 0.72, 0.55)
			secondary = Color.from_hsv(0.86, 0.48, 0.30)
			band = Color.from_hsv(0.93, 0.32, 0.58)
			bg = Color(0.022, 0.012, 0.024)
			accent = Color.from_hsv(0.95, 0.40, 0.88)
		"crimson":
			primary = Color.from_hsv(0.0, 0.72, 0.48)
			secondary = Color.from_hsv(0.97, 0.52, 0.28)
			band = Color.from_hsv(0.02, 0.36, 0.50)
			bg = Color(0.022, 0.01, 0.016)
			accent = Color.from_hsv(0.05, 0.45, 0.82)
		"cold_white":
			primary = Color.from_hsv(0.6, 0.2, 0.45)
			secondary = Color.from_hsv(0.65, 0.15, 0.28)
			band = Color.from_hsv(0.58, 0.1, 0.55)
			bg = Color(0.014, 0.016, 0.028)
			accent = Color(0.8, 0.85, 0.95)
		_:
			primary = Color.from_hsv(0.72, 0.52, 0.42)
			secondary = Color.from_hsv(0.62, 0.38, 0.28)
			band = Color.from_hsv(0.68, 0.22, 0.5)
			bg = Color(0.012, 0.014, 0.032)
			accent = Color.from_hsv(0.58, 0.28, 0.85)
	# Keep mood identity — only a light hue nudge from the system hint.
	# Strong lerp toward cool hints was washing amber/magenta into blue-violet.
	var hint_w := 0.08
	if mood in ["amber_gold", "magenta_rose", "crimson"]:
		hint_w = 0.04
	elif mood in ["cyan_teal", "indigo_violet", "cold_white"]:
		hint_w = 0.10
	primary = primary.lerp(hint, hint_w)
	secondary = secondary.lerp(hint, hint_w * 0.5)
	primary = Color.from_hsv(
		fmod(primary.h + rng.randf_range(-0.025, 0.025) + 1.0, 1.0),
		clampf(primary.s + rng.randf_range(-0.04, 0.06), 0.28, 0.88),
		clampf(primary.v + rng.randf_range(-0.03, 0.05), 0.28, 0.68)
	)
	return {
		"bg": bg,
		"band": band,
		"primary": primary,
		"secondary": secondary,
		"accent": accent,
		"fog": primary.lerp(bg, 0.7),
		"ambient": bg.lerp(primary, 0.28),
	}


static func _sample_near_plane(rng: SeededRNG, plane_n: Vector3, off_plane: float) -> Vector3:
	var dir := rng.dir3()
	dir = (dir - plane_n * dir.dot(plane_n) * (1.0 - off_plane)).normalized()
	return dir
