## Deterministic Limit Theory comparison harness.
## Scenarios: EMPTY / NEBULA / STAR / SHIP / STATION / ASTEROIDS
## Keys 1-6 select. C captures. Headless: -- --capture [--capture=/path]
extends Node3D

const SCENARIOS := [
	{"id": "empty", "seed": 7, "view": "sky", "yaw": 0.9, "pitch": -0.15, "dist": 1800.0},
	{"id": "nebula", "seed": 42, "view": "sky", "yaw": null, "pitch": -0.12, "dist": 1600.0},
	{"id": "star", "seed": 42, "view": "star", "yaw": 0.55, "pitch": -0.12, "dist": 520.0},
	{"id": "ship", "seed": 42, "view": "ship", "yaw": 0.55, "pitch": -0.1, "dist": 45.0},
	{"id": "station", "seed": 42, "view": "station", "yaw": 0.7, "pitch": -0.18, "dist": 200.0},
	{"id": "asteroids", "seed": 42, "view": "asteroid", "yaw": 1.1, "pitch": -0.2, "dist": 240.0},
]

@export var ship_count: int = 80
@export var capture_dir: String = "user://lt_compare"

var sim: StarSystemSim
var presenter: SystemPresenter
var camera: Camera3D
var label: Label
var scenario_i: int = 1
var yaw: float = 0.6
var pitch: float = -0.12
var distance: float = 1600.0
var focus: Vector3 = Vector3.ZERO
var _frames: int = 0
var _capture_queue: Array = []
var _capture_path: String = ""
var _capturing: bool = false
var _hide_hud_for_capture: bool = false


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 50000.0
	camera.near = 0.4
	camera.fov = 65.0
	add_child(camera)
	camera.current = true

	var hud := CanvasLayer.new()
	add_child(hud)
	label = Label.new()
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 0.95))
	hud.add_child(label)

	var auto := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture" or arg.begins_with("--capture="):
			auto = true
			if arg.begins_with("--capture=") and arg.length() > 10:
				capture_dir = arg.substr(10)
		elif arg.begins_with("--scenario="):
			var id := arg.substr(11)
			for i in SCENARIOS.size():
				if SCENARIOS[i]["id"] == id:
					scenario_i = i
	if OS.get_environment("LT_CAPTURE") != "":
		auto = true
		var env_dir := OS.get_environment("LT_CAPTURE_DIR")
		if env_dir != "":
			capture_dir = env_dir

	if auto:
		# If --scenario= was given, capture only that one; otherwise all.
		var only := scenario_i
		var scenario_pin := false
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--scenario="):
				scenario_pin = true
		if scenario_pin:
			_capture_queue = [only]
		else:
			_capture_queue = range(SCENARIOS.size())
		scenario_i = int(_capture_queue.pop_front())
		_capturing = true
	_apply_scenario()


