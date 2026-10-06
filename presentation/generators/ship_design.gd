## Semantic ship design descriptor — simulation constraints → intentional design language.
## Hierarchical tiers: silhouette → functional → secondary → surface (see ship plan).
## Visual generators consume this; they do not need economy internals.
class_name ShipDesign
extends RefCounted


## Build a full design description from a ship design dictionary (+ optional sim extras).
static func build(design: Dictionary, extras: Dictionary = {}) -> Dictionary:
	var design_seed: int = int(design.get("seed", 1))
	var ship_class: int = int(design.get("ship_class", SimEntities.ShipClass.TRADER))
	var style: String = str(design.get("style", "civilian"))
	var profile: Dictionary = StyleProfile.of(style)

	var hull_seed := SeedHash.derive(design_seed, "hull")
	var engine_seed := SeedHash.derive(design_seed, "engine")
	var module_seed := SeedHash.derive(design_seed, "module")
	var detail_seed := SeedHash.derive(design_seed, "detail")

	var hull_rng := SeededRNG.new(hull_seed)
	var eng_rng := SeededRNG.new(engine_seed)
	var mod_rng := SeededRNG.new(module_seed)
	var det_rng := SeededRNG.new(detail_seed)

	var dims := _role_dims(ship_class, hull_rng, profile)
	var length: float = float(dims["length"])
	var width: float = float(dims["width"])
	var height: float = float(dims["height"])
	var symmetric := hull_rng.randf() < float(profile["symmetry"])
	var gap := float(profile.get("negative_space", 0.4))
	var hull_lang := str(profile.get("hull_language", "wedge"))
	var hull_sides := int(profile.get("hull_sides", 6))
	if hull_lang == "block":
		hull_sides = mini(hull_sides, 5)
	elif hull_lang == "round":
		hull_sides = maxi(hull_sides, 8)

	var exhaust := StyleProfile.exhaust_color(profile, eng_rng)

	# Tier 1 — silhouette hull descriptor
	var hull := {
		"language": hull_lang,
		"sides": hull_sides,
		"nose_taper": float(profile["taper"]),
		"aft_taper": lerpf(0.82, 0.95, float(profile["taper"])),
		"center": Vector3.ZERO,
	}

	# Tier 2 — engines
	var engines: Array = []
	var engine_n: int = int(dims["engines"])
	for i in engine_n:
		var t := 0.0
		if engine_n > 1:
			t = (float(i) / float(engine_n - 1) - 0.5) * width * lerpf(0.55, 0.85, 1.0 - gap)
		if not symmetric and eng_rng.randf() < 0.4 and i == engine_n - 1:
			t += eng_rng.randf_range(0.08, 0.28) * width
		var y_off := -height * eng_rng.randf_range(0.05, 0.18)
		engines.append({
			"pos": Vector3(t, y_off, length * 0.48),
			"radius": width * 0.08 * float(profile["engine_scale"]) * eng_rng.randf_range(0.9, 1.15),
			"length": length * 0.16 * eng_rng.randf_range(0.85, 1.25),
			"exhaust": exhaust,
		})

	var modules: Array = _role_modules(ship_class, length, width, height, mod_rng, symmetric, profile, gap)
	var hardpoints: Array = _role_hardpoints(ship_class, length, width, height, mod_rng, symmetric, style)
	var wings: Array = _role_wings(ship_class, length, width, height, det_rng, symmetric, style, profile)
	var struts: Array = _role_struts(modules, length, width, height, mod_rng, profile, gap)
	var plates: Array = _role_plates(ship_class, length, width, height, det_rng, profile, style)

	var cargo_capacity := float(extras.get("cargo_capacity", dims.get("cargo", 0) * 20.0))
	var engine_power := float(extras.get("speed", 70.0))

	# Desaturate / darken hull colours toward LT matte silhouette language
	var color: Color = design.get("color", Color(0.55, 0.55, 0.58))
	var accent: Color = design.get("accent", Color(0.4, 0.38, 0.35))
	color = _matte_hull(color, style)
	accent = _matte_accent(accent, style)

	return {
		"seed": design_seed,
		"hull_seed": hull_seed,
		"engine_seed": engine_seed,
		"module_seed": module_seed,
		"detail_seed": detail_seed,
		"ship_class": ship_class,
		"style": style,
		"profile": profile,
		"length": length,
		"width": width,
		"height": height,
		"nose_taper": float(profile["taper"]),
		"symmetric": symmetric,
		"hull": hull,
		"engines": engines,
		"modules": modules,
		"hardpoints": hardpoints,
		"wings": wings,
		"struts": struts,
		"plates": plates,
		"exhaust": exhaust,
		"color": color,
		"accent": accent,
		"cargo_capacity": cargo_capacity,
		"engine_power": engine_power,
		"role_name": SimEntities.class_name_of(ship_class),
		"lod_hint": int(extras.get("lod", VisualLOD.LOD_FULL)),
		"negative_space": gap,
	}


