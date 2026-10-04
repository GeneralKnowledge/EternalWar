class_name Fighter
extends Ship

## Shared fighter systems used by both player and AI craft.
## Flight is BSGO-style Newtonian: attitude is independent of velocity.
## Release thrust to cut engines and coast — flip freely without losing momentum.

signal fired_weapon

const DEFAULT_MAX_SPEED := 520.0
const DEFAULT_ACCELERATION := 320.0
const DEFAULT_TURN_RATE := 2.8
const BOOST_MULTIPLIER := 1.85
const STRAFE_FACTOR := 0.65
const REVERSE_FACTOR := 0.55
## Tiny residual drag so coasting feels infinite for combat timescales.
const COAST_DRAG := 0.02
## Extra damping only when over max speed from boost/stacking.
const OVERSPEED_DRAG := 1.6

@export var max_speed: float = DEFAULT_MAX_SPEED
@export var acceleration: float = DEFAULT_ACCELERATION
@export var turn_rate: float = DEFAULT_TURN_RATE
@export var is_player: bool = false

var velocity: Vector3 = Vector3.ZERO
var throttle: float = 0.0
var boosting: bool = false
## True while main/strafe/reverse thrusters are commanded.
var engines_lit: bool = false
var current_target: Ship = null

var weapon: Weapon = null
var model_root: Node3D = null
var engine_light: OmniLight3D = null
var engine_particles: GPUParticles3D = null
var _engine_glows: Array[MeshInstance3D] = []

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
	# Slightly larger silhouette so fighters read at combat ranges.
	model_root.scale = Vector3(1.35, 1.35, 1.35)
	add_child(model_root)

	# High-contrast hulls: bright pale / hot amber against near-black void.
	var hull_color := Color(0.92, 0.94, 0.98) if team == Teams.Side.FRIENDLY else Color(1.0, 0.72, 0.28)
	var accent := Color(0.25, 0.55, 0.95) if team == Teams.Side.FRIENDLY else Color(0.85, 0.2, 0.1)
	var stripe := Color(0.2, 0.95, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.95, 0.25)
	var engine_col := Color(0.45, 0.95, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.55, 0.15)

	var body := BoxMesh.new()
	body.size = Vector3(1.6, 0.7, 5.5)
	model_root.add_child(Ship.make_mesh(body, hull_color))

	var nose := PrismMesh.new()
	nose.size = Vector3(1.2, 0.6, 2.0)
	var nose_mi := Ship.make_mesh(nose, hull_color.lightened(0.08))
	nose_mi.rotation_degrees = Vector3(90, 0, 0)
	nose_mi.position = Vector3(0, 0, -3.5)
	model_root.add_child(nose_mi)

	var canopy := SphereMesh.new()
	canopy.radius = 0.45
	canopy.height = 0.7
	var canopy_mi := Ship.make_mesh(canopy, Color(0.05, 0.08, 0.12))
	canopy_mi.position = Vector3(0, 0.45, -0.8)
	model_root.add_child(canopy_mi)

	var wing := BoxMesh.new()
	wing.size = Vector3(6.5, 0.15, 2.2)
	var wing_mi := Ship.make_mesh(wing, accent)
	wing_mi.position = Vector3(0, -0.1, 0.6)
	model_root.add_child(wing_mi)

	# Bright wing leading-edge stripes for readability
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(6.2, 0.08, 0.25)
	var stripe_mi := Ship.make_mesh(stripe_mesh, stripe, true, 2.2)
	stripe_mi.position = Vector3(0, 0.02, -0.3)
	model_root.add_child(stripe_mi)

	for side in [-1.0, 1.0]:
		var tip := BoxMesh.new()
		tip.size = Vector3(0.25, 0.9, 1.2)
		var tip_mi := Ship.make_mesh(tip, stripe, true, 1.4)
		tip_mi.position = Vector3(side * 3.2, 0.25, 0.4)
		model_root.add_child(tip_mi)

	for side in [-1.0, 1.0]:
		var eng := CylinderMesh.new()
		eng.top_radius = 0.35
		eng.bottom_radius = 0.4
		eng.height = 1.4
		var eng_mi := Ship.make_mesh(eng, accent.darkened(0.15))
		eng_mi.rotation_degrees = Vector3(90, 0, 0)
		eng_mi.position = Vector3(side * 0.9, 0.0, 2.6)
		model_root.add_child(eng_mi)

		var glow := SphereMesh.new()
		glow.radius = 0.32
		glow.height = 0.64
		var glow_mi := Ship.make_mesh(glow, engine_col, true, 6.0)
		glow_mi.position = Vector3(side * 0.9, 0.0, 3.4)
		glow_mi.name = "EngineGlow"
		model_root.add_child(glow_mi)
		_engine_glows.append(glow_mi)

	var hit_sphere := SphereMesh.new()
	hit_sphere.radius = 3.0
	hit_sphere.height = 6.0
	var hit_mi := MeshInstance3D.new()
	hit_mi.mesh = hit_sphere
	hit_mi.visible = false
	hit_mi.name = "HitRadius"
	add_child(hit_mi)


