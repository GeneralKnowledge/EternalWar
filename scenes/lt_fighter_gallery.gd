## Diagnostic gallery for the canonical Limit Theory–style patrol fighter.
## Modes: silhouette | clay | material | lit | compare | ortho
## Keys: 1-6 mode, V view, O ortho cycle, C capture, A capture all, Q/E seed family, Esc menu
extends Node3D

const CANONICAL_SEED := 42
const CANONICAL_ID := "LT_FIGHTER_REFERENCE"

const MODES := ["silhouette", "clay", "material", "lit", "compare", "ortho"]
const VIEWS := [
	"three_quarter_front", "three_quarter_rear",
	"front", "rear", "left", "right", "top", "bottom",
]
const ORTHO_VIEWS := ["front", "side", "top", "rear"]

@export var capture_dir: String = "user://fighter_gallery"

var camera: Camera3D
var light: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D
var env_node: WorldEnvironment
var ship_mi: MeshInstance3D
var label: Label
var mode_i: int = 3
var view_i: int = 0
var ortho_i: int = 0
var seed_offset: int = 0
var _frames: int = 0
var _capture_queue: Array = []
var _capturing: bool = false
var _capture_path: String = ""
var _family_mode: bool = false
var _family_index: int = 0


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 200.0
	camera.near = 0.05
	camera.fov = 38.0
	add_child(camera)
	camera.current = true

	light = DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.96, 0.9)
	light.light_energy = 1.4
	light.shadow_enabled = true
	light.transform = Transform3D(Basis.looking_at(Vector3(-0.5, -0.6, -0.35), Vector3.UP), Vector3.ZERO)
	add_child(light)

	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.62, 0.85)
	fill.light_energy = 0.32
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.65, 0.15, 0.55), Vector3.UP), Vector3.ZERO)
	add_child(fill)

	rim = DirectionalLight3D.new()
	rim.light_color = Color(0.75, 0.8, 1.0)
	rim.light_energy = 0.25
	rim.transform = Transform3D(Basis.looking_at(Vector3(0.2, 0.1, 0.9), Vector3.UP), Vector3.ZERO)
	add_child(rim)

	env_node = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.14, 0.18)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_bloom = 0.1
	e.set_glow_level(3, 1.0)
	e.set_glow_level(4, 0.65)
	env_node.environment = e
	add_child(env_node)

	ship_mi = MeshInstance3D.new()
	add_child(ship_mi)

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
		elif arg.begins_with("--mode="):
			var mid := arg.substr(7)
			for i in MODES.size():
				if MODES[i] == mid:
					mode_i = i
		elif arg.begins_with("--view="):
			var vid := arg.substr(7)
			for i in VIEWS.size():
				if VIEWS[i] == vid:
					view_i = i
		elif arg == "--family":
			_family_mode = true
		elif arg == "--silhouette":
			mode_i = 0

	if auto:
		if _family_mode:
			_capture_queue = []
			for s in 20:
				_capture_queue.append({"seed_off": s, "mode": "material", "view": "three_quarter_front"})
		else:
			_capture_queue = _default_capture_plan()
		_apply_queue_item(_capture_queue.pop_front())
		_capturing = true
	_rebuild()


func _default_capture_plan() -> Array:
	var plan: Array = []
	for mode in ["silhouette", "clay", "material", "lit"]:
		plan.append({"seed_off": 0, "mode": mode, "view": "three_quarter_front"})
	for v in VIEWS:
		plan.append({"seed_off": 0, "mode": "lit", "view": v})
	for ov in ORTHO_VIEWS:
		plan.append({"seed_off": 0, "mode": "ortho", "view": ov})
	plan.append({"seed_off": 0, "mode": "compare", "view": "three_quarter_front"})
	return plan


func _apply_queue_item(item: Variant) -> void:
	if typeof(item) != TYPE_DICTIONARY:
		return
	var d: Dictionary = item
	seed_offset = int(d.get("seed_off", 0))
	var m := str(d.get("mode", "lit"))
	for i in MODES.size():
		if MODES[i] == m:
			mode_i = i
	var v := str(d.get("view", "three_quarter_front"))
	if m == "ortho":
		for i in ORTHO_VIEWS.size():
			if ORTHO_VIEWS[i] == v:
				ortho_i = i
	else:
		for i in VIEWS.size():
			if VIEWS[i] == v:
				view_i = i


