## Developer visual showcase — iterate sky / star / bodies / ships by seed.
## Showcase modes match the forensics brief:
##   1 Deep space  2 Star  3 Planet  4 Station  5 Ship  6 Asteroid
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
var view_mode: int = 0 # 0 sky, 1 star, 2 planet, 3 station, 4 ship, 5 asteroid
var dragging := false


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
	_apply_view()
	_refresh_label()


func _apply_view() -> void:
	match view_mode:
		1: # local star against deep space
			focus = sim.world["star"]["position"] if sim != null else Vector3.ZERO
			distance = maxf(float(sim.world["star"].get("radius", 40.0)) * 6.5, 220.0)
			pitch = -0.05
		2: # planet
			focus = presenter.get_planet_focus() if presenter else Vector3.ZERO
			distance = 320.0
		3: # station
			focus = presenter.get_station_focus() if presenter else Vector3.ZERO
			distance = 180.0
		4: # ship
			if sim != null and not sim.world["ships"].is_empty():
				focus = sim.world["ships"][0]["position"]
			else:
				focus = Vector3.ZERO
			distance = 40.0
		5: # asteroid field
			if sim != null and not sim.world["yields"].is_empty():
				focus = sim.world["yields"][0]["position"]
			else:
				focus = Vector3.ZERO
			distance = 220.0
		_: # deep space — face primary luminous mass
			focus = Vector3.ZERO
			distance = 1500.0
			if presenter != null:
				var sky_dir := SkyComposition.primary_mass_dir(presenter.sky_comp)
				yaw = atan2(-sky_dir.x, -sky_dir.z) + 0.25
	_refresh_label()


func _process(_dt: float) -> void:
	if camera == null:
		return
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
				distance = minf(8000.0, distance * 1.18)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(20.0, distance * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(8000.0, distance * 1.1)
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.2, 1.2)


func _refresh_label() -> void:
	if label == null or sim == null:
		return
	var modes := ["DEEP SPACE", "STAR", "PLANET", "STATION", "SHIP", "ASTEROID"]
	var sky: Dictionary = sim.world.get("sky_composition", {})
	var star: Dictionary = sim.world.get("star", {})
	label.text = "\n".join(PackedStringArray([
		"VISUAL SHOWCASE  |  seed %d  |  view %s" % [world_seed, modes[view_mode]],
		"System %s  star=%s  mood=%s" % [
			str(sim.world.get("name", "?")), str(star.get("star_type", "?")), str(sky.get("mood", "?")),
		],
		"Masses=%s voids=%s gems=%s  ships=%d  backend=%s" % [
			str(sky.get("masses", 0)), str(sky.get("voids", 0)), str(sky.get("gems", 0)),
			sim.world["ships"].size(), NativeBridge.backend_name(),
		],
		"",
		"[ ] seed   R regen   1 sky 2 star 3 planet 4 station 5 ship 6 asteroid",
		"Arrows / drag orbit   +/- zoom   Esc/F5 back to main",
	]))
