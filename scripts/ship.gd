class_name Ship
extends Node3D

## Base class for all combat vessels. Handles hull/shield damage and team identity.

signal damaged(amount: float, remaining_shield: float, remaining_hull: float)
signal destroyed(ship: Ship)
signal shield_changed(current: float, maximum: float)
signal hull_changed(current: float, maximum: float)

@export var team: Teams.Side = Teams.Side.FRIENDLY
@export var ship_name: String = "Ship"
@export var max_health: float = 100.0
@export var max_shield: float = 0.0
@export var shield_regen_rate: float = 5.0
@export var shield_regen_delay: float = 3.0

var health: float = 100.0
var shield: float = 0.0
var is_alive: bool = true
var _time_since_damage: float = 999.0


func _ready() -> void:
	health = max_health
	shield = max_shield
	add_to_group("ships")
	add_to_group("team_%d" % team)


func _process(delta: float) -> void:
	if not is_alive:
		return
	_time_since_damage += delta
	_regenerate_shield(delta)


func _regenerate_shield(delta: float) -> void:
	if max_shield <= 0.0:
		return
	if _time_since_damage < shield_regen_delay:
		return
	if shield >= max_shield:
		return
	var before := shield
	shield = minf(max_shield, shield + shield_regen_rate * delta)
	if not is_equal_approx(before, shield):
		shield_changed.emit(shield, max_shield)


## Apply damage: shields absorb first, then hull. Returns true if destroyed.
func take_damage(amount: float, _source: Node = null) -> bool:
	if not is_alive or amount <= 0.0:
		return false

	_time_since_damage = 0.0
	var remaining := amount

	if shield > 0.0:
		var absorbed := minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
		shield_changed.emit(shield, max_shield)

	if remaining > 0.0:
		health = maxf(0.0, health - remaining)
		hull_changed.emit(health, max_health)

	damaged.emit(amount, shield, health)

	if health <= 0.0:
		_on_destroyed()
		return true
	return false


func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return health / max_health


func get_shield_ratio() -> float:
	if max_shield <= 0.0:
		return 0.0
	return shield / max_shield


func get_speed() -> float:
	return 0.0


func _on_destroyed() -> void:
	if not is_alive:
		return
	is_alive = false
	health = 0.0
	shield = 0.0
	remove_from_group("ships")
	destroyed.emit(self)
	_play_destruction()


func _play_destruction() -> void:
	# Override in subclasses for explosion visuals.
	queue_free()


## Shared helper: create a simple MeshInstance3D with a material.
static func make_mesh(mesh: Mesh, color: Color, emissive: bool = false, emission_energy: float = 2.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	mat.metallic = 0.25
	# Mild self-illumination so dark-space lighting never eats the silhouette.
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = emission_energy if emissive else 0.35
	mi.material_override = mat
	return mi
