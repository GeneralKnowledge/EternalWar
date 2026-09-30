class_name BattleHUD
extends CanvasLayer

## Minimal combat HUD: shields, hull, speed, target info, fleet counts.

var _shield_label: Label
var _hull_label: Label
var _speed_label: Label
var _engine_label: Label
var _target_label: Label
var _target_dist_label: Label
var _target_health_label: Label
var _fleet_label: Label
var _message_label: Label
var _pause_label: Label
var _spectate_label: Label
var _crosshair: Label

var _message_timer: float = 0.0
var _target_marker: Node3D = null


func _ready() -> void:
	layer = 10
	_build_ui()
	if BattleManager:
		BattleManager.player_died.connect(_on_player_died)
		BattleManager.player_respawned.connect(_on_player_respawned)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var font_color := Color(0.75, 0.9, 1.0)

	_shield_label = _make_label(root, Vector2(24, 24), font_color)
	_hull_label = _make_label(root, Vector2(24, 48), font_color)
	_speed_label = _make_label(root, Vector2(24, 72), font_color)
	_engine_label = _make_label(root, Vector2(24, 96), Color(0.55, 0.95, 0.7))
	_fleet_label = _make_label(root, Vector2(24, 132), Color(0.65, 0.8, 0.95))

	_target_label = _make_label(root, Vector2(24, -140), Color(1.0, 0.55, 0.45))
	_target_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_target_label.position = Vector2(24, -140)
	_target_dist_label = _make_label(root, Vector2(24, -116), font_color)
	_target_dist_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_target_dist_label.position = Vector2(24, -116)
	_target_health_label = _make_label(root, Vector2(24, -92), font_color)
	_target_health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_target_health_label.position = Vector2(24, -92)

	_message_label = _make_label(root, Vector2(0, 0), Color(1.0, 0.35, 0.3))
	_message_label.set_anchors_preset(Control.PRESET_CENTER)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 36)
	_message_label.position = Vector2(-200, -40)
	_message_label.size = Vector2(400, 50)
	_message_label.visible = false

	_pause_label = _make_label(root, Vector2(0, 0), Color(1, 1, 1, 0.9))
	_pause_label.set_anchors_preset(Control.PRESET_CENTER)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 28)
	_pause_label.text = "PAUSED"
	_pause_label.position = Vector2(-80, -80)
	_pause_label.size = Vector2(160, 40)
	_pause_label.visible = false

	_spectate_label = _make_label(root, Vector2(0, 24), Color(1.0, 0.85, 0.35))
	_spectate_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_label.add_theme_font_size_override("font_size", 20)
	_spectate_label.position = Vector2(-180, 24)
	_spectate_label.size = Vector2(360, 28)
	_spectate_label.text = "SPECTATING AI DOGFIGHT  (F4)"
	_spectate_label.visible = false

	_crosshair = _make_label(root, Vector2(0, 0), Color(0.8, 0.95, 1.0, 0.7))
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 22)
	_crosshair.position = Vector2(-10, -14)
	_crosshair.size = Vector2(20, 28)


func _make_label(parent: Control, pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.visible = false

	_pause_label.visible = BattleManager != null and BattleManager.paused

	var spectating := false
	var cam := get_tree().current_scene.get_node_or_null("ChaseCamera") as ChaseCamera if get_tree().current_scene else null
	if cam:
		spectating = cam.is_spectating()
	_spectate_label.visible = spectating
	_crosshair.visible = not spectating

	var p: PlayerFighter = BattleManager.player if BattleManager else null
	if spectating and cam and cam.target is Fighter:
		var f := cam.target as Fighter
		_shield_label.text = "SHIELD: %d%%" % int(f.get_shield_ratio() * 100.0)
		_hull_label.text = "HULL:   %d%%" % int(f.get_health_ratio() * 100.0)
		_speed_label.text = "SPEED:  %d m/s" % int(f.get_speed())
		_engine_label.text = "ENGINES: ON" if f.engines_lit else "ENGINES: OFF  (coasting)"
		_engine_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.7) if f.engines_lit else Color(1.0, 0.75, 0.35))
		_update_target_info_for_ship(f)
	elif p != null and is_instance_valid(p) and p.is_alive:
		_shield_label.text = "SHIELD: %d%%" % int(p.get_shield_ratio() * 100.0)
		_hull_label.text = "HULL:   %d%%" % int(p.get_health_ratio() * 100.0)
		_speed_label.text = "SPEED:  %d m/s" % int(p.get_speed())
		if p.engines_lit:
			_engine_label.text = "ENGINES: BURN" if p.boosting else "ENGINES: ON"
			_engine_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.7))
		else:
			_engine_label.text = "ENGINES: OFF  (coasting)"
			_engine_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		_update_target_info(p)
	else:
		_shield_label.text = "SHIELD: --"
		_hull_label.text = "HULL:   --"
		_speed_label.text = "SPEED:  --"
		_engine_label.text = "ENGINES: --"
		_target_label.text = ""
		_target_dist_label.text = ""
		_target_health_label.text = ""
		_clear_target_marker()

	if BattleManager:
		_fleet_label.text = "FLEET  F:%d  E:%d" % [
			BattleManager.get_friendly_fighter_count(),
			BattleManager.get_enemy_fighter_count()
		]


func _update_target_info(p: PlayerFighter) -> void:
	_update_target_info_for_ship(p)


func _update_target_info_for_ship(from: Fighter) -> void:
	var t := from.current_target
	if t == null or not is_instance_valid(t) or not t.is_alive:
		_target_label.text = "TARGET: NONE"
		_target_dist_label.text = ""
		_target_health_label.text = ""
		_clear_target_marker()
		return

	var dist := from.global_position.distance_to(t.global_position)
	var dist_str := "%.2f km" % (dist / 1000.0) if dist >= 1000.0 else "%d m" % int(dist)
	_target_label.text = "TARGET: %s" % t.ship_name.to_upper()
	_target_dist_label.text = "DISTANCE: %s" % dist_str
	_target_health_label.text = "HEALTH: %s  SHIELD: %d%%" % [
		_bar(t.get_health_ratio(), 10),
		int(t.get_shield_ratio() * 100.0)
	]
	_update_target_marker(t)


func _bar(ratio: float, width: int) -> String:
	var filled := int(clampf(ratio, 0.0, 1.0) * width)
	return "█".repeat(filled) + "░".repeat(width - filled)


func _update_target_marker(t: Ship) -> void:
	if _target_marker == null or not is_instance_valid(_target_marker):
		_target_marker = _create_marker()
		get_tree().current_scene.add_child(_target_marker)
	_target_marker.visible = true
	_target_marker.global_position = t.global_position
	# Soft pulse
	var s := 6.0 + sin(Time.get_ticks_msec() * 0.006) * 0.8
	_target_marker.scale = Vector3.ONE * s


func _create_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "TargetMarker"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.3, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.25)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root.add_child(mi)
	return root


func _clear_target_marker() -> void:
	if _target_marker and is_instance_valid(_target_marker):
		_target_marker.visible = false


func _on_player_died() -> void:
	show_message("FIGHTER DESTROYED", 2.4)
	_clear_target_marker()


func _on_player_respawned(_f: PlayerFighter) -> void:
	show_message("LAUNCHING", 1.2)


func show_message(text: String, duration: float = 2.0) -> void:
	_message_label.text = text
	_message_label.visible = true
	_message_timer = duration
