class_name FighterAI
extends Node

## Simple state-machine AI with BSGO-style drift / engine-cut passes.

enum State {
	SEARCHING,
	APPROACHING,
	ATTACKING,
	DRIFT_ATTACK,
	DESTROYED,
}

@export var preferred_range: float = 280.0
@export var attack_range: float = 750.0
@export var disengage_range: float = 100.0
@export var fire_angle_deg: float = 22.0

var fighter: Fighter = null
var state: State = State.SEARCHING
var target: Ship = null

var _break_timer: float = 0.0
var _break_direction: Vector3 = Vector3.ZERO
var _wander_offset: Vector3 = Vector3.ZERO
var _personality: float = 1.0
var _retarget_cooldown: float = 0.0
var _drift_timer: float = 0.0


func _ready() -> void:
	fighter = get_parent() as Fighter
	assert(fighter != null, "FighterAI must be child of Fighter")
	_personality = randf_range(0.75, 1.35)
	preferred_range *= randf_range(0.8, 1.25)
	_wander_offset = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()
	_break_timer = randf_range(2.0, 6.0)
	_drift_timer = randf_range(3.0, 8.0)


func _physics_process(delta: float) -> void:
	if fighter == null or not fighter.is_alive:
		state = State.DESTROYED
		return

	_retarget_cooldown = maxf(0.0, _retarget_cooldown - delta)
	_drift_timer = maxf(0.0, _drift_timer - delta)
	_update_target()
	_update_state()
	_steer(delta)


func _update_target() -> void:
	if target != null and (not is_instance_valid(target) or not target.is_alive):
		target = null
		fighter.clear_target()
		state = State.SEARCHING

	if target == null or _retarget_cooldown <= 0.0:
		var found := TargetSystem.find_nearest_enemy(fighter)
		if found != null:
			target = found
			fighter.set_target(found)
			_retarget_cooldown = randf_range(1.5, 3.5)


func _update_state() -> void:
	if target == null:
		state = State.SEARCHING
		return

	var dist := fighter.global_position.distance_to(target.global_position)
	match state:
		State.SEARCHING:
			state = State.APPROACHING
		State.APPROACHING:
			if dist <= attack_range:
				state = State.ATTACKING
		State.ATTACKING:
			if dist > attack_range * 1.35:
				state = State.APPROACHING
			elif dist < disengage_range:
				_start_breakaway()
			elif _drift_timer <= 0.0 and dist < preferred_range * 1.4:
				# Cut engines, flip toward target while coasting (Raider-style).
				state = State.DRIFT_ATTACK
				_drift_timer = randf_range(1.1, 2.2) * _personality
		State.DRIFT_ATTACK:
			if _drift_timer <= 0.0 or dist > attack_range:
				state = State.ATTACKING
				_drift_timer = randf_range(4.0, 9.0)
		_:
			pass


func _start_breakaway() -> void:
	_break_timer = randf_range(0.8, 1.8) * _personality
	var right := fighter.global_transform.basis.x
	var up := fighter.global_transform.basis.y
	_break_direction = (right * randf_range(-1, 1) + up * randf_range(-0.6, 0.6) - fighter.get_forward() * 0.2).normalized()


func _steer(delta: float) -> void:
	var desired := fighter.get_forward()
	var thrust := 0.55
	var strafe := Vector3.ZERO
	var boost := false

	_break_timer -= delta

	if state == State.SEARCHING or target == null:
		var rally := _get_rally_point()
		desired = (rally - fighter.global_position + _wander_offset * 120.0).normalized()
		thrust = 0.7
	else:
		var to_target := target.global_position - fighter.global_position
		var dist := to_target.length()
		var lead := Vector3.ZERO
		if target is Fighter:
			lead = (target as Fighter).velocity * (dist / 2200.0)
		var aim_dir := ((target.global_position + lead) - fighter.global_position).normalized()

		if state == State.DRIFT_ATTACK:
			# Engines off — face the enemy while sliding on existing momentum.
			desired = aim_dir
			thrust = 0.0
			strafe = Vector3.ZERO
			boost = false
			var facing := fighter.get_forward().dot(aim_dir)
			if facing >= cos(deg_to_rad(fire_angle_deg)) and dist <= attack_range:
				fighter.try_fire()
		elif _break_timer > 0.0 and state == State.ATTACKING:
			desired = (_break_direction + aim_dir * 0.35).normalized()
			thrust = 0.95
			boost = true
			strafe = Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), 0)
		elif state == State.APPROACHING:
			desired = (aim_dir + _wander_offset * 0.15).normalized()
			thrust = 0.95
			boost = dist > preferred_range * 2.0
			strafe.x = sin(Time.get_ticks_msec() * 0.002 * _personality + _personality * 10.0) * 0.4
		else:
			var orbit := fighter.global_transform.basis.x * sin(Time.get_ticks_msec() * 0.0015 * _personality)
			orbit += fighter.global_transform.basis.y * cos(Time.get_ticks_msec() * 0.0011 * _personality) * 0.5
			if dist > preferred_range * 1.2:
				desired = (aim_dir * 0.85 + orbit * 0.15).normalized()
				thrust = 0.85
			elif dist < preferred_range * 0.7:
				# Burn sideways / reverse while turning guns on target.
				desired = aim_dir
				thrust = -0.35
				strafe = Vector3(signf(sin(_personality * 9.0)), 0.2, 0.0)
				_start_breakaway()
			else:
				desired = (aim_dir * 0.75 + orbit * 0.25).normalized()
				thrust = 0.35 if randf() > 0.4 else 0.0
				strafe.x = sin(Time.get_ticks_msec() * 0.002 + _personality) * 0.7

			var facing2 := fighter.get_forward().dot(aim_dir)
			if facing2 >= cos(deg_to_rad(fire_angle_deg)) and dist <= attack_range:
				fighter.try_fire()

	if randf() < 0.002:
		_start_breakaway()

	fighter.apply_steering(desired, thrust, strafe, boost, delta)
	fighter._update_engine_fx()


func _get_rally_point() -> Vector3:
	var bm := get_node_or_null("/root/BattleManager")
	if bm == null:
		return Vector3.ZERO
	var enemy_ship: Battleship = bm.enemy_battleship if fighter.team == Teams.Side.FRIENDLY else bm.friendly_battleship
	if enemy_ship != null and is_instance_valid(enemy_ship):
		var mid := enemy_ship.global_position * 0.55
		mid.y += sin(_personality * 20.0) * 200.0
		return mid + _wander_offset * 400.0
	return _wander_offset * 500.0