static func _matte_hull(c: Color, style: String) -> Color:
	var v := clampf(c.v * 0.55 + 0.12, 0.15, 0.55)
	var s := clampf(c.s * 0.45, 0.05, 0.45)
	match style:
		"military":
			v = lerpf(v, 0.28, 0.5)
			s = lerpf(s, 0.08, 0.5)
		"mining", "industrial":
			v = lerpf(v, 0.32, 0.4)
			s = lerpf(s, 0.22, 0.3)
		"luxury":
			v = lerpf(v, 0.62, 0.4)
			s = lerpf(s, 0.08, 0.4)
		"pirate":
			v = lerpf(v, 0.25, 0.4)
			s = lerpf(s, 0.2, 0.3)
	return Color.from_hsv(c.h, s, v)


static func _matte_accent(c: Color, style: String) -> Color:
	var s := clampf(c.s * 0.55, 0.08, 0.5)
	var v := clampf(c.v * 0.7, 0.18, 0.55)
	if style == "luxury":
		v = lerpf(v, 0.7, 0.4)
	return Color.from_hsv(c.h, s, v)


static func _role_dims(ship_class: int, rng: SeededRNG, profile: Dictionary) -> Dictionary:
	var stretch := lerpf(0.95, 1.12, 1.0 - float(profile["taper"]))
	match ship_class:
		SimEntities.ShipClass.MINER:
			return {
				"length": rng.randf_range(2.8, 3.8) * stretch,
				"width": rng.randf_range(1.7, 2.35),
				"height": rng.randf_range(1.05, 1.45),
				"engines": 2,
				"cargo": 2,
			}
		SimEntities.ShipClass.HAULER:
			# Long sausage proportions (LT capital light).
			return {
				"length": rng.randf_range(4.6, 6.2) * stretch,
				"width": rng.randf_range(1.35, 1.85),
				"height": rng.randf_range(1.05, 1.45),
				"engines": 3,
				"cargo": 6,
			}
		SimEntities.ShipClass.PATROL:
			# Flat interceptor — LT fighter proportions (readable prism, not a pancake).
			return {
				"length": rng.randf_range(2.4, 3.2) * stretch,
				"width": rng.randf_range(1.45, 2.05),
				"height": rng.randf_range(0.48, 0.72),
				"engines": 2,
				"cargo": 0,
			}
		_:
			return {
				"length": rng.randf_range(2.5, 3.4) * stretch,
				"width": rng.randf_range(1.25, 1.8),
				"height": rng.randf_range(0.7, 1.1),
				"engines": 2,
				"cargo": 4,
			}


