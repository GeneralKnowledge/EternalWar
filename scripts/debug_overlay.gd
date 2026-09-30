class_name DebugOverlay
extends CanvasLayer

## Developer overlay toggled with F3.

var visible_debug: bool = false
var _label: Label
var _help: Label


func _ready() -> void:
	layer = 20
	_label = Label.new()
	_label.position = Vector2(24, 160)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)

	_help = Label.new()
	_help.position = Vector2(24, 320)
	_help.add_theme_font_size_override("font_size", 12)
	_help.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5, 0.8))
	_help.text = "F3 debug | F5 spawn ally | F6 spawn enemy | F7 kill target | F8 respawn | F9 reset"
	add_child(_help)

	_set_visible(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_set_visible(not visible_debug)
		get_viewport().set_input_as_handled()
		return

	if not visible_debug:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F5:
				BattleManager.debug_spawn_fighter(Teams.Side.FRIENDLY)
			KEY_F6:
				BattleManager.debug_spawn_fighter(Teams.Side.ENEMY)
			KEY_F7:
				BattleManager.debug_destroy_player_target()
			KEY_F8:
				BattleManager.debug_respawn_player()
			KEY_F9:
				BattleManager.debug_reset_battle()


func _set_visible(v: bool) -> void:
	visible_debug = v
	_label.visible = v
	_help.visible = v


func _process(_delta: float) -> void:
	if not visible_debug or BattleManager == null:
		return
	var fps := Engine.get_frames_per_second()
	_label.text = "\n".join([
		"=== DEBUG ===",
		"Battle time: %.1fs" % BattleManager.battle_time,
		"Friendly fighters: %d" % BattleManager.get_friendly_fighter_count(),
		"Enemy fighters: %d" % BattleManager.get_enemy_fighter_count(),
		"Player kills: %d" % BattleManager.player_kills,
		"Player deaths: %d" % BattleManager.player_deaths,
		"Active projectiles: %d" % BattleManager.active_projectiles,
		"FPS: %d" % fps,
		"Player alive: %s" % str(BattleManager.player != null and is_instance_valid(BattleManager.player) and BattleManager.player.is_alive),
	])
