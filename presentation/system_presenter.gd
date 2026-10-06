## Presentation layer: procedural starfield, stars, planets, asteroids, stations, ships.
## Reads simulation dictionaries — never owns world state.
class_name SystemPresenter
extends Node3D

var sim: StarSystemSim
var _ship_mm: Dictionary = {} # ship_class -> MultiMeshInstance3D
var _ship_index_map: Array = [] # per ship: {mm_key, local_index}
var _station_nodes: Dictionary = {}
var _planet_nodes: Dictionary = {}
var _yield_nodes: Dictionary = {}
var _built := false
var _camera: Camera3D
var _inspect_target: Dictionary = {}

const LOD_NEAR := 450.0
const LOD_MID := 1400.0


func setup(p_sim: StarSystemSim, camera: Camera3D = null) -> void:
	sim = p_sim
	_camera = camera
	MeshCache.clear()
	_clear_visuals()
	_build_environment()
	_build_star()
	_build_planets()
	_build_yields()
	_build_stations()
	_build_ships()
	_built = true


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func get_inspect_target() -> Dictionary:
	return _inspect_target


func _clear_visuals() -> void:
	for c in get_children():
		c.queue_free()
	_station_nodes.clear()
	_planet_nodes.clear()
	_yield_nodes.clear()
	_ship_mm.clear()
	_ship_index_map.clear()
	_built = false


func _build_environment() -> void:
	var star: Dictionary = sim.world["star"]
	var light := DirectionalLight3D.new()
	light.light_color = star["color"]
	light.light_energy = float(star.get("luminosity", 1.2))
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-35, 40, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	var nebula: Color = sim.world.get("nebula_color", Color(0.02, 0.03, 0.05))
	# Keep space mostly dark; nebula is a subtle tint, not a flat wash.
	e.background_color = Color(nebula.r * 0.15, nebula.g * 0.15, nebula.b * 0.2).darkened(0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.06, 0.07, 0.1).lerp(nebula, 0.25)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.35
	e.fog_enabled = true
	e.fog_light_color = nebula.darkened(0.2)
	e.fog_density = 0.00004
	env.environment = e
	add_child(env)

	var stars := MultiMeshInstance3D.new()
	stars.multimesh = StarfieldGen.build_multimesh(sim.seed_value, 3200)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	stars.material_override = mat
	add_child(stars)


func _build_star() -> void:
	var star: Dictionary = sim.world["star"]
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = float(star["radius"])
	sphere.height = float(star["radius"]) * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mi.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/star.gdshader")
	mat.set_shader_parameter("star_color", star["color"])
	mat.set_shader_parameter("emission_energy", 2.5 + float(star.get("luminosity", 1.0)) * 1.5)
	mat.set_shader_parameter("corona", 0.4)
	mi.material_override = mat
	mi.position = star["position"]
	add_child(mi)

	var corona := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = float(star["radius"]) * 1.15
	cs.height = cs.radius * 2.0
	cs.radial_segments = 24
	cs.rings = 12
	corona.mesh = cs
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(star["color"].r, star["color"].g, star["color"].b, 0.15)
	cm.emission_enabled = true
	cm.emission = star["color"]
	cm.emission_energy_multiplier = 1.2
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	corona.material_override = cm
	corona.position = star["position"]
	add_child(corona)


