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
	env.background_color = Color(0.015, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.1, 0.14)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.25
	env.glow_strength = 0.9
	world_env.environment = env

	sun.light_color = Color(0.95, 0.92, 0.85)
	sun.light_energy = 1.15
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
	camera.set_follow_target(fighter)


func _on_player_died() -> void:
	camera.clear_target()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		BattleManager.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not BattleManager.paused:
			if BattleManager.player and BattleManager.player.is_alive:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
