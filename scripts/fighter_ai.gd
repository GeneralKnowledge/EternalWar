class_name FighterAI
extends Node

## Simple state-machine AI for autonomous fighters in open space.

enum State {
	SEARCHING,
	APPROACHING,
	ATTACKING,
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


func _ready() -> void:
	fighter = get_parent() as Fighter
	assert(fighter != null, "FighterAI must be child of Fighter")
	_personality = randf_range(0.75, 1.35)
	preferred_range *= randf_range(0.8, 1.25)
	_wander_offset = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()
	_break_timer = randf_range(2.0, 6.0)


func _physics_process(delta: float) -> void:
	if fighter == null or not fighter.is_alive:
		state = State.DESTROYED
		return

	_retarget_cooldown = maxf(0.0, _retarget_cooldown - delta)
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
		# Drift toward enemy battleship / midfield with wander
		var rally := _get_rally_point()
		desired = (rally - fighter.global_position).normalized()
		desired = (desired + _wander_offset * 0.25).normalized()
		thrust = 0.7
	else:
		var to_target := target.global_position - fighter.global_position
		var dist := to_target.length()
		var to_dir := to_target / maxf(dist, 0.001)

		# Lead target slightly based on relative velocity
		var lead := Vector3.ZERO
		if target is Fighter:
			lead = (target as Fighter).velocity * (dist / 2200.0)
		var aim_point := target.global_position + lead
		var aim_dir := (aim_point - fighter.global_position).normalized()

		if _break_timer > 0.0 and state == State.ATTACKING:
			desired = (_break_direction + aim_dir * 0.35).normalized()
			thrust = 0.9
			boost = true
			strafe = Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), 0)
		elif state == State.APPROACHING:
			desired = (aim_dir + _wander_offset * 0.15).normalized()
			thrust = 0.95
			boost = dist > preferred_range * 2.0
			# Mild weave
			strafe.x = sin(Time.get_ticks_msec() * 0.002 * _personality + _personality * 10.0) * 0.4
		else: # ATTACKING
			var orbit := fighter.global_transform.basis.x * sin(Time.get_ticks_msec() * 0.0015 * _personality)
			orbit += fighter.global_transform.basis.y * cos(Time.get_ticks_msec() * 0.0011 * _personality) * 0.5
			if dist > preferred_range * 1.2:
				desired = (aim_dir * 0.85 + orbit * 0.15).normalized()
				thrust = 0.85
			elif dist < preferred_range * 0.7:
				desired = (-aim_dir * 0.35 + orbit.normalized() * 0.65 + _wander_offset * 0.2).normalized()
				thrust = 0.75
				_start_breakaway()
			else:
				desired = (aim_dir * 0.7 + orbit * 0.3).normalized()
				thrust = 0.65
				strafe.x = sin(Time.get_ticks_msec() * 0.002 + _personality) * 0.6

			# Fire when roughly aimed
			var facing := fighter.get_forward().dot(aim_dir)
			var fire_dot := cos(deg_to_rad(fire_angle_deg))
			if facing >= fire_dot and dist <= attack_range:
				fighter.try_fire()

	# Occasional random break to avoid identical paths
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
		# Midpoint toward enemy fleet with vertical scatter
		var mid := enemy_ship.global_position * 0.55
		mid.y += sin(_personality * 20.0) * 200.0
		return mid + _wander_offset * 400.0
	return _wander_offset * 500.0
