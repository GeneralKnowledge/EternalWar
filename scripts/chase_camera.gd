class_name ChaseCamera
extends Camera3D

## Third-person chase camera. Structured so additional modes can be added later.

enum Mode {
	CHASE,
	# Future: COCKPIT, CINEMATIC, ORBIT
}

@export var mode: Mode = Mode.CHASE
@export var follow_distance: float = 22.0
@export var follow_height: float = 6.5
@export var look_ahead: float = 18.0
@export var position_lerp: float = 6.0
@export var rotation_lerp: float = 8.0

var target: Node3D = null
var _fallback_position: Vector3 = Vector3(-2000, 200, 400)


func _ready() -> void:
	fov = 78.0
	far = 25000.0


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
		# Hover near friendly battleship while waiting to respawn
		var desired := _fallback_position
		if BattleManager and BattleManager.friendly_battleship:
			desired = BattleManager.friendly_battleship.global_position + Vector3(-200, 120, 180)
		global_position = global_position.lerp(desired, 1.0 - exp(-position_lerp * 0.5 * delta))
		var look_at_pos := desired + Vector3(400, -40, 0)
		if BattleManager and BattleManager.enemy_battleship:
			look_at_pos = BattleManager.enemy_battleship.global_position * 0.3 + desired * 0.7
		look_at(look_at_pos, Vector3.UP)
		return

	var back := target.global_transform.basis.z  # ship forward is -Z, so +Z is behind
	var up := target.global_transform.basis.y
	var desired_pos := target.global_position + back * follow_distance + up * follow_height
	global_position = global_position.lerp(desired_pos, 1.0 - exp(-position_lerp * delta))

	var look_point := target.global_position - target.global_transform.basis.z * look_ahead + up * 1.5
	var current_look := -global_transform.basis.z
	var desired_look := (look_point - global_position).normalized()
	var blended := current_look.lerp(desired_look, 1.0 - exp(-rotation_lerp * delta)).normalized()
	if blended.length_squared() > 0.0001:
		look_at(global_position + blended, up)
