## Deterministic Limit Theory comparison harness.
## Scenarios: EMPTY / NEBULA / STAR / SHIP / STATION / ASTEROIDS
## Keys 1-6 select. C captures. Headless: -- --capture [--capture=/path]
## Nebula mood sheet: -- --nebula-sheet [--capture=/path]
extends Node3D

const SCENARIOS := [
	{"id": "empty", "seed": 7, "view": "sky", "yaw": 0.9, "pitch": -0.15, "dist": 1800.0},
	{"id": "nebula", "seed": 42, "view": "sky", "yaw": null, "pitch": -0.12, "dist": 1600.0},
	{"id": "star", "seed": 42, "view": "star", "yaw": 0.55, "pitch": -0.12, "dist": 520.0},
	{"id": "ship", "seed": 42, "view": "ship", "yaw": 0.55, "pitch": -0.1, "dist": 45.0},
	{"id": "station", "seed": 42, "view": "station", "yaw": 0.7, "pitch": -0.18, "dist": 200.0},
	{"id": "asteroids", "seed": 42, "view": "asteroid", "yaw": 1.1, "pitch": -0.2, "dist": 240.0},
	{"id": "planet", "seed": 42, "view": "planet", "yaw": 0.85, "pitch": -0.08, "dist": 380.0},
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
var _nebula_sheet: bool = false
var _mood_override: String = ""
var _capture_tag: String = ""


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
		elif arg == "--nebula-sheet":
			auto = true
			_nebula_sheet = true
		elif arg.begins_with("--mood="):
			_mood_override = arg.substr(7)
	if OS.get_environment("LT_CAPTURE") != "":
		auto = true
		var env_dir := OS.get_environment("LT_CAPTURE_DIR")
		if env_dir != "":
			capture_dir = env_dir

	if auto:
		if _nebula_sheet:
			_capture_queue = []
			for mood in SkyComposition.MOODS:
				_capture_queue.append({"scenario": "nebula", "mood": mood, "tag": "nebula_%s" % mood})
			var first: Dictionary = _capture_queue.pop_front()
			_apply_capture_item(first)
			_capturing = true
		else:
			_capture_queue = range(SCENARIOS.size())
			scenario_i = int(_capture_queue.pop_front())
			_capturing = true
			_apply_scenario()
	else:
		_apply_scenario()


func _apply_capture_item(item: Dictionary) -> void:
	_mood_override = str(item.get("mood", ""))
	_capture_tag = str(item.get("tag", ""))
	var sid := str(item.get("scenario", "nebula"))
	for i in SCENARIOS.size():
		if SCENARIOS[i]["id"] == sid:
			scenario_i = i
			break
	_apply_scenario()


func _apply_scenario() -> void:
	var sc: Dictionary = SCENARIOS[scenario_i]
	if presenter != null:
		presenter.queue_free()
		presenter = null
	sim = StarSystemSim.new()
	sim.generate(int(sc["seed"]), ship_count)
	if _mood_override != "":
		sim.world["mood_override"] = _mood_override
		# Nudge system hint toward the forced mood so volumes/sky agree.
		match _mood_override:
			"amber_gold":
				sim.world["nebula_color"] = Color.from_hsv(0.10, 0.62, 0.42)
			"cyan_teal":
				sim.world["nebula_color"] = Color.from_hsv(0.55, 0.55, 0.40)
			"magenta_rose":
				sim.world["nebula_color"] = Color.from_hsv(0.90, 0.62, 0.44)
			"crimson":
				sim.world["nebula_color"] = Color.from_hsv(0.02, 0.65, 0.40)
			"cold_white":
				sim.world["nebula_color"] = Color.from_hsv(0.60, 0.18, 0.42)
			_:
				sim.world["nebula_color"] = Color.from_hsv(0.72, 0.52, 0.40)
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
		"planet":
			# Frame lit hemisphere: camera on the sunward / terminator side.
			var pfocus := presenter.get_planet_focus()
			var star_p: Vector3 = sim.world["star"].get("position", Vector3(200, 80, 100))
			var to_star := (star_p - pfocus).normalized()
			# Slight offset off the sun vector so terrain + terminator both read.
			var view_dir := (to_star + Vector3(0.45, 0.12, 0.28)).normalized()
			focus = pfocus
			distance = float(sc["dist"])
			yaw = atan2(view_dir.x, view_dir.z)
			pitch = clampf(asin(clampf(view_dir.y, -1.0, 1.0)), -0.75, 0.45)
		_:
			# Aim into the primary nebula mass lobe on the IFS sky.
			var sky_dir := SkyComposition.primary_mass_dir(presenter.sky_comp)
			focus = Vector3.ZERO
			distance = float(sc["dist"])
			if str(sc["id"]) == "nebula":
				yaw = atan2(-sky_dir.x, -sky_dir.z) + 0.15
			elif sc["yaw"] == null:
				yaw = atan2(-sky_dir.x, -sky_dir.z) + 0.2
			else:
				yaw = float(sc["yaw"])
	# Preserve custom pitch for nebula / planet framing
	if str(sc["id"]) == "nebula":
		pitch = clampf(float(sc["pitch"]) - 0.05, -1.2, 1.2)
	elif str(sc["id"]) != "planet":
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
	if _frames == 10:
		_hide_hud_for_capture = true
		if label:
			label.visible = false
	elif _frames == 14:
		_write_capture()
		if not _capture_queue.is_empty():
			var nxt = _capture_queue.pop_front()
			if typeof(nxt) == TYPE_DICTIONARY:
				_apply_capture_item(nxt)
			else:
				_mood_override = ""
				_capture_tag = ""
				scenario_i = int(nxt)
				_apply_scenario()
		else:
			var done_msg := "LT_COMPARE_CAPTURE_DONE dir=%s" % _capture_path
			if _nebula_sheet:
				done_msg = "LT_NEBULA_SHEET_DONE dir=%s" % _capture_path
			print(done_msg)
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
	var stem := _capture_tag if _capture_tag != "" else str(sc["id"])
	var path := "%s/ew_%s.png" % [_capture_path, stem]
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Captured ", path, " mood=", str(presenter.sky_comp.get("mood", "?")) if presenter else "?")


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
