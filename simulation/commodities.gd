## Commodity / item definitions for the systemic economy.
class_name Commodities
extends RefCounted

const ORE := "ore"
const METAL := "metal"
const COMPONENTS := "components"
const ENERGY := "energy"
const FOOD := "food"

const ALL: Array[String] = [ORE, METAL, COMPONENTS, ENERGY, FOOD]

const MASS := {
	ORE: 1.0,
	METAL: 1.0,
	COMPONENTS: 1.0,
	ENERGY: 0.5,
	FOOD: 0.5,
}

const BASE_PRICE := {
	ORE: 8.0,
	METAL: 22.0,
	COMPONENTS: 55.0,
	ENERGY: 12.0,
	FOOD: 10.0,
}

const DISPLAY_NAME := {
	ORE: "Ore",
	METAL: "Metal",
	COMPONENTS: "Components",
	ENERGY: "Energy",
	FOOD: "Food",
}


static func mass_of(item: String) -> float:
	return float(MASS.get(item, 1.0))


static func base_price_of(item: String) -> float:
	return float(BASE_PRICE.get(item, 10.0))


static func name_of(item: String) -> String:
	return str(DISPLAY_NAME.get(item, item))
