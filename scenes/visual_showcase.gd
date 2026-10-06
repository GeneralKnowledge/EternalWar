## Developer visual showcase — sky / nebula volume / bodies by seed.
## Modes: 1 Deep space  2 Star  3 Planet  4 Station  5 Ship  6 Asteroid  7 Nebula Volume
## Nebula diagnostics: N cycle beauty/density/depth/absorb   Q cycle ray quality
## Freeze sim; orbit with mouse/arrows. Esc/F5 → main.
extends Node3D

@export var world_seed: int = 42
@export var ship_count: int = 120

var sim: StarSystemSim
var presenter: SystemPresenter
var camera: Camera3D
var label: Label
var yaw: float = 0.6
var pitch: float = -0.25
var distance: float = 1400.0
var focus: Vector3 = Vector3.ZERO
var view_mode: int = 0
var dragging := false
var debug_nebula: int = 0
var volume_quality: int = 24
var flythrough_t: float = -1.0 # <0 inactive; else 0..1 dolly into primary mass


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 50000.0
	camera.near = 0.4
	camera.fov = 68.0
	add_child(camera)
	camera.current = true

	var hud := CanvasLayer.new()
	add_child(hud)
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	hud.add_child(label)

	_regen()


func _regen() -> void:
	if presenter != null:
		presenter.queue_free()
		presenter = null
	sim = StarSystemSim.new()
	sim.generate(world_seed, ship_count)
	presenter = SystemPresenter.new()
	add_child(presenter)
	presenter.setup(sim, camera)
	presenter.sky_comp["volume_quality"] = volume_quality
	presenter.sky_comp["debug_nebula"] = debug_nebula
	presenter.set_nebula_quality(volume_quality)
	presenter.set_nebula_debug_mode(debug_nebula)
	_apply_view()
	_refresh_label()


func _apply_view() -> void:
	flythrough_t = -1.0
	match view_mode:
		1:
			focus = sim.world["star"]["position"] if sim != null else Vector3.ZERO
			distance = maxf(float(sim.world["star"].get("radius", 40.0)) * 6.5, 220.0)
			pitch = -0.05
		2:
			focus = presenter.get_planet_focus() if presenter else Vector3.ZERO
			distance = 320.0
		3:
			focus = presenter.get_station_focus() if presenter else Vector3.ZERO
			distance = 180.0
		4:
			if sim != null and not sim.world["ships"].is_empty():
				focus = sim.world["ships"][0]["position"]
			else:
				focus = Vector3.ZERO
			distance = 40.0
		5:
			if sim != null and not sim.world["yields"].is_empty():
				focus = sim.world["yields"][0]["position"]
			else:
				focus = Vector3.ZERO
			distance = 220.0
		6: # Nebula Volume — face primary mass, start outside, ready for flythrough
			var mass := SkyComposition.primary_mass(presenter.sky_comp) if presenter else {}
			var center: Vector3 = mass.get("center", SkyComposition.primary_mass_dir(presenter.sky_comp) * 5000.0) if presenter else Vector3(2000, 0, 2000)
			focus = center
			distance = float(mass.get("radius", 3000.0)) * 2.4 if not mass.is_empty() else 7000.0
			if presenter != null:
				var sky_dir: Vector3 = mass.get("dir", SkyComposition.primary_mass_dir(presenter.sky_comp))
				yaw = atan2(-sky_dir.x, -sky_dir.z)
				pitch = -0.08
		_:
			focus = Vector3.ZERO
			distance = 1500.0
			if presenter != null:
				var sky_dir2 := SkyComposition.primary_mass_dir(presenter.sky_comp)
				yaw = atan2(-sky_dir2.x, -sky_dir2.z) + 0.25
	_refresh_label()


