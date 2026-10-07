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
var sky_comp: Dictionary = {}
var _star_packs: Dictionary = {}
var _nebula_volume_mats: Array = []

const NEAR_SHIP_CAP := 28


func setup(p_sim: StarSystemSim, camera: Camera3D = null) -> void:
	sim = p_sim
	_camera = camera
	MeshCache.clear()
	_clear_visuals()
	var nebula_hint: Color = sim.world.get("nebula_color", Color(0.3, 0.25, 0.55))
	var mood_override := str(sim.world.get("mood_override", ""))
	sky_comp = SkyComposition.build(sim.seed_value, nebula_hint, mood_override)
	var pm := SkyComposition.primary_mass(sky_comp)
	sim.world["sky_composition"] = {
		"mood": sky_comp.get("mood", ""),
		"masses": (sky_comp.get("masses", []) as Array).size(),
		"voids": (sky_comp.get("voids", []) as Array).size(),
		"gems": (sky_comp.get("gems", []) as Array).size(),
		"primary_radius": float(pm.get("radius", 0.0)),
		"primary_near": float(pm.get("depth_near", 0.0)),
		"primary_far": float(pm.get("depth_far", 0.0)),
	}
	_build_environment()
	_build_star()
	_build_planets()
	_build_yields()
	_build_stations()
	_build_ships()
	_build_life_fx()
	_built = true


func get_sky_focus() -> Vector3:
	## Direction toward primary nebula mass — for cinema composition.
	return SkyComposition.primary_mass_dir(sky_comp) * 800.0


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
	_star_packs.clear()
	_nebula_volume_mats.clear()
	_dust = null
	_engine_fx = null
	_env_node = null
	_built = false


func _build_environment() -> void:
	var star: Dictionary = sim.world["star"]
	var palette: Dictionary = sky_comp.get("palette", {})
	var primary: Color = palette.get("primary", Color(0.35, 0.28, 0.6))
	var secondary: Color = palette.get("secondary", primary.darkened(0.15))
	var band_c: Color = palette.get("band", primary.lightened(0.1))
	var bg: Color = palette.get("bg", Color(0.03, 0.035, 0.08))
	var fog_c: Color = palette.get("fog", primary.darkened(0.4))
	var ambient_c: Color = palette.get("ambient", bg.lerp(primary, 0.35))

	var light := DirectionalLight3D.new()
	var star_col := StellarColour.from_temperature(float(star.get("temperature", 5800.0)))
	# Star light ties the local environment together (LT object/sky relationship).
	light.light_color = star_col.lerp(primary, 0.12)
	light.light_energy = clampf(float(star.get("luminosity", 1.2)) * 0.78, 0.5, 1.75)
	light.shadow_enabled = false
	# Aim light so objects rim-light against the primary nebula mass.
	var mass_dir := SkyComposition.primary_mass_dir(sky_comp)
	var light_dir := (-mass_dir + Vector3(0.2, 0.55, 0.15)).normalized()
	light.transform = Transform3D(Basis.looking_at(light_dir, Vector3.UP), Vector3.ZERO)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Compatibility samples the radiance cubemap for the background. QUALITY with
	# heavy IFS often finishes only a face or two before capture (reads as a
	# black sphere with one lit patch). REALTIME + cheaper IFS stays continuous.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/deep_space_sky.gdshader")
	_apply_sky_uniforms(sky_mat, palette)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient_c
	e.ambient_light_energy = 0.14
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95
	# Bloom for star peaks; keep blacks (hex bokeh wash reads as "sphere tiles").
	e.glow_enabled = true
	e.glow_intensity = 0.38
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.2
	e.glow_hdr_scale = 1.1
	e.set_glow_level(2, 0.45)
	e.set_glow_level(3, 0.75)
	e.set_glow_level(4, 0.5)
	e.set_glow_level(5, 0.28)
	# Fog is aerial cue only — never the nebula (LT nebula is skybox/env).
	e.fog_enabled = true
	e.fog_light_color = fog_c.lerp(bg, 0.7)
	e.fog_density = 0.000003
	e.fog_aerial_perspective = 0.035
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.92
	e.adjustment_contrast = 1.16
	e.adjustment_brightness = 0.95
	env.environment = e
	_env_node = env
	add_child(env)

	# LT path: direction-space IFS sky is the nebula authority (gen/nebula.glsl).
	# World-space volumes/wisps are off — they reinvent fog and fight the IFS look.
	_build_starfield_layer("micro")
	_build_starfield_layer("field")
	_build_starfield_layer("notable")
	_build_starfield_layer("gems")
	_build_starfield_layer("dust")
	_build_dust(primary)
	_nebula_volume_mats.clear()


