## Semantic ship design descriptor — simulation constraints → intentional design language.
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

	var engines: Array = []
	var engine_n: int = int(dims["engines"])
	for i in engine_n:
		var t := 0.0
		if engine_n > 1:
			t = (float(i) / float(engine_n - 1) - 0.5) * width * 0.78
		if not symmetric and eng_rng.randf() < 0.35 and i == engine_n - 1:
			t += eng_rng.randf_range(0.05, 0.2) * width
		engines.append({
			"pos": Vector3(t, -height * 0.12, length * 0.48),
			"radius": width * 0.09 * float(profile["engine_scale"]) * eng_rng.randf_range(0.9, 1.15),
			"length": length * 0.18 * eng_rng.randf_range(0.85, 1.2),
		})

	var modules: Array = _role_modules(ship_class, length, width, height, mod_rng, symmetric, profile)
	var hardpoints: Array = []
	if ship_class == SimEntities.ShipClass.PATROL:
		hardpoints.append({"pos": Vector3(width * 0.38, height * 0.12, -length * 0.05), "size": Vector3(width * 0.16, height * 0.1, length * 0.22)})
		if symmetric:
			hardpoints.append({"pos": Vector3(-width * 0.38, height * 0.12, -length * 0.05), "size": Vector3(width * 0.16, height * 0.1, length * 0.22)})

	var wings: Array = []
	if ship_class == SimEntities.ShipClass.PATROL or style == "military" or (style == "pirate" and det_rng.randf() < 0.7):
		var span := width * det_rng.randf_range(0.55, 1.15)
		var chord := length * det_rng.randf_range(0.28, 0.4)
		wings.append({"root": Vector3(width * 0.4, 0, length * 0.02), "span": span, "chord": chord, "thickness": height * 0.07, "sweep": 0.18})
		if symmetric:
			wings.append({"root": Vector3(-width * 0.4, 0, length * 0.02), "span": -span, "chord": chord, "thickness": height * 0.07, "sweep": 0.18})

	var cargo_capacity := float(extras.get("cargo_capacity", dims.get("cargo", 0) * 20.0))
	var engine_power := float(extras.get("speed", 70.0))

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
		"engines": engines,
		"modules": modules,
		"hardpoints": hardpoints,
		"wings": wings,
		"color": design.get("color", Color(0.7, 0.75, 0.85)),
		"accent": design.get("accent", Color(0.45, 0.5, 0.55)),
		"cargo_capacity": cargo_capacity,
		"engine_power": engine_power,
		"role_name": SimEntities.class_name_of(ship_class),
		"lod_hint": int(extras.get("lod", VisualLOD.LOD_FULL)),
	}


static func _role_dims(ship_class: int, rng: SeededRNG, profile: Dictionary) -> Dictionary:
	var stretch := lerpf(0.95, 1.12, 1.0 - float(profile["taper"]))
	match ship_class:
		SimEntities.ShipClass.MINER:
			# Blocky industrial silhouette — wide belly, short nose.
			return {
				"length": rng.randf_range(2.6, 3.5) * stretch,
				"width": rng.randf_range(1.55, 2.15),
				"height": rng.randf_range(1.15, 1.55),
				"engines": 2,
				"cargo": 2,
			}
		SimEntities.ShipClass.HAULER:
			# Long spine + cargo volume — readable at distance.
			return {
				"length": rng.randf_range(3.8, 5.2) * stretch,
				"width": rng.randf_range(1.6, 2.2),
				"height": rng.randf_range(1.25, 1.7),
				"engines": 3,
				"cargo": 6,
			}
		SimEntities.ShipClass.PATROL:
			# Flat interceptor wedge — LT fighter-like proportions.
			return {
				"length": rng.randf_range(2.1, 2.9) * stretch,
				"width": rng.randf_range(1.25, 1.85),
				"height": rng.randf_range(0.35, 0.58),
				"engines": 2,
				"cargo": 0,
			}
		_:
			return {
				"length": rng.randf_range(2.4, 3.3) * stretch,
				"width": rng.randf_range(1.2, 1.75),
				"height": rng.randf_range(0.75, 1.2),
				"engines": 2,
				"cargo": 4,
			}


static func _role_modules(
	ship_class: int, length: float, width: float, height: float,
	rng: SeededRNG, symmetric: bool, profile: Dictionary
) -> Array:
	var modules: Array = []
	match ship_class:
		SimEntities.ShipClass.MINER:
			modules.append({"type": "drill", "pos": Vector3(0, -height * 0.42, -length * 0.05), "size": Vector3(width * 0.55, height * 0.32, length * 0.38)})
			modules.append({"type": "ore_bay", "pos": Vector3(0, -height * 0.15, length * 0.1), "size": Vector3(width * 0.7, height * 0.35, length * 0.3)})
			if rng.randf() < float(profile["detail_density"]):
				modules.append({"type": "crane", "pos": Vector3(width * 0.45, height * 0.1, 0), "size": Vector3(width * 0.2, height * 0.45, width * 0.2)})
		SimEntities.ShipClass.HAULER, SimEntities.ShipClass.TRADER:
			var cargo_n := 4 if ship_class == SimEntities.ShipClass.HAULER else 3
			for i in cargo_n:
				var side := 1.0 if i % 2 == 0 else -1.0
				if not symmetric and i == cargo_n - 1:
					side = 1.0
				var z := -length * 0.12 + float(i / 2) * length * 0.18
				modules.append({
					"type": "cargo",
					"pos": Vector3(side * width * 0.52, 0.0, z),
					"size": Vector3(width * 0.36, height * 0.52, length * 0.15),
				})
			if ship_class == SimEntities.ShipClass.HAULER:
				modules.append({"type": "spine", "pos": Vector3(0, height * 0.32, length * 0.05), "size": Vector3(width * 0.45, height * 0.18, length * 0.4)})
		SimEntities.ShipClass.PATROL:
			modules.append({"type": "cockpit", "pos": Vector3(0, height * 0.38, length * 0.05), "size": Vector3(width * 0.22, height * 0.18, length * 0.16)})
			modules.append({"type": "sensor", "pos": Vector3(0, height * 0.2, -length * 0.35), "size": Vector3(width * 0.15, height * 0.12, length * 0.12)})
	if float(profile["ornament"]) > 0.4 and rng.randf() < float(profile["ornament"]):
		modules.append({"type": "fin", "pos": Vector3(0, height * 0.45, -length * 0.05), "size": Vector3(width * 0.35, height * 0.2, length * 0.22)})
	return modules
