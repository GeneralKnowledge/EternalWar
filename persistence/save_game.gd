## Save/load stubs — full persistence comes after the living simulation is stable.
class_name SaveGame
extends RefCounted


static func encode_seed_and_tick(world: Dictionary) -> Dictionary:
	return {
		"version": 1,
		"seed": int(world.get("seed", 0)),
		"tick": int(world.get("tick", 0)),
		"sim_time": float(world.get("sim_time", 0.0)),
	}