func _apply_sky_uniforms(sky_mat: ShaderMaterial, palette: Dictionary) -> void:
	var bg: Color = palette.get("bg", Color(0.03, 0.035, 0.08))
	var band_c: Color = palette.get("band", Color(0.45, 0.4, 0.7))
	var primary: Color = palette.get("primary", Color(0.4, 0.3, 0.7))
	var secondary: Color = palette.get("secondary", Color(0.3, 0.35, 0.55))
	sky_mat.set_shader_parameter("seed", float(sim.seed_value))
	sky_mat.set_shader_parameter("bg_color", Vector3(bg.r, bg.g, bg.b))
	sky_mat.set_shader_parameter("band_color", Vector3(band_c.r, band_c.g, band_c.b))
	sky_mat.set_shader_parameter("primary_color", Vector3(primary.r, primary.g, primary.b))
	sky_mat.set_shader_parameter("secondary_color", Vector3(secondary.r, secondary.g, secondary.b))
	var gn: Vector3 = sky_comp.get("galaxy_normal", Vector3.UP)
	sky_mat.set_shader_parameter("galaxy_normal", gn)
	sky_mat.set_shader_parameter("band_width", float(sky_comp.get("band_width", 3.6)))
	sky_mat.set_shader_parameter("band_strength", float(sky_comp.get("band_strength", 0.55)))
	sky_mat.set_shader_parameter("roughness", float(sky_comp.get("roughness", 0.72)))
	# LT-style ColourLUT knots (Gen.ColorLUT) — drives IFS absorption wave colour
	var lut := _nebula_color_luts(sim.seed_value, primary, secondary)
	sky_mat.set_shader_parameter("lut_r", lut["lut_r"])
	sky_mat.set_shader_parameter("lut_g", lut["lut_g"])
	sky_mat.set_shader_parameter("lut_b", lut["lut_b"])
	sky_mat.set_shader_parameter("lut_rg_mid", lut["lut_rg_mid"])
	sky_mat.set_shader_parameter("lut_b_edge", lut["lut_b_edge"])
	var star: Dictionary = sim.world.get("star", {})
	var star_pos: Vector3 = star.get("position", Vector3(0.2, 0.55, 0.15))
	sky_mat.set_shader_parameter("star_dir", star_pos.normalized() if star_pos.length() > 0.01 else Vector3(0.2, 0.55, 0.15))
	var masses: Array = sky_comp.get("masses", [])
	for i in 3:
		var key_dir := "mass%d_dir" % i
		var key_par := "mass%d_params" % i
		if i < masses.size():
			var m: Dictionary = masses[i]
			sky_mat.set_shader_parameter(key_dir, m["dir"])
			sky_mat.set_shader_parameter(key_par, Vector3(float(m["scale"]), float(m["core"]), float(m["dark"])))
		else:
			sky_mat.set_shader_parameter(key_dir, Vector3(0.0, 1.0, 0.0))
			sky_mat.set_shader_parameter(key_par, Vector3(0.2, 0.2, 0.2))
	var voids: Array = sky_comp.get("voids", [])
	for i in 2:
		if i < voids.size():
			sky_mat.set_shader_parameter("void%d_dir" % i, voids[i]["dir"])
			sky_mat.set_shader_parameter("void%d_radius" % i, float(voids[i]["radius"]))
		else:
			sky_mat.set_shader_parameter("void%d_dir" % i, Vector3(0, 1, 0))
			sky_mat.set_shader_parameter("void%d_radius" % i, 0.2)


