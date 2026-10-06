## Presentation layer: procedural sky, bodies, fields, stations, LOD ships.
## Reads simulation dictionaries — never owns world state.
class_name SystemPresenter
extends Node3D

var sim: StarSystemSim
var _ship_mm: Dictionary = {} # ship_class -> MultiMeshInstance3D
var _ship_index_map: Array = [] # per ship: {class, local}
var _near_ship_nodes: Dictionary = {} # ship index -> MeshInstance3D
var _station_nodes: Dictionary = {}
var _planet_nodes: Dictionary = {}
var _yield_nodes: Dictionary = {}
var _built := false
var _camera: Camera3D
var _inspect_target: Dictionary = {}
var _dust: GPUParticles3D
var _engine_fx: GPUParticles3D
var _env_node: WorldEnvironment

const LOD_NEAR := 420.0
const LOD_MID := 1400.0
const NEAR_SHIP_CAP := 28


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
	_build_life_fx()
	_built = true


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func get_inspect_target() -> Dictionary:
	return _inspect_target


func get_planet_focus() -> Vector3:
	if sim == null or sim.world["planets"].is_empty():
		return Vector3.ZERO
	return sim.world["planets"][0]["position"]


func get_station_focus() -> Vector3:
	if sim == null or sim.world["stations"].is_empty():
		return Vector3.ZERO
	return sim.world["stations"][0]["position"]


func _clear_visuals() -> void:
	for c in get_children():
		c.queue_free()
	_station_nodes.clear()
	_planet_nodes.clear()
	_yield_nodes.clear()
	_ship_mm.clear()
	_ship_index_map.clear()
	_near_ship_nodes.clear()
	_dust = null
	_engine_fx = null
	_env_node = null
	_built = false


func _build_environment() -> void:
	var star: Dictionary = sim.world["star"]
	var light := DirectionalLight3D.new()
	light.light_color = star["color"]
	light.light_energy = float(star.get("luminosity", 1.2)) * 1.15
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-38, 42, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	var nebula: Color = sim.world.get("nebula_color", Color(0.02, 0.03, 0.05))
	# True deep space — almost black, nebula lives in layered shaders.
	e.background_color = Color(0.003, 0.004, 0.008)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.04, 0.045, 0.06).lerp(nebula, 0.12)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.92
	e.glow_enabled = true
	e.glow_intensity = 0.75
	e.glow_bloom = 0.38
	e.glow_hdr_threshold = 0.75
	e.fog_enabled = true
	e.fog_light_color = Color(nebula.r * 0.35, nebula.g * 0.35, nebula.b * 0.4)
	e.fog_density = 0.000018
	e.fog_aerial_perspective = 0.05
	env.environment = e
	_env_node = env
	add_child(env)

	_build_nebula_layers(nebula)
	_build_starfield()
	_build_dust(nebula)


func _build_starfield() -> void:
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = StarfieldGen.build_multimesh(sim.seed_value, 3600)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/starfield.gdshader")
	stars.material_override = mat
	add_child(stars)


func _build_nebula_layers(nebula: Color) -> void:
	var rng := SeedHash.make_rng(sim.seed_value, "nebula_layers")
	var shader: Shader = load("res://shaders/nebula.gdshader")
	for i in 3:
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		var sz := rng.randf_range(6000.0, 11000.0)
		plane.size = Vector2(sz, sz)
		mi.mesh = plane
		var mat := ShaderMaterial.new()
		mat.shader = shader
		# Structured colour against black — not a full-sky wash.
		var layer_col := Color.from_hsv(
			nebula.h + rng.randf_range(-0.06, 0.06),
			clampf(nebula.s * 1.1 + 0.1, 0.3, 0.7),
			clampf(nebula.v * 1.4 + 0.15, 0.2, 0.45)
		)
		mat.set_shader_parameter("nebula_color", layer_col)
		mat.set_shader_parameter("seed_offset", float(i) * 17.3 + float(sim.seed_value % 100) * 0.13)
		mat.set_shader_parameter("density", rng.randf_range(0.45, 0.65))
		mat.set_shader_parameter("soft_edge", rng.randf_range(0.4, 0.7))
		mat.set_shader_parameter("brightness", rng.randf_range(0.18, 0.38))
		mi.material_override = mat
		var dir := rng.dir3()
		mi.position = dir * rng.randf_range(9000.0, 16000.0)
		add_child(mi)
		mi.look_at(Vector3.ZERO, Vector3.UP)


