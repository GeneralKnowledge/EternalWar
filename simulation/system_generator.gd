## Deterministic procedural star-system generator with hierarchical seeds.
## Layout counts use the system stream; each object's content uses an independent child seed.
class_name SystemGenerator
extends RefCounted

const SYSTEM_RADIUS := 4200.0

var seed_value: int = 0
var rng: SeededRNG


func _init(p_seed: int = 42) -> void:
	seed_value = p_seed
	rng = SeededRNG.new(p_seed)


func generate(ship_count: int = 400) -> Dictionary:
	rng.reseed(seed_value)

	var star := _make_star()

	var planet_count := rng.randi_range(6, 10)
	var planets: Array = []
	for i in planet_count:
		planets.append(_make_planet(i + 1, i, planet_count))

	var yield_count := rng.randi_range(8, 14)
	var yields: Array = []
	for i in yield_count:
		yields.append(_make_yield(1000 + i, i, planets))

	var station_count := rng.randi_range(14, 22)
	var stations: Array = []
	for i in station_count:
		stations.append(_make_station(2000 + i, i, planets))

	var ships: Array = []
	for i in ship_count:
		ships.append(_make_ship(3000 + i, i, stations))

	var factions: Array = [
		{"id": 0, "name": "Aegis Combine", "color": Color(0.42, 0.45, 0.5), "style": "military", "accent": Color(0.55, 0.25, 0.22)},
		{"id": 1, "name": "Veldt Mining Guild", "color": Color(0.55, 0.42, 0.28), "style": "mining", "accent": Color(0.45, 0.32, 0.18)},
		{"id": 2, "name": "Nadir Free Traders", "color": Color(0.5, 0.52, 0.48), "style": "civilian", "accent": Color(0.35, 0.4, 0.32)},
		{"id": 3, "name": "Ashen Pact", "color": Color(0.38, 0.28, 0.28), "style": "pirate", "accent": Color(0.5, 0.35, 0.2)},
	]

	var nebula_rng := SeedHash.make_rng(seed_value, "nebula")
	# Bias toward space-readable hues (cyan / blue / violet / magenta / rose) — avoid muddy olives.
	# LT stills span amber/cockpit warmth, magenta ship gas, and cool planet blues —
	# not cyan-only. Keep cool masses common but reserve warm families.
	var hue_pick := nebula_rng.randf()
	var hue: float
	if hue_pick < 0.18:
		hue = nebula_rng.randf_range(0.06, 0.14) # amber–gold
	elif hue_pick < 0.40:
		hue = nebula_rng.randf_range(0.52, 0.62) # cyan–teal
	elif hue_pick < 0.62:
		hue = nebula_rng.randf_range(0.62, 0.78) # blue–violet
	elif hue_pick < 0.82:
		hue = nebula_rng.randf_range(0.78, 0.92) # violet–magenta
	else:
		hue = nebula_rng.randf_range(0.92, 1.0) # rose
		if nebula_rng.randf() < 0.45:
			hue = nebula_rng.randf_range(0.0, 0.06) # crimson
	var nebula_color := Color.from_hsv(hue, nebula_rng.randf_range(0.45, 0.78), nebula_rng.randf_range(0.28, 0.5))

	return {
		"seed": seed_value,
		"name": str(star["name"]).replace(" Primaris", ""),
		"star": star,
		"planets": planets,
		"yields": yields,
		"stations": stations,
		"ships": ships,
		"factions": factions,
		"nebula_color": nebula_color,
		"tick": 0,
		"sim_time": 0.0,
	}


