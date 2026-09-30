class_name PlayerFighter
extends Fighter

## Player fighter with BSGO-like mouse aim + Newtonian thrusters.
## Release Space to cut main engines and coast — turn freely without losing momentum.

signal request_respawn

@export var mouse_sensitivity: float = 0.0028
@export var pitch_limit_deg: float = 89.0

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var input_enabled: bool = true


func _ready() -> void:
	is_player = true
	ship_name = "Player Fighter"
	# Raider-leaning agility
	turn_rate = 3.1
	acceleration = 340.0
	max_speed = 540.0
	super._ready()
	add_to_group("player_fighter")
	_sync_look_from_transform()


func _sync_look_from_transform() -> void:
	var fwd := get_forward()
	_look_yaw = atan2(-fwd.x, -fwd.z)
	_look_pitch = asin(clampf(fwd.y, -1.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_look_yaw -= motion.relative.x * mouse_sensitivity
		_look_pitch -= motion.relative.y * mouse_sensitivity
		_look_pitch = clampf(_look_pitch, deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if input_enabled:
		_handle_targeting_input()
		_handle_combat_input()
		_apply_player_flight(delta)
	else:
		super._physics_process(delta)


func _handle_targeting_input() -> void:
	if Input.is_action_just_pressed("target_nearest"):
		set_target(TargetSystem.find_nearest_enemy(self))
	elif Input.is_action_just_pressed("target_cycle"):
		set_target(TargetSystem.cycle_enemy_target(self, current_target))

	if current_target != null and (not is_instance_valid(current_target) or not current_target.is_alive):
		clear_target()


func _handle_combat_input() -> void:
	if Input.is_action_pressed("fire_primary"):
		try_fire()


func _apply_player_flight(delta: float) -> void:
	# Mouse sets nose direction — independent of velocity vector.
	var aim_forward := Vector3(
		-sin(_look_yaw) * cos(_look_pitch),
		sin(_look_pitch),
		-cos(_look_yaw) * cos(_look_pitch)
	).normalized()

	var roll := 0.0
	if Input.is_action_pressed("roll_left"):
		roll -= 1.0
	if Input.is_action_pressed("roll_right"):
		roll += 1.0
	apply_attitude(aim_forward, roll, delta)

	# WASD = translational thrusters (strafe / vertical). Not automatic forward drive.
	var strafe := Vector3.ZERO
	if Input.is_action_pressed("move_left"):
		strafe.x -= 1.0
	if Input.is_action_pressed("move_right"):
		strafe.x += 1.0
	if Input.is_action_pressed("move_forward"):
		strafe.y += 1.0
	if Input.is_action_pressed("move_back"):
		strafe.y -= 1.0

	# Space = main engines. Release = engines off, keep momentum, flip freely.
	var thrust := 0.0
	if Input.is_action_pressed("thrust"):
		thrust = 1.0
	elif Input.is_action_pressed("reverse_thrust"):
		thrust = -1.0

	var boost := Input.is_action_pressed("boost") and thrust > 0.05
	apply_thrusters(thrust, strafe, boost, delta)
	_update_engine_fx()


func enable_control(enabled: bool) -> void:
	input_enabled = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_sync_look_from_transform()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