func _build_dust(nebula: Color) -> void:
	_dust = GPUParticles3D.new()
	_dust.amount = 180
	_dust.lifetime = 8.0
	_dust.preprocess = 4.0
	_dust.visibility_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.15
	mat.scale_max = 0.7
	mat.color = Color(nebula.r + 0.4, nebula.g + 0.4, nebula.b + 0.5, 0.35)
	_dust.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.35
	draw.height = 0.7
	draw.radial_segments = 4
	draw.rings = 2
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.7, 0.75, 0.85, 0.25)
	dm.emission_enabled = true
	dm.emission = Color(0.5, 0.55, 0.7)
	dm.emission_energy_multiplier = 0.6
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.material = dm
	_dust.draw_pass_1 = draw
	add_child(_dust)


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
	mat.set_shader_parameter("emission_energy", 3.2 + float(star.get("luminosity", 1.0)) * 1.8)
	mat.set_shader_parameter("corona", 0.55)
	mat.set_shader_parameter("core_hot", 1.4)
	mi.material_override = mat
	mi.position = star["position"]
	add_child(mi)

	var corona := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = float(star["radius"]) * 1.22
	cs.height = cs.radius * 2.0
	cs.radial_segments = 24
	cs.rings = 12
	corona.mesh = cs
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(star["color"].r, star["color"].g, star["color"].b, 0.12)
	cm.emission_enabled = true
	cm.emission = star["color"]
	cm.emission_energy_multiplier = 1.6
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	corona.material_override = cm
	corona.position = star["position"]
	add_child(corona)

	# Soft outer bloom shell
	var outer := MeshInstance3D.new()
	var os := SphereMesh.new()
	os.radius = float(star["radius"]) * 1.55
	os.height = os.radius * 2.0
	os.radial_segments = 16
	os.rings = 8
	outer.mesh = os
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(star["color"].r, star["color"].g, star["color"].b, 0.05)
	om.emission_enabled = true
	om.emission = star["color"]
	om.emission_energy_multiplier = 0.7
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.cull_mode = BaseMaterial3D.CULL_DISABLED
	outer.material_override = om
	outer.position = star["position"]
	add_child(outer)