## Approx LT Gen.ColorLUT — five knots per channel, seeded, biased to mood palette.
func _nebula_color_luts(system_seed: int, primary: Color, secondary: Color) -> Dictionary:
	var rng := SeedHash.make_rng(system_seed, "nebula_lut")
	var knots_r: Array = []
	var knots_g: Array = []
	var knots_b: Array = []
	for i in 5:
		var t := float(i) / 4.0
		var mood := secondary.lerp(primary, t)
		knots_r.append(clampf(mood.r * rng.randf_range(0.75, 1.15) + rng.randf_range(-0.05, 0.08), 0.05, 1.0))
		knots_g.append(clampf(mood.g * rng.randf_range(0.75, 1.15) + rng.randf_range(-0.05, 0.08), 0.05, 1.0))
		knots_b.append(clampf(mood.b * rng.randf_range(0.75, 1.15) + rng.randf_range(-0.05, 0.08), 0.05, 1.0))
	return {
		"lut_r": Vector3(float(knots_r[1]), float(knots_r[3]), float(knots_r[4])),
		"lut_g": Vector3(float(knots_g[1]), float(knots_g[3]), float(knots_g[4])),
		"lut_b": Vector3(float(knots_b[1]), float(knots_b[2]), float(knots_b[4])),
		"lut_rg_mid": Vector2(float(knots_r[2]), float(knots_g[2])),
		"lut_b_edge": Vector2(float(knots_b[1]), float(knots_b[3])),
	}


func _build_starfield_layer(key: String) -> void:
	if _star_packs.is_empty():
		_star_packs = StarfieldGen.build_from_composition(sky_comp)
	var mm: MultiMesh = _star_packs.get(key)
	if mm == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/starfield.gdshader")
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.name = "stars_%s" % key
	add_child(node)


