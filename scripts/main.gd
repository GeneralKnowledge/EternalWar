extends Node3D

## Main battlefield bootstrap — wires environment, fleets, HUD, camera.

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var camera: ChaseCamera = $ChaseCamera
@onready var friendly_battleship: Battleship = $FriendlyBattleship
@onready var enemy_battleship: Battleship = $EnemyBattleship
@onready var friendly_fighters: Node3D = $FriendlyFighterContainer
@onready var enemy_fighters: Node3D = $EnemyFighterContainer
@onready var projectiles: Node3D = $ProjectileContainer


func _ready() -> void:
	_configure_environment()
	_add_starfield()
	_setup_fleets()
	_setup_ui()

	BattleManager.setup(
		friendly_battleship,
		enemy_battleship,
		friendly_fighters,
		enemy_fighters,
		projectiles
	)
	BattleManager.player_respawned.connect(_on_player_respawned)
	BattleManager.player_died.connect(_on_player_died)

	# Capture mouse for flight
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame
	BattleManager.start_initial_launches()


func _configure_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Near-black void so bright hulls / stripes read clearly.
	env.background_color = Color(0.004, 0.006, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.2
	env.glow_strength = 0.85
	world_env.environment = env

	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.55
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.shadow_enabled = false


func _add_starfield() -> void:
	var stars := Starfield.new()
	stars.name = "Starfield"
	add_child(stars)


func _setup_fleets() -> void:
	friendly_battleship.team = Teams.Side.FRIENDLY
	friendly_battleship.ship_name = "Friendly Battleship"
	friendly_battleship.global_position = Vector3(-2200, 0, 0)
	friendly_battleship.rotation_degrees = Vector3(0, 0, 0)

	enemy_battleship.team = Teams.Side.ENEMY
	enemy_battleship.ship_name = "Enemy Battleship"
	enemy_battleship.global_position = Vector3(2200, 0, 0)
	enemy_battleship.rotation_degrees = Vector3(0, 180, 0)


func _setup_ui() -> void:
	var hud := BattleHUD.new()
	hud.name = "HUD"
	add_child(hud)
	var debug := DebugOverlay.new()
	debug.name = "DebugOverlay"
	add_child(debug)


func _on_player_respawned(fighter: PlayerFighter) -> void:
	if not camera.is_spectating():
		camera.set_follow_target(fighter)


func _on_player_died() -> void:
	if not camera.is_spectating():
		camera.clear_target()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		BattleManager.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		_toggle_ai_spectate()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not BattleManager.paused:
			if BattleManager.player and BattleManager.player.is_alive and not camera.is_spectating():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_ai_spectate() -> void:
	if camera.is_spectating():
		_return_to_player_camera()
		return
	_follow_ai_dogfight()


func _follow_ai_dogfight() -> void:
	var ai := _pick_ai_in_dogfight()
	if ai == null:
		return
	camera.set_spectate_target(ai)
	if not ai.destroyed.is_connected(_on_spectate_target_destroyed):
		ai.destroyed.connect(_on_spectate_target_destroyed)
	if BattleManager.player and is_instance_valid(BattleManager.player):
		BattleManager.player.enable_control(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_spectate_target_destroyed(_ship: Ship) -> void:
	if not camera.is_spectating():
		return
	# Keep watching the scrap — then hop to another dogfight.
	await get_tree().create_timer(0.8).timeout
	if camera.is_spectating():
		_follow_ai_dogfight()


func _return_to_player_camera() -> void:
	if BattleManager.player and is_instance_valid(BattleManager.player) and BattleManager.player.is_alive:
		camera.set_follow_target(BattleManager.player)
		BattleManager.player.enable_control(true)
	else:
		camera.clear_target()


func _pick_ai_in_dogfight() -> Fighter:
	var best: Fighter = null
	var best_score := -INF
	for node in get_tree().get_nodes_in_group("fighters"):
		if not node is Fighter:
			continue
		var f := node as Fighter
		if not f.is_alive or f.is_player:
			continue
		var score := 0.0
		if f.current_target != null and is_instance_valid(f.current_target) and f.current_target.is_alive:
			var dist := f.global_position.distance_to(f.current_target.global_position)
			score = 2000.0 - dist + f.get_speed()
		else:
			score = f.get_speed() * 0.1
		if score > best_score:
			best_score = score
			best = f
	return best