func _rebuild() -> void:
	MeshCache.clear()
	var design := _canonical_design()
	var mesh := ShipMeshGen.build(design, VisualLOD.LOD_FULL)
	ship_mi.mesh = mesh
	_apply_mode(design)
	_apply_view(design)
	_frames = 0
	_refresh_label(design)


func _canonical_design() -> Dictionary:
	var seed := CANONICAL_SEED + seed_offset * 17
	return {
		"seed": seed,
		"ship_class": SimEntities.ShipClass.PATROL,
		"style": "military",
		"color": Color(0.42, 0.45, 0.5),
		"accent": Color(0.5, 0.28, 0.24),
		"id": CANONICAL_ID,
	}


func _apply_mode(design: Dictionary) -> void:
	var mode := str(MODES[mode_i])
	var profile := StyleProfile.of("military")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 38.0
	match mode:
		"silhouette":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.02, 0.02, 0.02)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ship_mi.material_override = mat
			env_node.environment.background_color = Color(0.9, 0.9, 0.92)
			env_node.environment.ambient_light_energy = 0.0
			env_node.environment.glow_enabled = false
			light.light_energy = 0.0
			fill.light_energy = 0.0
			rim.light_energy = 0.0
		"clay":
			var clay := StandardMaterial3D.new()
			clay.albedo_color = Color(0.72, 0.7, 0.68)
			clay.roughness = 0.85
			clay.metallic = 0.0
			ship_mi.material_override = clay
			env_node.environment.background_color = Color(0.18, 0.19, 0.21)
			env_node.environment.ambient_light_energy = 0.55
			env_node.environment.glow_enabled = false
			light.light_energy = 1.2
			fill.light_energy = 0.4
			rim.light_energy = 0.2
		"material":
			var mat := VisualMaterials.make(str(profile["material"]), design["color"], 0.55)
			mat.roughness = float(profile.get("roughness", 0.5))
			mat.metallic = float(profile.get("metallic", 0.4))
			ship_mi.material_override = mat
			env_node.environment.background_color = Color(0.04, 0.045, 0.06)
			env_node.environment.ambient_light_energy = 0.4
			env_node.environment.glow_enabled = false
			light.light_energy = 1.25
			fill.light_energy = 0.3
			rim.light_energy = 0.15
		"compare":
			# Matched composition: dark matte + rim for LT still comparison
			var mat := VisualMaterials.make("metal_dark", design["color"], 0.5)
			mat.roughness = 0.55
			mat.metallic = 0.45
			ship_mi.material_override = mat
			env_node.environment.background_color = Color(0.015, 0.02, 0.035)
			env_node.environment.ambient_light_energy = 0.35
			env_node.environment.glow_enabled = true
			light.light_energy = 1.35
			fill.light_energy = 0.28
			rim.light_energy = 0.35
			camera.fov = 36.0
		"ortho":
			var clay := StandardMaterial3D.new()
			clay.albedo_color = Color(0.7, 0.7, 0.7)
			clay.roughness = 0.9
			ship_mi.material_override = clay
			env_node.environment.background_color = Color(0.22, 0.22, 0.24)
			env_node.environment.ambient_light_energy = 0.7
			env_node.environment.glow_enabled = false
			light.light_energy = 0.9
			fill.light_energy = 0.5
			rim.light_energy = 0.0
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_:
			# lit
			var mat := VisualMaterials.make(str(profile["material"]), design["color"], 0.55)
			mat.roughness = float(profile.get("roughness", 0.5))
			mat.metallic = float(profile.get("metallic", 0.4))
			ship_mi.material_override = mat
			env_node.environment.background_color = Color(0.02, 0.025, 0.04)
			env_node.environment.ambient_light_energy = 0.45
			env_node.environment.glow_enabled = true
			light.light_energy = 1.4
			fill.light_energy = 0.32
			rim.light_energy = 0.25


