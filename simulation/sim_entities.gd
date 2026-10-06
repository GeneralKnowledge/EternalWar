## Lightweight simulation entity factories (plain Dictionaries, not Nodes).
class_name SimEntities
extends RefCounted

enum ShipClass { MINER, TRADER, HAULER, PATROL }
enum Activity { IDLE, TRAVEL, MINE, DOCK, TRADE, UNDOCK }


static func make_planet(
	id: int,
	name: String,
	position: Vector3,
	radius: float,
	color: Color,
	habitability: float,
	resources: Dictionary
) -> Dictionary:
	return {
		"id": id,
		"kind": "planet",
		"name": name,
		"position": position,
		"radius": radius,
		"color": color,
		"habitability": habitability,
		"resources": resources.duplicate(),
	}


static func make_yield_site(
	id: int,
	name: String,
	position: Vector3,
	item: String,
	richness: float
) -> Dictionary:
	return {
		"id": id,
		"kind": "yield",
		"name": name,
		"position": position,
		"item": item,
		"richness": richness,
		"remaining": richness * 10000.0,
	}


static func make_station(
	id: int,
	name: String,
	position: Vector3,
	faction_id: int,
	recipe_ids: Array,
	inventory: Dictionary,
	credits: float
) -> Dictionary:
	var inv: Dictionary = {}
	for c in Commodities.ALL:
		inv[c] = float(inventory.get(c, 0.0))
	var prices: Dictionary = {}
	for c in Commodities.ALL:
		prices[c] = Commodities.base_price_of(c)
	var flows: Dictionary = {}
	for c in Commodities.ALL:
		flows[c] = 0.0
	var prod_state: Array = []
	for rid in recipe_ids:
		prod_state.append({"recipe_id": rid, "progress": 0.0})
	return {
		"id": id,
		"kind": "station",
		"name": name,
		"position": position,
		"faction_id": faction_id,
		"inventory": inv,
		"credits": credits,
		"prices": prices,
		"flows": flows,
		"productions": prod_state,
		"population": 100.0,
		"docked_ships": [],
	}


static func make_ship(
	id: int,
	faction_id: int,
	ship_class: int,
	position: Vector3,
	cargo_capacity: float,
	speed: float,
	credits: float
) -> Dictionary:
	var cargo: Dictionary = {}
	for c in Commodities.ALL:
		cargo[c] = 0.0
	return {
		"id": id,
		"kind": "ship",
		"faction_id": faction_id,
		"ship_class": ship_class,
		"position": position,
		"velocity": Vector3.ZERO,
		"heading": Vector3(0, 0, -1),
		"cargo": cargo,
		"cargo_capacity": cargo_capacity,
		"cargo_mass": 0.0,
		"credits": credits,
		"fuel": 100.0,
		"health": 100.0,
		"speed": speed,
		"activity": Activity.IDLE,
		"job": {},
		"target_id": -1,
		"target_kind": "",
		"docked_station_id": -1,
		"action_timer": 0.0,
		"mine_rate": 8.0,
		"is_player": false,
	}


static func cargo_used(ship: Dictionary) -> float:
	var used := 0.0
	for item in ship["cargo"]:
		used += float(ship["cargo"][item]) * Commodities.mass_of(item)
	return used


static func cargo_free(ship: Dictionary) -> float:
	return float(ship["cargo_capacity"]) - cargo_used(ship)


static func add_cargo(ship: Dictionary, item: String, amount: float) -> float:
	var free := cargo_free(ship)
	var mass := Commodities.mass_of(item)
	if mass <= 0.0:
		return 0.0
	var can_take := minf(amount, free / mass)
	if can_take <= 0.0:
		return 0.0
	ship["cargo"][item] = float(ship["cargo"].get(item, 0.0)) + can_take
	ship["cargo_mass"] = cargo_used(ship)
	return can_take


static func remove_cargo(ship: Dictionary, item: String, amount: float) -> float:
	var have := float(ship["cargo"].get(item, 0.0))
	var take := minf(have, amount)
	ship["cargo"][item] = have - take
	ship["cargo_mass"] = cargo_used(ship)
	return take


static func station_buy_price(station: Dictionary, item: String) -> float:
	# Station buys from ships (bid).
	return float(station["prices"].get(item, Commodities.base_price_of(item))) * 0.92


static func station_sell_price(station: Dictionary, item: String) -> float:
	# Station sells to ships (ask).
	return float(station["prices"].get(item, Commodities.base_price_of(item))) * 1.08