func _build_nebula_volumes(primary: Color, secondary: Color) -> void:
	## Hybrid: IFS sky = far colour; major masses = bounded raymarch;
	## thin wisps = cheap depth accents. Filaments raise mid-edge without cavity wash.
	var vol_shader: Shader = load("res://shaders/nebula_volume.gdshader")
	var wisp_shader: Shader = load("res://shaders/nebula.gdshader")
	var masses: Array = sky_comp.get("masses", [])
	var quality := int(sky_comp.get("volume_quality", 28))
	var debug_mode := int(sky_comp.get("debug_nebula", 0))
	_nebula_volume_mats.clear()
	var i := 0
	for m in masses:
		var t := float(m.get("color_t", 0.5))
		var layer_col := primary.lerp(secondary, t)
		var sec_col := secondary.lerp(primary, 0.35)
		var center: Vector3 = m.get("center", m["dir"] * float(m.get("shell", 5000.0)))
		var radius := float(m.get("radius", 2500.0))

		if bool(m.get("volumetric", true)) and i < 3:
			var mi := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = radius
			sphere.height = radius * 2.0
			sphere.radial_segments = 24
			sphere.rings = 12
			mi.mesh = sphere
			var mat := ShaderMaterial.new()
			mat.shader = vol_shader
			mat.set_shader_parameter("volume_center", center)
			mat.set_shader_parameter("volume_radius", radius)
			mat.set_shader_parameter("primary_color", Vector3(layer_col.r, layer_col.g, layer_col.b))
			mat.set_shader_parameter("secondary_color", Vector3(sec_col.r, sec_col.g, sec_col.b))
			mat.set_shader_parameter("seed", float(m.get("seed", i * 97)))
			mat.set_shader_parameter("density_scale", float(m.get("density", 1.0)) * 1.10)
			mat.set_shader_parameter("core_strength", float(m.get("core", 0.55)) * 0.95)
			mat.set_shader_parameter("cavity_strength", float(m.get("dark", 0.45)) * 0.52)
			mat.set_shader_parameter("filament_strength", float(m.get("filament", 0.55)) * 1.75)
			mat.set_shader_parameter("emission_strength", float(m.get("emission", 0.85)) * 1.25)
			mat.set_shader_parameter("absorb_strength", 0.85)
			mat.set_shader_parameter("elongation", m.get("elongation", Vector3(1.0, 0.7, 1.15)))
			mat.set_shader_parameter("ray_steps", quality)
			mat.set_shader_parameter("debug_mode", debug_mode)
			mi.material_override = mat
			mi.position = center
			mi.name = "nebula_volume_%d" % i
			add_child(mi)
			_nebula_volume_mats.append(mat)

		# Thin near/mid wisps — accents only; volumes carry primary structure
		var depth_near := float(m.get("depth_near", 2800.0))
		var depth_far := float(m.get("depth_far", 6200.0))
		var shells: Array = [
			{"dist": lerpf(depth_near, depth_far, 0.30), "bright": 0.16, "dens": 0.36, "size": 0.58},
			{"dist": lerpf(depth_near, depth_far, 0.65), "bright": 0.11, "dens": 0.40, "size": 0.80},
		]
		if i >= 2:
			shells = [shells[0]]
		var si := 0
		for shell in shells:
			var wmi := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			var sz := radius * 2.0 * float(shell["size"])
			plane.size = Vector2(sz, sz)
			wmi.mesh = plane
			var wmat := ShaderMaterial.new()
			wmat.shader = wisp_shader
			wmat.set_shader_parameter("nebula_color", layer_col)
			wmat.set_shader_parameter("secondary_color", sec_col)
			wmat.set_shader_parameter("seed_offset", float(m.get("seed", 0)) * 0.01 + float(si) * 31.7 + float(i) * 7.3)
			wmat.set_shader_parameter("density", float(shell["dens"]))
			wmat.set_shader_parameter("soft_edge", 0.48)
			wmat.set_shader_parameter("brightness", float(shell["bright"]))
			wmat.set_shader_parameter("core_strength", float(m.get("core", 0.5)) * 0.22)
			wmat.set_shader_parameter("dark_lanes", float(m.get("dark", 0.45)))
			wmi.material_override = wmat
			wmi.position = m["dir"] * float(shell["dist"])
			wmi.name = "nebula_wisp_%d_%d" % [i, si]
			add_child(wmi)
			wmi.look_at(Vector3.ZERO, Vector3.UP)
			si += 1
		i += 1


func set_nebula_debug_mode(mode: int) -> void:
	sky_comp["debug_nebula"] = mode
	for mat in _nebula_volume_mats:
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("debug_mode", mode)


func set_nebula_quality(steps: int) -> void:
	sky_comp["volume_quality"] = steps
	for mat in _nebula_volume_mats:
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("ray_steps", steps)


