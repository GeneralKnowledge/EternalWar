## Deterministic procedural star-system generator.
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

	var star := {
		"id": 0,
		"kind": "star",
		"name": _gen_name() + " Primaris",
		"position": Vector3.ZERO,
		"radius": 180.0,
		"color": Color(1.0, 0.85, 0.45),
		"temperature": rng.randf_range(4500.0, 7500.0),
	}

	var planets: Array = []
	var planet_count := rng.randi_range(6, 10)
	for i in planet_count:
		planets.append(_make_planet(i + 1, i, planet_count))

	var yields: Array = []
	var yield_count := rng.randi_range(8, 14)
	for i in yield_count:
		yields.append(_make_yield(1000 + i, planets))

	var stations: Array = []
	var station_count := rng.randi_range(14, 22)
	for i in station_count:
		stations.append(_make_station(2000 + i, planets, i))

	var ships: Array = []
	for i in ship_count:
		ships.append(_make_ship(3000 + i, stations, i))

	var factions: Array = [
		{"id": 0, "name": "Aegis Combine", "color": Color(0.35, 0.65, 0.95)},
		{"id": 1, "name": "Veldt Mining Guild", "color": Color(0.85, 0.55, 0.2)},
		{"id": 2, "name": "Nadir Free Traders", "color": Color(0.45, 0.85, 0.5)},
		{"id": 3, "name": "Ashen Pact", "color": Color(0.8, 0.35, 0.4)},
	]

	return {
		"seed": seed_value,
		"name": star["name"].replace(" Primaris", ""),
		"star": star,
		"planets": planets,
		"yields": yields,
		"stations": stations,
		"ships": ships,
		"factions": factions,
		"tick": 0,
		"sim_time": 0.0,
	}


func _make_planet(id: int, index: int, total: int) -> Dictionary:
	var t := (float(index) + 1.0) / float(total + 1)
	var orbit := lerpf(600.0, SYSTEM_RADIUS * 0.85, t)
	var angle := rng.randf() * TAU
	var y_off := rng.randf_range(-40.0, 40.0)
	var pos := Vector3(cos(angle) * orbit, y_off, sin(angle) * orbit)
	var radius := rng.randf_range(40.0, 110.0)
	var habit_jitter := rng.randf_range(-0.15, 0.15)
	var habit := clampf(1.0 - absf(t - 0.45) * 2.2 + habit_jitter, 0.0, 1.0)
	var color := Color(
		rng.randf_range(0.25, 0.7),
		rng.randf_range(0.35, 0.75),
		rng.randf_range(0.4, 0.9)
	)
	var ore_r := rng.randf_range(0.2, 1.0)
	var energy_r := rng.randf_range(0.1, 0.8)
	var food_r := habit * rng.randf_range(0.3, 1.0)
	var resources := {
		Commodities.ORE: ore_r,
		Commodities.ENERGY: energy_r,
		Commodities.FOOD: food_r,
	}
	return SimEntities.make_planet(id, _gen_name(), pos, radius, color, habit, resources)


func _make_yield(id: int, planets: Array) -> Dictionary:
	var anchor: Dictionary = rng.choose(planets)
	# Sequence RNG calls explicitly — never chain side-effecting calls in one expression.
	var dir: Vector3 = rng.dir3()
	var dist: float = rng.randf_range(180.0, 420.0)
	var offset: Vector3 = dir * dist
	offset.y *= 0.35
	var pos: Vector3 = anchor["position"] + offset
	var name: String = _gen_name() + " Field"
	var richness: float = rng.randf_range(0.6, 1.4)
	return SimEntities.make_yield_site(id, name, pos, Commodities.ORE, richness)


func _make_station(id: int, planets: Array, index: int) -> Dictionary:
	var anchor: Dictionary = rng.choose(planets)
	var dir: Vector3 = rng.dir2()
	var dist: float = rng.randf_range(140.0, 280.0)
	var offset: Vector3 = dir * dist
	offset.y = rng.randf_range(-20.0, 20.0)
	var pos: Vector3 = anchor["position"] + offset
	var faction_id := index % 4
	var recipe_ids: Array = []
	match faction_id:
		0:
			recipe_ids = ["fabricate_components", "refine_energy"]
		1:
			recipe_ids = ["smelt_metal", "refine_energy"]
		2:
			recipe_ids = ["process_food", "smelt_metal"]
		_:
			recipe_ids = ["fabricate_components", "process_food"]

	var inventory := {
		Commodities.ORE: rng.randf_range(40.0, 180.0),
		Commodities.METAL: rng.randf_range(20.0, 120.0),
		Commodities.COMPONENTS: rng.randf_range(5.0, 40.0),
		Commodities.ENERGY: rng.randf_range(30.0, 100.0),
		Commodities.FOOD: rng.randf_range(20.0, 90.0),
	}
	var name: String = _gen_name() + " Station"
	var credits: float = rng.randf_range(5000.0, 20000.0)
	return SimEntities.make_station(id, name, pos, faction_id, recipe_ids, inventory, credits)


func _make_ship(id: int, stations: Array, index: int) -> Dictionary:
	var home: Dictionary = stations[index % stations.size()]
	var dir: Vector3 = rng.dir3()
	var dist: float = rng.randf_range(30.0, 120.0)
	var pos: Vector3 = home["position"] + dir * dist
	var faction_id: int = home["faction_id"]
	var roll := rng.randf()
	var ship_class: int
	var capacity: float
	var speed: float
	if roll < 0.45:
		ship_class = SimEntities.ShipClass.MINER
		capacity = rng.randf_range(40.0, 70.0)
		speed = rng.randf_range(55.0, 75.0)
	elif roll < 0.8:
		ship_class = SimEntities.ShipClass.TRADER
		capacity = rng.randf_range(50.0, 90.0)
		speed = rng.randf_range(60.0, 85.0)
	elif roll < 0.95:
		ship_class = SimEntities.ShipClass.HAULER
		capacity = rng.randf_range(100.0, 160.0)
		speed = rng.randf_range(40.0, 55.0)
	else:
		ship_class = SimEntities.ShipClass.PATROL
		capacity = rng.randf_range(20.0, 35.0)
		speed = rng.randf_range(80.0, 110.0)
	var credits: float = rng.randf_range(200.0, 1200.0)
	return SimEntities.make_ship(id, faction_id, ship_class, pos, capacity, speed, credits)


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
