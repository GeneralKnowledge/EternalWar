class_name PlayerFighter
extends Fighter

## Player-controlled fighter using the shared Fighter flight and weapon systems.

signal request_respawn

@export var mouse_sensitivity: float = 0.0025
@export var aim_assist_strength: float = 0.0

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _aim_basis: Basis = Basis.IDENTITY
var input_enabled: bool = true


func _ready() -> void:
	is_player = true
	ship_name = "Player Fighter"
	super._ready()
	add_to_group("player_fighter")
	_sync_look_from_transform()


func _sync_look_from_transform() -> void:
	var fwd := get_forward()
	_look_yaw = atan2(-fwd.x, -fwd.z)
	_look_pitch = asin(clampf(fwd.y, -1.0, 1.0))
	_aim_basis = global_transform.basis


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_look_yaw -= motion.relative.x * mouse_sensitivity
		_look_pitch -= motion.relative.y * mouse_sensitivity
		_look_pitch = clampf(_look_pitch, deg_to_rad(-80.0), deg_to_rad(80.0))


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
		var nearest := TargetSystem.find_nearest_enemy(self)
		set_target(nearest)
	elif Input.is_action_just_pressed("target_cycle"):
		var next := TargetSystem.cycle_enemy_target(self, current_target)
		set_target(next)

	# Drop dead targets
	if current_target != null and (not is_instance_valid(current_target) or not current_target.is_alive):
		clear_target()


func _handle_combat_input() -> void:
	if Input.is_action_pressed("fire_primary"):
		try_fire()


func _apply_player_flight(delta: float) -> void:
	var aim_forward := Vector3(
		-sin(_look_yaw) * cos(_look_pitch),
		sin(_look_pitch),
		-cos(_look_yaw) * cos(_look_pitch)
	).normalized()

	var strafe := Vector3.ZERO
	if Input.is_action_pressed("move_left"):
		strafe.x -= 1.0
	if Input.is_action_pressed("move_right"):
		strafe.x += 1.0
	if Input.is_action_pressed("move_forward"):
		strafe.y += 1.0
	if Input.is_action_pressed("move_back"):
		strafe.y -= 1.0
	if strafe.length_squared() > 1.0:
		strafe = strafe.normalized()

	var thrust := 0.0
	if Input.is_action_pressed("thrust"):
		thrust = 1.0
	# Mild forward from W as well for comfort
	if Input.is_action_pressed("move_forward") and not Input.is_action_pressed("thrust"):
		thrust = maxf(thrust, 0.35)

	var boost := Input.is_action_pressed("boost") and thrust > 0.1
	apply_steering(aim_forward, thrust, strafe, boost, delta)
	_update_engine_fx()


func enable_control(enabled: bool) -> void:
	input_enabled = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_sync_look_from_transform()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