func _build_planets() -> void:
	var planet_shader: Shader = load("res://shaders/planet.gdshader")
	var atmo_shader: Shader = load("res://shaders/atmosphere.gdshader")
	for p in sim.world["planets"]:
		var root := Node3D.new()
		root.position = p["position"]
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = float(p["radius"])
		sphere.height = float(p["radius"]) * 2.0
		sphere.radial_segments = 48
		sphere.rings = 24
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
		var pclass := str(p.get("planet_class", "rocky"))
		mat.set_shader_parameter("gas_giant", 1.0 if pclass == "gas_giant" else 0.0)
		mat.set_shader_parameter("desert", 1.0 if pclass == "desert" else 0.0)
		mat.set_shader_parameter("ice_world", 1.0 if pclass == "ice" else 0.0)
		mi.material_override = mat
		root.add_child(mi)

		if float(p.get("atmosphere", 0.0)) > 0.08:
			var atmo := MeshInstance3D.new()
			var asphere := SphereMesh.new()
			asphere.radius = float(p["radius"]) * 1.08
			asphere.height = asphere.radius * 2.0
			asphere.radial_segments = 32
			asphere.rings = 16
			atmo.mesh = asphere
			var am := ShaderMaterial.new()
			am.shader = atmo_shader
			var ac: Color = p["color"]
			var atmo_col := Color(ac.r * 0.35 + 0.25, ac.g * 0.4 + 0.35, ac.b * 0.55 + 0.55, 1.0)
			if pclass == "ice":
				atmo_col = Color(0.55, 0.7, 0.95)
			elif pclass == "desert" or pclass == "lava" or pclass == "barren":
				atmo_col = Color(0.85, 0.55, 0.3)
			elif pclass == "ocean" or pclass == "habitable":
				atmo_col = Color(0.35, 0.55, 0.95)
			elif pclass == "gas_giant":
				atmo_col = Color(ac.r * 0.6 + 0.2, ac.g * 0.5 + 0.2, ac.b * 0.4 + 0.15)
			am.set_shader_parameter("atmo_color", atmo_col)
			am.set_shader_parameter("intensity", 0.55 + float(p.get("atmosphere", 0.3)) * 0.7)
			am.set_shader_parameter("power", 2.8)
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
	box.size = Vector3(3.2, 0.12, 1.4)
	mm.mesh = box
	var count := 260
	mm.instance_count = count
	var inner := planet_radius * 1.32
	var outer := planet_radius * 2.25
	for i in count:
		var a := float(i) / float(count) * TAU + rng.randf() * 0.015
		var r := lerpf(inner, outer, pow(rng.randf(), 0.7))
		var pos := Vector3(cos(a) * r, rng.randf_range(-1.2, 1.2), sin(a) * r)
		var basis := Basis.from_euler(Vector3(0, -a, 0))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var c := color
		c = c.lightened(rng.randf_range(-0.1, 0.2))
		c.a = rng.randf_range(0.2, 0.75)
		mm.set_instance_color(i, c)
	mm_i.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.25
	mm_i.material_override = mat
	parent.add_child(mm_i)


func _composition_palette(composition: String) -> Dictionary:
	match composition:
		"ice":
			return {
				"color": Color(0.65, 0.78, 0.92),
				"roughness": 0.35,
				"metallic": 0.15,
				"emission": Color(0.4, 0.55, 0.75),
				"emission_energy": 0.35,
				"spread_mul": 1.15,
				"size_mul": 0.85,
			}
		"carbon":
			return {
				"color": Color(0.18, 0.16, 0.15),
				"roughness": 0.95,
				"metallic": 0.05,
				"emission": Color(0.05, 0.05, 0.05),
				"emission_energy": 0.0,
				"spread_mul": 0.95,
				"size_mul": 1.05,
			}
		"silicate":
			return {
				"color": Color(0.55, 0.45, 0.32),
				"roughness": 0.9,
				"metallic": 0.08,
				"emission": Color(0.2, 0.15, 0.1),
				"emission_energy": 0.05,
				"spread_mul": 1.0,
				"size_mul": 1.0,
			}
		_: # iron
			return {
				"color": Color(0.42, 0.38, 0.34),
				"roughness": 0.55,
				"metallic": 0.55,
				"emission": Color(0.25, 0.2, 0.15),
				"emission_energy": 0.08,
				"spread_mul": 0.9,
				"size_mul": 1.1,
			}


