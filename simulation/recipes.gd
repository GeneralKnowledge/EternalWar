## Production recipes: inputs → outputs over a duration (seconds of factory time).
class_name Recipes
extends RefCounted

## Each recipe: { id, name, duration, inputs: {item:count}, outputs: {item:count} }
static func all() -> Array[Dictionary]:
	return [
		{
			"id": "smelt_metal",
			"name": "Smelt Metal",
			"duration": 4.0,
			"inputs": {Commodities.ORE: 3.0, Commodities.ENERGY: 1.0},
			"outputs": {Commodities.METAL: 2.0},
		},
		{
			"id": "fabricate_components",
			"name": "Fabricate Components",
			"duration": 6.0,
			"inputs": {Commodities.METAL: 2.0, Commodities.ENERGY: 2.0},
			"outputs": {Commodities.COMPONENTS: 1.0},
		},
		{
			"id": "refine_energy",
			"name": "Refine Energy Cells",
			"duration": 3.0,
			"inputs": {Commodities.ORE: 1.0},
			"outputs": {Commodities.ENERGY: 2.0},
		},
		{
			"id": "process_food",
			"name": "Process Food",
			"duration": 5.0,
			"inputs": {Commodities.ENERGY: 1.0},
			"outputs": {Commodities.FOOD: 2.0},
		},
	]


static func by_id(recipe_id: String) -> Dictionary:
	for r in all():
		if r["id"] == recipe_id:
			return r
	return {}