func _make_star() -> Dictionary:
	var s := SeedHash.derive(seed_value, "star")
	var srng := SeededRNG.new(s)
	var temp := srng.randf_range(2800.0, 12000.0)
	var star_type := _star_type(temp)
	var radius := 140.0
	match star_type:
		"red_dwarf":
			radius = srng.randf_range(90.0, 130.0)
		"sunlike":
			radius = srng.randf_range(160.0, 210.0)
		"blue_giant":
			radius = srng.randf_range(240.0, 320.0)
	var color := _temp_to_color(temp)
	var name_rng := SeedHash.make_rng(seed_value, "star_name")
	# Share naming helper via temporary use of instance method with local rng swap
	var old := rng
	rng = name_rng
	var name := _gen_name() + " Primaris"
	rng = old
	return {
		"id": 0,
		"kind": "star",
		"name": name,
		"position": Vector3.ZERO,
		"radius": radius,
		"color": color,
		"temperature": temp,
		"star_type": star_type,
		"luminosity": clampf((temp / 5800.0) * (radius / 180.0), 0.4, 3.5),
		"seed": s,
	}


func _make_planet(id: int, index: int, total: int) -> Dictionary:
	# Orbital layout from system stream (stable full-system regen).
	var t := (float(index) + 1.0) / float(total + 1)
	var orbit := lerpf(600.0, SYSTEM_RADIUS * 0.85, t)
	var angle := rng.randf() * TAU
	var y_off := rng.randf_range(-40.0, 40.0)
	var pos := Vector3(cos(angle) * orbit, y_off, sin(angle) * orbit)

	# Content from independent child seed — regenerating planet i does not affect j.
	var child := SeedHash.derive_i(seed_value, "planet", index)
	var prng := SeededRNG.new(child)
	var terrain_seed := SeedHash.derive(child, "terrain")
	var atmosphere_seed := SeedHash.derive(child, "atmosphere")
	var habit_jitter := prng.randf_range(-0.15, 0.15)
	var habit := clampf(1.0 - absf(t - 0.45) * 2.2 + habit_jitter, 0.0, 1.0)
	var pclass := _classify_planet(t, habit, prng)
	var radius := prng.randf_range(40.0, 110.0)
	if pclass == "gas_giant":
		radius = prng.randf_range(140.0, 220.0)
	var colors := _planet_palette(pclass, prng)
	var resources := {
		Commodities.ORE: prng.randf_range(0.2, 1.0),
		Commodities.ENERGY: prng.randf_range(0.1, 0.8),
		Commodities.FOOD: habit * prng.randf_range(0.3, 1.0),
	}
	var old := rng
	rng = SeededRNG.new(SeedHash.derive(child, "name"))
	var pname := _gen_name()
	rng = old
	return SimEntities.make_planet(id, pname, pos, radius, colors["a"], habit, resources, {
		"seed": child,
		"terrain_seed": terrain_seed,
		"atmosphere_seed": atmosphere_seed,
		"planet_class": pclass,
		"ocean_level": float(colors["ocean"]),
		"cloud_level": float(colors["cloud"]),
		"atmosphere": float(colors["atmo"]),
		"has_rings": (pclass == "gas_giant" and prng.randf() < 0.55) or (pclass == "ice" and prng.randf() < 0.2),
		"ring_color": colors["ring"],
		"temperature": lerpf(90.0, 700.0, t) + prng.randf_range(-40.0, 40.0),
		"color_b": colors["b"],
		"color_c": colors["c"],
		"color_d": colors["d"],
	})


func _make_yield(id: int, index: int, planets: Array) -> Dictionary:
	var anchor: Dictionary = rng.choose(planets)
	var dir: Vector3 = rng.dir3()
	var dist: float = rng.randf_range(180.0, 420.0)
	var offset: Vector3 = dir * dist
	offset.y *= 0.35
	var pos: Vector3 = anchor["position"] + offset

	var child := SeedHash.derive_i(seed_value, "yield", index)
	var yrng := SeededRNG.new(child)
	var composition := "iron"
	var roll := yrng.randf()
	if roll < 0.35:
		composition = "iron"
	elif roll < 0.6:
		composition = "silicate"
	elif roll < 0.8:
		composition = "carbon"
	else:
		composition = "ice"
	var color := Color(0.5, 0.42, 0.32)
	match composition:
		"silicate":
			color = Color(0.55, 0.5, 0.45)
		"carbon":
			color = Color(0.25, 0.25, 0.28)
		"ice":
			color = Color(0.7, 0.8, 0.9)
	var old := rng
	rng = SeededRNG.new(SeedHash.derive(child, "name"))
	var yname := _gen_name() + " Field"
	rng = old
	return SimEntities.make_yield_site(id, yname, pos, Commodities.ORE, yrng.randf_range(0.6, 1.4), {
		"seed": child,
		"composition": composition,
		"asteroid_count": yrng.randi_range(18, 40),
		"spread": yrng.randf_range(70.0, 140.0),
		"color": color,
	})


