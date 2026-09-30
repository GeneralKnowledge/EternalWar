class_name ChaseCamera
extends Camera3D

## BSGO-style third-person chase camera: sits behind the ship, tracks nose tightly.
## Structured so additional modes can be added later.

enum Mode {
	CHASE,
	# Future: COCKPIT, CINEMATIC, ORBIT
}

@export var mode: Mode = Mode.CHASE
@export var follow_distance: float = 16.0
@export var follow_height: float = 3.8
@export var look_ahead: float = 28.0
@export var position_lerp: float = 10.0
@export var rotation_lerp: float = 12.0
## Blend a little of velocity into camera offset so drifts read clearly.
@export var velocity_lag: float = 0.035

var target: Node3D = null
var _fallback_position: Vector3 = Vector3(-2000, 200, 400)


func _ready() -> void:
	fov = 72.0
	far = 30000.0
	near = 0.35


func set_follow_target(node: Node3D) -> void:
	target = node


func clear_target() -> void:
	target = null


func _process(delta: float) -> void:
	match mode:
		Mode.CHASE:
			_update_chase(delta)


func _update_chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		var desired := _fallback_position
		if BattleManager and BattleManager.friendly_battleship:
			desired = BattleManager.friendly_battleship.global_position + Vector3(-180, 100, 160)
		global_position = global_position.lerp(desired, 1.0 - exp(-position_lerp * 0.5 * delta))
		var look_at_pos := desired + Vector3(400, -30, 0)
		if BattleManager and BattleManager.enemy_battleship:
			look_at_pos = BattleManager.enemy_battleship.global_position * 0.35 + desired * 0.65
		look_at(look_at_pos, Vector3.UP)
		return

	var back := target.global_transform.basis.z
	var up := target.global_transform.basis.y
	var desired_pos := target.global_position + back * follow_distance + up * follow_height

	if target is Fighter:
		var vel: Vector3 = (target as Fighter).velocity
		# Lag slightly opposite travel so high-speed drifts feel cinematic.
		desired_pos -= vel * velocity_lag

	global_position = global_position.lerp(desired_pos, 1.0 - exp(-position_lerp * delta))

	var look_point := target.global_position - target.global_transform.basis.z * look_ahead + up * 1.0
	var look_dir := look_point - global_position
	if look_dir.length_squared() < 0.0001:
		return
	var safe_up := up
	if absf(look_dir.normalized().dot(safe_up)) > 0.95:
		safe_up = target.global_transform.basis.x
	var desired_basis := Basis.looking_at(look_dir.normalized(), safe_up)
	var t := 1.0 - exp(-rotation_lerp * delta)
	global_transform.basis = global_transform.basis.slerp(desired_basis, t)