func _build_planets() -> void:
	var planet_shader: Shader = load("res://shaders/planet.gdshader")
	for p in sim.world["planets"]:
		var root := Node3D.new()
		root.position = p["position"]
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = float(p["radius"])
		sphere.height = float(p["radius"]) * 2.0
		sphere.radial_segments = 36
		sphere.rings = 18
		mi.mesh = sphere
		var mat := ShaderMaterial.new()
		mat.shader = planet_shader
		mat.set_shader_parameter("color_a", p["color"])
		mat.set_shader_parameter("color_b", p.get("color_b", p["color"]))
		mat.set_shader_parameter("color_c", p.get("color_c", p["color"]))
		mat.set_shader_parameter("color_d", p.get("color_d", Color(0.9, 0.9, 0.95)))
		mat.set_shader_parameter("ocean_level", float(p.get("ocean_level", 0.3)))
		mat.set_shader_parameter("cloud_level", float(p.get("cloud_level", 0.1)))
		mat.set_shader_parameter("roughness_val", 0.88)
		mat.set_shader_parameter("seed_offset", float(int(p.get("seed", 1)) % 1000) * 0.01)
		mat.set_shader_parameter("atmosphere_tint", float(p.get("atmosphere", 0.3)))
		mi.material_override = mat
		root.add_child(mi)

		if float(p.get("atmosphere", 0.0)) > 0.1:
			var atmo := MeshInstance3D.new()
			var asphere := SphereMesh.new()
			asphere.radius = float(p["radius"]) * 1.06
			asphere.height = asphere.radius * 2.0
			asphere.radial_segments = 24
			asphere.rings = 12
			atmo.mesh = asphere
			var am := StandardMaterial3D.new()
			var ac: Color = p["color"]
			am.albedo_color = Color(ac.r * 0.5 + 0.2, ac.g * 0.5 + 0.25, ac.b * 0.6 + 0.4, 0.12)
			am.emission_enabled = true
			am.emission = am.albedo_color
			am.emission_energy_multiplier = 0.4
			am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			am.cull_mode = BaseMaterial3D.CULL_DISABLED
			am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			atmo.material_override = am
			root.add_child(atmo)

		if bool(p.get("has_rings", false)):
			_add_rings(root, float(p["radius"]), p.get("ring_color", Color(0.7, 0.65, 0.5, 0.45)), int(p.get("seed", 1)))

		add_child(root)
		_planet_nodes[p["id"]] = root


func _add_rings(parent: Node3D, planet_radius: float, color: Color, seed: int) -> void:
	var rng := SeededRNG.new(SeedHash.derive(seed, "rings"))
	var mm_i := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 0.15, 1.2)
	mm.mesh = box
	var count := 180
	mm.instance_count = count
	var inner := planet_radius * 1.35
	var outer := planet_radius * 2.1
	for i in count:
		var a := float(i) / float(count) * TAU + rng.randf() * 0.02
		var r := lerpf(inner, outer, rng.randf())
		var pos := Vector3(cos(a) * r, rng.randf_range(-1.5, 1.5), sin(a) * r)
		var basis := Basis.from_euler(Vector3(0, -a, 0))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var c := color
		c.a = rng.randf_range(0.25, 0.7)
		mm.set_instance_color(i, c)
	mm_i.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mm_i.material_override = mat
	parent.add_child(mm_i)


func _build_yields() -> void:
	for y in sim.world["yields"]:
		var root := Node3D.new()
		root.position = y["position"]
		var count: int = int(y.get("asteroid_count", 24))
		var spread: float = float(y.get("spread", 90.0))
		var mm_i := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = AsteroidMeshGen.build(int(y.get("seed", 1)), 1)
		mm.instance_count = count
		var rng := SeededRNG.new(SeedHash.derive(int(y.get("seed", 1)), "field"))
		var base_col: Color = y.get("color", Color(0.5, 0.42, 0.32))
		for i in count:
			var p: Vector3 = rng.dir3() * rng.randf_range(spread * 0.15, spread)
			p.y *= 0.45
			var s := rng.randf_range(4.0, 14.0) * (0.6 + float(y.get("richness", 1.0)) * 0.4)
			var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * s), p))
			mm.set_instance_color(i, base_col.lightened(rng.randf_range(-0.1, 0.15)))
		mm_i.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.95
		mm_i.material_override = mat
		root.add_child(mm_i)
		add_child(root)
		_yield_nodes[y["id"]] = root