func _setup_engine_fx() -> void:
	# Fill light so the hull stays readable from the chase camera, even coasting.
	var fill := OmniLight3D.new()
	fill.name = "HullFill"
	fill.light_color = Color(0.75, 0.85, 1.0) if team == Teams.Side.FRIENDLY else Color(1.0, 0.75, 0.45)
	fill.light_energy = 2.8
	fill.omni_range = 14.0
	fill.position = Vector3(0, 2.5, -1.0)
	add_child(fill)

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
	engine_particles.emitting = false
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


## Rotate toward a facing direction without changing velocity (attitude thrusters).
func apply_attitude(desired_forward: Vector3, roll_input: float, delta: float) -> void:
	if not is_alive:
		return
	if desired_forward.length_squared() > 0.0001:
		var up := Vector3.UP
		# Prefer current up when nearly inverted so we can flip freely.
		if absf(desired_forward.dot(up)) > 0.92:
			up = global_transform.basis.y
		var target_basis := Basis.looking_at(desired_forward.normalized(), up)
		if absf(roll_input) > 0.01:
			target_basis = target_basis.rotated(desired_forward.normalized(), -roll_input * turn_rate * 1.4 * delta)
		var t := clampf(turn_rate * delta, 0.0, 1.0)
		quaternion = quaternion.slerp(target_basis.get_rotation_quaternion(), t)


## BSGO-style thrusters: only change velocity when engines are commanded.
## thrust_input: -1..1 (negative = reverse), strafe.x/y in local ship axes, boost multiplies forward.
func apply_thrusters(thrust_input: float, strafe: Vector3, boost: bool, delta: float) -> void:
	if not is_alive:
		return

	throttle = clampf(thrust_input, -1.0, 1.0)
	boosting = boost and throttle > 0.05
	var strafe_cmd := strafe
	if strafe_cmd.length_squared() > 1.0:
		strafe_cmd = strafe_cmd.normalized()

	engines_lit = absf(throttle) > 0.02 or strafe_cmd.length_squared() > 0.01

	if engines_lit:
		var boost_mul := BOOST_MULTIPLIER if boosting else 1.0
		var forward_acc := acceleration * boost_mul
		if throttle < 0.0:
			forward_acc = acceleration * REVERSE_FACTOR
		var force := -global_transform.basis.z * throttle * forward_acc
		force += global_transform.basis.x * strafe_cmd.x * acceleration * STRAFE_FACTOR
		force += global_transform.basis.y * strafe_cmd.y * acceleration * STRAFE_FACTOR
		velocity += force * delta

	# Soft speed ceiling — does not yank you to a stop when engines cut.
	var speed_cap := max_speed * (BOOST_MULTIPLIER if boosting else 1.0)
	var speed := velocity.length()
	if speed > speed_cap:
		velocity = velocity.normalized() * lerpf(speed, speed_cap, 1.0 - exp(-OVERSPEED_DRAG * delta))
	elif speed > 0.01:
		# Near-zero coast drag (engines off keeps momentum).
		var drag := COAST_DRAG if not engines_lit else COAST_DRAG * 0.25
		velocity *= exp(-drag * delta)

	global_position += velocity * delta


## Combined helper used by AI: face a direction and optionally thrust.
func apply_steering(desired_forward: Vector3, thrust_input: float, strafe: Vector3, boost: bool, delta: float) -> void:
	apply_attitude(desired_forward, 0.0, delta)
	apply_thrusters(thrust_input, strafe, boost, delta)


func _apply_flight_physics(_delta: float) -> void:
	pass


func _update_engine_fx() -> void:
	var lit := engines_lit and absf(throttle) > 0.02
	var intensity := 0.15
	if lit:
		intensity = 0.9 + absf(throttle) * 2.2 + (1.8 if boosting else 0.0)
	if engine_light:
		engine_light.light_energy = intensity
		engine_light.visible = intensity > 0.2
	if engine_particles:
		engine_particles.emitting = lit and throttle > 0.05
		if engine_particles.emitting:
			engine_particles.amount = int(18 + absf(throttle) * 28 + (24 if boosting else 0))
	for glow in _engine_glows:
		if not is_instance_valid(glow):
			continue
		glow.visible = true
		var mat := glow.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 0.35 + (4.5 if lit else 0.0) + (2.0 if boosting else 0.0)


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

	await get_tree().create_timer(0.05).timeout
	queue_free()