func _build_dust(nebula: Color) -> void:
	_dust = GPUParticles3D.new()
	_dust.amount = 140
	_dust.lifetime = 8.0
	_dust.preprocess = 4.0
	_dust.visibility_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.12
	mat.scale_max = 0.55
	mat.color = Color(nebula.r + 0.25, nebula.g + 0.25, nebula.b + 0.35, 0.28)
	_dust.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.3
	draw.height = 0.6
	draw.radial_segments = 4
	draw.rings = 2
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(nebula.r + 0.3, nebula.g + 0.3, nebula.b + 0.4, 0.22)
	dm.emission_enabled = true
	dm.emission = nebula
	dm.emission_energy_multiplier = 0.45
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
	mat.set_shader_parameter("star_color", StellarColour.from_temperature(float(star.get("temperature", 5800.0))))
	mat.set_shader_parameter("emission_energy", StellarColour.luminosity_energy(float(star.get("luminosity", 1.0))))
	# Hot core + controlled corona — LT local star is a light event, not two soft spheres.
	mat.set_shader_parameter("corona", 0.42)
	mat.set_shader_parameter("core_hot", 1.65)
	mi.material_override = mat
	mi.position = star["position"]
	add_child(mi)

	var corona := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = float(star["radius"]) * 1.14
	cs.height = cs.radius * 2.0
	cs.radial_segments = 24
	cs.rings = 12
	corona.mesh = cs
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(star["color"].r, star["color"].g, star["color"].b, 0.1)
	cm.emission_enabled = true
	cm.emission = star["color"]
	cm.emission_energy_multiplier = 2.1
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	corona.material_override = cm
	corona.position = star["position"]
	add_child(corona)

	# Thin outer shell — bloom carries the rest (avoid giant soft disc)
	var outer := MeshInstance3D.new()
	var os := SphereMesh.new()
	os.radius = float(star["radius"]) * 1.38
	os.height = os.radius * 2.0
	os.radial_segments = 16
	os.rings = 8
	outer.mesh = os
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(star["color"].r, star["color"].g, star["color"].b, 0.04)
	om.emission_enabled = true
	om.emission = star["color"]
	om.emission_energy_multiplier = 0.85
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
		mat.set_shader_parameter("seed_offset", float(int(p.get("terrain_seed", p.get("seed", 1))) % 1000) * 0.01)
		mat.set_shader_parameter("atmosphere_tint", float(p.get("atmosphere", 0.3)))
		var pclass := str(p.get("planet_class", "rocky"))
		mat.set_shader_parameter("gas_giant", 1.0 if pclass == "gas_giant" else 0.0)
		mat.set_shader_parameter("desert", 1.0 if pclass == "desert" else 0.0)
		mat.set_shader_parameter("ice_world", 1.0 if pclass == "ice" else 0.0)
		# Volcanic / lava: boost emission via atmosphere_tint side channel
		if pclass == "lava":
			mat.set_shader_parameter("atmosphere_tint", 0.85)
			mat.set_shader_parameter("desert", 0.0)
			mat.set_shader_parameter("ocean_level", 0.0)
		elif pclass == "habitable" or pclass == "ocean":
			mat.set_shader_parameter("ocean_level", float(p.get("ocean_level", 0.45)))
			mat.set_shader_parameter("cloud_level", float(p.get("cloud_level", 0.28)))
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
			am.set_shader_parameter("power", 2.4)
			var mass_dir := SkyComposition.primary_mass_dir(sky_comp)
			am.set_shader_parameter("light_dir", (-mass_dir + Vector3(0.15, 0.6, 0.1)).normalized())
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
		# Family mesh from field seed + composition — not one rock scaled forever
		mm.mesh = AsteroidMeshGen.build(int(y.get("seed", 1)), 1, composition)
		mm.instance_count = count
		var rng := SeededRNG.new(SeedHash.derive(int(y.get("seed", 1)), "field"))
		var base_col: Color = pal["color"]
		# Belt / cluster composition (LT asteroid fields are spatial structures, not isotropic).
		var belt_n := Vector3(rng.randf_range(-0.25, 0.25), 1.0, rng.randf_range(-0.25, 0.25)).normalized()
		var cluster_a := rng.dir3()
		var cluster_b := (cluster_a + rng.dir3() * 0.5).normalized()
		for i in count:
			var dir: Vector3
			if rng.randf() < 0.7:
				dir = rng.dir3()
				dir = (dir - belt_n * dir.dot(belt_n) * rng.randf_range(0.7, 0.95)).normalized()
			else:
				var cdir: Vector3 = cluster_a if rng.randf() < 0.55 else cluster_b
				dir = (cdir + rng.dir3() * rng.randf_range(0.05, 0.35)).normalized()
			var p: Vector3 = dir * rng.randf_range(spread * 0.15, spread)
			p.y *= 0.28 if composition != "ice" else 0.4
			var s := rng.randf_range(3.5, 13.0) * (0.55 + float(y.get("richness", 1.0)) * 0.45) * float(pal["size_mul"])
			if composition == "iron" and rng.randf() < 0.2:
				s *= 1.45
			var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * s), p))
			var c := base_col.lightened(rng.randf_range(-0.12, 0.18))
			if composition == "ice":
				c = c.lerp(Color(0.85, 0.92, 1.0), rng.randf() * 0.35)
			mm.set_instance_color(i, c)
		mm_i.multimesh = mm
		var mat_name := "ice" if composition == "ice" else ("rock" if composition != "iron" else "industrial")
		var mat := VisualMaterials.make(mat_name, base_col, 0.55)
		mat.vertex_color_use_as_albedo = true
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
		mi.mesh = StationMeshGen.build(design, VisualLOD.LOD_FULL)
		var profile := StyleProfile.of(str(design["style"]))
		var mat := VisualMaterials.make(str(profile["material"]), design["color"], 0.45)
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
		# Archetype from first ship in bucket when available (faction-aware), else class default
		var sample: Dictionary = list[0]
		var design: Dictionary = sample.get("design", {
			"seed": 50 + int(sc) * 17,
			"ship_class": int(sc),
			"style": styles[int(sc) % styles.size()],
			"color": Color(0.75, 0.78, 0.85),
			"accent": Color(0.45, 0.48, 0.55),
		})
		# Force class archetype seed for batch mesh stability
		var arch := design.duplicate()
		arch["seed"] = 50 + int(sc) * 17
		arch["ship_class"] = int(sc)
		arch["style"] = styles[int(sc) % styles.size()]
		mm.mesh = ShipMeshGen.build(arch, VisualLOD.LOD_BATCH)
		mm.instance_count = list.size()
		mmi.multimesh = mm
		var profile := StyleProfile.of(str(arch["style"]))
		var mat := VisualMaterials.make(str(profile["material"]), arch.get("color", Color(0.45, 0.45, 0.48)), 0.55)
		mat.roughness = float(profile.get("roughness", mat.roughness))
		mat.metallic = float(profile.get("metallic", mat.metallic))
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
	# Warm amber default — style-specific exhaust lives on the mesh; FX stays neutral-warm.
	mat.color = Color(1.0, 0.55, 0.25, 0.5)
	_engine_fx.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.6
	draw.height = 1.2
	draw.radial_segments = 4
	draw.rings = 2
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(1.0, 0.6, 0.3, 0.4)
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.5, 0.2)
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


