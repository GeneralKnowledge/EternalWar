## Headless capture: ShapeLib ships at FULL + BATCH for key roles.
extends SceneTree

const OUT := "/opt/cursor/artifacts/screenshots"
const ROLES := [
	{"id": "patrol", "class": SimEntities.ShipClass.PATROL, "style": "military", "seed": 42},
	{"id": "miner", "class": SimEntities.ShipClass.MINER, "style": "mining", "seed": 42},
	{"id": "hauler", "class": SimEntities.ShipClass.HAULER, "style": "industrial", "seed": 42},
	{"id": "trader", "class": SimEntities.ShipClass.TRADER, "style": "civilian", "seed": 42},
]

var _vp: SubViewport
var _cam: Camera3D
var _mi: MeshInstance3D
var _queue: Array = []
var _frames := 0
var _current: Dictionary = {}
var _ready := false


func _initialize() -> void:
	print("CAPTURE_SHIP_LOD_BEGIN")
	DirAccess.make_dir_recursive_absolute(OUT)

	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 540)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 40.0
	_cam.far = 200.0
	_cam.near = 0.05
	world.add_child(_cam)

	var light := DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.85
	light.transform = Transform3D(Basis.looking_at(Vector3(-0.45, -0.55, -0.35), Vector3.UP), Vector3.ZERO)
	world.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.65, 0.85)
	fill.light_energy = 0.55
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.6, 0.2, 0.5), Vector3.UP), Vector3.ZERO)
	world.add_child(fill)

	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.14, 0.18)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = e
	world.add_child(env_node)

	_mi = MeshInstance3D.new()
	world.add_child(_mi)

	for role in ROLES:
		_queue.append({"role": role, "lod": VisualLOD.LOD_FULL, "tag": "full"})
		_queue.append({"role": role, "lod": VisualLOD.LOD_BATCH, "tag": "batch"})
	_advance()
	_ready = true


func _advance() -> void:
	if _queue.is_empty():
		print("CAPTURE_SHIP_LOD_DONE")
		quit()
		return
	_current = _queue.pop_front()
	var role: Dictionary = _current["role"]
	var lod: int = int(_current["lod"])
	MeshCache.clear()
	var design := {
		"seed": int(role["seed"]),
		"ship_class": int(role["class"]),
		"style": str(role["style"]),
		"color": Color(0.45, 0.46, 0.48),
		"accent": Color(0.5, 0.3, 0.25),
	}
	match str(role["style"]):
		"mining", "industrial":
			design["color"] = Color(0.55, 0.42, 0.28)
			design["accent"] = Color(0.45, 0.32, 0.18)
		"civilian":
			design["color"] = Color(0.5, 0.52, 0.48)
			design["accent"] = Color(0.35, 0.4, 0.32)
	var mesh := ShipMeshGen.build(design, lod)
	_mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = design["color"]
	mat.roughness = 0.55
	mat.metallic = 0.35
	_mi.material_override = mat
	var length := float(ShipDesign.build(design)["length"])
	var dist := length * 2.8 + 2.5
	var pos := Vector3(dist * 0.65, dist * 0.35, dist * 0.7)
	_cam.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
	_frames = 0
	print("CAPTURE role=", role["id"], " lod=", _current["tag"], " surfaces=", mesh.get_surface_count())


func _process(_dt: float) -> bool:
	if not _ready:
		return false
	_frames += 1
	if _frames < 8:
		return false
	if _current.is_empty():
		return false
	var role: Dictionary = _current["role"]
	var tag: String = str(_current["tag"])
	var path := "%s/ew_ship_%s_%s_uniform.png" % [OUT, str(role["id"]), tag]
	var tex := _vp.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img.save_png(path)
			print("WROTE ", path)
		else:
			print("WARN empty image for ", path)
	else:
		print("WARN empty texture for ", path)
	_current = {}
	_advance()
	return false
