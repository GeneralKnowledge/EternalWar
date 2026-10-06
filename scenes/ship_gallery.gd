## Deterministic Limit Theory ship comparison gallery.
## Roles: PATROL TRADER MINER HAULER + style variants MILITARY PIRATE LUXURY INDUSTRIAL
## Views: 3/4, front, side, rear, top, silhouette
## Keys 1-8 roles, Q/E seed, V view, S silhouette, C capture, A capture all
extends Node3D

const ROLES := [
	{"id": "patrol", "class": SimEntities.ShipClass.PATROL, "style": "military", "seed": 42},
	{"id": "trader", "class": SimEntities.ShipClass.TRADER, "style": "civilian", "seed": 42},
	{"id": "miner", "class": SimEntities.ShipClass.MINER, "style": "mining", "seed": 42},
	{"id": "hauler", "class": SimEntities.ShipClass.HAULER, "style": "industrial", "seed": 42},
	{"id": "military", "class": SimEntities.ShipClass.PATROL, "style": "military", "seed": 77},
	{"id": "pirate", "class": SimEntities.ShipClass.TRADER, "style": "pirate", "seed": 88},
	{"id": "luxury", "class": SimEntities.ShipClass.TRADER, "style": "luxury", "seed": 55},
	{"id": "industrial", "class": SimEntities.ShipClass.HAULER, "style": "industrial", "seed": 66},
]

const VIEWS := ["three_quarter", "front", "side", "rear", "top"]

@export var capture_dir: String = "user://ship_gallery"

var camera: Camera3D
var light: DirectionalLight3D
var fill: DirectionalLight3D
var env_node: WorldEnvironment
var ship_mi: MeshInstance3D
var label: Label
var role_i: int = 0
var seed_offset: int = 0
var view_i: int = 0
var silhouette: bool = false
var _frames: int = 0
var _capture_queue: Array = []
var _capturing: bool = false
var _capture_path: String = ""


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 200.0
	camera.near = 0.05
	camera.fov = 40.0
	add_child(camera)
	camera.current = true

	light = DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.35
	light.transform = Transform3D(Basis.looking_at(Vector3(-0.45, -0.55, -0.35), Vector3.UP), Vector3.ZERO)
	add_child(light)

	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.65, 0.85)
	fill.light_energy = 0.35
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.6, 0.2, 0.5), Vector3.UP), Vector3.ZERO)
	add_child(fill)

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
	e.glow_intensity = 0.45
	e.glow_bloom = 0.12
	e.set_glow_level(3, 1.0)
	e.set_glow_level(4, 0.7)
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
		elif arg.begins_with("--role="):
			var id := arg.substr(7)
			for i in ROLES.size():
				if ROLES[i]["id"] == id:
					role_i = i
		elif arg == "--silhouette":
			silhouette = true

	if auto:
		_capture_queue = range(ROLES.size())
		role_i = int(_capture_queue.pop_front())
		_capturing = true
	_rebuild()


func _rebuild() -> void:
	MeshCache.clear()
	var role: Dictionary = ROLES[role_i]
	var seed := int(role["seed"]) + seed_offset * 17
	var design := {
		"seed": seed,
		"ship_class": int(role["class"]),
		"style": str(role["style"]),
		"color": _role_color(str(role["style"])),
		"accent": _role_accent(str(role["style"])),
	}
	var mesh := ShipMeshGen.build(design, VisualLOD.LOD_FULL)
	ship_mi.mesh = mesh
	var profile := StyleProfile.of(str(role["style"]))
	var mat := VisualMaterials.make(str(profile["material"]), design["color"], 0.55)
	mat.roughness = float(profile.get("roughness", 0.5))
	mat.metallic = float(profile.get("metallic", 0.4))
	if silhouette:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.02, 0.02, 0.02)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		env_node.environment.background_color = Color(0.92, 0.92, 0.94)
		env_node.environment.ambient_light_energy = 0.0
		light.light_energy = 0.0
		fill.light_energy = 0.0
	else:
		env_node.environment.background_color = Color(0.02, 0.025, 0.04)
		env_node.environment.ambient_light_energy = 0.45
		light.light_energy = 1.35
		fill.light_energy = 0.35
	ship_mi.material_override = mat
	_apply_view(design)
	_frames = 0
	_refresh_label(design)