func _apply_view(design: Dictionary) -> void:
	var length := float(ShipDesign.build(design)["length"])
	var dist := length * 2.9 + 2.4
	var mode := str(MODES[mode_i])
	var view := str(ORTHO_VIEWS[ortho_i]) if mode == "ortho" else str(VIEWS[view_i])
	var pos := Vector3.ZERO
	match view:
		"front":
			pos = Vector3(0, length * 0.08, -dist)
		"rear":
			pos = Vector3(0, length * 0.08, dist)
		"left":
			pos = Vector3(-dist, length * 0.08, 0)
		"right", "side":
			pos = Vector3(dist, length * 0.08, 0)
		"top":
			pos = Vector3(0.01, dist, 0.01)
		"bottom":
			pos = Vector3(0.01, -dist, 0.01)
		"three_quarter_rear":
			pos = Vector3(dist * 0.6, dist * 0.32, -dist * 0.65)
		_:
			pos = Vector3(dist * 0.62, dist * 0.34, dist * 0.68)
	if mode == "ortho":
		camera.size = length * 2.2
	camera.global_position = pos
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)


func _process(_dt: float) -> void:
	_frames += 1
	if not _capturing:
		return
	if _frames == 6 and label:
		label.visible = false
	elif _frames == 8:
		_write_capture()
		if not _capture_queue.is_empty():
			_apply_queue_item(_capture_queue.pop_front())
			_rebuild()
		else:
			print("FIGHTER_GALLERY_CAPTURE_DONE dir=", _capture_path)
			_capturing = false
			if label:
				label.visible = true
			get_tree().quit()


func _write_capture() -> void:
	var dir := capture_dir
	if dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		_capture_path = ProjectSettings.globalize_path(dir)
	else:
		DirAccess.make_dir_recursive_absolute(dir)
		_capture_path = dir
	var mode := str(MODES[mode_i])
	var view := str(ORTHO_VIEWS[ortho_i]) if mode == "ortho" else str(VIEWS[view_i])
	var seed := CANONICAL_SEED + seed_offset * 17
	var path := "%s/ew_fighter_s%d_%s_%s.png" % [_capture_path, seed, mode, view]
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Captured ", path)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				mode_i = event.keycode - KEY_1
				_rebuild()
			KEY_V:
				if str(MODES[mode_i]) == "ortho":
					ortho_i = (ortho_i + 1) % ORTHO_VIEWS.size()
				else:
					view_i = (view_i + 1) % VIEWS.size()
				_rebuild()
			KEY_O:
				mode_i = 5
				ortho_i = (ortho_i + 1) % ORTHO_VIEWS.size()
				_rebuild()
			KEY_Q:
				seed_offset = maxi(seed_offset - 1, 0)
				_rebuild()
			KEY_E:
				seed_offset += 1
				_rebuild()
			KEY_C:
				_capture_queue = [{"seed_off": seed_offset, "mode": MODES[mode_i], "view": VIEWS[view_i]}]
				_capturing = true
				_frames = 0
			KEY_A:
				_capture_queue = _default_capture_plan()
				_apply_queue_item(_capture_queue.pop_front())
				_capturing = true
				_rebuild()
			KEY_F:
				# 20-seed family board
				_capture_queue = []
				for s in 20:
					_capture_queue.append({"seed_off": s, "mode": "material", "view": "three_quarter_front"})
				_apply_queue_item(_capture_queue.pop_front())
				_capturing = true
				_rebuild()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main.tscn")


func _refresh_label(design: Dictionary) -> void:
	var desc := ShipMeshGen.describe(design)
	var mode := str(MODES[mode_i])
	var view := str(ORTHO_VIEWS[ortho_i]) if mode == "ortho" else str(VIEWS[view_i])
	label.visible = true
	label.text = "\n".join(PackedStringArray([
		"%s  seed=%d  mode=%s  view=%s" % [CANONICAL_ID, int(design["seed"]), mode, view],
		"hull=%s stations=%d  LWH=%.2f/%.2f/%.2f  gap=%.2f" % [
			str(desc.get("hull_language", "?")),
			int(desc.get("stations", 0)),
			float(desc["length"]), float(desc["width"]), float(desc["height"]),
			float(desc.get("negative_space", 0)),
		],
		"1-6 mode  V view  O ortho  Q/E seed  C/A/F capture  Esc",
	]))