static func _role_modules(
	ship_class: int, length: float, width: float, height: float,
	rng: SeededRNG, symmetric: bool, profile: Dictionary, gap: float
) -> Array:
	var modules: Array = []
	var pod_gap := lerpf(0.42, 0.72, gap)
	match ship_class:
		SimEntities.ShipClass.MINER:
			# Forward boom + asymmetric drill — mining gear owns the silhouette.
			modules.append({
				"type": "boom",
				"pos": Vector3(0, -height * 0.1, -length * 0.48),
				"size": Vector3(width * 0.22, height * 0.22, length * 0.55),
			})
			var drill_side := 1.0 if rng.randf() < 0.5 else -1.0
			if symmetric:
				drill_side = 0.15
			modules.append({
				"type": "drill",
				"pos": Vector3(drill_side * width * 0.28, -height * 0.42, -length * 0.45),
				"size": Vector3(width * 0.55, height * 0.4, length * 0.42),
			})
			modules.append({
				"type": "ore_bay",
				"pos": Vector3(-drill_side * width * pod_gap * 0.6, -height * 0.08, length * 0.08),
				"size": Vector3(width * 0.42, height * 0.5, length * 0.3),
			})
			modules.append({
				"type": "ore_bay",
				"pos": Vector3(drill_side * width * pod_gap * 0.5, height * 0.02, length * 0.22),
				"size": Vector3(width * 0.36, height * 0.4, length * 0.24),
			})
			if rng.randf() < float(profile["detail_density"]):
				modules.append({
					"type": "crane",
					"pos": Vector3((1.0 if drill_side <= 0.0 else -1.0) * width * 0.52, height * 0.28, -length * 0.02),
					"size": Vector3(width * 0.18, height * 0.7, width * 0.18),
				})
			modules.append({
				"type": "cockpit",
				"pos": Vector3(0, height * 0.48, length * 0.02),
				"size": Vector3(width * 0.3, height * 0.28, length * 0.2),
			})
		SimEntities.ShipClass.HAULER:
			# Spine segments + spaced cargo pods (LT sausage negative space).
			modules.append({
				"type": "spine",
				"pos": Vector3(0, 0, length * 0.02),
				"size": Vector3(width * 0.38, height * 0.42, length * 0.85),
			})
			var cargo_n := 5
			for i in cargo_n:
				var side := 1.0 if i % 2 == 0 else -1.0
				if not symmetric and i == cargo_n - 1:
					side = 1.0
				var z := -length * 0.28 + float(i) * length * 0.14
				modules.append({
					"type": "cargo",
					"pos": Vector3(side * width * pod_gap, rng.randf_range(-0.05, 0.08) * height, z),
					"size": Vector3(width * 0.4, height * 0.55, length * 0.11),
				})
			modules.append({
				"type": "cockpit",
				"pos": Vector3(0, height * 0.45, -length * 0.32),
				"size": Vector3(width * 0.3, height * 0.25, length * 0.14),
			})
		SimEntities.ShipClass.TRADER:
			modules.append({
				"type": "cockpit",
				"pos": Vector3(0, height * 0.38, -length * 0.15),
				"size": Vector3(width * 0.32, height * 0.28, length * 0.2),
			})
			for i in 3:
				var side := 1.0 if i % 2 == 0 else -1.0
				if not symmetric and i == 2:
					side = 1.0
				var z := -length * 0.05 + float(i) * length * 0.16
				modules.append({
					"type": "cargo",
					"pos": Vector3(side * width * pod_gap * 0.85, 0.0, z),
					"size": Vector3(width * 0.34, height * 0.48, length * 0.14),
				})
		SimEntities.ShipClass.PATROL:
			modules.append({
				"type": "cockpit",
				"pos": Vector3(0, height * 0.55, length * 0.02),
				"size": Vector3(width * 0.22, height * 0.35, length * 0.18),
			})
			modules.append({
				"type": "sensor",
				"pos": Vector3(0, height * 0.15, -length * 0.38),
				"size": Vector3(width * 0.14, height * 0.2, length * 0.12),
			})
			# Side weapon mounts (LT WingMounts) — close to hull so wings read as attached.
			var mount_x := width * lerpf(0.48, 0.62, gap)
			modules.append({
				"type": "mount",
				"pos": Vector3(mount_x, 0, length * 0.02),
				"size": Vector3(width * 0.18, height * 0.7, length * 0.4),
			})
			if symmetric:
				modules.append({
					"type": "mount",
					"pos": Vector3(-mount_x, 0, length * 0.02),
					"size": Vector3(width * 0.18, height * 0.7, length * 0.4),
				})
	if float(profile["ornament"]) > 0.45 and rng.randf() < float(profile["ornament"]):
		modules.append({
			"type": "fin",
			"pos": Vector3(0, height * 0.55, -length * 0.08),
			"size": Vector3(width * 0.28, height * 0.35, length * 0.2),
		})
	return modules


static func _role_hardpoints(
	ship_class: int, length: float, width: float, height: float,
	rng: SeededRNG, symmetric: bool, style: String
) -> Array:
	var hardpoints: Array = []
	if ship_class == SimEntities.ShipClass.PATROL or style == "military":
		hardpoints.append({
			"pos": Vector3(width * 0.42, height * 0.05, -length * 0.08),
			"size": Vector3(width * 0.12, height * 0.12, length * 0.28),
		})
		if symmetric:
			hardpoints.append({
				"pos": Vector3(-width * 0.42, height * 0.05, -length * 0.08),
				"size": Vector3(width * 0.12, height * 0.12, length * 0.28),
			})
		if style == "military" and rng.randf() < 0.55:
			hardpoints.append({
				"pos": Vector3(0, height * 0.35, length * 0.15),
				"size": Vector3(width * 0.18, height * 0.1, length * 0.16),
			})
	if style == "pirate" and rng.randf() < 0.7:
		hardpoints.append({
			"pos": Vector3(width * rng.randf_range(0.3, 0.55), height * 0.1, length * rng.randf_range(-0.1, 0.2)),
			"size": Vector3(width * 0.14, height * 0.12, length * 0.2),
		})
	return hardpoints