func _build_yields() -> void:
	for y in sim.world["yields"]:
		var root := Node3D.new()
		root.position = y["position"]
		var composition := str(y.get("composition", "iron"))
		var pal: Dictionary = _composition_palette(composition)
		var count: int = int(y.get("asteroid_count", 24))
		if composition == "ice":
			count = int(float(count) * 1.25)
		elif composition == "iron":
			count = int(float(count) * 0.9)
		var spread: float = float(y.get("spread", 90.0)) * float(pal["spread_mul"])
		var mm_i := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = AsteroidMeshGen.build(int(y.get("seed", 1)), 1 if composition != "ice" else 1)
		mm.instance_count = count
		var rng := SeededRNG.new(SeedHash.derive(int(y.get("seed", 1)), "field"))
		var base_col: Color = pal["color"]
		for i in count:
			var p: Vector3 = rng.dir3() * rng.randf_range(spread * 0.12, spread)
			p.y *= 0.4 if composition != "ice" else 0.55
			var s := rng.randf_range(3.5, 13.0) * (0.55 + float(y.get("richness", 1.0)) * 0.45) * float(pal["size_mul"])
			if composition == "iron" and rng.randf() < 0.2:
				s *= 1.45 # chunky industrial ore
			var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * s), p))
			var c := base_col.lightened(rng.randf_range(-0.12, 0.18))
			if composition == "ice":
				c = c.lerp(Color(0.85, 0.92, 1.0), rng.randf() * 0.35)
			mm.set_instance_color(i, c)
		mm_i.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = float(pal["roughness"])
		mat.metallic = float(pal["metallic"])
		if float(pal["emission_energy"]) > 0.01:
			mat.emission_enabled = true
			mat.emission = pal["emission"]
			mat.emission_energy_multiplier = float(pal["emission_energy"])
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
		mat.metallic = 0.5
		mat.roughness = 0.45
		mat.emission_enabled = true
		mat.emission = design["color"]
		mat.emission_energy_multiplier = 0.15
		mi.material_override = mat
		mi.scale = Vector3.ONE * 14.0
		root.add_child(mi)

		# Soft station beacon glow
		var glow := MeshInstance3D.new()
		var gs := SphereMesh.new()
		gs.radius = 8.0
		gs.height = 16.0
		glow.mesh = gs
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.9, 0.85, 0.5, 0.08)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.85, 0.4)
		gm.emission_energy_multiplier = 1.2
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.material_override = gm
		glow.position = Vector3(0, 18, 0)
		root.add_child(glow)

		add_child(root)
		_station_nodes[st["id"]] = root


func _build_ships() -> void:
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
		mat.roughness = 0.42
		mat.metallic = 0.4
		mmi.material_override = mat
		add_child(mmi)
		_ship_mm[sc] = mmi

	sync_ships()


func _build_life_fx() -> void:
	_engine_fx = GPUParticles3D.new()
	_engine_fx.amount = 64
	_engine_fx.lifetime = 1.2
	_engine_fx.emitting = true
	_engine_fx.visibility_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 1)
	mat.spread = 12.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 28.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.3
	mat.scale_max = 1.2
	mat.color = Color(0.45, 0.75, 1.0, 0.55)
	_engine_fx.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.6
	draw.height = 1.2
	draw.radial_segments = 4
	draw.rings = 2
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.5, 0.8, 1.0, 0.4)
	dm.emission_enabled = true
	dm.emission = Color(0.4, 0.7, 1.0)
	dm.emission_energy_multiplier = 2.0
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.material = dm
	_engine_fx.draw_pass_1 = draw
	add_child(_engine_fx)


func _ship_scale(s: Dictionary) -> float:
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
	return scale


func _ensure_near_ship(index: int, s: Dictionary) -> MeshInstance3D:
	if _near_ship_nodes.has(index):
		return _near_ship_nodes[index]
	var mi := MeshInstance3D.new()
	var design: Dictionary = s.get("design", {})
	if design.is_empty():
		design = {
			"seed": int(s.get("seed", index + 1)),
			"ship_class": int(s["ship_class"]),
			"style": "civilian",
			"color": Color(0.75, 0.78, 0.85),
			"accent": Color(0.45, 0.5, 0.55),
		}
	mi.mesh = ShipMeshGen.build(design)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	mat.metallic = 0.45
	mi.material_override = mat
	add_child(mi)
	_near_ship_nodes[index] = mi
	return mi