func _ensure_near_ship(index: int, s: Dictionary, lod: int = VisualLOD.LOD_FULL) -> MeshInstance3D:
	var key := "%d:%d" % [index, lod]
	# Reuse node if same index; rebuild mesh if LOD tier changed
	if _near_ship_nodes.has(index):
		var existing: MeshInstance3D = _near_ship_nodes[index]
		if existing.get_meta("lod_tier", -1) == lod:
			return existing
		existing.queue_free()
		_near_ship_nodes.erase(index)
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
	mi.mesh = ShipMeshGen.build(design, lod)
	var profile := StyleProfile.of(str(design.get("style", "civilian")))
	var mat := VisualMaterials.make(str(profile["material"]), design.get("color", Color(0.45, 0.45, 0.48)), 0.55)
	mat.roughness = float(profile.get("roughness", mat.roughness))
	mat.metallic = float(profile.get("metallic", mat.metallic))
	mi.material_override = mat
	mi.set_meta("lod_tier", lod)
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

	# SoA buckets per ship class for native MultiMesh apply.
	var batch_local: Dictionary = {} # sc -> PackedInt32Array
	var batch_pos: Dictionary = {}
	var batch_head: Dictionary = {}
	var batch_scale: Dictionary = {}
	var batch_hidden: Dictionary = {}
	var batch_color_i: Dictionary = {} # sc -> Array of local indices needing color
	var batch_color_c: Dictionary = {} # sc -> Array of Color

	for i in ships.size():
		var s: Dictionary = ships[i]
		var meta: Dictionary = _ship_index_map[i]
		var sc: int = int(meta["class"])
		var local_i: int = int(meta["local"])
		if not _ship_mm.has(sc):
			continue
		var pos: Vector3 = s["position"]
		var dist := cam_pos.distance_to(pos) if _camera != null else 800.0
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = s

		if not batch_local.has(sc):
			batch_local[sc] = PackedInt32Array()
			batch_pos[sc] = PackedFloat32Array()
			batch_head[sc] = PackedFloat32Array()
			batch_scale[sc] = PackedFloat32Array()
			batch_hidden[sc] = PackedInt32Array()
			batch_color_i[sc] = []
			batch_color_c[sc] = []

		var locals: PackedInt32Array = batch_local[sc]
		var positions: PackedFloat32Array = batch_pos[sc]
		var headings: PackedFloat32Array = batch_head[sc]
		var scales: PackedFloat32Array = batch_scale[sc]
		var hidden: PackedInt32Array = batch_hidden[sc]

		locals.append(local_i)
		positions.append(pos.x)
		positions.append(pos.y)
		positions.append(pos.z)
		var heading: Vector3 = s.get("heading", Vector3(0, 0, -1))
		headings.append(heading.x)
		headings.append(heading.y)
		headings.append(heading.z)

		var hide := false
		if int(s.get("docked_station_id", -1)) >= 0 and not s.get("is_player", false):
			hide = true
		elif dist < VisualLOD.DIST_LOW or s.get("is_player", false):
			near_candidates.append({"dist": dist, "index": i, "lod": VisualLOD.for_distance(dist)})
			hide = true

		var scale := _ship_scale(s)
		if not hide and dist > VisualLOD.DIST_BATCH * 0.5:
			scale *= 0.85
		scales.append(scale)
		hidden.append(1 if hide else 0)

		if not hide:
			var design: Dictionary = s.get("design", {})
			var col: Color = design.get("color", Color(0.7, 0.75, 0.85))
			if s.get("is_player", false):
				col = Color(1.0, 0.95, 0.55)
			batch_color_i[sc].append(local_i)
			batch_color_c[sc].append(col)

		batch_local[sc] = locals
		batch_pos[sc] = positions
		batch_head[sc] = headings
		batch_scale[sc] = scales
		batch_hidden[sc] = hidden

	for sc2 in batch_local.keys():
		var mm: MultiMesh = _ship_mm[sc2].multimesh
		NativeBridge.apply_ship_transforms(
			mm,
			batch_local[sc2],
			batch_pos[sc2],
			batch_head[sc2],
			batch_scale[sc2],
			batch_hidden[sc2],
		)
		var cols_i: Array = batch_color_i[sc2]
		var cols_c: Array = batch_color_c[sc2]
		for ci in cols_i.size():
			mm.set_instance_color(int(cols_i[ci]), cols_c[ci])

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
			var sc3: int = int(meta2["class"])
			var local2: int = int(meta2["local"])
			if _ship_mm.has(sc3):
				var heading2: Vector3 = s["heading"]
				if heading2.length_squared() < 0.001:
					heading2 = Vector3(0, 0, -1)
				var basis2 := Basis.looking_at(heading2.normalized(), Vector3.UP)
				var scale2 := _ship_scale(s) * 1.05
				_ship_mm[sc3].multimesh.set_instance_transform(
					local2, Transform3D(basis2.scaled(Vector3.ONE * scale2), s["position"])
				)
				var design2: Dictionary = s.get("design", {})
				_ship_mm[sc3].multimesh.set_instance_color(
					local2, design2.get("color", Color(0.7, 0.75, 0.85))
				)
			continue
		var lod: int = int(c.get("lod", VisualLOD.LOD_FULL))
		if lod > VisualLOD.LOD_LOW:
			lod = VisualLOD.LOD_LOW
		keep[idx] = true
		n_keep += 1
		var mi := _ensure_near_ship(idx, s, lod)
		var heading3: Vector3 = s["heading"]
		if heading3.length_squared() < 0.001:
			heading3 = Vector3(0, 0, -1)
		var basis3 := Basis.looking_at(heading3.normalized(), Vector3.UP)
		var scale3 := _ship_scale(s) * (1.08 if lod == VisualLOD.LOD_FULL else 1.02)
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
