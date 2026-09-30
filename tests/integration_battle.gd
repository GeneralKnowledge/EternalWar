extends SceneTree

## Integration smoke test: load main scene, let battle run briefly, assert invariants.
## godot --path . --rendering-driver opengl3 -s res://tests/integration_battle.gd

var _frames: int = 0
var _done: bool = false


func _initialize() -> void:
	# Load main scene under root
	var packed := load("res://scenes/main.tscn")
	if packed == null:
		push_error("Failed to load main.tscn")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	print("Integration: main scene loaded")


func _process(_delta: float) -> bool:
	if _done:
		return false
	_frames += 1
	# After ~3 seconds at 60fps-ish, check state
	if _frames < 180:
		return false
	_done = true
	_validate()
	return false


func _validate() -> void:
	var bm := root.get_node_or_null("/root/BattleManager")
	var failed := 0
	if bm == null:
		print("FAIL: BattleManager missing")
		quit(1)
		return

	print("Battle time: ", bm.battle_time)
	print("Friendly fighters: ", bm.get_friendly_fighter_count())
	print("Enemy fighters: ", bm.get_enemy_fighter_count())
	print("Player: ", bm.player)
	print("Projectiles (tracked): ", bm.active_projectiles)

	if bm.get_friendly_fighter_count() < 1:
		print("FAIL: expected friendly fighters")
		failed += 1
	else:
		print("PASS: friendly fighters present")

	if bm.get_enemy_fighter_count() < 1:
		print("FAIL: expected enemy fighters")
		failed += 1
	else:
		print("PASS: enemy fighters present")

	if bm.player == null or not is_instance_valid(bm.player) or not bm.player.is_alive:
		print("FAIL: player should be alive after launch")
		failed += 1
	else:
		print("PASS: player fighter alive")

	if bm.friendly_battleship == null or bm.enemy_battleship == null:
		print("FAIL: battleships missing")
		failed += 1
	else:
		print("PASS: both battleships present")
		var sep: float = bm.friendly_battleship.global_position.distance_to(bm.enemy_battleship.global_position)
		print("Battleship separation: ", sep)
		if sep < 1000.0:
			print("FAIL: battleships too close")
			failed += 1
		else:
			print("PASS: battleships separated")

	# Damage/respawn smoke: destroy player and ensure respawn schedules
	var deaths_before: int = bm.player_deaths
	bm.player.take_damage(9999.0)
	await create_timer(0.1).timeout
	if bm.player_deaths <= deaths_before:
		print("FAIL: player death not recorded")
		failed += 1
	else:
		print("PASS: player death recorded")

	# Wait for respawn
	await create_timer(bm.player_respawn_delay + 0.5).timeout
	if bm.player == null or not is_instance_valid(bm.player) or not bm.player.is_alive:
		print("FAIL: player did not respawn")
		failed += 1
	else:
		print("PASS: player respawned")

	# Fleet should still have fighters (battle continued)
	if bm.get_enemy_fighter_count() < 1 and bm.get_friendly_fighter_count() < 1:
		print("FAIL: battle emptied after player death")
		failed += 1
	else:
		print("PASS: battle continued after player death (F:%d E:%d)" % [
			bm.get_friendly_fighter_count(), bm.get_enemy_fighter_count()
		])

	print("=== Integration %s (%d failures) ===" % ["PASS" if failed == 0 else "FAIL", failed])
	quit(0 if failed == 0 else 1)