func _make_station(id: int, index: int, planets: Array) -> Dictionary:
	var anchor: Dictionary = rng.choose(planets)
	var dir: Vector3 = rng.dir2()
	var dist: float = rng.randf_range(140.0, 280.0)
	var offset: Vector3 = dir * dist
	offset.y = rng.randf_range(-20.0, 20.0)
	var pos: Vector3 = anchor["position"] + offset
	var faction_id := index % 4

	var child := SeedHash.derive_i(seed_value, "station", index)
	var srng := SeededRNG.new(child)
	var role := "trade"
	var recipe_ids: Array = []
	match faction_id:
		0:
			role = "military" if srng.randf() < 0.45 else "industrial"
			recipe_ids = ["fabricate_components", "refine_energy"]
		1:
			role = "mining"
			recipe_ids = ["smelt_metal", "refine_energy"]
		2:
			role = "trade" if srng.randf() < 0.6 else "habitat"
			recipe_ids = ["process_food", "smelt_metal"]
		_:
			role = "industrial" if srng.randf() < 0.5 else "pirate"
			if role == "pirate":
				role = "trade"
			recipe_ids = ["fabricate_components", "process_food"]

	var style_list: Array[String] = ["military", "mining", "civilian", "pirate"]
	var style: String = style_list[faction_id]
	var inventory := {
		Commodities.ORE: srng.randf_range(40.0, 180.0),
		Commodities.METAL: srng.randf_range(20.0, 120.0),
		Commodities.COMPONENTS: srng.randf_range(5.0, 40.0),
		Commodities.ENERGY: srng.randf_range(30.0, 100.0),
		Commodities.FOOD: srng.randf_range(20.0, 90.0),
	}
	var modules := _station_modules(role)
	var faction_colors := [
		Color(0.4, 0.55, 0.75),
		Color(0.7, 0.5, 0.3),
		Color(0.4, 0.65, 0.45),
		Color(0.65, 0.35, 0.4),
	]
	var old := rng
	rng = SeededRNG.new(SeedHash.derive(child, "name"))
	var sname := _gen_name() + " Station"
	rng = old
	return SimEntities.make_station(id, sname, pos, faction_id, recipe_ids, inventory, srng.randf_range(5000.0, 20000.0), {
		"seed": child,
		"role": role,
		"style": style,
		"modules": modules,
		"color": faction_colors[faction_id],
		"population": srng.randf_range(80.0, 220.0),
	})