func _build_stations() -> void:
	for st in sim.world["stations"]:
		var root := Node3D.new()
		root.position = st["position"]
		var mi := MeshInstance3D.new()
		var design := {
			"seed": int(st.get("seed", st["id"])),
			"role": str(st.get("role", "trade")),
			"style": str(st.get("style", "industrial")),
			"color": st.get("color", Color(0.55, 0.6, 0.65)),
		}
		mi.mesh = StationMeshGen.build(design)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.metallic = 0.45
		mat.roughness = 0.5
		mi.material_override = mat
		mi.scale = Vector3.ONE * 14.0
		root.add_child(mi)
		add_child(root)
		_station_nodes[st["id"]] = root


func _build_ships() -> void:
	# One MultiMesh per ship class for silhouette variety.
	var buckets: Dictionary = {}
	for sc in [SimEntities.ShipClass.MINER, SimEntities.ShipClass.TRADER, SimEntities.ShipClass.HAULER, SimEntities.ShipClass.PATROL]:
		buckets[sc] = []

	_ship_index_map.clear()
	_ship_index_map.resize(sim.world["ships"].size())
	for i in sim.world["ships"].size():
		var s: Dictionary = sim.world["ships"][i]
		var sc: int = int(s["ship_class"])
		if not buckets.has(sc):
			sc = SimEntities.ShipClass.TRADER
		var local_i: int = buckets[sc].size()
		buckets[sc].append(s)
		_ship_index_map[i] = {"class": sc, "local": local_i}

	var styles := ["mining", "civilian", "civilian", "military"]
	for sc in buckets.keys():
		var list: Array = buckets[sc]
		if list.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var design := {
			"seed": 50 + int(sc) * 17,
			"ship_class": int(sc),
			"style": styles[int(sc) % styles.size()],
			"color": Color(0.75, 0.78, 0.85),
			"accent": Color(0.45, 0.48, 0.55),
		}
		mm.mesh = ShipMeshGen.build(design)
		mm.instance_count = list.size()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.45
		mat.metallic = 0.35
		mmi.material_override = mat
		add_child(mmi)
		_ship_mm[sc] = mmi

	sync_ships()


func sync_ships() -> void:
	if sim == null or _ship_mm.is_empty():
		return
	var ships: Array = sim.world["ships"]
	var cam_pos := Vector3.ZERO
	if _camera != null:
		cam_pos = _camera.global_position

	var nearest_dist := INF
	var nearest: Dictionary = {}

	for i in ships.size():
		var s: Dictionary = ships[i]
		var meta: Dictionary = _ship_index_map[i]
		var sc: int = int(meta["class"])
		var local_i: int = int(meta["local"])
		if not _ship_mm.has(sc):
			continue
		var mm: MultiMesh = _ship_mm[sc].multimesh
		var pos: Vector3 = s["position"]
		var dist := cam_pos.distance_to(pos) if _camera != null else 800.0
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = s

		if int(s.get("docked_station_id", -1)) >= 0 and not s.get("is_player", false):
			mm.set_instance_transform(local_i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), pos))
			continue

		var heading: Vector3 = s["heading"]
		if heading.length_squared() < 0.001:
			heading = Vector3(0, 0, -1)
		var basis := Basis.looking_at(heading.normalized(), Vector3.UP)
		var scale := 5.5
		match int(s["ship_class"]):
			SimEntities.ShipClass.HAULER:
				scale = 8.5
			SimEntities.ShipClass.PATROL:
				scale = 4.5
			SimEntities.ShipClass.MINER:
				scale = 6.5
		if s.get("is_player", false):
			scale = 7.5
		if dist > LOD_MID:
			scale *= 0.85
		elif dist < LOD_NEAR:
			scale *= 1.08
		mm.set_instance_transform(local_i, Transform3D(basis.scaled(Vector3.ONE * scale), pos))
		var design: Dictionary = s.get("design", {})
		var col: Color = design.get("color", Color(0.7, 0.75, 0.85))
		if s.get("is_player", false):
			col = Color(1.0, 0.95, 0.55)
		mm.set_instance_color(local_i, col)

	_inspect_target = nearest


func _process(_dt: float) -> void:
	if _built:
		sync_ships()
