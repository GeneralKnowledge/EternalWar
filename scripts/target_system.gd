class_name TargetSystem
extends RefCounted

## Modular target selection for fighters. Extend later for bombers / capital priorities.


static func get_enemy_ships(from: Ship, fighters_only: bool = true) -> Array[Ship]:
	var result: Array[Ship] = []
	if from == null or not is_instance_valid(from):
		return result
	var tree := from.get_tree()
	if tree == null:
		return result
	var group := "fighters" if fighters_only else "ships"
	for node in tree.get_nodes_in_group(group):
		if not node is Ship:
			continue
		var ship: Ship = node
		if not ship.is_alive:
			continue
		if not Teams.is_enemy(from.team, ship.team):
			continue
		result.append(ship)
	return result


static func find_nearest_enemy(from: Ship, fighters_only: bool = true) -> Ship:
	var best: Ship = null
	var best_dist := INF
	for ship in get_enemy_ships(from, fighters_only):
		var d := from.global_position.distance_squared_to(ship.global_position)
		if d < best_dist:
			best_dist = d
			best = ship
	return best


static func cycle_enemy_target(from: Ship, current: Ship, fighters_only: bool = true) -> Ship:
	var enemies := get_enemy_ships(from, fighters_only)
	if enemies.is_empty():
		return null

	# Sort by distance for stable cycling
	enemies.sort_custom(func(a: Ship, b: Ship) -> bool:
		return from.global_position.distance_squared_to(a.global_position) < from.global_position.distance_squared_to(b.global_position)
	)

	if current == null or not is_instance_valid(current):
		return enemies[0]

	var idx := enemies.find(current)
	if idx < 0:
		return enemies[0]
	return enemies[(idx + 1) % enemies.size()]


static func distance_to(from: Node3D, to: Node3D) -> float:
	if from == null or to == null:
		return 0.0
	return from.global_position.distance_to(to.global_position)