func _make_ship(id: int, index: int, stations: Array) -> Dictionary:
	var home: Dictionary = stations[index % stations.size()]
	var dir: Vector3 = rng.dir3()
	var dist: float = rng.randf_range(30.0, 120.0)
	var pos: Vector3 = home["position"] + dir * dist
	var faction_id: int = home["faction_id"]

	var child := SeedHash.derive_i(seed_value, "ship", index)
	var srng := SeededRNG.new(child)
	var roll := srng.randf()
	var ship_class: int
	var capacity: float
	var speed: float
	if roll < 0.45:
		ship_class = SimEntities.ShipClass.MINER
		capacity = srng.randf_range(40.0, 70.0)
		speed = srng.randf_range(55.0, 75.0)
	elif roll < 0.8:
		ship_class = SimEntities.ShipClass.TRADER
		capacity = srng.randf_range(50.0, 90.0)
		speed = srng.randf_range(60.0, 85.0)
	elif roll < 0.95:
		ship_class = SimEntities.ShipClass.HAULER
		capacity = srng.randf_range(100.0, 160.0)
		speed = srng.randf_range(40.0, 55.0)
	else:
		ship_class = SimEntities.ShipClass.PATROL
		capacity = srng.randf_range(20.0, 35.0)
		speed = srng.randf_range(80.0, 110.0)

	var style_list: Array[String] = ["military", "mining", "civilian", "pirate"]
	var style: String = style_list[faction_id]
	# Class can override style lean
	if ship_class == SimEntities.ShipClass.MINER:
		style = "mining"
	elif ship_class == SimEntities.ShipClass.PATROL and faction_id == 0:
		style = "military"
	# Desaturated faction hulls — LT ships read as matte neutrals, not neon faction paint.
	var colors := [
		Color(0.42, 0.45, 0.5),   # military grey
		Color(0.55, 0.42, 0.28),  # warm industrial
		Color(0.5, 0.52, 0.48),   # civilian cream-grey
		Color(0.38, 0.28, 0.28),  # pirate charcoal-red
	]
	var accents := [
		Color(0.55, 0.25, 0.22),  # military warning red
		Color(0.45, 0.32, 0.18),  # mining ochre
		Color(0.35, 0.4, 0.32),   # trader muted green
		Color(0.5, 0.35, 0.2),    # pirate copper
	]
	return SimEntities.make_ship(id, faction_id, ship_class, pos, capacity, speed, srng.randf_range(200.0, 1200.0), {
		"seed": child,
		"design_seed": SeedHash.derive(child, "design"),
		"style": style,
		"color": colors[faction_id],
		"accent": accents[faction_id],
	})


func _station_modules(role: String) -> Array:
	match role:
		"mining":
			return ["core", "docking", "cargo", "processing", "power"]
		"industrial":
			return ["core", "docking", "factories", "cargo", "power", "habitation"]
		"military":
			return ["core", "docking", "weapons", "sensors", "armour", "command"]
		"habitat":
			return ["core", "docking", "habitation", "communications", "power"]
		_:
			return ["core", "docking", "cargo", "habitation", "communications"]


func _classify_planet(orbit_t: float, habit: float, prng: SeededRNG) -> String:
	if orbit_t < 0.2:
		return "lava" if prng.randf() < 0.6 else "barren"
	if orbit_t > 0.85:
		return "ice" if prng.randf() < 0.7 else "gas_giant"
	if habit > 0.55:
		return "habitable" if prng.randf() < 0.55 else "ocean"
	if orbit_t > 0.65 and prng.randf() < 0.35:
		return "gas_giant"
	if prng.randf() < 0.25:
		return "desert"
	if prng.randf() < 0.2:
		return "industrial"
	return "rocky"


