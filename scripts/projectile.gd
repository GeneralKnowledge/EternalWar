class_name Projectile
extends Node3D

## Lightweight projectile — motion + proximity hit checks, no physics bodies.

const HIT_RADIUS := 4.5
const POOL_SIZE_HINT := 64

static var _pool: Array[Projectile] = []

var direction: Vector3 = Vector3.FORWARD
var speed: float = 2500.0
var damage: float = 10.0
var lifetime: float = 1.0
var team: Teams.Side = Teams.Side.FRIENDLY
var owner_ship: Ship = null
var age: float = 0.0
var active: bool = false

var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null


static func acquire() -> Projectile:
	while not _pool.is_empty():
		var p: Projectile = _pool.pop_back()
		if is_instance_valid(p):
			return p
	return Projectile.new()


static func release(p: Projectile) -> void:
	if not is_instance_valid(p):
		return
	p.active = false
	if p.get_parent():
		p.get_parent().remove_child(p)
	if _pool.size() < POOL_SIZE_HINT:
		_pool.append(p)
	else:
		p.queue_free()


static func clear_pool() -> void:
	for p in _pool:
		if is_instance_valid(p):
			p.queue_free()
	_pool.clear()


func _ready() -> void:
	if _mesh == null:
		_build_visual()


func _build_visual() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 3.5
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cyl
	_mesh.rotation_degrees = Vector3(90, 0, 0)
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.omni_range = 18.0
	_light.light_energy = 2.5
	add_child(_light)


func launch(
	origin: Vector3,
	dir: Vector3,
	spd: float,
	dmg: float,
	life: float,
	own_team: Teams.Side,
	owner: Ship,
	color: Color
) -> void:
	if _mesh == null:
		_build_visual()

	global_position = origin
	direction = dir.normalized()
	speed = spd
	damage = dmg
	lifetime = life
	team = own_team
	owner_ship = owner
	age = 0.0
	active = true
	visible = true
	set_process(true)

	# Orient without look_at() so this works before entering the tree
	if direction.length_squared() > 0.0001:
		basis = Basis.looking_at(direction, Vector3.UP)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	_mesh.material_override = mat
	_light.light_color = color


func _process(delta: float) -> void:
	if not active:
		return

	age += delta
	if age >= lifetime:
		_expire()
		return

	var step := direction * speed * delta
	var from := global_position
	global_position = from + step

	_check_hits(from, global_position)


func _check_hits(from: Vector3, to: Vector3) -> void:
	var ships := get_tree().get_nodes_in_group("ships")
	var best: Ship = null
	var best_dist := HIT_RADIUS

	for node in ships:
		if not node is Ship:
			continue
		var ship: Ship = node
		if not ship.is_alive:
			continue
		if not Teams.is_enemy(team, ship.team):
			continue
		if ship == owner_ship:
			continue

		var closest := Geometry3D.get_closest_point_to_segment(ship.global_position, from, to)
		var dist := closest.distance_to(ship.global_position)
		# Prefer fighter-sized hit radius; battleships get larger radius
		var radius := HIT_RADIUS
		if ship is Battleship:
			radius = 55.0
		if dist <= radius and dist < best_dist:
			best_dist = dist
			best = ship

	if best != null:
		best.take_damage(damage, owner_ship)
		var bm := _battle_manager()
		if bm and owner_ship is Fighter and (owner_ship as Fighter).is_player:
			if not best.is_alive and best is Fighter:
				bm.register_player_kill()
		_expire()


func _battle_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/BattleManager")


func _expire() -> void:
	active = false
	set_process(false)
	visible = false
	var bm := _battle_manager()
	if bm:
		bm.unregister_projectile(self)
	Projectile.release(self)
