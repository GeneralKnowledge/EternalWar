## Debug / simulation HUD overlay with procedural inspect panel.
class_name DebugOverlay
extends CanvasLayer

var sim: StarSystemSim
var player: PlayerController
var presenter: SystemPresenter
var label: Label
var paused: bool = false


func setup(p_sim: StarSystemSim, p_player: PlayerController, p_presenter: SystemPresenter = null) -> void:
	sim = p_sim
	player = p_player
	presenter = p_presenter
	layer = 100
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.92))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)


func set_paused(p: bool) -> void:
	paused = p
	if player != null and player.get_parent() != null:
		var main = player.get_parent()
		if main.get("time_scale") != null:
			main.time_scale = 0.0 if paused else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			set_paused(not paused)


func _process(_dt: float) -> void:
	if sim == null or label == null or sim.world.is_empty():
		return
	var p := sim.perf
	var m: Dictionary = sim.economy.metrics
	var prices: Dictionary = m.get("avg_prices", {})
	var mode := "OBSERVE (F1 fly, 1/2/3 cinema)" if player == null or player.observe_mode else "FLY (F1 observe, F2 dock/trade)"
	var cinema := ""
	if player != null and player.observe_mode:
		var names := ["system orbit", "planet approach", "station flyby"]
		cinema = "  Cinema: %s" % names[clampi(player.cinematic_preset, 0, 2)]
	var star: Dictionary = sim.world.get("star", {})
	var cache := MeshCache.stats()
	var lines: PackedStringArray = PackedStringArray([
		"Limit Theory Prototype  |  seed %d  |  %s%s%s" % [sim.seed_value, mode, cinema, "  [PAUSED F3]" if paused else ""],
		"System: %s   t=%.1fs   Star: %s (%.0fK)" % [
			str(sim.world.get("name", "?")), float(sim.world.get("sim_time", 0.0)),
			str(star.get("star_type", "?")), float(star.get("temperature", 0.0))
		],
		"",
		"Simulation",
		"  Ships: %d   Active: %d   Idle: %d" % [p.get("ships_total", 0), p.get("ships_active", 0), p.get("ships_idle", 0)],
		"  Mining: %d   Dock/Trade: %d" % [p.get("ships_mining", 0), p.get("ships_trading", 0)],
		"  Jobs: %d   MeshCache: %d (hits %d)" % [m.get("job_count", 0), cache.get("entries", 0), cache.get("hits", 0)],
		"  Economy: %.2f ms   AI: %.2f ms   Tick: %.2f ms" % [p.get("economy_ms", 0.0), p.get("ai_ms", 0.0), p.get("sim_ms", 0.0)],
		"",
		"Economy",
		"  Ore: %.0f @ %.1f   Metal: %.0f @ %.1f" % [m.get("total_ore", 0.0), prices.get(Commodities.ORE, 0.0), m.get("total_metal", 0.0), prices.get(Commodities.METAL, 0.0)],
		"  Components: %.0f @ %.1f   Trades: %d" % [m.get("total_components", 0.0), prices.get(Commodities.COMPONENTS, 0.0), m.get("transactions", 0)],
	])

	if presenter != null:
		var target: Dictionary = presenter.get_inspect_target()
		if not target.is_empty():
			lines.append("")
			lines.append("Inspect (nearest)")
			if target.get("kind", "") == "ship" or target.has("ship_class"):
				var design: Dictionary = target.get("design", {})
				var desc := ShipMeshGen.describe(design)
				lines.append("  Ship #%d  class=%s  style=%s" % [
					int(target.get("id", 0)),
					SimEntities.class_name_of(int(target.get("ship_class", 0))),
					str(design.get("style", "?")),
				])
				lines.append("  Seeds  system=%d  object=%d  design=%d" % [
					sim.seed_value, int(target.get("seed", 0)), int(desc.get("seed", 0)),
				])
				lines.append("  Child  hull=%d  engine=%d  module=%d  detail=%d" % [
					int(desc.get("hull_seed", 0)), int(desc.get("engine_seed", 0)),
					int(desc.get("module_seed", 0)), int(desc.get("detail_seed", 0)),
				])
				lines.append("  Hull L/W/H: %.1f / %.1f / %.1f  engines=%d cargo=%d  sym=%s" % [
					float(desc.get("length", 0)), float(desc.get("width", 0)), float(desc.get("height", 0)),
					int(desc.get("engines", 0)), int(desc.get("cargo_modules", 0)),
					str(desc.get("symmetric", true)),
				])
				lines.append("  Modules: %s" % str(desc.get("module_types", [])))
				lines.append("  Activity: %d  credits: %.0f" % [int(target.get("activity", 0)), float(target.get("credits", 0))])

	# Sample planet / station identity
	if not sim.world["planets"].is_empty():
		var pl: Dictionary = sim.world["planets"][0]
		lines.append("")
		lines.append("Planet[0]: %s  class=%s  seed=%d  terrain=%d  atmo=%d" % [
			pl.get("name", "?"), pl.get("planet_class", "?"), int(pl.get("seed", 0)),
			int(pl.get("terrain_seed", 0)), int(pl.get("atmosphere_seed", 0)),
		])
	if not sim.world["stations"].is_empty():
		var st: Dictionary = sim.world["stations"][0]
		var sd := StationMeshGen.describe(st)
		lines.append("Station[0]: %s  role=%s  layout=%d  modules=%s" % [
			st.get("name", "?"), st.get("role", "?"), int(sd.get("layout_seed", 0)), str(sd.get("modules", [])),
		])

	if player != null and not player.ship.is_empty() and not player.observe_mode:
		var s: Dictionary = player.ship
		lines.append("")
		lines.append("Player  credits=%.0f  cargo=%.0f/%.0f" % [s["credits"], SimEntities.cargo_used(s), s["cargo_capacity"]])

	lines.append("")
	var sky: Dictionary = sim.world.get("sky_composition", {})
	if not sky.is_empty():
		lines.append("Sky mood=%s  masses=%s  voids=%s  gems=%s" % [
			str(sky.get("mood", "?")), str(sky.get("masses", "?")),
			str(sky.get("voids", "?")), str(sky.get("gems", "?")),
		])
	lines.append("F1 fly/observe  F2 dock  F3 pause  [ ] seed  R regen  F5 showcase  1/2/3 cinema")
	label.text = "\n".join(lines)
