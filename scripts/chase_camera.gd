class_name ChaseCamera
extends Camera3D

## BSGO-style chase cam locked to ship attitude.
## Hard catch-up prevents the camera from drifting off-frame during coasting flips.

enum Mode {
	CHASE,
}

@export var mode: Mode = Mode.CHASE
@export var follow_distance: float = 14.0
@export var follow_height: float = 2.8
@export var look_ahead: float = 45.0
@export var position_lerp: float = 22.0
@export var rotation_lerp: float = 20.0
## Max distance the camera may lag behind its ideal seat.
@export var max_lag: float = 8.0

var target: Node3D = null
var _fallback_position: Vector3 = Vector3(-2000, 200, 400)
var _spectating: bool = false


func _ready() -> void:
	fov = 68.0
	far = 30000.0
	near = 0.35


func set_follow_target(node: Node3D) -> void:
	target = node
	_spectating = false
	if target != null and is_instance_valid(target):
		_snap_to_target()


func set_spectate_target(node: Node3D) -> void:
	target = node
	_spectating = true
	if target != null and is_instance_valid(target):
		_snap_to_target()


func clear_target() -> void:
	target = null
	_spectating = false


func is_spectating() -> bool:
	return _spectating


func _snap_to_target() -> void:
	var ship_xf := target.global_transform
	global_position = ship_xf * Vector3(0.0, follow_height, follow_distance)
	var look_point := target.global_position + (-ship_xf.basis.z) * look_ahead
	if not look_point.is_equal_approx(global_position):
		look_at(look_point, ship_xf.basis.y)


func _process(delta: float) -> void:
	match mode:
		Mode.CHASE:
			_update_chase(delta)


func _update_chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_update_fallback(delta)
		return

	var ship_xf := target.global_transform
	var desired_pos := ship_xf * Vector3(0.0, follow_height, follow_distance)

	# Clamp lag so a 180° flip never leaves the ship on the screen edge.
	var to_desired := desired_pos - global_position
	var lag := to_desired.length()
	if lag > max_lag:
		global_position = desired_pos - to_desired.normalized() * max_lag

	var catch_up := position_lerp + clampf(lag * 2.5, 0.0, 40.0)
	global_position = global_position.lerp(desired_pos, 1.0 - exp(-catch_up * delta))

	var forward := -ship_xf.basis.z
	var look_point := target.global_position + forward * look_ahead + ship_xf.basis.y * 0.5
	var look_dir := look_point - global_position
	if look_dir.length_squared() < 0.0001:
		look_dir = forward
	else:
		look_dir = look_dir.normalized()

	var cam_up := ship_xf.basis.y
	if absf(look_dir.dot(cam_up)) > 0.9:
		cam_up = ship_xf.basis.x

	var desired_basis := Basis.looking_at(look_dir, cam_up)
	global_transform.basis = global_transform.basis.slerp(desired_basis, 1.0 - exp(-rotation_lerp * delta)).orthonormalized()


func _update_fallback(delta: float) -> void:
	var desired := _fallback_position
	if BattleManager and BattleManager.friendly_battleship and is_instance_valid(BattleManager.friendly_battleship):
		desired = BattleManager.friendly_battleship.global_position + Vector3(-180, 100, 160)
	global_position = global_position.lerp(desired, 1.0 - exp(-position_lerp * 0.5 * delta))
	var look_at_pos := desired + Vector3(400, -30, 0)
	if BattleManager and BattleManager.enemy_battleship and is_instance_valid(BattleManager.enemy_battleship):
		look_at_pos = BattleManager.enemy_battleship.global_position * 0.35 + desired * 0.65
	if not look_at_pos.is_equal_approx(global_position):
		look_at(look_at_pos, Vector3.UP)