func _planet_palette(pclass: String, prng: SeededRNG) -> Dictionary:
	match pclass:
		"ocean":
			return {"a": Color(0.1, 0.25, 0.55), "b": Color(0.15, 0.45, 0.25), "c": Color(0.4, 0.35, 0.2), "d": Color(0.9, 0.92, 0.95), "ocean": 0.55, "cloud": 0.25, "atmo": 0.55, "ring": Color(0.6, 0.65, 0.7, 0.4)}
		"habitable":
			return {"a": Color(0.15, 0.35, 0.55), "b": Color(0.2, 0.5, 0.2), "c": Color(0.45, 0.4, 0.25), "d": Color(0.9, 0.9, 0.95), "ocean": 0.4, "cloud": 0.3, "atmo": 0.6, "ring": Color(0.7, 0.7, 0.6, 0.3)}
		"desert":
			return {"a": Color(0.65, 0.45, 0.25), "b": Color(0.75, 0.55, 0.3), "c": Color(0.5, 0.35, 0.2), "d": Color(0.85, 0.8, 0.7), "ocean": 0.08, "cloud": 0.05, "atmo": 0.25, "ring": Color(0.7, 0.6, 0.4, 0.3)}
		"ice":
			return {"a": Color(0.55, 0.65, 0.8), "b": Color(0.7, 0.8, 0.9), "c": Color(0.4, 0.5, 0.65), "d": Color(0.95, 0.97, 1.0), "ocean": 0.2, "cloud": 0.35, "atmo": 0.3, "ring": Color(0.8, 0.85, 0.95, 0.45)}
		"lava":
			return {"a": Color(0.25, 0.1, 0.08), "b": Color(0.85, 0.3, 0.05), "c": Color(0.45, 0.15, 0.05), "d": Color(1.0, 0.7, 0.2), "ocean": 0.0, "cloud": -0.1, "atmo": 0.15, "ring": Color(0.5, 0.3, 0.2, 0.3)}
		"gas_giant":
			return {"a": Color(0.75, 0.55, 0.35), "b": Color(0.85, 0.7, 0.45), "c": Color(0.55, 0.4, 0.3), "d": Color(0.9, 0.85, 0.75), "ocean": 0.0, "cloud": 0.55, "atmo": 0.8, "ring": Color(0.75, 0.7, 0.55, 0.5)}
		"industrial":
			return {"a": Color(0.35, 0.35, 0.38), "b": Color(0.45, 0.4, 0.35), "c": Color(0.25, 0.28, 0.3), "d": Color(0.6, 0.6, 0.55), "ocean": 0.15, "cloud": 0.4, "atmo": 0.35, "ring": Color(0.5, 0.5, 0.45, 0.3)}
		"barren":
			return {"a": Color(0.32, 0.3, 0.28), "b": Color(0.55, 0.48, 0.4), "c": Color(0.22, 0.2, 0.18), "d": Color(0.75, 0.72, 0.68), "ocean": 0.0, "cloud": -0.15, "atmo": 0.08, "ring": Color(0.5, 0.5, 0.5, 0.25)}
		_:
			return {"a": Color(prng.randf_range(0.25, 0.55), prng.randf_range(0.25, 0.5), prng.randf_range(0.3, 0.55)), "b": Color(0.35, 0.4, 0.3), "c": Color(0.45, 0.35, 0.25), "d": Color(0.85, 0.85, 0.9), "ocean": 0.25, "cloud": 0.12, "atmo": 0.3, "ring": Color(0.65, 0.6, 0.5, 0.35)}


func _star_type(temp: float) -> String:
	if temp < 4000.0:
		return "red_dwarf"
	if temp > 9000.0:
		return "blue_giant"
	return "sunlike"


func _temp_to_color(temp: float) -> Color:
	var t := clampf((temp - 2800.0) / (12000.0 - 2800.0), 0.0, 1.0)
	if t < 0.35:
		return Color(1.0, lerpf(0.35, 0.7, t / 0.35), 0.25)
	if t < 0.65:
		return Color(1.0, lerpf(0.75, 0.95, (t - 0.35) / 0.3), lerpf(0.45, 0.75, (t - 0.35) / 0.3))
	return Color(lerpf(1.0, 0.65, (t - 0.65) / 0.35), lerpf(0.95, 0.8, (t - 0.65) / 0.35), 1.0)


func _gen_name() -> String:
	const CONS := ["b", "c", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "w", "z", "ll", "ss", "rr"]
	const VOWELS := ["a", "e", "i", "o", "u", "y", "ae", "ee", "ou"]
	var parts: PackedStringArray = PackedStringArray()
	var syllables := rng.randi_range(2, 4)
	for _i in syllables:
		parts.append(CONS[rng.randi_range(0, CONS.size() - 1)])
		parts.append(VOWELS[rng.randi_range(0, VOWELS.size() - 1)])
	var name := "".join(parts)
	return name.capitalize()