func _role_color(style: String) -> Color:
	match style:
		"military":
			return Color(0.42, 0.45, 0.5)
		"mining", "industrial":
			return Color(0.55, 0.42, 0.28)
		"pirate":
			return Color(0.38, 0.28, 0.28)
		"luxury":
			return Color(0.7, 0.7, 0.72)
		_:
			return Color(0.5, 0.52, 0.48)


func _role_accent(style: String) -> Color:
	match style:
		"military":
			return Color(0.55, 0.25, 0.22)
		"mining", "industrial":
			return Color(0.45, 0.32, 0.18)
		"pirate":
			return Color(0.5, 0.35, 0.2)
		"luxury":
			return Color(0.55, 0.6, 0.7)
		_:
			return Color(0.35, 0.4, 0.32)


func _apply_view(design: Dictionary) -> void:
	var length := float(ShipDesign.build(design)["length"])
	var dist := length * 2.8 + 2.5
	var view := str(VIEWS[view_i])
	var pos := Vector3.ZERO
	match view:
		"front":
			pos = Vector3(0, length * 0.1, -dist)
		"side":
			pos = Vector3(dist, length * 0.1, 0)
		"rear":
			pos = Vector3(0, length * 0.1, dist)
		"top":
			pos = Vector3(0.01, dist, 0.01)
		_:
			pos = Vector3(dist * 0.65, dist * 0.35, dist * 0.7)
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
			role_i = int(_capture_queue.pop_front())
			_rebuild()
		else:
			print("SHIP_GALLERY_CAPTURE_DONE dir=", _capture_path)
			_capturing = false
			if label:
				label.visible = true
			get_tree().quit()


func _write_capture() -> void:
	var role: Dictionary = ROLES[role_i]
	var dir := capture_dir
	if dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		_capture_path = ProjectSettings.globalize_path(dir)
	else:
		DirAccess.make_dir_recursive_absolute(dir)
		_capture_path = dir
	var tag := "sil" if silhouette else str(VIEWS[view_i])
	var path := "%s/ew_ship_%s_s%d_%s.png" % [_capture_path, str(role["id"]), int(role["seed"]) + seed_offset * 17, tag]
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Captured ", path)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				role_i = event.keycode - KEY_1
				_rebuild()
			KEY_Q:
				seed_offset = maxi(seed_offset - 1, 0)
				_rebuild()
			KEY_E:
				seed_offset += 1
				_rebuild()
			KEY_V:
				view_i = (view_i + 1) % VIEWS.size()
				_rebuild()
			KEY_S:
				silhouette = not silhouette
				_rebuild()
			KEY_C:
				_capture_queue = [role_i]
				_capturing = true
				_frames = 0
			KEY_A:
				_capture_queue = range(ROLES.size())
				role_i = int(_capture_queue.pop_front())
				_capturing = true
				_rebuild()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main.tscn")


func _refresh_label(design: Dictionary) -> void:
	var role: Dictionary = ROLES[role_i]
	var desc := ShipMeshGen.describe(design)
	label.visible = true
	label.text = "\n".join(PackedStringArray([
		"SHIP GALLERY  |  %s  style=%s  seed=%d" % [str(role["id"]), str(role["style"]), int(design["seed"])],
		"hull=%s  LWH=%.1f/%.1f/%.1f  gap=%.2f  exhaust=%s  view=%s%s" % [
			str(desc.get("hull_language", "?")),
			float(desc["length"]), float(desc["width"]), float(desc["height"]),
			float(desc.get("negative_space", 0)),
			str(StyleProfile.of(str(role["style"])).get("exhaust_family", "?")),
			str(VIEWS[view_i]),
			"  SILHOUETTE" if silhouette else "",
		],
		"modules=%s  1-8 roles  Q/E seed  V view  S silhouette  C/A capture" % str(desc.get("module_types", [])),
	]))
