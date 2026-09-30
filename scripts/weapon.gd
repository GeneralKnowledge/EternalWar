class_name Weapon
extends Node3D

## Reusable energy weapon component shared by player and AI fighters.

@export var damage: float = 10.0
@export var fire_rate: float = 6.0
@export var weapon_range: float = 2000.0
@export var projectile_speed: float = 2500.0
@export var muzzle_offset: Vector3 = Vector3(0, 0, -4.5)
@export var projectile_color: Color = Color(0.4, 0.9, 1.0)

var owner_ship: Ship = null
var _cooldown: float = 0.0


func setup(ship: Ship) -> void:
	owner_ship = ship
	if ship.team == Teams.Side.ENEMY:
		projectile_color = Color(1.0, 0.45, 0.25)
	else:
		projectile_color = Color(0.35, 0.85, 1.0)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


func can_fire() -> bool:
	return owner_ship != null and owner_ship.is_alive and _cooldown <= 0.0


func try_fire() -> bool:
	if not can_fire():
		return false
	_cooldown = 1.0 / maxf(fire_rate, 0.01)
	_spawn_projectile()
	var audio := get_node_or_null("/root/GameAudio") if is_inside_tree() else null
	if audio and audio.has_method("play_laser"):
		audio.play_laser(global_position)
	return true


func _spawn_projectile() -> void:
	var bm: Node = null
	if is_inside_tree():
		bm = get_node_or_null("/root/BattleManager")
	var container: Node = null
	if bm and bm.has_method("get_projectile_container"):
		container = bm.get_projectile_container()
	if container == null:
		container = get_tree().current_scene

	var proj := Projectile.acquire()
	var origin := owner_ship.global_transform * muzzle_offset
	var direction := -owner_ship.global_transform.basis.z
	proj.launch(
		origin,
		direction,
		projectile_speed,
		damage,
		weapon_range / maxf(projectile_speed, 1.0),
		owner_ship.team,
		owner_ship,
		projectile_color
	)
	container.add_child(proj)
	if bm and bm.has_method("register_projectile"):
		bm.register_projectile(proj)
