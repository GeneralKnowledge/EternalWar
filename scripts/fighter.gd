class_name Fighter
extends Ship

## Shared fighter systems used by both player and AI craft.

signal fired_weapon

const DEFAULT_MAX_SPEED := 420.0
const DEFAULT_ACCELERATION := 280.0
const DEFAULT_TURN_RATE := 2.4
const BOOST_MULTIPLIER := 1.75
const STRAFE_FACTOR := 0.55
const DRAG := 1.8

@export var max_speed: float = DEFAULT_MAX_SPEED
@export var acceleration: float = DEFAULT_ACCELERATION
@export var turn_rate: float = DEFAULT_TURN_RATE
@export var is_player: bool = false

var velocity: Vector3 = Vector3.ZERO
var throttle: float = 0.0
var boosting: bool = false
var current_target: Ship = null

var weapon: Weapon = null
var model_root: Node3D = null
var engine_light: OmniLight3D = null
var engine_particles: GPUParticles3D = null

var _explosion_played: bool = false


func _ready() -> void:
	max_health = 100.0
	max_shield = 50.0
	shield_regen_rate = 8.0
	shield_regen_delay = 2.5
	ship_name = "Fighter"
	super._ready()
	add_to_group("fighters")
	_build_model()
	_setup_weapon()
	_setup_engine_fx()


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_apply_flight_physics(delta)
	_update_engine_fx()


func _setup_weapon() -> void:
	weapon = Weapon.new()
	weapon.name = "PrimaryWeapon"
	weapon.damage = 10.0
	weapon.fire_rate = 6.0
	weapon.weapon_range = 2000.0
	weapon.projectile_speed = 2500.0
	weapon.muzzle_offset = Vector3(0, 0, -4.5)
	add_child(weapon)
	weapon.setup(self)


func _build_model() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	var hull_color := Color(0.35, 0.55, 0.85) if team == Teams.Side.FRIENDLY else Color(0.85, 0.32, 0.28)
	var accent := Color(0.15, 0.2, 0.3) if team == Teams.Side.FRIENDLY else Color(0.3, 0.12, 0.1)
	var engine_col := Color(0.4, 0.75, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.45, 0.2)

	# Main fuselage
	var body := BoxMesh.new()
	body.size = Vector3(1.6, 0.7, 5.5)
	var body_mi := Ship.make_mesh(body, hull_color)
	model_root.add_child(body_mi)

	# Nose
	var nose := PrismMesh.new()
	nose.size = Vector3(1.2, 0.6, 2.0)
	var nose_mi := Ship.make_mesh(nose, hull_color.lightened(0.1))
	nose_mi.rotation_degrees = Vector3(90, 0, 0)
	nose_mi.position = Vector3(0, 0, -3.5)
	model_root.add_child(nose_mi)

	# Cockpit canopy
	var canopy := SphereMesh.new()
	canopy.radius = 0.45
	canopy.height = 0.7
	var canopy_mi := Ship.make_mesh(canopy, Color(0.2, 0.35, 0.5, 0.85))
	canopy_mi.position = Vector3(0, 0.45, -0.8)
	model_root.add_child(canopy_mi)

	# Wings
	var wing := BoxMesh.new()
	wing.size = Vector3(6.5, 0.15, 2.2)
	var wing_mi := Ship.make_mesh(wing, accent)
	wing_mi.position = Vector3(0, -0.1, 0.6)
	model_root.add_child(wing_mi)

	# Wing tips
	for side in [-1.0, 1.0]:
		var tip := BoxMesh.new()
		tip.size = Vector3(0.2, 0.8, 1.2)
		var tip_mi := Ship.make_mesh(tip, hull_color)
		tip_mi.position = Vector3(side * 3.2, 0.2, 0.4)
		model_root.add_child(tip_mi)

	# Engines
	for side in [-1.0, 1.0]:
		var eng := CylinderMesh.new()
		eng.top_radius = 0.35
		eng.bottom_radius = 0.4
		eng.height = 1.4
		var eng_mi := Ship.make_mesh(eng, accent)
		eng_mi.rotation_degrees = Vector3(90, 0, 0)
		eng_mi.position = Vector3(side * 0.9, 0.0, 2.6)
		model_root.add_child(eng_mi)

		var glow := SphereMesh.new()
		glow.radius = 0.28
		glow.height = 0.56
		var glow_mi := Ship.make_mesh(glow, engine_col, true, 4.0)
		glow_mi.position = Vector3(side * 0.9, 0.0, 3.4)
		glow_mi.name = "EngineGlow"
		model_root.add_child(glow_mi)

	# Soft selection / hit radius visual (invisible collision proxy via group queries)
	var hit_sphere := SphereMesh.new()
	hit_sphere.radius = 3.0
	hit_sphere.height = 6.0
	var hit_mi := MeshInstance3D.new()
	hit_mi.mesh = hit_sphere
	hit_mi.visible = false
	hit_mi.name = "HitRadius"
	add_child(hit_mi)


