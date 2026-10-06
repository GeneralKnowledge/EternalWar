## Renders simulation state with primitives + MultiMesh ships.
class_name SystemPresenter
extends Node3D

var sim: StarSystemSim
var ship_multimesh: MultiMeshInstance3D
var _station_nodes: Dictionary = {}
var _planet_nodes: Dictionary = {}
var _yield_nodes: Dictionary = {}
var _built := false

const SHIP_COLORS := [
	Color(0.45, 0.75, 1.0),
	Color(1.0, 0.7, 0.35),
	Color(0.5, 0.95, 0.55),
	Color(1.0, 0.45, 0.5),
]


func setup(p_sim: StarSystemSim) -> void:
	sim = p_sim
	_clear_visuals()
	_build_environment()
	_build_star()
	_build_planets()
	_build_yields()
	_build_stations()
	_build_ships()
	_built = true


func _clear_visuals() -> void:
	for c in get_children():
		c.queue_free()
	_station_nodes.clear()
	_planet_nodes.clear()
	_yield_nodes.clear()
	ship_multimesh = null
	_built = false


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.light_energy = 1.35
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-42, 35, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.08, 0.1, 0.14)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.15
	env.environment = e
	add_child(env)

	# Distant starfield points.
	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _sphere_mesh(1.0)
	mm.use_colors = true
	mm.instance_count = 400
	var rng := SeededRNG.new(sim.seed_value ^ 12345)
	for i in 400:
		var p: Vector3 = rng.dir3() * rng.randf_range(8000.0, 14000.0)
		var s: float = rng.randf_range(4.0, 12.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), p))
		mm.set_instance_color(i, Color(0.75, 0.82, 1.0))
	stars.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stars.material_override = mat
	add_child(stars)


func _build_star() -> void:
	var star: Dictionary = sim.world["star"]
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(float(star["radius"]))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = star["color"]
	mat.emission_enabled = true
	mat.emission = star["color"]
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = star["position"]
	add_child(mi)


func _build_planets() -> void:
	for p in sim.world["planets"]:
		var mi := MeshInstance3D.new()
		mi.mesh = _sphere_mesh(float(p["radius"]))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p["color"]
		mat.roughness = 0.85
		mi.material_override = mat
		mi.position = p["position"]
		add_child(mi)
		_planet_nodes[p["id"]] = mi


func _build_yields() -> void:
	for y in sim.world["yields"]:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(Vector3(28, 14, 28))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.45, 0.3)
		mat.roughness = 1.0
		mi.material_override = mat
		mi.position = y["position"]
		add_child(mi)
		_yield_nodes[y["id"]] = mi


func _build_stations() -> void:
	for st in sim.world["stations"]:
		var root := Node3D.new()
		root.position = st["position"]
		var body := MeshInstance3D.new()
		body.mesh = _box_mesh(Vector3(36, 18, 36))
		var mat := StandardMaterial3D.new()
		var faction: Dictionary = sim.world["factions"][int(st["faction_id"]) % sim.world["factions"].size()]
		mat.albedo_color = faction["color"].darkened(0.15)
		mat.metallic = 0.55
		mat.roughness = 0.4
		body.material_override = mat
		root.add_child(body)
		var spire := MeshInstance3D.new()
		spire.mesh = _box_mesh(Vector3(8, 40, 8))
		spire.position = Vector3(0, 24, 0)
		spire.material_override = mat
		root.add_child(spire)
		add_child(root)
		_station_nodes[st["id"]] = root


func _build_ships() -> void:
	ship_multimesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _ship_mesh()
	# use_colors must be set before instance_count
	mm.use_colors = true
	mm.instance_count = sim.world["ships"].size()
	ship_multimesh.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.metallic = 0.3
	ship_multimesh.material_override = mat
	add_child(ship_multimesh)
	sync_ships()


func sync_ships() -> void:
	if ship_multimesh == null or sim == null:
		return
	var mm := ship_multimesh.multimesh
	var ships: Array = sim.world["ships"]
	if mm.instance_count != ships.size():
		mm.instance_count = ships.size()
	for i in ships.size():
		var s: Dictionary = ships[i]
		if int(s.get("docked_station_id", -1)) >= 0 and not s.get("is_player", false):
			# Hide docked NPC ships inside stations.
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), s["position"]))
			continue
		var heading: Vector3 = s["heading"]
		if heading.length_squared() < 0.001:
			heading = Vector3(0, 0, -1)
		var basis := Basis.looking_at(heading.normalized(), Vector3.UP)
		var scale := 6.0
		match int(s["ship_class"]):
			SimEntities.ShipClass.HAULER:
				scale = 9.0
			SimEntities.ShipClass.PATROL:
				scale = 5.0
			SimEntities.ShipClass.MINER:
				scale = 7.0
		if s.get("is_player", false):
			scale = 8.0
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * scale), s["position"]))
		var col: Color = SHIP_COLORS[int(s["faction_id"]) % SHIP_COLORS.size()]
		if s.get("is_player", false):
			col = Color(1.0, 0.95, 0.55)
		mm.set_instance_color(i, col)


func _process(_dt: float) -> void:
	if _built:
		sync_ships()


func _sphere_mesh(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 24
	m.rings = 12
	return m


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _ship_mesh() -> PrismMesh:
	var m := PrismMesh.new()
	m.size = Vector3(1.2, 0.5, 2.2)
	return m