static func _role_wings(
	ship_class: int, length: float, width: float, height: float,
	rng: SeededRNG, symmetric: bool, style: String, profile: Dictionary
) -> Array:
	var wings: Array = []
	var want := ship_class == SimEntities.ShipClass.PATROL or style == "military" or (style == "pirate" and rng.randf() < 0.65)
	if style == "luxury" and ship_class == SimEntities.ShipClass.TRADER and rng.randf() < 0.4:
		want = true
	if not want:
		return wings
	var span := width * rng.randf_range(0.7, 1.35) * lerpf(0.9, 1.15, float(profile.get("negative_space", 0.4)))
	var chord := length * rng.randf_range(0.32, 0.48)
	var thick := height * rng.randf_range(0.08, 0.16)
	var sweep := rng.randf_range(0.12, 0.35)
	var root_x := width * 0.42
	wings.append({
		"root": Vector3(root_x, 0, length * 0.02),
		"span": span,
		"chord": chord,
		"thickness": thick,
		"sweep": sweep,
	})
	if symmetric:
		wings.append({
			"root": Vector3(-root_x, 0, length * 0.02),
			"span": -span,
			"chord": chord,
			"thickness": thick,
			"sweep": sweep,
		})
	# Occasional TIE-like vertical panel (LT WingsTie)
	if ship_class == SimEntities.ShipClass.PATROL and rng.randf() < 0.28:
		wings.append({
			"root": Vector3(width * 0.9, 0, 0),
			"span": width * 0.15,
			"chord": length * 0.55,
			"thickness": height * 0.9,
			"sweep": 0.05,
			"tie": true,
		})
		if symmetric:
			wings.append({
				"root": Vector3(-width * 0.9, 0, 0),
				"span": -width * 0.15,
				"chord": length * 0.55,
				"thickness": height * 0.9,
				"sweep": 0.05,
				"tie": true,
			})
	return wings


static func _role_struts(
	modules: Array, length: float, width: float, height: float,
	rng: SeededRNG, profile: Dictionary, gap: float
) -> Array:
	var struts: Array = []
	if float(profile.get("strut_bias", 0.3)) < 0.35:
		return struts
	for m in modules:
		var t := str(m.get("type", ""))
		if t in ["cargo", "ore_bay", "mount"]:
			var pos: Vector3 = m["pos"]
			var hull_attach := Vector3(signf(pos.x) * width * 0.2, pos.y * 0.3, pos.z)
			if absf(pos.x) < 0.05:
				hull_attach = Vector3(0, 0, pos.z)
			struts.append({"a": hull_attach, "b": pos, "thickness": lerpf(0.04, 0.09, gap) * width})
			if rng.randf() < 0.4:
				struts.append({
					"a": hull_attach + Vector3(0, height * 0.15, length * 0.04),
					"b": pos + Vector3(0, height * 0.08, 0),
					"thickness": 0.05 * width,
				})
	return struts


static func _role_plates(
	ship_class: int, length: float, width: float, height: float,
	rng: SeededRNG, profile: Dictionary, style: String
) -> Array:
	var plates: Array = []
	if float(profile.get("panel_bias", 0.4)) < 0.4:
		return plates
	var n := 2 if style == "military" else 1
	if style == "industrial" or style == "mining":
		n = 3
	for i in n:
		var z := -length * 0.2 + float(i) * length * 0.18
		plates.append({
			"pos": Vector3(0, height * 0.48, z),
			"size": Vector3(width * rng.randf_range(0.7, 0.95), height * 0.06, length * 0.08),
		})
	if style == "military":
		plates.append({
			"pos": Vector3(0, -height * 0.35, length * 0.05),
			"size": Vector3(width * 0.85, height * 0.08, length * 0.35),
		})
	return plates
