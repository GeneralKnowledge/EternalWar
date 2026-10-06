## Debug / simulation HUD overlay.
class_name DebugOverlay
extends CanvasLayer

var sim: StarSystemSim
var player: PlayerController
var label: Label


func setup(p_sim: StarSystemSim, p_player: PlayerController) -> void:
	sim = p_sim
	player = p_player
	layer = 100
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.92))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)


func _process(_dt: float) -> void:
	if sim == null or label == null or sim.world.is_empty():
		return
	var p := sim.perf
	var m: Dictionary = sim.economy.metrics
	var prices: Dictionary = m.get("avg_prices", {})
	var mode := "OBSERVE (F1 fly)" if player == null or player.observe_mode else "FLY (F1 observe, F2 dock/trade)"
	var lines: PackedStringArray = PackedStringArray([
		"Limit Theory Prototype  |  seed %d  |  %s" % [sim.seed_value, mode],
		"System: %s   t=%.1fs" % [str(sim.world.get("name", "?")), float(sim.world.get("sim_time", 0.0))],
		"",
		"Simulation",
		"  Ships: %d   Active: %d   Idle: %d" % [p.get("ships_total", 0), p.get("ships_active", 0), p.get("ships_idle", 0)],
		"  Mining: %d   Dock/Trade: %d" % [p.get("ships_mining", 0), p.get("ships_trading", 0)],
		"  Jobs: %d" % [m.get("job_count", 0)],
		"  Economy: %.2f ms   AI: %.2f ms   Tick: %.2f ms" % [p.get("economy_ms", 0.0), p.get("ai_ms", 0.0), p.get("sim_ms", 0.0)],
		"",
		"Economy (station totals / avg price)",
		"  Ore: %.0f @ %.1f" % [m.get("total_ore", 0.0), prices.get(Commodities.ORE, 0.0)],
		"  Metal: %.0f @ %.1f" % [m.get("total_metal", 0.0), prices.get(Commodities.METAL, 0.0)],
		"  Components: %.0f @ %.1f" % [m.get("total_components", 0.0), prices.get(Commodities.COMPONENTS, 0.0)],
		"  Energy avg: %.1f   Food avg: %.1f" % [prices.get(Commodities.ENERGY, 0.0), prices.get(Commodities.FOOD, 0.0)],
		"  Production cycles: %d   Trades: %d" % [m.get("production_cycles", 0), m.get("transactions", 0)],
	])
	if player != null and not player.ship.is_empty() and not player.observe_mode:
		var s: Dictionary = player.ship
		lines.append("")
		lines.append("Player")
		lines.append("  Credits: %.0f   Cargo: %.0f/%.0f" % [s["credits"], SimEntities.cargo_used(s), s["cargo_capacity"]])
		lines.append("  Pos: (%.0f, %.0f, %.0f)" % [s["position"].x, s["position"].y, s["position"].z])
	lines.append("")
	lines.append("Observe: arrows orbit  +/- zoom   Fly: WASD+mouse  Space/C vertical")
	label.text = "\n".join(lines)