func _apply_scenario() -> void:
	var sc: Dictionary = SCENARIOS[scenario_i]
	if presenter != null:
		presenter.queue_free()
		presenter = null
	sim = StarSystemSim.new()
	sim.generate(int(sc["seed"]), ship_count)
	presenter = SystemPresenter.new()
	add_child(presenter)
	presenter.setup(sim, camera)

	match str(sc["view"]):
		"star":
			focus = sim.world["star"]["position"]
			distance = float(sc["dist"])
			yaw = float(sc["yaw"])
		"ship":
			focus = sim.world["ships"][0]["position"] if not sim.world["ships"].is_empty() else Vector3.ZERO
			distance = float(sc["dist"])
			yaw = float(sc["yaw"])
		"station":
			focus = presenter.get_station_focus()
			distance = float(sc["dist"])
			yaw = float(sc["yaw"])
		"asteroid":
			focus = sim.world["yields"][0]["position"] if not sim.world["yields"].is_empty() else Vector3.ZERO
			distance = float(sc["dist"])
			yaw = float(sc["yaw"])
		_:
			# Look into the primary nebula mass (not at the star at origin).
			# LT nebula stills are gas-dominated frames; star-centric framing reads flat.
			var sky_dir := SkyComposition.primary_mass_dir(presenter.sky_comp)
			var pm: Dictionary = SkyComposition.primary_mass(presenter.sky_comp)
			var mass_center: Vector3 = pm.get("center", sky_dir * 5000.0)
			if str(sc["id"]) == "nebula":
				# Sit outside the mass looking through it — gas fills most of the FOV.
				focus = mass_center
				distance = maxf(float(pm.get("radius", 2500.0)) * 1.35, 2800.0)
				var view_dir := -sky_dir
				yaw = atan2(view_dir.x, view_dir.z)
				pitch = clampf(-asin(clampf(view_dir.y, -1.0, 1.0)) * 0.65 + float(sc["pitch"]), -1.2, 1.2)
			else:
				focus = Vector3.ZERO
				distance = float(sc["dist"])
				if sc["yaw"] == null:
					yaw = atan2(-sky_dir.x, -sky_dir.z) + 0.2
				else:
					yaw = float(sc["yaw"])
				pitch = float(sc["pitch"])
	if str(sc.get("id", "")) != "nebula":
		pitch = float(sc["pitch"])
	_frames = 0
	_hide_hud_for_capture = false
	if label:
		label.visible = true
	_refresh_label()


func _process(_dt: float) -> void:
	if camera == null:
		return
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)
	if presenter != null:
		presenter.sync_ships()
	_frames += 1
	if not _capturing:
		return
	if _frames == 6:
		_hide_hud_for_capture = true
		if label:
			label.visible = false
	elif _frames == 8:
		_write_capture()
		if not _capture_queue.is_empty():
			scenario_i = int(_capture_queue.pop_front())
			_apply_scenario()
		else:
			print("LT_COMPARE_CAPTURE_DONE dir=", _capture_path)
			_capturing = false
			if label:
				label.visible = true
			# Auto-quit after batch capture (headless or DISPLAY session).
			get_tree().quit()


func _write_capture() -> void:
	var sc: Dictionary = SCENARIOS[scenario_i]
	var dir := capture_dir
	if dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		_capture_path = ProjectSettings.globalize_path(dir)
	else:
		DirAccess.make_dir_recursive_absolute(dir)
		_capture_path = dir
	var path := "%s/ew_%s.png" % [_capture_path, str(sc["id"])]
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Captured ", path)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				scenario_i = event.keycode - KEY_1
				_capturing = false
				_apply_scenario()
			KEY_C:
				_capture_queue = [scenario_i]
				_capturing = true
				_frames = 0
			KEY_A:
				_capture_queue = range(SCENARIOS.size())
				scenario_i = int(_capture_queue.pop_front())
				_capturing = true
				_apply_scenario()
			KEY_ESCAPE, KEY_F5:
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			KEY_LEFT:
				yaw -= 0.1
			KEY_RIGHT:
				yaw += 0.1
			KEY_UP:
				pitch = clampf(pitch + 0.06, -1.2, 1.2)
			KEY_DOWN:
				pitch = clampf(pitch - 0.06, -1.2, 1.2)


func _refresh_label() -> void:
	if label == null or sim == null:
		return
	var sc: Dictionary = SCENARIOS[scenario_i]
	var sky: Dictionary = sim.world.get("sky_composition", {})
	label.text = "\n".join(PackedStringArray([
		"LT COMPARE  |  scenario %s  seed %s" % [str(sc["id"]), str(sc["seed"])],
		"mood=%s masses=%s  fov=65  backend=%s" % [
			str(sky.get("mood", "?")), str(sky.get("masses", "?")), NativeBridge.backend_name(),
		],
		"1 empty 2 nebula 3 star 4 ship 5 station 6 asteroids   C capture  A all   Esc main",
	]))