func _setup_engine_fx() -> void:
	engine_light = OmniLight3D.new()
	engine_light.light_color = Color(0.5, 0.8, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.5, 0.25)
	engine_light.light_energy = 1.5
	engine_light.omni_range = 12.0
	engine_light.position = Vector3(0, 0, 4.0)
	add_child(engine_light)

	engine_particles = GPUParticles3D.new()
	engine_particles.amount = 24
	engine_particles.lifetime = 0.35
	engine_particles.position = Vector3(0, 0, 3.5)
	engine_particles.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 1)
	mat.spread = 12.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.15
	mat.scale_max = 0.4
	mat.color = Color(0.5, 0.85, 1.0, 0.7) if team == Teams.Side.FRIENDLY else Color(1.0, 0.55, 0.2, 0.7)
	engine_particles.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.2
	draw.height = 0.4
	engine_particles.draw_pass_1 = draw
	add_child(engine_particles)


func apply_steering(desired_forward: Vector3, thrust_input: float, strafe: Vector3, boost: bool, delta: float) -> void:
	if not is_alive:
		return
	boosting = boost
	throttle = clampf(thrust_input, -0.35, 1.0)

	if desired_forward.length_squared() > 0.0001:
		var target_basis := Basis.looking_at(desired_forward.normalized(), Vector3.UP)
		var current_q := quaternion
		var target_q := target_basis.get_rotation_quaternion()
		var t := clampf(turn_rate * delta, 0.0, 1.0)
		quaternion = current_q.slerp(target_q, t)

	var speed_cap := max_speed * (BOOST_MULTIPLIER if boost else 1.0)
	var forward_force := -global_transform.basis.z * throttle * acceleration * (BOOST_MULTIPLIER if boost else 1.0)
	var strafe_force := (
		global_transform.basis.x * strafe.x
		+ global_transform.basis.y * strafe.y
	) * acceleration * STRAFE_FACTOR

	velocity += (forward_force + strafe_force) * delta
	# Soft drag toward speed cap
	var speed := velocity.length()
	if speed > speed_cap:
		velocity = velocity.normalized() * lerpf(speed, speed_cap, 1.0 - exp(-DRAG * delta))
	else:
		velocity = velocity.lerp(velocity * (0.92 if throttle < 0.05 else 1.0), 1.0 - exp(-0.4 * delta))

	global_position += velocity * delta


func _apply_flight_physics(_delta: float) -> void:
	# Player / AI drive apply_steering externally.
	pass


func _update_engine_fx() -> void:
	if engine_light:
		var intensity := 0.8 + throttle * 2.0 + (1.5 if boosting else 0.0)
		engine_light.light_energy = intensity
	if engine_particles:
		engine_particles.amount = int(16 + throttle * 24 + (20 if boosting else 0))
		engine_particles.emitting = throttle > 0.05 or boosting or velocity.length() > 20.0


func get_speed() -> float:
	return velocity.length()


func get_forward() -> Vector3:
	return -global_transform.basis.z


func try_fire() -> bool:
	if not is_alive or weapon == null:
		return false
	if weapon.try_fire():
		fired_weapon.emit()
		return true
	return false


func set_target(target: Ship) -> void:
	if target != null and target.is_alive and Teams.is_enemy(team, target.team):
		current_target = target
	else:
		current_target = null


func clear_target() -> void:
	current_target = null


func _play_destruction() -> void:
	if _explosion_played:
		return
	_explosion_played = true
	velocity = Vector3.ZERO
	if weapon:
		weapon.set_process(false)
	if model_root:
		model_root.visible = false
	if engine_particles:
		engine_particles.emitting = false
	if engine_light:
		engine_light.visible = false

	var explosion := ExplosionEffect.new()
	explosion.global_position = global_position
	explosion.team_color = Color(0.4, 0.75, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.45, 0.2)
	var parent := get_parent()
	if parent:
		parent.add_child(explosion)
	else:
		get_tree().root.add_child(explosion)

	var audio := get_node_or_null("/root/GameAudio")
	if audio and audio.has_method("play_explosion"):
		audio.play_explosion(global_position)

	# Delay free so managers can react to destroyed signal first.
	await get_tree().create_timer(0.05).timeout
	queue_free()