func _process(dt: float) -> void:
	if camera == null:
		return
	if view_mode == 6 and flythrough_t >= 0.0:
		flythrough_t = minf(1.0, flythrough_t + dt * 0.08)
		var mass := SkyComposition.primary_mass(presenter.sky_comp) if presenter else {}
		var center: Vector3 = mass.get("center", focus)
		var rad := float(mass.get("radius", 3000.0))
		var dir: Vector3 = mass.get("dir", Vector3(0.4, 0.1, 0.35)).normalized()
		# Dolly from outside → through dense region → look back angle
		var start := center - dir * rad * 2.6
		var mid := center - dir * rad * 0.15
		var end := center + dir * rad * 0.4 + Vector3(0, rad * 0.25, 0)
		var t := flythrough_t
		var pos: Vector3
		if t < 0.55:
			pos = start.lerp(mid, t / 0.55)
			camera.global_position = pos
			camera.look_at(center, Vector3.UP)
		else:
			pos = mid.lerp(end, (t - 0.55) / 0.45)
			camera.global_position = pos
			camera.look_at(center - dir * rad * 0.5, Vector3.UP)
		distance = camera.global_position.distance_to(focus)
	else:
		var offset := Vector3(
			sin(yaw) * cos(pitch),
			sin(pitch),
			cos(yaw) * cos(pitch)
		) * distance
		camera.global_position = focus + offset
		camera.look_at(focus, Vector3.UP)
	if presenter != null and sim != null:
		presenter.sync_ships()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETLEFT:
				world_seed = maxi(1, world_seed - 1)
				_regen()
			KEY_BRACKETRIGHT:
				world_seed += 1
				_regen()
			KEY_R:
				_regen()
			KEY_1:
				view_mode = 0
				_apply_view()
			KEY_2:
				view_mode = 1
				_apply_view()
			KEY_3:
				view_mode = 2
				_apply_view()
			KEY_4:
				view_mode = 3
				_apply_view()
			KEY_5:
				view_mode = 4
				_apply_view()
			KEY_6:
				view_mode = 5
				_apply_view()
			KEY_7:
				view_mode = 6
				_apply_view()
			KEY_N:
				debug_nebula = (debug_nebula + 1) % 4
				if presenter:
					presenter.set_nebula_debug_mode(debug_nebula)
				_refresh_label()
			KEY_Q:
				# Cycle ray quality 16 → 24 → 32 → 16
				if volume_quality <= 16:
					volume_quality = 24
				elif volume_quality <= 24:
					volume_quality = 32
				else:
					volume_quality = 16
				if presenter:
					presenter.set_nebula_quality(volume_quality)
				_refresh_label()
			KEY_F:
				# Start / restart volume flythrough (nebula mode)
				if view_mode != 6:
					view_mode = 6
					_apply_view()
				flythrough_t = 0.0
				_refresh_label()
			KEY_ESCAPE, KEY_F5:
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			KEY_LEFT:
				yaw -= 0.12
			KEY_RIGHT:
				yaw += 0.12
			KEY_UP:
				pitch = clampf(pitch + 0.08, -1.2, 1.2)
			KEY_DOWN:
				pitch = clampf(pitch - 0.08, -1.2, 1.2)
			KEY_EQUAL, KEY_KP_ADD:
				distance = maxf(20.0, distance * 0.85)
			KEY_MINUS, KEY_KP_SUBTRACT:
				distance = minf(12000.0, distance * 1.18)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(20.0, distance * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(12000.0, distance * 1.1)
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.2, 1.2)


func _refresh_label() -> void:
	if label == null or sim == null:
		return
	var modes := ["DEEP SPACE", "STAR", "PLANET", "STATION", "SHIP", "ASTEROID", "NEBULA VOLUME"]
	var dbg := ["beauty", "density", "depth", "absorb"]
	var sky: Dictionary = sim.world.get("sky_composition", {})
	var star: Dictionary = sim.world.get("star", {})
	var mass := SkyComposition.primary_mass(presenter.sky_comp) if presenter else {}
	label.text = "\n".join(PackedStringArray([
		"VISUAL SHOWCASE  |  seed %d  |  view %s" % [world_seed, modes[view_mode]],
		"System %s  star=%s  mood=%s" % [
			str(sim.world.get("name", "?")), str(star.get("star_type", "?")), str(sky.get("mood", "?")),
		],
		"Masses=%s voids=%s gems=%s  ships=%d  backend=%s" % [
			str(sky.get("masses", 0)), str(sky.get("voids", 0)), str(sky.get("gems", 0)),
			sim.world["ships"].size(), NativeBridge.backend_name(),
		],
		"Nebula debug=%s  ray_steps=%d  primary r=%.0f near=%.0f far=%.0f" % [
			dbg[debug_nebula], volume_quality,
			float(mass.get("radius", 0.0)), float(mass.get("depth_near", 0.0)), float(mass.get("depth_far", 0.0)),
		],
		"",
		"[ ] seed  R regen  1-6 views  7 nebula volume  F flythrough",
		"N debug  Q quality  Arrows/drag orbit  +/- zoom  Esc/F5 main",
	]))