func _prune_near_ships(keep: Dictionary) -> void:
	var drop: Array = []
	for k in _near_ship_nodes.keys():
		if not keep.has(k):
			drop.append(k)
	for k in drop:
		var node: MeshInstance3D = _near_ship_nodes[k]
		node.queue_free()
		_near_ship_nodes.erase(k)


func sync_ships() -> void:
	if sim == null or _ship_mm.is_empty():
		return
	var ships: Array = sim.world["ships"]
	var cam_pos := Vector3.ZERO
	if _camera != null:
		cam_pos = _camera.global_position

	var nearest_dist := INF
	var nearest: Dictionary = {}
	var near_candidates: Array = [] # {dist, index}

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

		if dist < LOD_NEAR or s.get("is_player", false):
			near_candidates.append({"dist": dist, "index": i})
			# Hide MultiMesh for now; may restore if over cap.
			mm.set_instance_transform(local_i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), pos))
		else:
			var heading: Vector3 = s["heading"]
			if heading.length_squared() < 0.001:
				heading = Vector3(0, 0, -1)
			var basis := Basis.looking_at(heading.normalized(), Vector3.UP)
			var scale := _ship_scale(s)
			if dist > LOD_MID:
				scale *= 0.85
			mm.set_instance_transform(local_i, Transform3D(basis.scaled(Vector3.ONE * scale), pos))
			var design: Dictionary = s.get("design", {})
			var col: Color = design.get("color", Color(0.7, 0.75, 0.85))
			if s.get("is_player", false):
				col = Color(1.0, 0.95, 0.55)
			mm.set_instance_color(local_i, col)

	near_candidates.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	var keep: Dictionary = {}
	var n_keep := 0
	for c in near_candidates:
		var idx: int = int(c["index"])
		var s: Dictionary = ships[idx]
		var is_player: bool = bool(s.get("is_player", false))
		if n_keep >= NEAR_SHIP_CAP and not is_player:
			# Over cap — restore MultiMesh archetype
			var meta2: Dictionary = _ship_index_map[idx]
			var sc2: int = int(meta2["class"])
			var local2: int = int(meta2["local"])
			if _ship_mm.has(sc2):
				var heading2: Vector3 = s["heading"]
				if heading2.length_squared() < 0.001:
					heading2 = Vector3(0, 0, -1)
				var basis2 := Basis.looking_at(heading2.normalized(), Vector3.UP)
				var scale2 := _ship_scale(s) * 1.05
				_ship_mm[sc2].multimesh.set_instance_transform(
					local2, Transform3D(basis2.scaled(Vector3.ONE * scale2), s["position"])
				)
				var design2: Dictionary = s.get("design", {})
				_ship_mm[sc2].multimesh.set_instance_color(
					local2, design2.get("color", Color(0.7, 0.75, 0.85))
				)
			continue
		keep[idx] = true
		n_keep += 1
		var mi := _ensure_near_ship(idx, s)
		var heading3: Vector3 = s["heading"]
		if heading3.length_squared() < 0.001:
			heading3 = Vector3(0, 0, -1)
		var basis3 := Basis.looking_at(heading3.normalized(), Vector3.UP)
		var scale3 := _ship_scale(s) * 1.08
		mi.transform = Transform3D(basis3.scaled(Vector3.ONE * scale3), s["position"])
		mi.visible = true

	_prune_near_ships(keep)
	_inspect_target = nearest

	if _engine_fx != null and not nearest.is_empty():
		var np: Vector3 = nearest.get("position", Vector3.ZERO)
		var nh: Vector3 = nearest.get("heading", Vector3(0, 0, -1))
		if nh.length_squared() < 0.001:
			nh = Vector3(0, 0, -1)
		var aft := np - nh.normalized() * 6.0
		_engine_fx.global_position = aft
		_engine_fx.look_at_from_position(aft, np - nh.normalized() * 20.0, Vector3.UP)


func _process(_dt: float) -> void:
	if not _built:
		return
	sync_ships()
	if _dust != null and _camera != null:
		_dust.global_position = _camera.global_position
