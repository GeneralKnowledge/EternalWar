class_name Battleship
extends Ship

## Capital ship: visual centre of a fleet and fighter launch platform.

signal fighter_launched(fighter: Fighter)
signal fighter_count_changed(count: int)

@export var fighter_capacity: int = 12
@export var fighter_spawn_interval: float = 5.0
@export var launch_spread: float = 80.0

var active_fighters: Array[Fighter] = []
var _spawn_timer: float = 0.0
var _hangar_points: Array[Vector3] = []
var model_root: Node3D = null
var spawning_enabled: bool = false


func _ready() -> void:
	max_health = 10000.0
	max_shield = 0.0
	ship_name = "Battleship"
	super._ready()
	add_to_group("battleships")
	_build_model()
	_setup_hangars()
	_spawn_timer = randf_range(0.5, 2.0)


func enable_spawning(enabled: bool = true) -> void:
	spawning_enabled = enabled
	if enabled:
		_spawn_timer = randf_range(1.0, fighter_spawn_interval)


func _process(delta: float) -> void:
	super._process(delta)
	if not is_alive or not spawning_enabled:
		return
	_cleanup_dead_fighters()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = fighter_spawn_interval
		if active_fighters.size() < fighter_capacity:
			launch_fighter()


func _setup_hangars() -> void:
	# Launch points relative to hull — outward from midship hangar bays
	var forward := -1.0 if team == Teams.Side.FRIENDLY else 1.0
	for i in range(4):
		var y := ((i % 2) * 2 - 1) * 25.0
		var z := (i / 2) * 40.0 - 20.0
		_hangar_points.append(Vector3(forward * 40.0, y, z))


func get_launch_position() -> Vector3:
	if _hangar_points.is_empty():
		return global_position + Vector3(0, 40, 0)
	var local: Vector3 = _hangar_points[randi() % _hangar_points.size()]
	local += Vector3(randf_range(-launch_spread, launch_spread) * 0.15, randf_range(-20, 20), randf_range(-30, 30))
	return global_transform * local


func get_launch_direction() -> Vector3:
	# Face toward the opposite fleet / midfield
	if team == Teams.Side.FRIENDLY:
		return Vector3(1, 0, 0)
	return Vector3(-1, 0, 0)


func get_fighter_count() -> int:
	_cleanup_dead_fighters()
	return active_fighters.size()


func _cleanup_dead_fighters() -> void:
	var alive: Array[Fighter] = []
	for f in active_fighters:
		if is_instance_valid(f) and f.is_alive:
			alive.append(f)
	if alive.size() != active_fighters.size():
		active_fighters = alive
		fighter_count_changed.emit(active_fighters.size())


func launch_fighter(as_player: bool = false) -> Fighter:
	if not as_player and active_fighters.size() >= fighter_capacity:
		return null

	var fighter: Fighter
	if as_player:
		fighter = PlayerFighter.new()
	else:
		fighter = Fighter.new()

	fighter.team = team
	var launch_pos := get_launch_position()
	var launch_dir := get_launch_direction()
	fighter.velocity = launch_dir * 120.0

	var container: Node = null
	var bm := _battle_manager()
	if bm:
		container = bm.get_fighter_container(team)
	if container == null:
		container = get_parent()
	container.add_child(fighter)
	fighter.global_position = launch_pos
	# Orient without look_at() (safe even if tree state is edge-casey)
	if launch_dir.length_squared() > 0.0001:
		fighter.basis = Basis.looking_at(launch_dir, Vector3.UP)

	if not as_player:
		var ai := FighterAI.new()
		ai.name = "AI"
		fighter.add_child(ai)
		active_fighters.append(fighter)
		fighter.destroyed.connect(_on_fighter_destroyed)
		fighter_count_changed.emit(active_fighters.size())

	fighter_launched.emit(fighter)
	return fighter


func _battle_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/BattleManager")


func _on_fighter_destroyed(ship: Ship) -> void:
	if ship is Fighter:
		active_fighters.erase(ship)
		fighter_count_changed.emit(active_fighters.size())


func register_external_fighter(fighter: Fighter) -> void:
	if fighter == null:
		return
	if not active_fighters.has(fighter):
		active_fighters.append(fighter)
		if not fighter.destroyed.is_connected(_on_fighter_destroyed):
			fighter.destroyed.connect(_on_fighter_destroyed)
		fighter_count_changed.emit(active_fighters.size())


