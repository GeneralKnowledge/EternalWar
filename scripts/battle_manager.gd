extends Node

## High-level battle simulation state. Does not micromanage fighter movement.

signal battle_started
signal player_died
signal player_respawned(fighter: PlayerFighter)
signal stats_changed

var friendly_battleship: Battleship = null
var enemy_battleship: Battleship = null
var friendly_fighter_container: Node3D = null
var enemy_fighter_container: Node3D = null
var projectile_container: Node3D = null
var player: PlayerFighter = null
var player_spawn_pending: bool = false

var battle_time: float = 0.0
var player_kills: int = 0
var player_deaths: int = 0
var active_projectiles: int = 0
var battle_running: bool = false
var paused: bool = false

var player_respawn_delay: float = 2.5
var _respawn_timer: float = -1.0
var _initial_spawn_done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not battle_running or paused:
		return
	battle_time += delta
	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn_timer = -1.0
			respawn_player()


func setup(
	friendly: Battleship,
	enemy: Battleship,
	friendly_container: Node3D,
	enemy_container: Node3D,
	proj_container: Node3D
) -> void:
	friendly_battleship = friendly
	enemy_battleship = enemy
	friendly_fighter_container = friendly_container
	enemy_fighter_container = enemy_container
	projectile_container = proj_container
	battle_time = 0.0
	player_kills = 0
	player_deaths = 0
	active_projectiles = 0
	battle_running = true
	_initial_spawn_done = false
	battle_started.emit()


func start_initial_launches() -> void:
	if _initial_spawn_done:
		return
	_initial_spawn_done = true
	# Stagger initial fighter cloud so battle isn't empty at t=0
	if friendly_battleship:
		for i in range(friendly_battleship.fighter_capacity):
			var f := friendly_battleship.launch_fighter()
			if f:
				# Spread initial positions toward midfield
				f.global_position += Vector3(randf_range(200, 1800), randf_range(-300, 300), randf_range(-400, 400))
	if enemy_battleship:
		for i in range(enemy_battleship.fighter_capacity):
			var f := enemy_battleship.launch_fighter()
			if f:
				f.global_position += Vector3(randf_range(-1800, -200), randf_range(-300, 300), randf_range(-400, 400))
	# Player launches after a brief moment from hangar
	await get_tree().create_timer(0.3).timeout
	respawn_player()


func get_fighter_container(team: Teams.Side) -> Node3D:
	if team == Teams.Side.FRIENDLY:
		return friendly_fighter_container
	return enemy_fighter_container


func get_projectile_container() -> Node3D:
	return projectile_container


func get_friendly_fighter_count() -> int:
	if friendly_battleship:
		return friendly_battleship.get_fighter_count()
	return 0


func get_enemy_fighter_count() -> int:
	if enemy_battleship:
		return enemy_battleship.get_fighter_count()
	return 0


func register_projectile(_p: Projectile) -> void:
	active_projectiles += 1
	stats_changed.emit()


func unregister_projectile(_p: Projectile) -> void:
	active_projectiles = maxi(0, active_projectiles - 1)
	stats_changed.emit()


func register_player_kill() -> void:
	player_kills += 1
	stats_changed.emit()


func bind_player(fighter: PlayerFighter) -> void:
	player = fighter
	player_spawn_pending = false
	if not player.destroyed.is_connected(_on_player_destroyed):
		player.destroyed.connect(_on_player_destroyed)
	player.enable_control(true)
	player_respawned.emit(player)
	stats_changed.emit()


func _on_player_destroyed(_ship: Ship) -> void:
	player_deaths += 1
	player = null
	player_spawn_pending = true
	_respawn_timer = player_respawn_delay
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()
	stats_changed.emit()


func respawn_player() -> void:
	if friendly_battleship == null or not is_instance_valid(friendly_battleship):
		return
	if player != null and is_instance_valid(player) and player.is_alive:
		return

	var fighter := friendly_battleship.launch_fighter(true) as PlayerFighter
	if fighter == null:
		return
	# Nudge out of hangar toward battle
	fighter.global_position = friendly_battleship.get_launch_position() + Vector3(60, 30, 0)
	fighter.look_at(fighter.global_position + Vector3(1, 0, 0), Vector3.UP)
	fighter.velocity = Vector3(150, 0, 0)
	if fighter is PlayerFighter:
		(fighter as PlayerFighter)._sync_look_from_transform()
	bind_player(fighter)


func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif player != null and is_instance_valid(player) and player.is_alive:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func debug_spawn_fighter(team: Teams.Side) -> void:
	var ship := friendly_battleship if team == Teams.Side.FRIENDLY else enemy_battleship
	if ship:
		ship.launch_fighter()


func debug_destroy_player_target() -> void:
	if player and player.current_target and player.current_target.is_alive:
		player.current_target.take_damage(9999.0, player)


func debug_respawn_player() -> void:
	if player and is_instance_valid(player) and player.is_alive:
		player.take_damage(9999.0)
	else:
		respawn_player()


func debug_reset_battle() -> void:
	# Clear fighters and relaunch
	for container in [friendly_fighter_container, enemy_fighter_container]:
		if container:
			for child in container.get_children():
				child.queue_free()
	if projectile_container:
		for child in projectile_container.get_children():
			child.queue_free()
	Projectile.clear_pool()
	player = null
	player_kills = 0
	player_deaths = 0
	battle_time = 0.0
	active_projectiles = 0
	if friendly_battleship:
		friendly_battleship.active_fighters.clear()
	if enemy_battleship:
		enemy_battleship.active_fighters.clear()
	_initial_spawn_done = false
	call_deferred("start_initial_launches")
	stats_changed.emit()