func _build_model() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	var hull := Color(0.28, 0.38, 0.55) if team == Teams.Side.FRIENDLY else Color(0.5, 0.22, 0.2)
	var dark := hull.darkened(0.35)
	var accent := Color(0.4, 0.7, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.4, 0.25)
	var facing := 1.0 if team == Teams.Side.FRIENDLY else -1.0

	# Main hull — long capital silhouette (readable at combat distances)
	var main := BoxMesh.new()
	main.size = Vector3(420, 48, 78)
	var main_mi := Ship.make_mesh(main, hull)
	model_root.add_child(main_mi)

	# Lower hull bulge
	var lower := BoxMesh.new()
	lower.size = Vector3(300, 30, 55)
	var lower_mi := Ship.make_mesh(lower, dark)
	lower_mi.position = Vector3(0, -28, 0)
	model_root.add_child(lower_mi)

	# Bow wedge
	var bow := PrismMesh.new()
	bow.size = Vector3(70, 42, 100)
	var bow_mi := Ship.make_mesh(bow, hull.lightened(0.08))
	bow_mi.rotation_degrees = Vector3(0, 0, -90 * facing)
	bow_mi.position = Vector3(facing * 240, 0, 0)
	model_root.add_child(bow_mi)

	# Bridge superstructure
	var bridge := BoxMesh.new()
	bridge.size = Vector3(55, 40, 42)
	var bridge_mi := Ship.make_mesh(bridge, dark)
	bridge_mi.position = Vector3(-facing * 60, 40, 0)
	model_root.add_child(bridge_mi)

	var bridge_top := BoxMesh.new()
	bridge_top.size = Vector3(24, 16, 24)
	var bridge_top_mi := Ship.make_mesh(bridge_top, accent.darkened(0.2), true, 0.8)
	bridge_top_mi.position = Vector3(-facing * 60, 68, 0)
	model_root.add_child(bridge_top_mi)

	# Hangar bays (indented boxes)
	for side in [-1.0, 1.0]:
		var hangar := BoxMesh.new()
		hangar.size = Vector3(70, 24, 10)
		var hangar_mi := Ship.make_mesh(hangar, Color(0.05, 0.05, 0.08))
		hangar_mi.position = Vector3(facing * 30, -8, side * 40)
		model_root.add_child(hangar_mi)
		# Hangar glow
		var glow := BoxMesh.new()
		glow.size = Vector3(55, 14, 1.5)
		var glow_mi := Ship.make_mesh(glow, accent, true, 2.5)
		glow_mi.position = Vector3(facing * 30, -8, side * 46)
		model_root.add_child(glow_mi)

	# Weapon mounts
	for i in range(3):
		var x := (i - 1) * 90.0
		var mount := CylinderMesh.new()
		mount.top_radius = 4.0
		mount.bottom_radius = 5.5
		mount.height = 22.0
		var mount_mi := Ship.make_mesh(mount, dark)
		mount_mi.position = Vector3(x, 30, 0)
		model_root.add_child(mount_mi)
		var barrel := CylinderMesh.new()
		barrel.top_radius = 1.6
		barrel.bottom_radius = 2.0
		barrel.height = 40.0
		var barrel_mi := Ship.make_mesh(barrel, hull.darkened(0.1))
		barrel_mi.rotation_degrees = Vector3(0, 0, 90)
		barrel_mi.position = Vector3(x + facing * 20, 38, 0)
		model_root.add_child(barrel_mi)

	# Engines at stern
	for i in range(3):
		var z := (i - 1) * 22.0
		var eng := CylinderMesh.new()
		eng.top_radius = 12.0
		eng.bottom_radius = 14.0
		eng.height = 40.0
		var eng_mi := Ship.make_mesh(eng, dark)
		eng_mi.rotation_degrees = Vector3(0, 0, 90)
		eng_mi.position = Vector3(-facing * 220, 0, z)
		model_root.add_child(eng_mi)
		var glow := SphereMesh.new()
		glow.radius = 13.0
		glow.height = 26.0
		var glow_mi := Ship.make_mesh(glow, accent, true, 5.0)
		glow_mi.position = Vector3(-facing * 245, 0, z)
		model_root.add_child(glow_mi)

	# Engine light
	var light := OmniLight3D.new()
	light.light_color = accent
	light.light_energy = 6.0
	light.omni_range = 200.0
	light.position = Vector3(-facing * 250, 0, 0)
	model_root.add_child(light)


func _play_destruction() -> void:
	# Battleships are immortal for MVP visuals — keep husk if somehow destroyed
	var explosion := ExplosionEffect.new()
	explosion.global_position = global_position
	explosion.duration = 2.5
	explosion.team_color = Color(0.4, 0.7, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.4, 0.25)
	get_parent().add_child(explosion)
	model_root.visible = false
	spawning_enabled = false
	await get_tree().create_timer(2.0).timeout
	queue_free()
